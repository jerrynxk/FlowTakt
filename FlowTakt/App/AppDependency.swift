import Foundation
import SwiftUI
import CoreData
import Combine

// MARK: - 依赖注入容器

final class AppDependency: ObservableObject {
    // MARK: - 数据层
    let persistenceController: PersistenceController

    // MARK: - 服务层
    let timerManager: TimerManager
    let focusService: FocusServiceProtocol
    let taskService: TaskServiceProtocol
    let achievementService: AchievementServiceProtocol
    let notificationService: NotificationServiceProtocol
    let appBlockerService: AppBlockerServiceProtocol
    let audioService: AudioServiceProtocol
    let syncService: SyncServiceProtocol
    let scheduleService: ScheduleServiceProtocol
    let habitService: HabitServiceProtocol
    let timeRecordService: TimeRecordServiceProtocol

    // MARK: - ViewModel 层
    let focusViewModel: FocusViewModel
    let taskViewModel: TaskViewModel
    let statsViewModel: StatsViewModel
    let settingsViewModel: SettingsViewModel
    let achievementViewModel: AchievementViewModel
    let scheduleViewModel: ScheduleViewModel
    let habitViewModel: HabitViewModel
    let timeRecordViewModel: TimeRecordViewModel

    init() {
        // 初始化 PersistenceController
        persistenceController = PersistenceController.shared

        // 初始化 TimerManager
        timerManager = TimerManager()

        // 初始化 Service 层
        let notificationService = NotificationService()
        self.notificationService = notificationService
        self.appBlockerService = AppBlockerService()
        self.audioService = AudioService()
        self.syncService = SyncService(persistenceController: persistenceController)
        self.scheduleService = ScheduleService(persistenceController: persistenceController)
        self.habitService = HabitService(persistenceController: persistenceController)
        self.timeRecordService = TimeRecordService(persistenceController: persistenceController)

        let focusService = FocusService(
            persistenceController: persistenceController,
            notificationService: notificationService
        )
        self.focusService = focusService

        self.taskService = TaskService(persistenceController: persistenceController)

        self.achievementService = AchievementService(
            persistenceController: persistenceController,
            focusService: focusService
        )

        // 将 achievementService 注入 FocusService（互相引用的循环依赖通过 weak 解决）
        focusService.setAchievementService(achievementService)

        // 初始化 ViewModel 层
        self.focusViewModel = FocusViewModel(
            focusService: focusService,
            timerManager: timerManager,
            notificationService: notificationService,
            appBlockerService: appBlockerService,
            audioService: audioService,
            achievementService: achievementService,
            taskService: taskService
        )

        self.taskViewModel = TaskViewModel(
            taskService: taskService,
            persistenceController: persistenceController
        )

        self.statsViewModel = StatsViewModel(
            focusService: focusService,
            taskService: taskService,
            persistenceController: persistenceController
        )

        self.settingsViewModel = SettingsViewModel()

        self.achievementViewModel = AchievementViewModel(
            achievementService: achievementService
        )

        self.scheduleViewModel = ScheduleViewModel(
            scheduleService: scheduleService
        )

        self.habitViewModel = HabitViewModel(
            habitService: habitService,
            persistenceController: persistenceController
        )

        self.timeRecordViewModel = TimeRecordViewModel(
            timeRecordService: timeRecordService,
            persistenceController: persistenceController
        )

        // 注入数据库重置回调（在所有属性初始化后）
        settingsViewModel.onResetDatabase = { [weak self] in
            guard let self = self else { return false }
            do {
                try self.persistenceController.resetDatabase()
                print("数据库已成功重置")
                return true
            } catch {
                print("数据库重置失败：\(error.localizedDescription)")
                return false
            }
        }
    }

    /// 应用启动初始化
    func setupApp() {
        // 请求通知权限
        Swift.Task {
            _ = await notificationService.requestAuthorization()
        }
        // 设置 iCloud 同步
        syncService.setupCloudKit()
    }
}
