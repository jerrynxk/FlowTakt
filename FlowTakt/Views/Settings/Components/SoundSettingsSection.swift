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
        } header: {
            Text(L10n.shared.声音与震动)
        }
    }
}

#Preview {
    Form {
        SoundSettingsSection(viewModel: SettingsViewModel())
    }
}
