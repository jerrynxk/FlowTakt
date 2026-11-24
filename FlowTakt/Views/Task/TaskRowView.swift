import SwiftUI
import CoreData

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: Task
    @EnvironmentObject var l10n: L10n

    var body: some View {
        HStack(spacing: 12) {
            // 优先级指示点
            priorityDot

            // 任务信息
            VStack(alignment: .leading, spacing: 4) {
                // 标题
                Text(task.title)
                    .font(.body)
                    .fontWeight(task.isCompleted ? .regular : .semibold)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)

                // 底部信息行
                HStack(spacing: 12) {
                    // 番茄钟进度
                    pomodoroBadge

                    // 截止日期
                    if let dueDate = task.dueDate {
                        dueDateBadge(dueDate)
                    }

                    // 标签徽章（用户反馈 2026-11-19：任务↔标签关系可视化，最多展示 3 个）
                    if !sortedTags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(sortedTags.prefix(3)) { tag in
                                tagBadge(tag)
                            }
                            if sortedTags.count > 3 {
                                Text("+\(sortedTags.count - 3)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // 进度环指示
            if !task.isCompleted {
                progressIndicator
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityRowLabel)
    }

    // MARK: - Priority Dot

    private var priorityDot: some View {
        Circle()
            .fill(Color.forPriority(task.priority))
            .frame(width: 8, height: 8)
    }

    // MARK: - Pomodoro Badge

    private var pomodoroBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "timer")
                .imageScale(.small)
            Text("\(task.completedPomodoros)/\(task.estimatedPomodoros)")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.systemGray6))
        .cornerRadius(4)
    }

    // MARK: - Tag Badge

    /// 任务标签按名称排序（与统计归属的 resolvedTag「按名称取首个」判据一致，首个标签即主分类）
    private var sortedTags: [Tag] {
        task.tags.sorted { ($0.name) < ($1.name) }
    }

    private func tagBadge(_ tag: Tag) -> some View {
        let color = tag.colorHex.flatMap { Color(hex: $0) } ?? Color(hex: TagPalette.colors[0])
        return HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(tag.name)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.14))
        .cornerRadius(4)
    }

    // MARK: - Due Date Badge

    private func dueDateBadge(_ date: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar")
                .imageScale(.small)
            Text(formattedDueDate(date))
        }
        .foregroundColor(date.isToday ? .focusRed : .secondary)
    }

    // MARK: - Progress Indicator

    private var progressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 3)

            Circle()
                .trim(from: 0, to: CGFloat(min(task.pomodoroProgress, 1.0)))
                .stroke(Color.forPriority(task.priority), lineWidth: 3)
                .rotationEffect(.degrees(-90))

            Text("\(Int(task.pomodoroProgress * 100))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(width: 36, height: 36)
    }

    // MARK: - Helpers

    private var accessibilityRowLabel: String {
        let statusText = task.isCompleted ? L10n.shared.已完成 : L10n.shared.进行中
        // 无障碍修复（2026-08-12）：label 并入番茄进度与截止日期，避免 combine 后丢失子文本信息
        var parts = [task.title, statusText]
        if task.estimatedPomodoros > 0 {
            parts.append("\(L10n.shared.番茄进度(Int(task.completedPomodoros), Int(task.estimatedPomodoros)))")
        }
        if let due = task.dueDate {
            parts.append(formattedDueDate(due))
        }
        // 无障碍：标签名并入整行朗读（与可见内容一致）
        for tag in sortedTags.prefix(3) {
            parts.append(tag.name)
        }
        return parts.joined(separator: "，")
    }

    private func formattedDueDate(_ date: Date) -> String {
        if date.isToday {
            return L10n.shared.今日
        } else if date.isYesterday {
            return L10n.shared.昨日
        } else {
            return date.shortDateString
        }
    }
}

// MARK: - Preview

#Preview {
    TaskRowView(task: TaskRowView.previewTask())
        .padding(.horizontal)
        .environmentObject(L10n.shared)
}

extension TaskRowView {
    /// Preview 用：创建一个示例任务（ViewBuilder 闭包内不允许赋值语句）
    static func previewTask() -> Task {
        let context = PersistenceController.preview.viewContext
        let task = Task(context: context)
        task.storageId = UUID()
        task.title = "完成项目报告"
        task.estimatedPomodoros = 4
        task.completedPomodoros = 1
        task.priority = 3
        task.status = TaskStatus.active.rawValue
        task.dueDate = Date()
        task.createdAt = Date()
        task.updatedAt = Date()
        return task
    }
}
