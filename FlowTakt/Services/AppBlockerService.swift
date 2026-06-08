import Foundation

// MARK: - AppBlockerService 协议

protocol AppBlockerServiceProtocol {
    func startBlocking()
    func stopBlocking()
    var isBlocking: Bool { get }
}

// MARK: - 应用屏蔽服务（占位实现）

final class AppBlockerService: AppBlockerServiceProtocol {
    private(set) var isBlocking = false

    func startBlocking() {
        isBlocking = true
        // 实际实现需要调用 Screen Time API 或引导式访问
        print("专注模式已开启 - 应用屏蔽启动")
    }

    func stopBlocking() {
        isBlocking = false
        print("专注模式已关闭 - 应用屏蔽停止")
    }
}
