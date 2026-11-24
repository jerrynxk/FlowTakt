import Foundation

// MARK: - ServiceErrorReporter
// 修复（2026-10-14 审查 P2）：`FocusService` / `TaskService` / `AchievementService` 都声明了
// `onError: ((Error) -> Void)?`，但**全仓没有任何赋值点** —— 契约存在却从未接线，
// save 失败只落进 `print`，调用方（ViewModel / UI）完全不知情。
//
// 本类给出唯一实现：把 Service 层错误统一收敛为「可被观测」的事件。
// 之所以不直接弹 toast：Service 是 @MainActor 且可能被后台任务（BGTask / CloudKit 回调）
// 调用，弹窗时机不可控；UI 提示应由 ViewModel 决定是否呈现。
// 后续若要做用户可见提示，可在 ViewModel 订阅 `NotificationCenter` 的
// `.serviceDidReportError` 通知后自行决定。

final class ServiceErrorReporter {
    static let shared = ServiceErrorReporter()

    /// Service 层错误广播名（ViewModel 可订阅以便提示用户）
    static let notificationName = Notification.Name("FlowTaktServiceDidReportError")

    private init() {}

    /// 记录并广播一条 Service 层错误
    func report(_ error: Error, context: String) {
        let message = "⚠️ [\(context)] \(error.localizedDescription)"
        print(message)
        // 开发期断点友好：把最近一次错误暴露出来，便于 UI 层读取
        lastError = error
        lastContext = context
        NotificationCenter.default.post(name: Self.notificationName, object: error,
                                        userInfo: ["context": context])
    }

    /// 最近一次 Service 层错误（供 UI 读取）
    private(set) var lastError: Error?
    private(set) var lastContext: String?

    /// 清空最近一次错误（UI 已处理后调用）
    func clear() {
        lastError = nil
        lastContext = nil
    }
}
