import Foundation
import AppIntents

// MARK: - 专注控制 Intents（App 与 Widget 共享，2026-10-14）
//
// 为什么放在 FlowTaktShared：灵动岛 / 锁屏 Live Activity 的交互按钮
// （Button(intent:)）要求 Intent 类型对 Widget 扩展可见 —— 本文件同时编入
// App 与 Widget 两个 target。
//
// 为什么经 FocusControlBridge 而非直接访问 AppDependency：本文件编入 Widget
// 模块时 AppDependency（App 专属类型）不存在，直接引用无法通过编译。
// 按钮点击由系统在 **App 进程** 内执行 perform → 访问 App 模块中注册的闭包，
// 再经 FocusViewModel 更新计时与 Live Activity。Widget 模块中的副本永不执行
// （若意外执行，闭包为 nil，安全 no-op）。
//
// 注意：不要给 intent 结构体标注 @MainActor —— AppIntent.perform 本身在 main
// actor 上执行，标注结构体会与 AppShortcutsProvider（nonisolated）冲突产生
// 并发警告（既有约定，见 FlowTaktIntents.swift）。

/// 控制桥：App 启动时（AppDependency.init）注册真实实现
enum FocusControlBridge {
    static var pause: (() -> Void)?
    static var resume: (() -> Void)?
    static var stop: (() -> Void)?
}

// MARK: 暂停专注

struct PauseFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "暂停专注"
    static var description = IntentDescription("暂停当前专注计时，可随时继续")

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.pause?()
        return .result()
    }
}

// MARK: 继续专注

struct ResumeFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "继续专注"
    static var description = IntentDescription("继续被暂停的专注计时")

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.resume?()
        return .result()
    }
}

// MARK: 停止专注

struct StopFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "停止专注"
    static var description = IntentDescription("停止并放弃当前专注时段")

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.stop?()
        return .result()
    }
}

// MARK: - Live Activity 专用变体（iOS 17+，供灵动岛 / 锁屏卡片按钮）
//
// 为什么需要单独一套（2026-10-14，实测踩坑）：
// 普通 AppIntent 在 Live Activity 按钮中被系统放到 **Widget 扩展进程**执行
// （该进程的 FocusControlBridge 为 nil → 按钮点了没反应）。
// Apple 文档《Adding interactivity to widgets and Live Activities》：
// Live Activity 交互必须采用 LiveActivityIntent 协议，系统会把执行路由到 App 进程。
// 上面三个普通变体保持 AppIntent —— 供 Siri / 快捷指令使用（其执行本就在 App 进程），
// 并保留 AppShortcutsProvider 的 Siri 短语注册。

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
struct PauseFocusLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "暂停专注"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.pause?()
        return .result()
    }
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
struct ResumeFocusLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "继续专注"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.resume?()
        return .result()
    }
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
struct StopFocusLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停止专注"

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusControlBridge.stop?()
        return .result()
    }
}
