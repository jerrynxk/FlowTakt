import SwiftUI

struct SoundSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Toggle(isOn: $viewModel.soundEnabled) {
                Label("音效", systemImage: "speaker.wave.2.fill")
            }

            Text("专注与休息切换时的提示音")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            Toggle(isOn: $viewModel.vibrationEnabled) {
                Label("震动反馈", systemImage: "iphone.radiowaves.left.and.right")
            }

            Text("计时结束时的震动提醒")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)

            Toggle(isOn: $viewModel.whiteNoiseEnabled) {
                Label("白噪音", systemImage: "wind")
            }

            Text("专注时播放白噪音帮助集中注意力")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 32)
        } header: {
            Text("声音与震动")
        }
    }
}

#Preview {
    Form {
        SoundSettingsSection(viewModel: SettingsViewModel())
    }
}
