import SwiftUI
import CoreData

// MARK: - TaskDetailView

struct TaskDetailView: View {
    let task: Task

    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var tagViewModel: TagViewModel
    @EnvironmentObject var l10n: L10n
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedPomodoros: Int16 = 1
    @State private var priority: Int16 = 2
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var hasChanges: Bool = false
    /// 标签选择态（loadTaskValues 时从 task.tags 初始化；保存时全量替换）
    @State private var selectedTagIDs: Set<UUID> = []

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
        List {
            // MARK: 编辑区域
            Section {
                TextField(L10n.shared.任务标题, text: $title)
                    .font(.body)
                    .onChange(of: title) { _, _ in hasChanges = true }

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text(L10n.shared.添加备注)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        // 无障碍（2026-10-14）：TextEditor 补标签
                        .accessibilityLabel(L10n.shared.备注)
                        .onChange(of: notes) { _, _ in hasChanges = true }
                }
            }

            // MARK: 番茄钟
            Section(L10n.shared.番茄钟) {
                Stepper(value: $estimatedPomodoros, in: 1...20) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.focusRed)
                            // 无障碍补齐（2026-11-02）：装饰图标不单独朗读（否则读「计时器 2 个番茄钟」）
                            .accessibilityHidden(true)
                        Text(L10n.shared.estimatedPomodoros(Int(estimatedPomodoros)))
                    }
                }
                .onChange(of: estimatedPomodoros) { _, _ in hasChanges = true }

                // 进度条
                VStack(spacing: 6) {
                    HStack {
                        Text(L10n.shared.进度)
                            .foregroundColor(.secondary)
                        Spacer()
                        // 修复（2026-10-14 P2）：分子按分母钳制 —— completedPomodoros 只增不减，
                        // 而 estimatedPomodoros 可下调到 1，原实现会显示「5 / 2」
                        Text("\(min(Int(task.completedPomodoros), max(1, Int(estimatedPomodoros)))) / \(max(1, Int(estimatedPomodoros)))")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.top, 4)
                    // 无障碍补齐（2026-11-02）：数字原样朗读会被读成「2 斜杠 6 番茄钟」，
                    // 合并为一句语义化描述
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.shared.番茄进度(
                        min(Int(task.completedPomodoros), max(1, Int(estimatedPomodoros))),
                        max(1, Int(estimatedPomodoros))
                    ))

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            let progress = estimatedPomodoros > 0
                                ? min(Double(task.completedPomodoros) / Double(estimatedPomodoros), 1.0)
                                : 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.forPriority(priority))  // 读编辑中的优先级，改完即变色（修复 P2-40）
                                .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                        }
                    }
                    .frame(height: 8)
                    // 无障碍补齐（2026-11-02）：纯视觉进度条，数值已由上方文字元素播报
                    .accessibilityHidden(true)
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
                .onChange(of: priority) { _, _ in hasChanges = true }
            }

            // MARK: 标签（用户反馈 2026-11-19：打通任务↔标签关联，补创建入口）
            Section(L10n.shared.标签) {
                TagEditorView(selectedTagIDs: $selectedTagIDs)
                    .onChange(of: selectedTagIDs) { _, _ in hasChanges = true }
            }

            // MARK: 状态
            Section(L10n.shared.状态) {
                HStack {
                    Text(L10n.shared.当前状态)
                    Spacer()
                    statusBadge
                }
            }

            // MARK: 截止日期
            Section(L10n.shared.截止日期) {
                Toggle(L10n.shared.设置截止日期, isOn: $hasDueDate)
                    .tint(.focusRed)
                    .onChange(of: hasDueDate) { _, _ in hasChanges = true }

                if hasDueDate {
                    DatePicker(
                        L10n.shared.截止日期,
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .onChange(of: dueDate) { _, _ in hasChanges = true }
                }
            }

            // MARK: 归档信息
            Section {
                VStack(spacing: 8) {
                    infoRow(label: L10n.shared.创建时间, value: formattedDate(task.createdAt))
                    infoRow(label: L10n.shared.更新时间, value: formattedDate(task.updatedAt))
                    if let completedAt = task.completedAt {
                        infoRow(label: L10n.shared.完成时间, value: formattedDate(completedAt))
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // MARK: 删除按钮
            if task.isCompleted == false {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "trash")
                            Text(L10n.shared.删除任务)
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
        .disableBounce()
        .navigationTitle(L10n.shared.任务详情)
        .navigationBarTitleDisplayMode(.inline)
        // 2026-10-14：列表页为让标题行紧贴顶部分段控件而隐藏了导航栏
        // （`.toolbar(.hidden, for: .navigationBar)`）。此处显式声明可见，
        // 确保详情页的返回按钮与「保存」按钮不受父级设置波及。
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.shared.保存) {
                    saveChanges()
                }
                .fontWeight(.semibold)
                .disabled(!hasChanges || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert(L10n.shared.确认删除, isPresented: $showDeleteConfirmation) {
            Button(L10n.shared.取消, role: .cancel) { }
            Button(L10n.shared.删除, role: .destructive) {
                deleteTask()
            }
        } message: {
            Text(L10n.shared.deleteConfirm(task.title))
        }
        .onAppear {
            loadTaskValues()
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(task.isCompleted ? Color.green : Color.blue)
                .frame(width: 8, height: 8)
            Text(task.isCompleted ? L10n.shared.已完成 : L10n.shared.进行中)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((task.isCompleted ? Color.green : Color.blue).opacity(0.12))
        )
    }

    // MARK: - Helpers

    private func loadTaskValues() {
        title = task.title
        notes = task.notes ?? ""
        estimatedPomodoros = task.estimatedPomodoros
        priority = task.priority
        // 标签选择态初始化（id 集合，保存时经 TagViewModel 解析回 Tag）
        selectedTagIDs = Set(task.tags.map { $0.id })
        if let date = task.dueDate {
            hasDueDate = true
            dueDate = date
        } else {
            hasDueDate = false
            dueDate = Date().addingTimeInterval(86400)
        }
        hasChanges = false
    }

    private func saveChanges() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
        let targetDueDate = hasDueDate ? dueDate : nil

        // 通过 ViewModel 更新任务，避免 View 直接修改 NSManagedObject
        taskViewModel.updateTask(
            task,
            title: trimmedTitle,
            notes: trimmedNotes,
            estimatedPomodoros: estimatedPomodoros,
            priority: priority,
            dueDate: targetDueDate
        )
        // 标签全量替换（走 TagService；与 updateTask 一样经 Service 层写入）
        tagViewModel.setTags(tagViewModel.resolveTags(ids: selectedTagIDs), on: task)
        hasChanges = false
    }

    private func deleteTask() {
        taskViewModel.deleteTask(task)
        dismiss()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func formattedDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(label))
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.viewContext
    let task = Task(context: context)
    task.storageId = UUID()
    task.title = "完成设计稿"
    task.notes = "包括首页、详情页和设置页"
    task.estimatedPomodoros = 6
    task.completedPomodoros = 2
    task.priority = 3
    task.status = TaskStatus.active.rawValue
    task.dueDate = Date()
    task.createdAt = Date()
    task.updatedAt = Date()

    return NavigationStack {
        TaskDetailView(task: task)
            .environment(\.managedObjectContext, context)
            .environmentObject(AppDependency().taskViewModel)
            .environmentObject(TagViewModel(
                tagService: TagService(persistenceController: PersistenceController.preview),
                persistenceController: PersistenceController.preview
            ))
            .environmentObject(L10n.shared)
    }
}
