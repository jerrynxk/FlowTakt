import Foundation
import CoreData

// MARK: - Achievement 扩展方法

extension Achievement {
    /// 关联的图标系统名称
    var systemImageName: String {
        iconName ?? "star.fill"
    }
}
