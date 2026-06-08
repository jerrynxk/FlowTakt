import SwiftUI

struct TimerSettingsSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    /// 将 TimeInterval（秒）格式化为可读的分钟字符串
    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes) 分钟"
    }

    var body: some View {
        Section {
            Picker(selection: Binding(
                get: { viewModel.selectedFocusOption },
                set: { viewModel.updateFocusDuration(at: $0) }
            )) {
                ForEach(viewModel.focusOptions.indices, id: \.self) { index in
                    Text(formattedDuration(viewModel.focusOptions[index]))
                        .tag(index)
                }
            } label: {
                Label("专注时长", systemImage: "clock.fill")
            }

            Picker(selection: Binding(
                get: { viewModel.selectedShortBreakOption },
                set: { viewModel.updateShortBreakDuration(at: $0) }
            )) {
                ForEach(viewModel.shortBreakOptions.indices, id: \.self) { index in
                    Text(formattedDuration(viewModel.shortBreakOptions[index]))
                        .tag(index)
                }
            } label: {
                Label("短休息时长", systemImage: "cup.and.saucer.fill")
            }

            Picker(selection: Binding(
                get: { viewModel.selectedLongBreakOption },
                set: { viewModel.updateLongBreakDuration(at: $0) }
            )) {
                ForEach(viewModel.longBreakOptions.indices, id: \.self) { index in
                    Text(formattedDuration(viewModel.longBreakOptions[index]))
                        .tag(index)
                }
            } label: {
                Label("长休息时长", systemImage: "mug.fill")
            }

            Stepper(value: $viewModel.longBreakAfterRounds, in: 1...10) {
                Label("长休息轮次", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Text("每 \(viewModel.longBreakAfterRounds) 轮后")
                    .foregroundColor(.secondary)
            }

            Toggle(isOn: $viewModel.autoStartBreaks) {
                Label("自动开始休息", systemImage: "play.circle.fill")
            }

            Toggle(isOn: $viewModel.autoStartFocus) {
                Label("自动开始专注", systemImage: "forward.circle.fill")
            }
        } header: {
            Text("计时设置")
        }
    }
}

#Preview {
    Form {
        TimerSettingsSection(viewModel: SettingsViewModel())
    }
}
