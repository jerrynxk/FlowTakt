import SwiftUI
import CoreData

// MARK: - 任务关联选择器（v1.3 UI 优化：卡片化，空态/任务详情双形态）

struct TaskBindingView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    var body: some View {
        Menu {
            // "无关联任务" 选项
            Button(action: {
                focusViewModel.selectTask(nil)
            }) {
                HStack {
                    Text(L10n.shared.无关联任务)
                    if selectedTask == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            // 活跃任务列表
            ForEach(taskViewModel.activeTasks) { task in
                Button(action: {
                    focusViewModel.selectTask(task)
                }) {
                    HStack {
                        Text(task.title)
                            .lineLimit(1)
                        if selectedTask?.id == task.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            content
        }
        // 无障碍：Menu 触发卡片补齐可读标签（VoiceOver 朗读「关联任务」+ 当前选中任务）
        .accessibilityLabel(accessibilityMenuLabel)
    }

    /// VoiceOver 菜单标签：有选中任务时读任务名，否则读「关联任务」
    private var accessibilityMenuLabel: String {
        if let task = selectedTask {
            return L10n.shared.关联任务 + "，" + task.title
        }
        return L10n.shared.关联任务
    }

    /// 当前选中的任务；已从库中删除（任务被删 / 云端同步删除）时视为无选择，
    /// 避免把已删除的托管对象渲染出来（fault 访问是本项目历史崩溃源之一）。
    private var selectedTask: Task? {
        guard let task = focusViewModel.selectedTask, !task.isDeleted else { return nil }
        return task
    }

    /// 卡片内容：有任务显示任务详情，无任务显示占位提示
    private var content: some View {
        Group {
            if let task = selectedTask {
                HStack(spacing: 10) {
                    // 状态圆点（按优先级着色）
                    Circle()
                        .fill(priorityColor(task.priority))
                        .frame(width: 8, height: 8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.footnote.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            // 无障碍（2026-10-15 AX5 实测）：大字体下同行空间被挤压时
                            // 文本会被 SwiftUI 直接压没（只剩图标），缩放兜底保证始终可读
                            .minimumScaleFactor(0.7)

                        // 番茄进度
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.focusRed.opacity(0.8))
                            Text(L10n.shared.番茄进度(Int(task.completedPomodoros), Int(task.estimatedPomodoros)))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)

                    Text(L10n.shared.关联任务)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func priorityColor(_ priority: Int16) -> Color {
        switch priority {
        case 1: return .blue
        case 2: return .orange
        case 3: return .red
        default: return .secondary
        }
    }
}

#if DEBUG
struct TaskBindingView_Previews: PreviewProvider {
    static var previews: some View {
        TaskBindingView()
            .environmentObject(FocusViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                timerManager: TimerManager(),
                notificationService: NotificationService(),
                appBlockerService: AppBlockerService(),
                audioService: AudioService(),
                achievementService: AchievementService(
                    persistenceController: PersistenceController.shared
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                speechService: SpeechService()
            ))
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif
