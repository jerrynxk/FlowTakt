import SwiftUI

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

    /// 从十六进制字符串初始化
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
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

    /// 根据会话状态返回颜色
    static func forSessionStatus(_ status: SessionStatus) -> Color {
        switch status {
        case .completed: return .green
        case .interrupted: return .orange
        case .abandoned: return .red
        case .running: return .blue
        }
    }
}
