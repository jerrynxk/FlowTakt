import SwiftUI

// MARK: - View 扩展

extension View {
    /// 卡片样式（全项目统一：systemBackground + 12 圆角 + 0.08/4/2 阴影）
    func cardStyle() -> some View {
        self
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}