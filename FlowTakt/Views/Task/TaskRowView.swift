import SwiftUI
import CoreData

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: Task

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

    private func formattedDueDate(_ date: Date) -> String {
        if date.isToday {
            return "今天"
        } else if date.isYesterday {
            return "昨天"
        } else {
            return date.shortDateString
        }
    }
}

// MARK: - Preview

#Preview {
    let context = PersistenceController.preview.viewContext
    let task = Task(context: context)
    task.id = UUID()
    task.title = "完成项目报告"
    task.estimatedPomodoros = 4
    task.completedPomodoros = 1
    task.priority = 3
    task.status = TaskStatus.active.rawValue
    task.dueDate = Date()
    task.createdAt = Date()
    task.updatedAt = Date()

    return TaskRowView(task: task)
        .padding(.horizontal)
        .environment(\.managedObjectContext, context)
}
