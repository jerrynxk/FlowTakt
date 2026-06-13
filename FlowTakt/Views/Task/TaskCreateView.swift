import SwiftUI

// MARK: - TaskCreateView

struct TaskCreateView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedPomodoros: Int16 = 1
    @State private var priority: Int16 = 2
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(86400)
    @State private var isSaving: Bool = false

    private let priorityValues: [Int16] = [1, 2, 3]

    private func priorityLabel(_ value: Int16) -> String {
        switch value {
        case 1: return L10n.shared.低优先
        case 2: return L10n.shared.中优先
        case 3: return L10n.shared.高优先
        default: return ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 基本信息
                Section {
                    TextField(L10n.shared.任务标题, text: $title)
                        .font(.body)

                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text(L10n.shared.备注可选)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }
                }

                // MARK: 番茄钟设置
                Section(L10n.shared.番茄钟) {
                    Stepper(value: $estimatedPomodoros, in: 1...20) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.focusRed)
                            Text(L10n.shared.estimatedPomodoros(Int(estimatedPomodoros)))
                        }
                    }
                }

                // MARK: 优先级
                Section(L10n.shared.优先级) {
                    Picker(L10n.shared.优先级, selection: $priority) {
                        ForEach(priorityValues, id: \.self) { value in
                            HStack {
                                Circle()
                                    .fill(Color.forPriority(value))
                                    .frame(width: 10, height: 10)
                                Text(priorityLabel(value))
                            }
                            .tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: 截止日期
                Section(L10n.shared.截止日期) {
                    Toggle(L10n.shared.设置截止日期, isOn: $hasDueDate)
                        .tint(.focusRed)

                    if hasDueDate {
                        DatePicker(
                            L10n.shared.截止日期,
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle(L10n.shared.新建任务)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.shared.取消) {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shared.保存) {
                        saveTask()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .interactiveDismissDisabled(title.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
    }

    // MARK: - Actions

    private func saveTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSaving = true
        taskViewModel.createTask(
            title: title.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes,
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil
        )
        // dismiss is handled internally by taskViewModel setting showCreateSheet = false
    }
}

// MARK: - Preview

#Preview {
    TaskCreateView()
        .environmentObject(AppDependency().taskViewModel)
}
