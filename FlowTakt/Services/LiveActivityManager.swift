import Foundation
import ActivityKit

// MARK: - 灵动岛 / 锁屏 Live Activity 管理（2026-10-14）
//
// 架构说明（有意决策）：
// 1. 采用单例而非「Service + Protocol 注入」——与 HapticManager 同类，属于系统能力
//    桥接、无业务分支；ActivityKit 在单元测试环境不可用（无断言价值），且避免为
//    FocusViewModel 的全部构造点（Preview/测试约 15 处）改造 init 签名。
// 2. 业务代码（FocusViewModel）一律经 FocusLiveActivity 门面调用——内部处理
//    iOS 16.2 可用性判断，调用点不做版本分支。
// 3. 本模块存在 Core Data 实体 `Task` 遮蔽并发的 `Task`，异步一律写 `Swift.Task`。
//
// 生命周期契约：同一时刻仅维护一个活动（current 取 activities.first）。
// 开始/恢复/跨阶段 → startOrUpdate；暂停 → updatePaused；放弃/切阶段/重置 → end；
// 自然完成 → endCompleted（保留「已完成」30s）。staleDate = endDate，
// 即使 App 被挂起无法在结束时更新，系统也会在到点后将其置为过期态。

@available(iOS 16.2, *)
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    // 修复（2026-10-15，「灵动岛总是很宽」）：
    // 曾用 `advanceTimer` 每 30s 发一次 activity.update() 驱动进度条推进 ——
    // 而 **iOS 在每次活动更新后会短暂展示灵动岛展开态**（系统行为，用于提示更新）
    // → 灵动岛每 30 秒"闪一次宽卡"，用户几乎总能看到宽条。
    // 现删除定时 update：进度条改为系统驱动的 ProgressView(timerInterval:)（自动推进），
    // 展开态只在用户真实操作（开始/暂停/恢复/停止）时短暂出现 —— 符合系统设计意图。

    /// 当前活动（仅维护一个）
    private var current: Activity<FocusActivityAttributes>? {
        Activity<FocusActivityAttributes>.activities.first
    }

    /// 开始 / 更新（运行中）：已存在活动则更新，否则新建
    func startOrUpdate(phaseRaw: String, startDate: Date, endDate: Date,
                       totalDuration: TimeInterval, taskTitle: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = FocusActivityAttributes.ContentState(
            phaseRaw: phaseRaw,
            isPaused: false,
            isFinished: false,
            // 区间起点反推（2026-10-15）：endDate - 计划总时长，保证系统驱动的
            // ProgressView(timerInterval:) 比例 = 已用/总长（含暂停冻结），详情见
            // FocusActivityAttributes.normalizedStartDate
            startDate: FocusActivityAttributes.normalizedStartDate(
                endDate: endDate, totalDuration: totalDuration),
            endDate: endDate,
            pausedRemaining: 0,
            totalDuration: max(1, totalDuration),
            taskTitle: taskTitle
        )
        if let activity = current {
            Swift.Task {
                await activity.update(ActivityContent(state: state, staleDate: endDate))
            }
        } else {
            do {
                _ = try Activity<FocusActivityAttributes>.request(
                    attributes: FocusActivityAttributes(sessionID: UUID().uuidString),
                    content: ActivityContent(state: state, staleDate: endDate),
                    pushType: nil
                )
            } catch {
                print("⚠️ Live Activity 启动失败：\(error.localizedDescription)")
            }
        }
    }

    /// 暂停态：无活动则创建（供冷启动恢复暂停会话使用），有活动则更新
    func startOrUpdatePaused(phaseRaw: String, remaining: TimeInterval,
                             totalDuration: TimeInterval, taskTitle: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let previous = current?.content.state
        let state = FocusActivityAttributes.ContentState(
            phaseRaw: phaseRaw,
            isPaused: true,
            isFinished: false,
            startDate: previous?.startDate ?? Date(),
            endDate: Date().addingTimeInterval(max(0, remaining)),
            pausedRemaining: max(0, remaining),
            totalDuration: totalDuration > 0 ? totalDuration
                : (previous?.totalDuration ?? max(1, remaining)),
            taskTitle: taskTitle
        )
        if let activity = current {
            Swift.Task {
                await activity.update(ActivityContent(state: state, staleDate: previous?.endDate))
            }
        } else {
            do {
                _ = try Activity<FocusActivityAttributes>.request(
                    attributes: FocusActivityAttributes(sessionID: UUID().uuidString),
                    // staleDate 有意为 nil（2026-10-15 审查 P2-L1 澄清）：暂停态没有
                    // 未来的 endDate，若沿用 previous?.endDate（已过时刻）会被系统
                    // 立即标记 stale 并淡化展示。nil = 常驻至手动结束/恢复。
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                print("☁️ 已为暂停中的会话重建 Live Activity")
            } catch {
                print("⚠️ 暂停态 Live Activity 创建失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 状态流转

    /// 暂停：冻结剩余时间，静态展示
    func updatePaused(phaseRaw: String, remaining: TimeInterval,
                      totalDuration: TimeInterval, taskTitle: String?) {
        guard let activity = current else { return }
        let previous = activity.content.state
        let state = FocusActivityAttributes.ContentState(
            phaseRaw: phaseRaw,
            isPaused: true,
            isFinished: false,
            startDate: previous.startDate,
            endDate: previous.endDate,
            pausedRemaining: max(0, remaining),
            totalDuration: totalDuration > 0 ? totalDuration : previous.totalDuration,  // 暂停可能先于本字段引入
            taskTitle: taskTitle
        )
        Swift.Task {
            // 修复（P2-27）：暂停态也按 endDate 置过期，避免 App 被挂起后活动长时间滞留
            await activity.update(ActivityContent(state: state, staleDate: previous.endDate))
        }
    }

    /// 结束（放弃 / 切换阶段 / 重置数据库）：立即移除
    func end() {
        guard let activity = current else { return }
        Swift.Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// 结束（自然完成）：保留「已完成」30s 后自动消失
    func endCompleted(phaseRaw: String, taskTitle: String?) {
        guard let activity = current else { return }
        let previousTotal = activity.content.state.totalDuration
        let finished = FocusActivityAttributes.ContentState(
            phaseRaw: phaseRaw,
            isPaused: false,
            isFinished: true,
            startDate: Date(),
            endDate: Date(),
            pausedRemaining: 0,
            totalDuration: previousTotal,   // 保留真实总长，供完成态展示
            taskTitle: taskTitle
        )
        Swift.Task {
            await activity.end(
                // staleDate 有意为 nil（2026-10-15 审查 P2-L1 澄清）：完成态由下方
                // dismissalPolicy(.after(+30s)) 兜底移除，staleDate 不再承担职责。
                ActivityContent(state: finished, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30))
            )
        }
    }
}

// MARK: - 版本门面（调用点无版本负担）

/// 业务代码统一经此门面；内部完成 iOS 16.2 可用性判断
enum FocusLiveActivity {
    static func startOrUpdate(phaseRaw: String, startDate: Date, endDate: Date,
                              totalDuration: TimeInterval, taskTitle: String?) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.startOrUpdate(
                phaseRaw: phaseRaw, startDate: startDate, endDate: endDate,
                totalDuration: totalDuration, taskTitle: taskTitle
            )
        }
    }

    static func updatePaused(phaseRaw: String, remaining: TimeInterval,
                             totalDuration: TimeInterval, taskTitle: String?) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.updatePaused(
                phaseRaw: phaseRaw, remaining: remaining,
                totalDuration: totalDuration, taskTitle: taskTitle
            )
        }
    }

    /// 暂停态：不存在活动时会创建（冷启动恢复暂停会话的场景）
    static func startOrUpdatePaused(phaseRaw: String, remaining: TimeInterval,
                                    totalDuration: TimeInterval, taskTitle: String?) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.startOrUpdatePaused(
                phaseRaw: phaseRaw, remaining: remaining,
                totalDuration: totalDuration, taskTitle: taskTitle
            )
        }
    }

    static func end() {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.end()
        }
    }

    static func endCompleted(phaseRaw: String, taskTitle: String?) {
        if #available(iOS 16.2, *) {
            LiveActivityManager.shared.endCompleted(phaseRaw: phaseRaw, taskTitle: taskTitle)
        }
    }
}
