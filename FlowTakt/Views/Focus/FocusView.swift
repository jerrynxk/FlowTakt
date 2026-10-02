import SwiftUI

// MARK: - 专注主视图（v1.3.4 视觉统一重设计 · 整页不滚动 · 单 viewport 容下全部元素）
// 设计规范（对照其余标签页）：
// 1. 视觉统一：顶部 Segmented（与计划/习惯/统计页顶层完全一致，紧贴状态栏）+ NavigationStack 大标题「专注」+ 阶段说明行（subheadline semibold + footnote，与 DateSectionHeader 同规格）；卡片全部 cardStyle()（systemBackground + 12 圆角 + 0.08/4/2 阴影）；背景 appBackground
// 2. 布局逻辑：模仿 PlanView/HabitTrackView/StatsOverviewView 的 VStack { Picker + switch(child) } 结构 ——
//    picker 在 NavigationStack 之外（VStack 第一项），child NavigationStack 提供大标题与主内容
// 3. 热区重排：主按钮组（开始/暂停/停止）置于屏幕垂直中下部拇指热区；辅助功能（时长/任务/白噪音/统计）贴底
// 4. 一屏适配：GeometryReader 撑满 viewport，圆环按可用高度自适应；弹性空间吸收余量，无滚动、无大面积留白

