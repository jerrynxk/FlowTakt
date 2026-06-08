import SwiftUI

struct AboutSection: View {
    var body: some View {
        Section {
            NavigationLink {
                UsageGuideView()
            } label: {
                Label("使用说明", systemImage: "book.pages.fill")
            }

            HStack {
                Label("应用名称", systemImage: "app.fill")
                Spacer()
                Text("FlowTakt")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("版本", systemImage: "number")
                Spacer()
                Text("1.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Label("构建", systemImage: "hammer.fill")
                Spacer()
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")")
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("关于")
        }
    }
}

#Preview {
    Form {
        AboutSection()
    }
}
