import UIKit
import SwiftUI

// MARK: - 触觉反馈管理器

final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)
    private let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let heavyGenerator = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private let selectionGenerator = UISelectionFeedbackGenerator()

    private init() {
        lightGenerator.prepare()
        mediumGenerator.prepare()
        heavyGenerator.prepare()
        notificationGenerator.prepare()
        selectionGenerator.prepare()
    }

    /// 轻微震动（按钮交互）
    func lightImpact() {
        lightGenerator.impactOccurred()
    }

    /// 中等震动（重要操作）
    func mediumImpact() {
        mediumGenerator.impactOccurred()
    }

    /// 强震动（警告/错误）
    func heavyImpact() {
        heavyGenerator.impactOccurred()
    }

    /// 通知反馈（成功/失败/警告）
    func notificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
    }

    /// 选择反馈（列表滚动/切换）
    func selectionFeedback() {
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
