import SwiftUI

// MARK: - TaskCreateView

struct TaskCreateView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var tagViewModel: TagViewModel
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedPomodoros: Int16 = 1
    @State private var priority: Int16 = 2
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(86400)
    @State private var hasRecurrence: Bool = false
    @State private var recurrenceRule: String = "none"
    /// 选中的标签 id 集合（保存时经 TagViewModel 解析为 Tag，写入 task.tags）
    @State private var selectedTagIDs: Set<UUID> = []

    private let priorityValues: [Int16] = [1, 2, 3]
    private let recurrenceOptions: [(String, String, String)] = [
        ("none", L10n.shared.不重复, "No Repeat"),
        ("daily", L10n.shared.每天, "Daily"),
        ("weekday", L10n.shared.工作日, "Weekdays"),
        ("weekly", L10n.shared.每周, "Weekly"),
        ("biweekly", L10n.shared.每两周, "Biweekly"),
        ("monthly", L10n.shared.每月, "Monthly")
    ]

    private func recurrenceLabel(_ rule: String) -> String {
        recurrenceOptions.first { $0.0 == rule }.map { L10n.shared.isEnglish ? $0.2 : $0.1 } ?? rule
    }

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
                            // 无障碍（2026-10-14）：TextEditor 补标签（占位文案是独立元素，不会自动成为输入框标签）
                            .accessibilityLabel(L10n.shared.备注)
                    }
                }

                // MARK: 番茄钟设置
                Section(L10n.shared.番茄钟) {
                    Stepper(value: $estimatedPomodoros, in: 1...20) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(.focusRed)
                                // 无障碍补齐（2026-11-02）：装饰图标不单独朗读
                                .accessibilityHidden(true)
                            Text(L10n.shared.estimatedPomodoros(Int(estimatedPomodoros)))
                        }
                    }
                }

                // MARK: 标签（用户反馈 2026-11-19：打通任务↔标签关联，补创建入口）
                Section(L10n.shared.标签) {
                    TagEditorView(selectedTagIDs: $selectedTagIDs)
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

                // MARK: 重复
                Section {
                    Toggle(L10n.shared.重复任务, isOn: $hasRecurrence)
                        .tint(.focusRed)

                    if hasRecurrence {
                        Picker(L10n.shared.重复频率, selection: $recurrenceRule) {
                            ForEach(recurrenceOptions.filter { $0.0 != "none" }, id: \.0) { option in
                                Text(recurrenceLabel(option.0)).tag(option.0)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.shared.新建任务)
            .navigationBarTitleDisplayMode(.inline)
            // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
            .disableBounce()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.shared.取消) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shared.保存) {
                        saveTask()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .interactiveDismissDisabled(title.trimmingCharacters(in: .whitespaces).isEmpty == false)
        }
    }

    // MARK: - Actions

    private func saveTask() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let newTask = taskViewModel.createTask(
            title: title.trimmingCharacters(in: .whitespaces),
            // 修复（P2-40）：与 TaskDetailView 统一 —— 判空与入库用同一份 trim 结果
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : notes.trimmingCharacters(in: .whitespacesAndNewlines),
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            dueDate: hasDueDate ? dueDate : nil,
            recurrenceRule: hasRecurrence ? recurrenceRule : nil
        )

        // 保存后挂标签（全量替换语义；标签对象经 TagViewModel 解析，走 Service 层写入）
        if let newTask, !selectedTagIDs.isEmpty {
            tagViewModel.setTags(tagViewModel.resolveTags(ids: selectedTagIDs), on: newTask)
        }
    }
}

// MARK: - Preview

#Preview {
    TaskCreateView()
        .environmentObject(AppDependency().taskViewModel)
        .environmentObject(TagViewModel(
            tagService: TagService(persistenceController: PersistenceController.preview),
            persistenceController: PersistenceController.preview
        ))
        .environmentObject(L10n.shared)
}
