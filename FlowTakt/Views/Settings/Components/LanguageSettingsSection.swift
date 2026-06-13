import SwiftUI

struct LanguageSettingsSection: View {
    @EnvironmentObject var l10n: L10n

    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Section {
            Picker(selection: $viewModel.selectedLanguageOption) {
                ForEach(0..<viewModel.languageNames.count, id: \.self) { index in
                    Text(viewModel.languageNames[index]).tag(index)
                }
            } label: {
                Label(L10n.shared.语言, systemImage: "globe")
            }
            .onChange(of: viewModel.selectedLanguageOption) { newIndex in
                viewModel.updateLanguage(at: newIndex)
            }
        } header: {
            Text(L10n.shared.语言)
        }
    }
}

#Preview {
    Form {
        LanguageSettingsSection(viewModel: SettingsViewModel())
    }
}
