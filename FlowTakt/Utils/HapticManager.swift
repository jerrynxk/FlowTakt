import UIKit
import SwiftUI

// MARK: - 触觉反馈管理器

final class HapticManager {
    static let shared = HapticManager()

    private init() {}

    /// 轻微震动（按钮交互）
    func lightImpact() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// 中等震动（重要操作）
    func mediumImpact() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    /// 强震动（警告/错误）
    func heavyImpact() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    /// 通知反馈（成功/失败/警告）
    func notificationFeedback(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    /// 选择反馈（列表滚动/切换）
    func selectionFeedback() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
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
