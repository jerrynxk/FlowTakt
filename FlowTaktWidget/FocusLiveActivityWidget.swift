import WidgetKit
import SwiftUI
import ActivityKit
// Button(intent:) 的 init 定义于 AppIntents —— 新 SDK 的 MemberImportVisibility
// 要求使用处显式 import 定义模块（仅经共享文件间接引用不够）
import AppIntents

// MARK: - 专注 Live Activity（灵动岛 + 锁屏）★ 2026-10-14
//
// 数据流：FocusViewModel 状态流转 → FocusLiveActivity 门面 → LiveActivityManager
//        → ActivityContent 更新 → 本文件视图渲染。
// 倒计时为系统级组件（Text / ProgressView 的 timerInterval 初值器），锁屏与灵动岛
// 自动走时，无需后台推送或定时刷新。
// 交互按钮（暂停/继续/停止，iOS 17+）所需 Intent 定义于 FlowTaktShared/FocusControlIntents.swift。

// MARK: - 阶段样式（与 App 端 Color.forPhase / FocusPhaseBadge 对齐）

enum FocusActivityStyle {
    /// 与 App 端一致：专注 focusRed / 短休 breakGreen / 长休 longBreakBlue
    static func color(for raw: String) -> Color {
        switch raw {
        case "shortBreak": return Color(red: 0.20, green: 0.78, blue: 0.50)
        case "longBreak":  return Color(red: 0.24, green: 0.55, blue: 0.91)
        default:           return Color(red: 0.94, green: 0.30, blue: 0.25)
        }
    }

    /// 与 App 端 FocusPhaseBadge 同一组图标
    static func icon(for raw: String) -> String {
        switch raw {
        case "shortBreak": return "cup.and.saucer.fill"
        case "longBreak":  return "moon.stars.fill"
        default:           return "flame.fill"
        }
    }

    static func name(for raw: String) -> String {
        let en = WidgetLanguage.isEnglish
        switch raw {
        case "shortBreak": return en ? "Short Break" : "短休息"
        case "longBreak":  return en ? "Long Break" : "长休息"
        default:           return en ? "Focus" : "专注"
        }
    }

    /// 静态时间文本（暂停 / 完成态用）
    static func timeText(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Widget 定义

@available(iOSApplicationExtension 16.2, *)
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            // 锁屏 / 横幅卡片
            FocusActivityLockScreenView(context: context)
                .activitySystemActionForegroundColor(FocusActivityStyle.color(for: context.state.phaseRaw))
                .widgetURL(URL(string: "flowtakt://focus"))
        } dynamicIsland: { context in
            let phaseColor = FocusActivityStyle.color(for: context.state.phaseRaw)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: FocusActivityStyle.icon(for: context.state.phaseRaw))
                            .font(.caption)
                            .foregroundColor(phaseColor)
                        Text(FocusActivityStyle.name(for: context.state.phaseRaw))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusActivityTimeText(state: context.state,
                                          font: .system(.title3, design: .rounded).weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    if let task = context.state.taskTitle {
                        Text(task)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        FocusActivityProgressBar(state: context.state)
                        if #available(iOS 17.0, *) {
                            FocusActivityControls(state: context.state)
                        }
                    }
                }
            } compactLeading: {
                // 2026-10-15 终局修复（用户对照系统计时器实拍确认）：
                // iOS 26 的胶囊宽度**随内容自适应扩展**（"the pill expands to show it"）——
                // 「专注」二字（2 个汉字）把胶囊撑宽约 20%（系统计时器纯图标+短时间 ≈ 51% 屏宽，
                // 含文字版 ≈ 70%）。恢复纯图标（10-14 的正确方向），只保留阶段图形。
                // 阶段文字信息保留在展开态与锁屏卡片中，紧凑态不承载文字。
                Image(systemName: FocusActivityStyle.icon(for: context.state.phaseRaw))
                    .foregroundColor(phaseColor)
            } compactTrailing: {
                // 紧凑态仅保留"圆环 + 数字"（不可交互——点击穿透为打开 App，符合系统规则）。
                // 注意：勿改回 Text(timerInterval:)/Text(.timer)——自动计时文本会撑宽胶囊，
                // 详见 CompactActivityTimeText 头注释（2026-10-15 四轮对照实验结论）。
                CompactActivityTimeText(state: context.state)
            } minimal: {
                Image(systemName: FocusActivityStyle.icon(for: context.state.phaseRaw))
                    .foregroundColor(phaseColor)
            }
            .keylineTint(phaseColor)
            .widgetURL(URL(string: "flowtakt://focus"))
        }
    }
}

