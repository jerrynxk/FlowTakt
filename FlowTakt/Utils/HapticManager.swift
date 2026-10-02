import UIKit
import SwiftUI

// MARK: - 触觉反馈管理器

final class HapticManager {
    static let shared = HapticManager()

    // 崩溃修复（2026-10-02）：5 个 `lazy` 生成器在首次访问时初始化，
    // `lazy` 的首次初始化若发生在非主线程，会在后台线程创建 UIKit 对象（未定义行为）。
    // 所有调用点当前均在主线程，此处加断言固化该约束。
    // 注：未直接标注 @MainActor —— 那会级联要求全部 8 处调用点
    // （含 XCTestCase 子类）一并标注，危及「0 编译警告」基线。
    private lazy var lightGenerator = Self.makeGenerator(.light)
    private lazy var mediumGenerator = Self.makeGenerator(.medium)
    private lazy var heavyGenerator = Self.makeGenerator(.heavy)
    private lazy var notificationGenerator = Self.makeNotificationGenerator()
    private lazy var selectionGenerator = Self.makeSelectionGenerator()

    private init() {}

    /// 在主线程创建触觉生成器，并断言调用线程。
    private static func makeGenerator(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        dispatchPrecondition(condition: .onQueue(.main))
        return UIImpactFeedbackGenerator(style: style)
    }

    private static func makeNotificationGenerator() -> UINotificationFeedbackGenerator {
        dispatchPrecondition(condition: .onQueue(.main))
        return UINotificationFeedbackGenerator()
    }

    private static func makeSelectionGenerator() -> UISelectionFeedbackGenerator {
        dispatchPrecondition(condition: .onQueue(.main))
        return UISelectionFeedbackGenerator()
    }

    /// 预准备所有生成器（可在 App 启动后调用，减少首次触觉延迟）
    func prepareForUse() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// 轻微震动（按钮交互）
    func lightImpact() {
        lightGenerator.prepare()
        lightGenerator.impactOccurred()
    }

    /// 中等震动（重要操作）
    func mediumImpact() {
        mediumGenerator.prepare()
        mediumGenerator.impactOccurred()
    }

    /// 强震动（警告/错误）
    func heavyImpact() {
        heavyGenerator.prepare()
        heavyGenerator.impactOccurred()
    }

    /// 通知反馈（成功/失败/警告）
    func notificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.prepare()
        notificationGenerator.notificationOccurred(type)
    }

    /// 选择反馈（列表滚动/切换）
    func selectionFeedback() {
        selectionGenerator.prepare()
        selectionGenerator.selectionChanged()
    }

    /// 专注完成时的成功反馈
    func focusComplete() {
        notificationFeedback(type: .success)
    }

    /// 专注中断时的警告反馈
    func focusInterrupted() {
        notificationFeedback(type: .warning)
    }
}
