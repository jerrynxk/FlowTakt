import SwiftUI
import UIKit

// MARK: - 颜色扩展

extension Color {
    /// 专注阶段颜色 - 专注（番茄红）
    static let focusRed = Color(red: 0.94, green: 0.30, blue: 0.25)
    /// 专注阶段颜色 - 短休息（薄荷绿）
    static let breakGreen = Color(red: 0.20, green: 0.78, blue: 0.50)
    /// 专注阶段颜色 - 长休息（天空蓝）
    static let longBreakBlue = Color(red: 0.24, green: 0.55, blue: 0.91)
    /// 背景色（浅灰）
    static let appBackground = Color(.systemGroupedBackground)

    /// 卡片内嵌控件底色（2026-11-02）
    ///
    /// 场景：在 `cardStyle()` 卡片表面再放一层控件（如白噪音的音效选择行）时，
    /// 需要与卡片底色本身再拉开一级层次。
    ///
    /// 为何不能用系统语义色：`secondarySystemFill` 在浅色下是浅灰（可见），
    /// 但在深色下叠加到 #1C1C1E 卡片上后与卡片底色几乎相同；
    /// 而 `tertiarySystemBackground` 恰好相反 —— 深色下 #2C2C2E 可见，
    /// 浅色下却是纯白、与卡片融为一片。两者都只能覆盖一种模式。
    ///
    /// 故用「相对反色」定义：深色提亮、浅色压暗，两种模式下都能稳定产生
    /// 一层可感知但不过分的对比。
    static let cardInsetFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.06)
            : UIColor(white: 0.0, alpha: 0.05)
    })

    /// 从十六进制字符串初始化
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    /// 根据专注阶段返回对应的颜色
    static func forPhase(_ phase: FocusPhase) -> Color {
        switch phase {
        case .focus:
            return .focusRed
        case .shortBreak:
            return .breakGreen
        case .longBreak:
            return .longBreakBlue
        }
    }

    /// 根据任务优先级返回颜色
    static func forPriority(_ priority: Int16) -> Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        default: return .secondary
        }
    }
}