// MARK: - 锁屏卡片

@available(iOSApplicationExtension 16.2, *)
private struct FocusActivityLockScreenView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    private var phaseColor: Color { FocusActivityStyle.color(for: context.state.phaseRaw) }

    var body: some View {
        VStack(spacing: 10) {
            // 第一行：阶段徽章 + 关联任务（无任务时显示状态词）
            HStack(spacing: 6) {
                Image(systemName: FocusActivityStyle.icon(for: context.state.phaseRaw))
                    .font(.footnote)
                Text(FocusActivityStyle.name(for: context.state.phaseRaw))
                    .font(.footnote.weight(.semibold))

                Spacer(minLength: 8)

                if let task = context.state.taskTitle {
                    Text(task)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .foregroundColor(phaseColor)

            // 第二行：大时间 + 控制按钮（iOS 17+）
            HStack(alignment: .center) {
                FocusActivityTimeText(state: context.state,
                                      font: .system(size: 38, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                if #available(iOS 17.0, *) {
                    // 修复（2026-10-15）：按钮组优先保持完整（layoutPriority 1；组件内含
                    // fixedSize）——空间不足时由大时间先缩放（其内部 minimumScaleFactor 0.6）。
                    // 旧实现下 HStack 压缩了「停止」按钮 → 文字换行两行、按钮变形（16 Pro 复现）
                    FocusActivityControls(state: context.state)
                        .layoutPriority(1)
                }
            }

            FocusActivityProgressBar(state: context.state)
        }
        .padding(14)
    }

    private var statusText: String {
        let en = WidgetLanguage.isEnglish
        if context.state.isFinished { return en ? "Completed" : "已完成" }
        if context.state.isPaused { return en ? "Paused" : "已暂停" }
        return en ? "Focusing" : "进行中"
    }
}

// MARK: - 复用子视图

/// 大时间文本：运行中为系统级倒计时；暂停 / 完成时静态展示
@available(iOSApplicationExtension 16.2, *)
private struct FocusActivityTimeText: View {
    let state: FocusActivityAttributes.ContentState
    var font: Font = .system(.largeTitle, design: .rounded).weight(.bold)

    var body: some View {
        Group {
            if state.isFinished {
                Text(WidgetLanguage.isEnglish ? "Completed" : "已完成")
            } else if state.isPaused {
                Text(FocusActivityStyle.timeText(seconds: state.pausedRemaining))
            } else {
                Text(timerInterval: state.startDate...state.endDate,
                     countsDown: true,
                     showsHours: false)
            }
        }
        .font(font)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// 灵动岛紧凑尾区内容（2026-10-15 终版：自动走秒数字 + 强制限宽）
///
/// **四轮对照实验的最终结论**（用户实拍对比系统计时器后定位）：
/// - `Text(timerInterval:)` / `Text(_, style: .timer)` 等"**自动计时文本**"默认会让系统
///   按"全宽级"预留灵动岛胶囊宽度（这是"灵动岛太宽"的根因；系统计时器等系统 App 用
///   私有渲染故不受影响）
/// - **给自动计时文本加 `.frame(maxWidth:)` 限宽即可解除该预留** —— 胶囊收缩到与系统
///   计时器同级的窄形态，且**不影响自动走秒**（实测 5 秒间隔精准推进）
/// - （备选形态：`ProgressView(timerInterval:)` 圆环亦窄且系统驱动；最终按用户偏好用"图标+数字"）
@available(iOSApplicationExtension 16.2, *)
private struct CompactActivityTimeText: View {
    let state: FocusActivityAttributes.ContentState

    /// 时间文本限宽：mm:ss 最长 "59:59"（5 字符 @13pt ≈ 44pt），56pt 留渲染余量
    private static let trailingTextMaxWidth: CGFloat = 56

    var body: some View {
        Group {
            if state.isFinished {
                Image(systemName: "checkmark.circle.fill")
            } else if state.isPaused {
                // 暂停：静态剩余时间（冻结值；静态文本再加限宽作统一防护）
                Text(FocusActivityStyle.timeText(seconds: state.pausedRemaining))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: Self.trailingTextMaxWidth, alignment: .trailing)
            } else {
                // 运行：自动走秒倒计时（限宽解除系统"全宽预留"）
                Text(timerInterval: state.startDate...state.endDate,
                     countsDown: true,
                     showsHours: false)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: Self.trailingTextMaxWidth, alignment: .trailing)
            }
        }
        .foregroundColor(FocusActivityStyle.color(for: state.phaseRaw))
    }
}

/// 进度条（2026-10-15 改版）
///
/// 运行态改用**系统驱动的 `ProgressView(timerInterval:)`**：随系统时钟自动推进，
/// 不再依赖 App 侧每 30s 的 activity.update()（更新会触发系统"短暂展开灵动岛"，
/// 导致灵动岛周期性闪宽卡——用户反馈"总是很宽"的根因）。
/// 区间起点由 `FocusActivityAttributes.normalizedStartDate` 反推（endDate - 总时长），
/// 保证「暂停 → 继续」后进度比例仍是（已用 / 总长），不跳变。
/// 暂停 / 完成态保持静态自绘（无推进语义）。
@available(iOSApplicationExtension 16.2, *)
private struct FocusActivityProgressBar: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isFinished || state.isPaused {
                ProgressView(value: staticProgressValue)
            } else {
                ProgressView(timerInterval: state.startDate...state.endDate)
            }
        }
        .tint(FocusActivityStyle.color(for: state.phaseRaw))
        .labelsHidden()
        // 无障碍补齐（2026-11-02）：labelsHidden 后进度条在读屏里没有名称，
        // 只会念「进度 40%」，补上语义标签
        .accessibilityLabel(WidgetLanguage.isEnglish ? "Focus progress" : "专注进度")
    }

    /// 静态进度（暂停 / 完成）：1 - 剩余 / 总长
    private var staticProgressValue: Double {
        if state.isFinished { return 1 }
        let total = max(1, state.totalDuration)
        let remaining = max(0, state.pausedRemaining)
        return min(1, max(0, 1 - remaining / total))
    }
}

