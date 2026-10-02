import Foundation
import AppIntents

// MARK: - FlowTakt AppIntents（快捷指令 / Siri，B1）
// AppDependency.shared 由 App 入口初始化时注册，intent 经其访问运行中的 VM。
// 注意：不要给 intent 结构体标注 @MainActor——AppIntent.perform 本身在 main actor 上执行，
// 标注会与 AppShortcutsProvider（nonisolated）冲突并产生并发警告。

// MARK: 开始专注

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "开始专注"
    static var description = IntentDescription("开始一个番茄钟专注时段")

    /// 专注时长（分钟），快捷指令中可配置
    @Parameter(title: "时长（分钟）", default: 25)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("开始 \(\.$minutes) 分钟专注")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let dependency = AppDependency.shared else {
            return .result()
        }
        let clamped = min(max(1, minutes), 480)   // 钳制 1...480 分钟（审查 #18）
        let duration = TimeInterval(clamped * 60)
        dependency.focusViewModel.startFocus(phase: .focus, durationOverride: duration)
        return .result()
    }
}

// MARK: 停止专注

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "停止专注"
    static var description = IntentDescription("停止并放弃当前专注时段")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDependency.shared?.focusViewModel.abandonSession()
        return .result()
    }
}

// MARK: 快捷指令注册

struct FlowTaktShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "在 ${applicationName} 中开始专注",
                "用 ${applicationName} 开始一个番茄钟",
            ],
            shortTitle: "开始专注",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: [
                "在 ${applicationName} 中停止专注",
                "让 ${applicationName} 结束专注",
            ],
            shortTitle: "停止专注",
            systemImageName: "stop.fill"
        )
    }
}