struct FocusView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var l10n: L10n
    // v1.3.4p：iPad 全量适配 — 区分 compact（iPhone 贴顶布局）与 regular（iPad 垂直居中）
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - 进度计算

    /// 精确的进度值（0.0 ~ 1.0），直接使用 TimerManager 的 progress，避免字符串解析
    private var progressValue: Double {
        switch focusViewModel.timerState {
        case .idle:
            return 0
        case .finished:
            return 1
        case .running, .paused:
            return min(1, max(0, focusViewModel.progress))
        }
    }

    /// 长休息前的轮次阈值
    private var longBreakAfterRounds: Int {
        settingsViewModel.longBreakAfterRounds
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 Segmented（与其它标签页一致：紧贴状态栏，NavigationStack 之外）
            PhasePickerView()

            // child NavigationStack 提供「大标题「专注」」与主内容（v1.3.4i：标题区与其它 Tab 一致，中间不再夹统计卡片）
            NavigationStack {
                GeometryReader { geometry in
                    // v1.3.4p 第四轮：整页不滚动改为 ScrollView 包裹（横屏/分屏/大动态字体时内容超高可滚动），
                    // 用 minHeight 保持原布局语义：内容不足一屏时垂直居中，超一屏时可滚动
                    ScrollView {
                        // 一屏布局预算（iPhone 13 Pro content ~665pt）：
                        // large title ~52 + caption ~20 + ring 225 + rounds 24 + button 68 + chips 36 + cards 170 + spacing 50 ≈ 645pt
                        // 余量由 Spacer 吸收，将主按钮组压入拇指热区、卡片区贴底
                        let width = geometry.size.width
                        let height = geometry.size.height

                        // 圆环尺寸：受宽度（56% 与 240 上限）和高度（35% 与 240 上限）双重约束，下限 180
                        // v1.3.4p：上限 280→240——iPad 13" 大屏幕上 280pt 圆环底部外发光阴影侵入 timerDisplay 字符底部造成"贴字"，
                        // 缩小 14% 后文字距圆环 stroke 有 90pt buffer，iPhone 上因 width*0.56=200 自然限到 ~200pt 不变
                        let ringSize = min(
                            min(width * 0.56, 240),
                            max(180, height * 0.35)
                        )

                        VStack(spacing: 10) {
                        // 阶段说明行（跟在大标题下方，与其它 section header 规格一致）
                        PhaseCaptionView()

                        // 计时圆环 + 轮次泡泡（泡泡紧贴圆环底部）
                        VStack(spacing: 6) {
                            CircularTimerView(progress: progressValue)
                                .frame(width: ringSize, height: ringSize)

                            roundProgressView
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)    // 圆环下移留白（v1.3.4i：48→20，给底部 stats 腾空间；按钮/卡片位置由 Spacer 吸收）

                        // v1.3.4p 第三轮：状态文字从 CircularTimerView 移出到此，圆环 VStack 之外、独立位置
                        // 避免主按钮覆盖；与「准备就绪/进行中/已暂停/已完成」白底胶囊显示在时间大字下方（用户要求）
                        Text(focusViewModel.timerState == .running ? L10n.shared.进行中
                             : focusViewModel.timerState == .paused ? L10n.shared.已暂停
                             : focusViewModel.timerState == .finished ? L10n.shared.已完成
                             : L10n.shared.准备就绪)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.forPhase(focusViewModel.activePhase))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(.systemBackground).opacity(0.85))
                            )
                            .accessibilityHidden(true)

                        // 弹性空间：iPhone 上把主按钮推至拇指热区（屏垂直中下部）；
                        // v1.3.4p：iPad 上跳过 Spacer —— 否则 iPad 大屏 Spacer 会吃光 400+pt 空白让布局松散
                        if horizontalSizeClass == .compact {
                            Spacer(minLength: 4)
                        }

                        // 高频操作按钮组（开始/暂停 + 停止）——最顺手、最易触达
                        // v1.3.4p 第二轮：offset(y:-24) 撤回为 0（v1.3.4n/o 上移 24pt 在 iPad 大圆环上让主按钮覆盖「第 1 轮」指示），
                        // padding(.top, 12) 给主按钮独立 12pt 顶部间距，避免压字
                        StartButtonView()
                            .padding(.top, 12)

                        // v1.3.4m：「自定义」chip + 「关联任务」卡片放一行
                        HStack(spacing: 8) {
                            DurationChipsView()
                                .frame(maxWidth: 140)
                                .alignmentGuide(.top, computeValue: { $0[.top] })

                            TaskBindingView()
                                .frame(maxWidth: .infinity)
                        }

                        // 低频辅助卡片区 —— 贴底，铺满可视区域
                        VStack(spacing: 10) {
                            WhiteNoiseSliderCard()
                            TodayMiniStatsView()
                        }
                    }
                    // v1.3.4p：iPad 全量适配 — maxWidth 460→640（合并 frame，水平居中）
                    // iPhone 上 maxWidth 640 自动按可用宽度压缩（iPhone Pro Max 也只 ~398pt 可用），无视觉差异
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 8)
                    // v1.3.4p 第四轮：minHeight 替代 maxHeight——ScrollView 内内容高度由内容决定，
                    // 不足一屏时 minHeight 撑满可视高度（配合 alignment 保持居中），超一屏时可滚动
                    .frame(minHeight: geometry.size.height, alignment: horizontalSizeClass == .regular ? .center : .top)
                    }
                }
                .background(Color.appBackground.ignoresSafeArea())
                .navigationTitle(L10n.shared.focus)
                .navigationBarTitleDisplayMode(.large)
                .task {
                    focusViewModel.restorePendingSessionIfNeeded()
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - 轮次进度（紧凑版）

    private var roundProgressView: some View {
        HStack(spacing: 6) {
            // 审查修复（2026-08-12）：防 0（存储被写 0 时 % 会崩溃，VM 侧用 nonZeroElse 而 View 未防护）
            let safeRounds = max(1, longBreakAfterRounds)
            let completedInCycle = ((focusViewModel.currentRoundIndex - 1) % safeRounds + safeRounds) % safeRounds
            ForEach(0..<safeRounds, id: \.self) { index in
                Circle()
                    .fill(index < completedInCycle
                          ? Color.forPhase(focusViewModel.activePhase)
                          : Color(.systemGray4))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }

            Text(L10n.shared.round(focusViewModel.currentRoundIndex))
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 2)
                .accessibilityLabel(L10n.shared.round(focusViewModel.currentRoundIndex))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color(.systemGray6).opacity(0.7))
        )
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
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
            .environmentObject(SettingsViewModel(syncService: MockSyncService()))
    }
}
#endif