import Foundation
import CloudKit
import CoreData

// MARK: - CloudKitPurgeService
// 修复（2026-10-14）：「重置数据库」只清本地，云端副本会重新下载回来。
//
// 原理：`NSPersistentCloudKitContainer` 把每个托管实体镜像为一个 CKRecord
// （recordType = 实体名），统一存放在名为 `com.apple.coredata.cloudkit.zone`
// 的自定义 zone 中（注意：不是 `_DefaultZone`，必须切到该 zone 才能浏览到数据）。
// 销毁本地 SQLite store 并不会删除这些云端记录，下次同步会原样灌回本地，
// 表现为「刚重置完数据又出现了」。
//
// 时序契约：重置时**先清云端、成功后再清本地**。若云端删除失败则整体中止，
// 本地数据保持原样，避免出现「本地已清、云端仍在」的中间态。

/// 清除 CloudKit 私有数据库中本 App 的全部镜像记录。
enum CloudKitPurgeService {

    /// `NSPersistentCloudKitContainer` 镜像专用 zone 名（Core Data 内部约定）。
    /// zoneID 的 ownerName 必须是 `CKCurrentUserDefaultName`（私有数据库）。
    static let mirroringZoneName = "com.apple.coredata.cloudkit.zone"

    /// 单次 `modifyRecords` 的批量删除上限。CloudKit 硬上限为 400，取 200 留余量。
    private static let deleteBatchSize = 200

    /// 需要清除的 recordType 列表：模型中全部实体均为 `syncable="YES"`，都会被镜像。
    private static func mirrorRecordTypes() -> [String] {
        PersistenceController.sharedManagedObjectModel.entities.compactMap(\.name)
    }

    /// 清除全部镜像记录。
    /// - Parameter completion: 主线程回调。成功时携带已删除的记录条数。
    static func purgeAll(completion: @escaping (Result<Int, Error>) -> Void) {
        let container = CKContainer(identifier: AppConstants.cloudKitContainerIdentifier)

        container.accountStatus { status, error in
            switch status {
            case .available:
                let recordTypes = mirrorRecordTypes()
                guard !recordTypes.isEmpty else {
                    DispatchQueue.main.async { completion(.success(0)) }
                    return
                }
                let zoneID = CKRecordZone.ID(zoneName: mirroringZoneName,
                                             ownerName: CKCurrentUserDefaultName)
                // 注意：本模块定义了 Core Data 实体 `Task`，会遮蔽 _Concurrency.Task，
                // 故必须写全限定名 Swift.Task，否则会被解析成 NSManagedObject 子类。
                Swift.Task {
                    do {
                        let deleted = try await purge(recordTypes: recordTypes,
                                                      database: container.privateCloudDatabase,
                                                      zoneID: zoneID)
                        await MainActor.run { completion(.success(deleted)) }
                    } catch {
                        await MainActor.run { completion(.failure(error)) }
                    }
                }

            case .noAccount:
                fail(Self.error(.notSignedIn), completion)
            case .restricted:
                fail(Self.error(.restricted), completion)
            default:
                // couldNotDetermine / temporarilyUnavailable：带上底层错误便于定位
                fail(error ?? Self.error(.indeterminate), completion)
            }
        }
    }

    // MARK: - 内部实现

    /// 逐个 recordType 清空，累计删除条数。
    private static func purge(recordTypes: [String],
                              database: CKDatabase,
                              zoneID: CKRecordZone.ID) async throws -> Int {
        var total = 0
        var zoneMissing = false
        for recordType in recordTypes {
            // 修复（2026-10-14 审查 P2-14）：镜像 zone 不存在时，后续 recordType 只会
            // 重复发必败请求（旧实现每个类型各跑一次）。首次确认 zone 不存在即整体短路。
            if zoneMissing { break }
            let outcome = try await purge(recordType: recordType, database: database, zoneID: zoneID)
            switch outcome {
            case .deleted(let count):
                total += count
            case .typeMissing:
                // 修复（2026-10-15）：该实体从未同步上云（云端 schema 无此 type），
                // 仅跳过本类型——其它类型可能有真实数据，不得短路。
                continue
            case .zoneMissing:
                zoneMissing = true
            }
        }
        return total
    }

