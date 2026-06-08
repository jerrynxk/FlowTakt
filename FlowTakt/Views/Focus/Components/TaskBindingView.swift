import SwiftUI

// MARK: - 任务关联选择器

struct TaskBindingView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel

    @State private var selectedTaskId: UUID?

    var body: some View {
        HStack {
            Image(systemName: "link")
                .font(.caption)
                .foregroundColor(.secondary)

            Menu {
                // "无关联任务" 选项
                Button(action: {
                    selectedTaskId = nil
                    focusViewModel.selectedTask = nil
                }) {
                    HStack {
                        Text("无关联任务")
                        if focusViewModel.selectedTask == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Divider()

                // 活跃任务列表
                ForEach(taskViewModel.activeTasks) { task in
                    Button(action: {
                        selectedTaskId = task.id
                        focusViewModel.selectedTask = task
                    }) {
                        HStack {
                            Text(task.title)
                                .lineLimit(1)
                            if focusViewModel.selectedTask?.id == task.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(focusViewModel.selectedTask?.title ?? "关联任务")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(focusViewModel.selectedTask != nil ? .primary : .secondary)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
        .onAppear {
            selectedTaskId = focusViewModel.selectedTask?.id
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
                    persistenceController: PersistenceController.shared,
                    focusService: FocusService(
                        persistenceController: PersistenceController.shared,
                        notificationService: NotificationService()
                    )
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared)
            ))
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
    }
}
#endif
