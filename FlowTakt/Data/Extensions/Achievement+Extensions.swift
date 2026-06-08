import Foundation
import CoreData

// MARK: - Achievement 扩展方法

extension Achievement {
    /// 获得成就后的格式化提示文本
    var unlockMessage: String {
        "恭喜解锁「\(title)」！"
    }

    /// 关联的图标系统名称
    var systemImageName: String {
        iconName ?? "star.fill"
    }
}