    /// 单个 recordType 的清除结果。
    ///
    /// `zoneNotFound` 与「Did not find record type」都表示**没有云端副本需要清除**
    ///（前者 = 用户从未同步过任何数据；后者 = 该实体从未有记录同步上云，schema 中
    /// 无此 type），均不应让整个重置失败。
    private enum PurgeOutcome {
        /// 正常删除，携带删除条数
        case deleted(Int)
        /// 镜像 zone 不存在（后续所有类型必败，可整体短路）
        case zoneMissing
        /// 云端无此 recordType（仅跳过本类型，不影响其它类型）
        case typeMissing
    }

    /// 清除单个 recordType。
    /// - Returns: 清除结果；typeMissing 仅影响当前类型，zoneMissing 触发整体短路。
    private static func purge(recordType: String,
                              database: CKDatabase,
                              zoneID: CKRecordZone.ID) async throws -> PurgeOutcome {
        do {
            let deleted = try await purgeRecords(recordType: recordType, database: database, zoneID: zoneID)
            return .deleted(deleted)
        } catch let error as CKError where error.code == .zoneNotFound {
            print("☁️ 镜像 zone 不存在（尚未同步过数据），跳过 recordType \(recordType)")
            return .zoneMissing
        } catch where isRecordTypeMissing(error) {
            // 修复（2026-10-15）：实体（如 Achievement）从未有记录同步上云时，
            // CloudKit schema 中不存在该 recordType，查询直接报
            // "Did not find record type: X"。这等价于「无数据可清」，
            // 旧实现将其当成真实失败 → 整体重置中止 → 弹「云端数据清除失败」。
            print("☁️ recordType \(recordType) 从未同步上云（云端无此 type），跳过")
            return .typeMissing
        }
    }

    /// 判据收口（唯一处）：错误链中是否含「record type 不存在」。
    ///
    /// CloudKit 无专门的 `unknownRecordType` 错误码，该错误以服务器原文
    /// "Did not find record type: X" 出现，可能被包装在 `CKError.partialFailure`
    /// 的逐条错误里。Swift 侧只暴露 `CKError.partialErrorsByItemID` 属性，而其
    /// 背后的 NSString 常量既未导出也未公开取值，故同时按 userInfo 键名匹配兜底，
    /// 避免因常量值不可知而漏判（漏判 = 用户看到假失败文案）。
    /// 抽成纯函数以便单测覆盖。
    static func isRecordTypeMissing(_ error: Error) -> Bool {
        var queue: [Error] = [error]
        var visited = Set<ObjectIdentifier>()
        while let current = queue.popLast() {
            let nsError = current as NSError
            if !visited.insert(ObjectIdentifier(nsError)).inserted { continue }

            // 官方 API：逐条失败的包装形态
            if let ckError = current as? CKError, ckError.code == .partialFailure {
                queue.append(contentsOf: ckError.partialErrorsByItemID?.values ?? [:].values)
            }
            // 兜底：userInfo 中任何「逐条错误」字典（键名含 PartialErrors）
            for (key, value) in nsError.userInfo where key.description.contains("PartialErrors") {
                if let dict = value as? [AnyHashable: any Error] {
                    queue.append(contentsOf: dict.values)
                } else if let dict = value as? NSDictionary {
                    queue.append(contentsOf: dict.allValues.compactMap { $0 as? Error })
                }
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                queue.append(underlying)
            }
            let text = nsError.localizedDescription
            if text.contains("Did not find record type") || text.contains("Unknown record type") {
                return true
            }
        }
        return false
    }

