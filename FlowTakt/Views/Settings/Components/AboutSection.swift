import SwiftUI

struct AboutSection: View {
    @EnvironmentObject var l10n: L10n
    var body: some View {
        Section {
            NavigationLink {
                UsageGuideView()
            } label: {
                Label(L10n.shared.使用说明, systemImage: "book.pages.fill")
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label(L10n.shared.隐私政策, systemImage: "hand.raised.fill")
            }

            HStack {
                Label(L10n.shared.应用名称, systemImage: "app.fill")
                Spacer()
                Text("FlowTakt")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label(L10n.shared.版本, systemImage: "number")
                Spacer()
                Text("1.0")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text(L10n.shared.关于)
        }
    }
}

#Preview {
    Form {
        AboutSection()
    }
}
