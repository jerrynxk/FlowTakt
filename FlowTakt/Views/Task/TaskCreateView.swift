import SwiftUI

// MARK: - TaskCreateView

struct TaskCreateView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedPomodoros: Int16 = 1
    @State private var priority: Int16 = 2
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(86400)
    @State private var isSaving: Bool = false

    private let priorityOptions: [(label: String, value: Int16)] = [
        ("低", 1), ("中", 2), ("高", 3)
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 基本信息
                Section {
                    TextField("任务标题", text: $title)
                        .font(.body)

                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("备注（可选）")
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }
                }

                // MARK: 番茄钟设置
                Section("番茄钟") {
                    Stepper(value: $estimatedPomodoros, in: 1...20) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.focusRed)
                            Text("\(estimatedPomodoros) 个番茄钟")
                        }
                    }
                }

                // MARK: 优先级
                Section("优先级") {
                    Picker("优先级", selection: $priority) {
                        ForEach(priorityOptions, id: \.value) { option in
                            HStack {
                                Circle()
                                    .fill(Color.forPriority(option.value))
                                    .frame(width: 10, height: 10)
                                Text(option.label)
                            }
                            .tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: 截止日期
                Section("截止日期") {
                    Toggle("设置截止日期", isOn: $hasDueDate)
                        .tint(.focusRed)

                    if hasDueDate {
                        DatePicker(
                            "截止日期",
                            selection: $dueDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                }
            }
            .navigationTitle("新建任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
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