    private static func purgeRecords(recordType: String,
                                     database: CKDatabase,
                                     zoneID: CKRecordZone.ID) async throws -> Int {
        var deleted = 0
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)],
                       queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                page = try await database.records(continuingMatchFrom: cursor)
            } else {
                page = try await database.records(
                    matching: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)),
                    inZoneWith: zoneID,
                    resultsLimit: CKQueryOperation.maximumResults
                )
            }

            var ids = [CKRecord.ID]()
            ids.reserveCapacity(page.matchResults.count)
            for (_, result) in page.matchResults {
                // 单条取记录失败（如已被其它设备删除）不影响整批删除，跳过即可
                if case .success(let record) = result { ids.append(record.recordID) }
            }

            if !ids.isEmpty {
                deleted += try await delete(ids: ids, database: database)
            }

            cursor = page.queryCursor
            // 无更多数据时退出
            if page.matchResults.isEmpty { break }
        } while cursor != nil

        return deleted
    }

    /// 批量删除，分片以遵守 CloudKit 单次 400 条的上限。
    private static func delete(ids: [CKRecord.ID], database: CKDatabase) async throws -> Int {
        var deleted = 0
        var index = 0
        while index < ids.count {
            let end = min(index + deleteBatchSize, ids.count)
            let batch = Array(ids[index..<end])
            let (_, deleteResults) = try await database.modifyRecords(
                saving: [],
                deleting: batch,
                savePolicy: .changedKeys,
                atomically: false
            )
            // 修复（2026-10-14 审查 P1-7 + T8）：分类逻辑抽成纯函数，既修 bug 又可被单测覆盖
            // （此前该分支零测试，部分失败被当成功的回归无人守）。
            let outcome = Self.classifyDeleteResults(deleteResults)
            deleted += outcome.deleted
            // 有真实失败即抛出 → 由 purgeAll 走「云端失败即中止，本地数据保持原样」契约
            if let failure = outcome.failure { throw failure }
            index = end
        }
        return deleted
    }

    /// `modifyRecords(atomically: false)` 的逐条结果分类（抽成纯函数以便单测）
    ///
    /// - `unknownItem`（记录已被其它设备删除）视为已删除，不计失败；
    /// - 其余失败一律上报 → 触发「云端失败即中止」契约。
    static func classifyDeleteResults(
        _ results: [CKRecord.ID: Result<Void, any Error>]
    ) -> (deleted: Int, failure: Error?) {
        var deleted = 0
        var failure: Error?
        for (_, result) in results {
            switch result {
            case .success:
                deleted += 1
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .unknownItem {
                    deleted += 1
                } else if failure == nil {
                    failure = error
                }
            }
        }
        return (deleted, failure)
    }

    // MARK: - 错误

    enum PurgeError: LocalizedError {
        case notSignedIn
        case restricted
        case indeterminate

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return L10n.shared.云端未登录
            case .restricted:
                return L10n.shared.云端受限
            case .indeterminate:
                return L10n.shared.云端状态未知
            }
        }
    }

    /// 把错误转成面向用户的中文文案。
    ///
    /// 判据收口（2026-10-14 审查 P1-3）：**返回空串 = 不是云端错误**，调用方据此走本地
    /// 失败分支。旧实现对任何非 CKError 一律返回「云端清除失败」，导致本地失败
    /// （如 store 重载失败）被显示成云端错误并附「本机数据未做任何改动」的假说明；
    /// 同时 `PurgeError` 的专属文案（未登录/受限/状态未知）因不匹配 CKError 而永不可达。
    static func userMessage(for error: Error) -> String {
        if let purgeError = error as? PurgeError {
            return purgeError.errorDescription ?? L10n.shared.云端清除失败
        }
        if let ckError = error as? CKError {
            switch ckError.code {
            case .notAuthenticated:
                return L10n.shared.云端未登录
            case .networkUnavailable, .networkFailure:
                return L10n.shared.云端网络错误
            case .zoneNotFound:
                // 云端本来就没有数据，等于清除成功
                return ""
            case .limitExceeded, .quotaExceeded:
                return L10n.shared.云端容量超限
            default:
                // recordType 从未同步上云（schema 无此 type）= 无数据可清，兜底同 zoneNotFound
                if isRecordTypeMissing(error) { return "" }
                return String(format: L10n.shared.云端清除失败原因, ckError.localizedDescription)
            }
        }
        return ""
    }

    private static func error(_ e: PurgeError) -> Error { e }
    private static func fail(_ error: Error, _ completion: @escaping (Result<Int, Error>) -> Void) {
        DispatchQueue.main.async { completion(.failure(error)) }
    }
}