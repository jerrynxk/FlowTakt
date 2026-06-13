import SwiftUI

// MARK: - TaskFilterBar

struct TaskFilterBar: View {
    @EnvironmentObject var l10n: L10n

    @Binding var selectedPriority: Int16?

    private let filters: [(label: String, priority: Int16?)] = [
        (L10n.shared.全部, nil),
        (L10n.shared.高优先, 3),
        (L10n.shared.中优先, 2),
        (L10n.shared.低优先, 1),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters, id: \.label) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPriority = filter.priority
                        }
                    } label: {
                        Text(filter.label)
                            .font(.subheadline)
                            .fontWeight(selectedPriority == filter.priority ? .semibold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedPriority == filter.priority
                                          ? Color.forPriority(filter.priority ?? 0).opacity(0.15)
                                          : Color(.systemGray6))
                            )
                            .foregroundColor(selectedPriority == filter.priority
                                             ? Color.forPriority(filter.priority ?? 0)
                                             : .secondary)
                            .overlay(
                                Capsule()
                                    .stroke(selectedPriority == filter.priority
                                            ? Color.forPriority(filter.priority ?? 0).opacity(0.3)
                                            : Color.clear, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Preview

#Preview {
    TaskFilterBar(selectedPriority: .constant(3))
}
