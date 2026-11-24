import UIKit
import BackgroundTasks

// MARK: - AppDelegate（BGTask 合规注册 + CloudKit 推送通道）
//
// 修复（2026-10-14 审查 P2）：`BGTaskScheduler.register` 按 Apple 要求必须在
// `application(_:didFinishLaunchingWithOptions:)` **返回前**完成。此前注册写在
// SwiftUI 的 `.task` 里（场景呈现后才执行），时点已晚 → 返回 false 且返回值被丢弃，
// 后台刷新静默失效，系统「后台 App 刷新」列表里也不会出现本 App。
//
// 修复（2026-10-15 审查 P1-034）：补齐 CloudKit 静默推送注册链路。
// entitlements 已声明 `aps-environment` + `UIBackgroundModes:remote-notification`，
// 但从未调用 `registerForRemoteNotifications()` —— 设备没有注册 APNs 通道，
// CloudKit 的 `CKDatabaseSubscription` 触发的静默推送永远送不到本机，
// 跨设备同步只能等下次前台 `fetch`，表现为「另一台设备改了数据本机迟迟不更新」。

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 滚动行为（2026-11-02 二次修正，用户反馈「撞墙还是没弹」）：
        // `bounces = false` 的语义是「到边界立即停住」——它会彻底移除 iOS 惯有的
        // 边缘橡皮筋反馈，无论怎么调减速曲线都不会「弹」。故**恢复 bounces 默认值**，
        // 让滚动到顶/底时保留原生回弹。
        // 仅保留 `alwaysBounceVertical = false`：内容不足一屏的短页面仍完全「拉不动」
        // （没有可滚动内容时拖动无反馈），这一条是用户此前明确要求的，不回退。
        // 注：各页面背景均为 appBackground 且与滚动容器同层，回弹时露出的是同色底，
        // 不会出现刺眼的白色块。
        UIScrollView.appearance().alwaysBounceVertical = false

        let identifier = AppDependency.backgroundRefreshIdentifier
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            // 唤醒时才依赖依赖容器（此时 AppDependency 已就绪）
            AppDependency.shared?.handleBackgroundRefresh(task)
        }
        if !registered {
            print("⚠️ BGTask 注册未成功（identifier: \(identifier)）——后台刷新不会运行")
        }

        // CloudKit 静默推送通道注册（异步授权，无需用户弹窗——静默推送不算用户通知）
        // 说明：这里只是注册 APNs 通道让系统能投递 CloudKit 推送；用户可见的
        // 本地通知授权仍由 NotificationService 单独管理，两者互不影响。
        application.registerForRemoteNotifications()
        return true
    }

    /// APNs 注册成功（token 仅用于推送投递路由；CloudKit 内部消费，App 无需自行保存）
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("✅ APNs 通道注册成功（CloudKit 静默推送可送达）：\(token.prefix(16))…")
    }

    /// APNs 注册失败（如模拟器/无证书环境）：CloudKit 仍可通过前台轮询同步，仅降级不阻断
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("⚠️ APNs 通道注册失败（CloudKit 推送降级为前台轮询）：\(error.localizedDescription)")
    }

    /// 接收远程推送（CloudKit 静默推送 content-available=1 时由此进入）
    /// 把 payload 交给系统默认处理：CloudKit 会自动拉取远端变更并写库，
    /// 随后 `NSPersistentStoreRemoteChange` 通知驱动 PersistenceController 刷新上下文。
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // CloudKit 变更拉取是异步的；此处给系统一个保守的 newData 结果，
        // 实际数据落地由 NSPersistentCloudKitContainer 的导入管线完成。
        completionHandler(.newData)
    }
}
