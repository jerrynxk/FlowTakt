import Foundation

#if os(macOS)
import AppKit
#endif

// MARK: - AppBlockerService 协议

protocol AppBlockerServiceProtocol {
    func startBlocking()
    func stopBlocking()
    var isBlocking: Bool { get }
}

// MARK: - 应用屏蔽服务

/// 在 macOS 上通过系统勿扰模式实现专注环境下的通知抑制。
/// Screen Time 级别的应用屏蔽需要 MDM 或 NetworkExtension 授权，
/// 普通沙盒应用无法实现，故退而求其次激活/关闭系统勿扰模式。
///
/// 在 iOS 上，系统级的专注模式屏蔽需要 FamilyControls 授权（iOS 15+），
/// 当前作为占位实现，后续可通过 Screen Time API 扩展。
final class AppBlockerService: AppBlockerServiceProtocol {
    private(set) var isBlocking = false

    func startBlocking() {
        guard !isBlocking else { return }
        isBlocking = true

        #if os(macOS)
        setMacOSDoNotDisturb(enabled: true)
        #else
        print("专注模式已开启（iOS 平台：Screen Time 级屏蔽待后续实现）")
        #endif
    }

    func stopBlocking() {
        guard isBlocking else { return }
        isBlocking = false

        #if os(macOS)
        setMacOSDoNotDisturb(enabled: false)
        #else
        print("专注模式已关闭")
        #endif
    }

    // MARK: - macOS 私有方法

    #if os(macOS)
    /// 通过 defaults write 直接控制 macOS 系统勿扰模式（Do Not Disturb）
    private func setMacOSDoNotDisturb(enabled: Bool) {
        let dndScript: String
        if enabled {
            dndScript = """
            do shell script "defaults -currentHost write ~/Library/Preferences/ByHost/com.apple.notificationcenterui doNotDisturb -boolean true && \
            defaults -currentHost write ~/Library/Preferences/ByHost/com.apple.notificationcenterui doNotDisturbDate -date '$(date -u +\\"%Y-%m-%dT%H:%M:%SZ\\")' && \
            killall NotificationCenter 2>/dev/null; \
            osascript -e 'display notification \\"FlowTakt 已激活专注模式\\" with title \\"专注模式\\"' 2>/dev/null"
            """
        } else {
            dndScript = """
            do shell script "defaults -currentHost write ~/Library/Preferences/ByHost/com.apple.notificationcenterui doNotDisturb -boolean false && \
            defaults -currentHost delete ~/Library/Preferences/ByHost/com.apple.notificationcenterui doNotDisturbDate 2>/dev/null; \
            killall NotificationCenter 2>/dev/null"
            """
        }

        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", dndScript]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                print("系统勿扰模式已\(enabled ? "开启" : "关闭")")
            }
        } catch {
            print("系统勿扰模式切换失败：\(error.localizedDescription)")
        }
    }
    #endif
}
