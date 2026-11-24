import Foundation
#if canImport(ActivityKit)
import ActivityKit

// MARK: - 专注 Live Activity 属性（App 与 Widget 共享，2026-10-14）
//
// 归属 FlowTaktShared：App 与 Widget 两个 target 都编译本文件（同步文件夹成员），
// Widget 端用 ActivityConfiguration(for:) 渲染，App 端用 Activity 发起/更新。
//
// 设计：静态属性仅含 sessionID；阶段、暂停、时间等全部放入 ContentState ——
// 「专注 → 休息」跨阶段时更新同一 Activity，无需中止重建。
//
// 部署目标 iOS 16.0 < ActivityKit 要求的 16.2，故类型与所有使用处均带可用性标注。
// （16.1 亦可运行 Live Activity，但其 API 不支持 staleDate/dismissalPolicy 等能力，
//  16.2 起 API 完整，统一按 16.2 起步。）
//
// nonisolated：App target 开启了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，
// 默认隔离会让本类型的 ActivityAttributes 遵循被推断为主线程隔离，
// 而 ActivityKit 在 @concurrent 上下文使用该遵循 → 触发
// 「main actor-isolated conformance cannot be used in @concurrent context」警告
// （Swift 6 模式下为错误）。显式 nonisolated 使遵循脱离主线程隔离。

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
nonisolated struct FocusActivityAttributes: ActivityAttributes {

    /// 动态内容（每次状态流转整体更新）
    public struct ContentState: Codable, Hashable {
        /// 阶段原始值："focus" / "shortBreak" / "longBreak"
        /// （用 String 而非 App 侧 FocusPhase，避免共享层依赖 App 目标类型）
        var phaseRaw: String
        /// 是否暂停中（暂停时静态展示 pausedRemaining）
        var isPaused: Bool
        /// 是否已完成（结束前保留 30s 的「已完成」展示态）
        var isFinished: Bool
        /// 本段计时起点（运行中：驱动系统级倒计时 Text/ProgressView 的 timerInterval）
        var startDate: Date
        /// 预计结束时间（运行中有效）
        var endDate: Date
        /// 暂停时剩余秒数（暂停态静态显示用）
        var pausedRemaining: TimeInterval
        /// 本段**计划总时长**（秒）。
        ///
        /// 修复（2026-10-14 审查 P1-13）：暂停→继续后 App 侧会用「现在 → 现在+剩余」
        /// 重建 startDate/endDate，若进度条仍按 `timerInterval` 区间渲染就会从 0 重新推进
        /// （每次恢复都跳变）。改为记录真实总时长，进度条自绘 `1 - remaining / totalDuration`，
        /// 跨暂停/恢复保持连续。
        var totalDuration: TimeInterval
        /// 关联任务标题（可选，展示在灵动岛展开态与锁屏卡片）
        var taskTitle: String?

        /// 解码兜底（修复 2026-10-14 P2）：Swift 合成的 `init(from:)` 对缺失键抛
        /// keyNotFound，且**不会**使用属性默认值 —— 给 ContentState 加字段因此成为破坏性变更。
        /// 显式实现后，新增字段对旧活动解码透明。
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            phaseRaw = try c.decode(String.self, forKey: .phaseRaw)
            isPaused = try c.decode(Bool.self, forKey: .isPaused)
            isFinished = try c.decode(Bool.self, forKey: .isFinished)
            startDate = try c.decode(Date.self, forKey: .startDate)
            endDate = try c.decode(Date.self, forKey: .endDate)
            pausedRemaining = try c.decode(TimeInterval.self, forKey: .pausedRemaining)
            totalDuration = try c.decodeIfPresent(TimeInterval.self, forKey: .totalDuration) ?? 0
            taskTitle = try c.decodeIfPresent(String.self, forKey: .taskTitle)
        }

        public init(phaseRaw: String, isPaused: Bool, isFinished: Bool, startDate: Date,
                    endDate: Date, pausedRemaining: TimeInterval, totalDuration: TimeInterval,
                    taskTitle: String?) {
            self.phaseRaw = phaseRaw
            self.isPaused = isPaused
            self.isFinished = isFinished
            self.startDate = startDate
            self.endDate = endDate
            self.pausedRemaining = pausedRemaining
            self.totalDuration = totalDuration
            self.taskTitle = taskTitle
        }
    }

    /// 会话标识（发起时生成的 UUID 字符串；同一时刻仅维护一个活动）
    var sessionID: String
}

// MARK: - 运行态区间修正（2026-10-15）

@available(iOS 16.2, iOSApplicationExtension 16.2, *)
extension FocusActivityAttributes {
    /// 反推运行态的区间起点：`endDate - totalDuration`。
    ///
    /// 背景（2026-10-15 修复「灵动岛总是很宽」）：进度条曾依赖 App 侧每 30s 的
    /// `activity.update()` 定时推进，而 **iOS 在每次活动更新后会短暂展示灵动岛展开态**
    /// → 灵动岛周期性"闪宽卡"，用户几乎总能看到宽条。
    /// 现改为系统驱动的 `ProgressView(timerInterval: startDate...endDate)`（无需 update）：
    /// 区间长度必须等于计划总时长、且起点反映真实已用时长（含暂停冻结），
    /// 否则「暂停 → 继续」后进度比例错误（P1-13 原始问题的根治方案）。
    /// 全新开始时 endDate = now + totalDuration，反推结果 ≈ now，无副作用。
    static func normalizedStartDate(endDate: Date, totalDuration: TimeInterval) -> Date {
        endDate.addingTimeInterval(-max(1, totalDuration))
    }
}
#endif
