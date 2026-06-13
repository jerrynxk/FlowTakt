import SwiftUI

struct TimerSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel

    /// 将 TimeInterval（秒）格式化为可读的分钟文本
    private func formattedDuration(_ seconds: TimeInterval) -> Text {
        let minutes = Int(seconds) / 60
        return L10n.shared.isEnglish
            ? Text("\(minutes) min")
            : Text("\(minutes) 分钟")
    }

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.selectedFocusOption },
                set: { viewModel.updateFocusDuration(at: $0) }
            )) {
                ForEach(viewModel.focusOptions.indices, id: \.self) { index in
                    formattedDuration(viewModel.focusOptions[index])
                        .tag(index)
                }
            } label: {
                Label(L10n.shared.专注时长, systemImage: "clock.fill")
            }

            Picker(selection: Binding(
                get: { viewModel.selectedShortBreakOption },
                set: { viewModel.updateShortBreakDuration(at: $0) }
            )) {
                ForEach(viewModel.shortBreakOptions.indices, id: \.self) { index in
                    formattedDuration(viewModel.shortBreakOptions[index])
                        .tag(index)
                }
            } label: {
                Label(L10n.shared.短休息时长, systemImage: "cup.and.saucer.fill")
            }

            Picker(selection: Binding(
                get: { viewModel.selectedLongBreakOption },
                set: { viewModel.updateLongBreakDuration(at: $0) }
            )) {
                ForEach(viewModel.longBreakOptions.indices, id: \.self) { index in
                    formattedDuration(viewModel.longBreakOptions[index])
                        .tag(index)
                }
            } label: {
                Label(L10n.shared.长休息时长, systemImage: "mug.fill")
            }

            Stepper(value: $viewModel.longBreakAfterRounds, in: 1...10) {
                Label(L10n.shared.长休息轮次, systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                formattedRounds(viewModel.longBreakAfterRounds)
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $viewModel.autoStartBreaks) {
                Label(L10n.shared.自动开始休息, systemImage: "play.circle.fill")
            }

            Toggle(isOn: $viewModel.autoStartFocus) {
                Label(L10n.shared.自动开始专注, systemImage: "forward.circle.fill")
            }
        } header: {
            Text(L10n.shared.计时设置)
        }
    }

    /// 将轮次格式化为可读的文本
    private func formattedRounds(_ rounds: Int) -> Text {
        return L10n.shared.isEnglish
            ? Text("After \(rounds) rounds")
            : Text("每 \(rounds) 轮后")
    }
}

#Preview {
    Form {
        TimerSettingsSection(viewModel: SettingsViewModel())
    }
}
