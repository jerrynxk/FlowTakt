import SwiftUI
import CoreData

// MARK: - TaskDetailView

struct TaskDetailView: View {
    let task: Task

    @EnvironmentObject var taskViewModel: TaskViewModel
    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var estimatedPomodoros: Int16 = 1
    @State private var priority: Int16 = 2
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var hasChanges: Bool = false

    private let priorityOptions: [(label: String, value: Int16)] = [
        ("低", 1), ("中", 2), ("高", 3)
    ]

    var body: some View {
        List {
            // MARK: 编辑区域
            Section {
                TextField("任务标题", text: $title)
                    .font(.body)
                    .onChange(of: title) { _ in hasChanges = true }

                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("添加备注...")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .onChange(of: notes) { _ in hasChanges = true }
                }
            }

            // MARK: 番茄钟
            Section("番茄钟") {
                Stepper(value: $estimatedPomodoros, in: 1...20) {
                    HStack {
                        Image(systemName: "timer")
                            .foregroundColor(.focusRed)
                        Text("\(estimatedPomodoros) 个番茄钟")
                    }
                }
                .onChange(of: estimatedPomodoros) { _ in hasChanges = true }

                // 进度条
                VStack(spacing: 6) {
                    HStack {
                        Text("进度")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(task.completedPomodoros) / \(estimatedPomodoros)")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    .padding(.top, 4)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            let progress = estimatedPomodoros > 0
                                ? min(Double(task.completedPomodoros) / Double(estimatedPomodoros), 1.0)
                                : 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.forPriority(task.priority))
                                .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                        }
                    }
                    .frame(height: 8)
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
                .onChange(of: priority) { _ in hasChanges = true }
            }

            // MARK: 状态
            Section("状态") {
                HStack {
                    Text("当前状态")
                    Spacer()
                    statusBadge
                }
            }

            // MARK: 截止日期
            Section("截止日期") {
                Toggle("设置截止日期", isOn: $hasDueDate)
                    .tint(.focusRed)
                    .onChange(of: hasDueDate) { _ in hasChanges = true }

                if hasDueDate {
                    DatePicker(
                        "截止日期",
                        selection: $dueDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .onChange(of: dueDate) { _ in hasChanges = true }
                }
            }

            // MARK: 归档信息
            Section {
                VStack(spacing: 8) {
                    infoRow(label: "创建时间", value: formattedDate(task.createdAt))
                    infoRow(label: "更新时间", value: formattedDate(task.updatedAt))
                    if let completedAt = task.completedAt {
                        infoRow(label: "完成时间", value: formattedDate(completedAt))
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
                            Text("删除任务")
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveChanges()
                }
                .fontWeight(.semibold)
                .disabled(!hasChanges || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert("确认删除", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                deleteTask()
            }
        } message: {
            Text("确定要删除「\(task.title)」吗？此操作不可撤销。")
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
            Text(task.isCompleted ? "已完成" : "进行中")
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
        task.title = title.trimmingCharacters(in: .whitespaces)
        task.notes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        task.estimatedPomodoros = estimatedPomodoros
        task.priority = priority
        task.dueDate = hasDueDate ? dueDate : nil
        task.updatedAt = Date()

        taskViewModel.refreshTask(task)
        hasChanges = false
    }

    private func deleteTask() {
        taskViewModel.deleteTask(task)
        dismiss()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.viewContext
    let task = Task(context: context)
    task.id = UUID()
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
    }
}
