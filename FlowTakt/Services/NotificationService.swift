import Foundation
import UserNotifications

// MARK: - NotificationService 协议

protocol NotificationServiceProtocol {
    func requestAuthorization() async -> Bool
    func scheduleSessionEndNotification(sessionId: UUID, title: String, timeInterval: TimeInterval)
    func cancelNotification(withIdentifier: String)
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
        let content = UNMutableNotificationContent()
        content.title = "专注结束"
        content.body = "「\(title)」的番茄钟已完成！"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        let request = UNNotificationRequest(
            identifier: sessionId.uuidString,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    func cancelNotification(withIdentifier identifier: String) {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