/// 交互按钮（iOS 17+；LiveActivityIntent 协议要求 iOS 17 起——
/// 系统将按钮执行路由到 App 进程，见 FlowTaktShared/FocusControlIntents.swift 头注释）
@available(iOS 17.0, iOSApplicationExtension 17.0, *)
private struct FocusActivityControls: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        if !state.isFinished {
            HStack(spacing: 10) {
                if state.isPaused {
                    Button(intent: ResumeFocusLiveActivityIntent()) {
                        Label(WidgetLanguage.isEnglish ? "Resume" : "继续", systemImage: "play.fill")
                            .lineLimit(1)
                    }
                    .tint(FocusActivityStyle.color(for: state.phaseRaw))
                } else {
                    Button(intent: PauseFocusLiveActivityIntent()) {
                        Label(WidgetLanguage.isEnglish ? "Pause" : "暂停", systemImage: "pause.fill")
                            .lineLimit(1)
                    }
                    .tint(FocusActivityStyle.color(for: state.phaseRaw))
                }

                Button(intent: StopFocusLiveActivityIntent()) {
                    Label(WidgetLanguage.isEnglish ? "Stop" : "停止", systemImage: "stop.fill")
                        .lineLimit(1)
                }
                .tint(.red)
            }
            .buttonStyle(.bordered)
            // 修复（2026-10-15 锁屏排版）：按钮组禁止被压缩（Label 亦 lineLimit(1) 双重兜底），
            // 防止「停止」按钮在窄卡片上被 HStack 挤压缩小、文字换行两行（16 Pro 复现）
            .fixedSize()
        }
    }
}
