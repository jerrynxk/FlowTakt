import Foundation
import UserNotifications

// MARK: - NotificationService 协议

protocol NotificationServiceProtocol {
    func requestAuthorization() async -> Bool
    func scheduleSessionEndNotification(sessionId: UUID, title: String, timeInterval: TimeInterval)
    func cancelNotification(withIdentifier: String)
    /// 清理所有「专注结束」类待处理通知（修复 2026-10-15 通知乱弹）
    func cancelAllSessionNotifications()
}

// MARK: - 通知服务实现

final class NotificationService: NotificationServiceProtocol {
    private let notificationCenter = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("通知权限请求失败：\(error.localizedDescription)")
            return false
        }
    }

    func scheduleSessionEndNotification(sessionId: UUID, title: String, timeInterval: TimeInterval) {
        // UNTimeIntervalNotificationTrigger 要求正数 timeInterval，否则抛异常
        guard timeInterval > 0 else {
            print("⚠️ 通知触发时间必须大于 0，已忽略：\(timeInterval)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = L10n.shared.专注结束
        content.body = L10n.shared.番茄钟已完成(title)
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.sessionNotificationPrefix + sessionId.uuidString,
            content: content,
            trigger: trigger
        )

        // 修复（2026-10-15 通知乱弹）：调度前先清掉**其它**会话的残留通知。
        // 场景：iOS 在 App 进程被杀后仍保留 pending 通知；若期间会话被重建/切换
        // （或旧通知的 identifier 与当前 session.id 不一致），旧通知不会被同名 add 覆盖，
        // 到点与新通知齐弹。此处按前缀全清，保证任一时刻至多一条「专注结束」通知。
        cancelAllSessionNotifications()
        notificationCenter.add(request)
    }

    func cancelNotification(withIdentifier identifier: String) {
        // 兼容两种写法：调用方可能传裸 sessionId，也可能已带前缀
        let ids = [identifier,
                   Self.sessionNotificationPrefix + identifier,
                   identifier.hasPrefix(Self.sessionNotificationPrefix) ? identifier : Self.sessionNotificationPrefix + identifier]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: Array(Set(ids)))
    }

    /// 清理所有「专注结束」待处理通知（修复 2026-10-15 通知乱弹）。
    ///
    /// 用于：① 恢复会话前清残留；② 恢复为暂停态时清掉"本该取消却仍在"的旧通知；
    /// ③ 数据库重置/恢复数据后兜底。异步查询后按前缀移除。
    func cancelAllSessionNotifications() {
        let center = notificationCenter
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
                .filter { $0.hasPrefix(Self.sessionNotificationPrefix) }
            guard !ids.isEmpty else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            print("🧹 已清理残留的专注结束通知 \(ids.count) 条")
        }
    }

    /// 「专注结束」通知的 identifier 前缀（标识本 App 的会话类通知）
    static let sessionNotificationPrefix = "focus_session_"
}
