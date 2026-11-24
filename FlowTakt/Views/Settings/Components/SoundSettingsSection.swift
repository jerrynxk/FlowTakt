import SwiftUI

struct SoundSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.soundEnabled) {
                Label(L10n.shared.音效, systemImage: "speaker.wave.2.fill")
            }

            Text(L10n.shared.专注与休息切换时的提示音)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            Toggle(isOn: $viewModel.vibrationEnabled) {
                Label(L10n.shared.震动反馈, systemImage: "iphone.radiowaves.left.and.right")
            }

            Text(L10n.shared.计时结束时的震动提醒)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            // 2026-11-22：图标从 waveform 改走气泡系 —— 白噪音开关已用 waveform，两开关同图标会撞。
            // 注意：speech.bubble 在当前 SDK 渲染为空（与 speaker.waves 同类坑），用确定有效的 text.bubble。
            Toggle(isOn: $viewModel.speechEnabled) {
                Label(L10n.shared.语音播报, systemImage: "text.bubble")
            }

            Text(L10n.shared.语音播报说明)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            // 用户反馈 2026-11-19：白噪音记忆 —— 关闭后开始专注不再自动播放背景音
            // 2026-11-22：原图标 "speaker.waves" 在当前系统渲染为空（与专注页工具条同一个坑），
            // 换成已验证可用的 "waveform"，与 FocusToolbarView 白噪音按钮开启态图标保持一致。
            Toggle(isOn: $viewModel.autoPlayWhiteNoise) {
                Label(L10n.shared.专注时自动播放白噪音, systemImage: "waveform")
            }

            Text(L10n.shared.白噪音记忆说明)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)
        } header: {
            Text(L10n.shared.声音与震动)
        }
    }
}

#Preview {
    Form {
        SoundSettingsSection(viewModel: SettingsViewModel(syncService: MockSyncService()))
    }
    .environmentObject(L10n.shared)
}
