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
    /// 计时模式（番茄钟/正计时）存于 DI 容器而非本地 @State ——
    /// iPad 调窗口触发 sizeClass 跳变、视图重建时本地 @State 会归零（2026-11-22 bug 修复）
    @EnvironmentObject var appDependency: AppDependency
    // 注：taskViewModel / statsViewModel 由本页子视图直接从环境读取，本视图不再重复声明 ——
    // 未使用的 @EnvironmentObject 会让本页无谓订阅其 objectWillChange，并在缺失注入时更早崩溃。
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    /// 正计时（用户反馈 2026-11-19）：入口并入专注主面板，与番茄钟同页切换
    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var l10n: L10n
    // v1.3.4p：iPad 全量适配 — 区分 compact（iPhone 贴顶布局）与 regular（iPad 垂直居中）
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 减少动态效果（2026-11-22）：系统设置开启时直接切换、不播放过渡动画
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 与 FocusViewModel.activePhase 镜像的本地选择（驱动顶部 Segmented 选中态 + 左右滑动切换）
    @State private var selectedPhase: FocusPhase = .focus

    /// 主内容区实测高度（含 minHeight 撑开后的结果），用于决定是否允许纵向滚动
    @State private var contentHeight: CGFloat = 0

    /// 当前是否处于「正计时」模式（false = 番茄钟）。两种计时同属专注，同页切换。
    /// 读写代理到 AppDependency：视图因 iPad 窗口缩放重建时状态不丢失（2026-11-22 修复）。
    private var showStopwatch: Bool {
        get { appDependency.isStopwatchMode }
        nonmutating set { appDependency.isStopwatchMode = newValue }
    }
    /// 切换计时方式时的二次确认（避免番茄钟被静默丢弃）
    @State private var showSwitchToStopwatchConfirm = false
    @State private var showSwitchToPomodoroConfirm = false

    // MARK: - 计时方式切换过渡（2026-11-22 用户反馈）

    /// 切换动画：0.22s 短促过渡（系统原生 API，不自绘）。
    /// `withAnimation` 对 `if` 分支的插入/移除会套用系统默认的淡入淡出过渡，
    /// 因此两个模式的内容区（含顶部阶段分段控件）会一起柔和切换。
    /// 遵循系统「减少动态效果」设置：开启时传 nil，立即切换、不播放动画。
    private var modeSwitchAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    /// 统一切换入口（4 处调用全部走这里，避免遗漏动画）
    private func switchMode(to stopwatch: Bool) {
        withAnimation(modeSwitchAnimation) {
            showStopwatch = stopwatch
        }
    }

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
            // 正计时模式无「专注/短休/长休」阶段语义，故隐藏该分段控件
            if !showStopwatch {
                PhasePickerView(selection: $selectedPhase)
            }

            // child NavigationStack 提供「大标题「专注」」与主内容（v1.3.4i：标题区与其它 Tab 一致，中间不再夹统计卡片）
            NavigationStack {
                Group {
                if showStopwatch {
                    stopwatchContent
                } else {
                GeometryReader { geometry in
                    // v1.3.4p 第四轮：整页不滚动改为 ScrollView 包裹（横屏/分屏/大动态字体时内容超高可滚动），
                    // 用 minHeight 保持原布局语义：内容不足一屏时垂直居中，超一屏时可滚动
                ScrollView {
                        // 一屏布局预算（iPhone 13 Pro content ~665pt）：
                        // large title ~52 + caption ~20 + ring 225 + rounds 24 + button 68 + chips 36 + cards 170 + spacing 50 ≈ 645pt
                        // 余量由 Spacer 吸收，将主按钮组压入拇指热区、卡片区贴底
                        let width = geometry.size.width
                        let height = geometry.size.height

                        // 圆环尺寸分档（2026-11-02 实测收敛）：
                        // - 宽度上限 240（v1.3.4p 从 280 下调：iPad 13" 上更大半径会让外发光
                        //   侵入时间数字底部，形成"贴字"）
                        // - 短屏（可用高 ≤700）：`height*0.24`，13 Pro/17e 上约 156pt。
                        //   该系数经逐轮实测收敛 —— 再大则内容溢出视口、底部统计卡被 TabBar 遮挡
                        // - 大屏（>700）：`width*0.62 / height*0.33`，18 Pro Max 上约 240pt。
                        //   大屏内容本就填不满版面，让圆环吃掉余量，避免全部沉底成大片黑场
                        // - 下限 150（原 180）：旧下限会顶掉系数，导致"自适应"对短屏完全失效
                        let isTallViewport = height > 700
                        let ringSize = min(
                            min(width * (isTallViewport ? 0.62 : 0.56), 240),
                            max(150, height * (isTallViewport ? 0.33 : 0.24))
                        )

                        // 纵向节奏重排（2026-11-02）：
                        // 旧实现用一个统一的 VStack spacing 串起全部元素，再叠加各处零散 padding/Spacer，
                        // 结果是间距实际落在 10~55pt 之间不等，且"按钮附近最松、底部最紧"，看着别扭。
                        // 现改为 spacing: 0 + 逐元素显式 padding，建立统一栅格：
                        //   同组紧邻 10pt ／ 跨组间隔 14pt ／ 主区段 14~19pt
                        // 弹性只保留两处（状态→按钮、按钮→自定义），且设上限，多余空间沉到页面底部。
                        VStack(spacing: 0) {
                        // 大标题「专注」（2026-10-14）：系统导航栏已隐藏，标题改由内容区绘制。
                        // 字号/字重对齐系统 .large 标题（34pt bold），左对齐、水平边距 16，
                        // 与计划/习惯/统计页的视觉层级保持一致。
                        // 2026-11-19（用户反馈）：右侧增加「正计时」入口 —— 番茄钟与正计时同属
                        // 专注计时，集中在本页切换，不再需要去「习惯 → 计时」查找。
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(L10n.shared.focus)
                                .font(.largeTitle.weight(.bold))
                                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                                .accessibilityHeading(.h1)
                                // UI 测试锚点（2026-11-02）：滚动位移断言必须盯 ScrollView **内部**元素，
                                // 此前误用顶部分段控件（位于 ScrollView 之外的 VStack）→ 永远测不出位移。
                                .accessibilityIdentifier("focusLargeTitle")

                            Spacer(minLength: 8)

                            Button {
                                if focusViewModel.timerState == .running || focusViewModel.timerState == .paused {
                                    showSwitchToStopwatchConfirm = true
                                } else {
                                    switchMode(to: true)
                                }
                            } label: {
                                Label(L10n.shared.正计时, systemImage: "stopwatch")
                                    .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            // AX5 下不让切换按钮抢走大标题宽度（文本仍放大到 3xl，可读性不受影响）
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .accessibilityIdentifier("switchToStopwatchButton")
                            .accessibilityHint(L10n.shared.切换计时方式)
                        }

                        // 阶段说明行（跟在大标题下方，与其它 section header 规格一致）
                        // 2026-11-22：字体放大一级（subheadline/footnote）+ 上边距 4→12→18 逐步下移，
                        // 与大标题拉开距离；顶部弹性 Spacer 吸收差值，计时区位置不变
                        PhaseCaptionView()
                            .padding(.top, 18)

                        // 顶部弹性（2026-11-22 布局调整）：与计时区下方的弹性 D 均分剩余空间，
                        // 使计时内容区（圆环+轮次+状态+主按钮）在「页头」与「底部工具条」之间垂直居中。
                        // 无上限——不同屏幕高度下自动平分，天然自适应，无需硬编码尺寸。
                        Spacer(minLength: 0)

                        // 计时圆环 + 轮次泡泡
                        //
                        // 间距（2026-11-02）：spacing 19 —— CircularTimerView 的表盘外框用
                        // `padding(-9)` 向外溢出绘制、**不占布局高度**，故布局间距需多给 9pt，
                        // 视觉间隙才是 10pt。
                        VStack(spacing: 19) {
                            CircularTimerView(progress: progressValue)
                                .frame(width: ringSize, height: ringSize)

                            roundProgressView
                        }
                        .frame(maxWidth: .infinity)
                        // 19 = 视觉间距 10 + 表盘外框向外溢出的 9pt（负 padding 不占布局）
                        .padding(.top, 19)

                        // v1.3.4p 第三轮：状态文字从 CircularTimerView 移出到此，圆环 VStack 之外、独立位置
                        // 避免主按钮覆盖；与「准备就绪/进行中/已暂停/已完成」白底胶囊显示在时间大字下方（用户要求）
                        //
                        // 深色修复（2026-11-02）：底色原为 systemBackground.opacity(0.85) —— 深色下即
                        // 85% 纯黑叠在纯黑页面上，胶囊形体完全消失，只剩红色文字裸浮。
                        // 改为阶段色 14% 淡底：两种模式下都能读出"这是一枚状态标签"，
                        // 且与圆环内 FocusPhaseBadge、进度弧同色系，强化阶段语义。
                        Text(focusViewModel.timerState == .running ? L10n.shared.进行中
                             : focusViewModel.timerState == .paused ? L10n.shared.已暂停
                             : focusViewModel.timerState == .finished ? L10n.shared.已完成
                             : L10n.shared.准备就绪)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color.forPhase(focusViewModel.activePhase))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.forPhase(focusViewModel.activePhase).opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                Color.forPhase(focusViewModel.activePhase).opacity(0.22),
                                                lineWidth: 0.5
                                            )
                                    )
                            )
                            // 与上方「第 N 轮」泡泡的间距（2026-11-02 栅格）：12pt
                            .padding(.top, 12)
                            .accessibilityHidden(true)

                        // 弹性 A：状态标签 → 主按钮
                        // 下限 14 / 上限 20 —— 设下限是关键：纯弹性时短屏会把这段压到 6pt，
                        // 造成"上方 29pt、下方 12pt"的失衡（用户反馈"看着不舒服"）。
                        if horizontalSizeClass == .compact {
                            Spacer(minLength: 14)
                                .frame(maxHeight: 20)
                        }

                        // 高频操作按钮组（开始/暂停 + 停止）
                        // regular（iPad）没有上方弹性 Spacer，需自带间距，
                        // 否则状态标签会被按钮的柔光盖住（2026-11-02 实测）。
                        StartButtonView()
                            .padding(.top, horizontalSizeClass == .regular ? 16 : 0)

                        // 弹性 B：主按钮 → 工具条（2026-11-22 二次调整）
                        // 与「页头 → 计时区」之间的顶部弹性均分剩余空间：计时区落在页头与
                        // 工具条的垂直居中位置，工具条沉底贴住 TabBar。
                        // 无上限、无条件（compact/regular 一致）——随屏幕高度自适应，无需硬编码尺寸。
                        Spacer(minLength: 12)

                        // 辅助工具条（2026-11-22）：时长 / 任务 / 白噪音 / 统计 一行收口，
                        // 功能与原四块完全一致，详见 FocusToolbarView。
                        FocusToolbarView()
                    }
                    // v1.3.4p：iPad 全量适配 — maxWidth 460→640（合并 frame，水平居中）
                    // iPhone 上 maxWidth 640 自动按可用宽度压缩（iPhone Pro Max 也只 ~398pt 可用），无视觉差异
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 16)
                    // 与 TaskListView.titleRow 的 `.padding(.top, 4)` 对齐
                    // （2026-11-02：专注页原为 8，比计划页多 4pt，页头间距不一致）
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    // 内容不足一屏时用 minHeight 撑满可视高度（超一屏则可滚动）。
                    //
                    // 对齐策略（2026-11-02 定案）：
                    // - compact（iPhone）：`.top` —— 大标题必须贴顶，与计划/习惯/统计页的
                    //   「Segment → 贴顶大标题」页头结构保持一致。此前为消除大屏底部留白
                    //   改成居中，导致标题脱离顶部、两页风格不一，已回退。
                    // - regular（iPad）：`.center` —— iPad 可用高度远大于内容，贴顶会在底部
                    //   留下数百点空白；居中才是原有设计（v1.3.4p 起）。
                    .frame(
                        minHeight: geometry.size.height,
                        alignment: horizontalSizeClass == .regular ? .center : .top
                    )
                    // 测量内容真实高度（含 minHeight 撑开后的结果），供下方判断是否需要滚动
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FocusContentHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
                    }
                    // 滚动开关（2026-11-02 二次修复「上滑/下拉后又跳回去」）：
                    //
                    // 首版用 `.scrollBounceBehavior(.basedOnSize)` 无效 —— 该修饰符按
                    // 「内容尺寸 vs 容器尺寸」判定是否放行回弹，只要内容比视口高出哪怕十几点，
                    // 它就判定为"可滚动"，橡皮筋照旧生效。真机录屏逐帧实测：
                    // 下拉时内容整体下移约 96pt 后弹回，与未修复前完全一致。
                    //
                    // 改为按实测高度**硬性禁用滚动**：内容不超过视口（含 0.5pt 浮点容差）时
                    // `.scrollDisabled(true)`，物理上无法产生任何位移；只有真超一屏
                    // （AX5 大字体 / 横屏 / 分屏）才放开，恢复原生滚动与边缘回弹。
                    .onPreferenceChange(FocusContentHeightKey.self) { contentHeight = $0 }
                    .scrollDisabled(contentHeight <= geometry.size.height + 0.5)
                }
                }
                }
                .background(Color.appBackground.ignoresSafeArea())
                .disableBounce()
                .navigationTitle(L10n.shared.focus)
                // 紧凑顶距（2026-10-14）：Picker 位于 NavigationStack **之外**，而大标题由栈内
                // `.large` 模式渲染 —— 系统会在标题上方额外预留一整段导航栏高度，
                // 使 Picker 与「专注」之间出现约 48pt 空白（用户反馈）。
                // 改为隐藏系统导航栏（保留 navigationTitle 供 VoiceOver / 深链标题使用），
                // 由内容区自绘大标题，层级与字号与其它 Tab 保持一致。
                .toolbar(.hidden, for: .navigationBar)
                .task {
                    focusViewModel.restorePendingSessionIfNeeded()
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        // 左右滑动切换顶部「专注 / 短休 / 长休」标签（与竖向滚动不冲突）
        // 正计时模式下无阶段语义，滑动不再切阶段
        .swipeToSwitchTab(
            onSwipeLeft: { if !showStopwatch { switchPhase(by: 1) } },
            onSwipeRight: { if !showStopwatch { switchPhase(by: -1) } }
        )
        // 番茄钟 → 正计时：确认后按「提前结束」落库（净时长保留，状态 earlyCompleted）
        .confirmationDialog(
            L10n.shared.正计时,
            isPresented: $showSwitchToStopwatchConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.shared.正计时) {
                focusViewModel.abandonSession(reason: nil)
                switchMode(to: true)
            }
            Button(L10n.shared.取消, role: .cancel) {}
        } message: {
            Text(L10n.shared.切换至正计时确认)
        }
        // 正计时 → 番茄钟：确认后结束并记录当前净时长
        .confirmationDialog(
            L10n.shared.返回番茄钟,
            isPresented: $showSwitchToPomodoroConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.shared.确定) {
                timeRecordViewModel.stopRecording()
                switchMode(to: false)
            }
            Button(L10n.shared.取消, role: .cancel) {}
        } message: {
            Text(L10n.shared.切换至番茄钟确认)
        }
        .onAppear { selectedPhase = focusViewModel.activePhase }
        .onChange(of: selectedPhase) { _, newPhase in
            // 用户点击 Segmented 或左右滑动 → 切换阶段（运行中由 ViewModel 自行处理 abandon）
            if newPhase != focusViewModel.activePhase {
                focusViewModel.switchPhase(newPhase)
            }
        }
        .onChange(of: focusViewModel.activePhase) { _, newPhase in
            // 阶段被其它路径改变（如自动流转）→ 同步回 Segmented 选中态
            selectedPhase = newPhase
        }
    }

    /// 按方向切换阶段（向左 = 下一个，向右 = 上一个），边界处夹紧不回环
    private func switchPhase(by direction: Int) {
        let order = FocusPhase.allCases
        guard let idx = order.firstIndex(of: selectedPhase) else { return }
        let newIdx = min(max(idx + direction, 0), order.count - 1)
        if newIdx != idx {
            selectedPhase = order[newIdx]
        }
    }

    // MARK: - 正计时模式（2026-11-19 用户反馈：番茄钟与正计时同属专注，集中在本页）

    /// 正计时面板：复用 TimeRecordView 的 embedded 形态（开始 / 暂停 / 继续 / 停止 + 今日合计 + 最近记录）
    private var stopwatchContent: some View {
        Group {
            if horizontalSizeClass == .regular {
                // v1.3.5 iPad（2026-11-22 用户定夺）：正计时内容铺满整个 detail 区——
                // · 宽度：maxWidth:.infinity 自适应窗口（横竖屏/分屏自动跟随），卡片 padding 16 留边距。
                // · 高度：不再垂直居中，改为顶部起排 + minHeight 撑满视口；
                //   底部「最近记录」卡由 TimeRecordView 在 regular 下拉伸填满剩余高度，
                //   从而上下铺满、消除大片留白（用户明确要求"上下也铺满"）。
                GeometryReader { geometry in
                    ScrollView {
                        stopwatchInner
                            .frame(maxWidth: .infinity, alignment: .top)
                            .frame(
                                minHeight: geometry.size.height,
                                alignment: .top
                            )
                    }
                    .disableBounce()
                }
            } else {
                // iPhone（compact）：贴顶 + 640 限宽。因 embeddedBody 已移除自带 ScrollView
                // （见 H1），此处补 ScrollView 保证内容超高（AX 大字体/横屏）仍可滚动。
                ScrollView {
                    stopwatchInner
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disableBounce()
            }
        }
    }

    /// 正计时内容主体（标题行 + 嵌入计时面板），两种 sizeClass 共用
    private var stopwatchInner: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.shared.正计时)
                    .font(.largeTitle.weight(.bold))
                    // 无障碍：与其它页大标题一致，标记为一级标题
                    .accessibilityHeading(.h1)
                    .accessibilityIdentifier("stopwatchLargeTitle")

                Spacer(minLength: 8)

                Button {
                    // 正计时仍在跑时先确认，避免用户以为「切回去就停了」而漏记
                    if timeRecordViewModel.isRecording {
                        showSwitchToPomodoroConfirm = true
                    } else {
                        switchMode(to: false)
                    }
                } label: {
                    Label(L10n.shared.返回番茄钟, systemImage: "timer")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityIdentifier("switchToPomodoroButton")
                .accessibilityHint(L10n.shared.切换计时方式)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)

            TimeRecordView(embedded: true)
                // v1.3.5 iPad（2026-11-22）：吃掉标题以下的剩余高度，
                // 使 embeddedBody 的记录卡能拉伸铺到 detail 区底部（compact 保持自然高度）。
                .if(horizontalSizeClass == .regular) {
                    $0.frame(maxHeight: .infinity, alignment: .top)
                }
        }
        .if(horizontalSizeClass == .regular) {
            // stopwatchInner 自身撑满外层 minHeight 分配的高度
            $0.frame(maxHeight: .infinity, alignment: .top)
        }
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

// MARK: - 内容高度测量（2026-11-02）
// 专注页整页不滚动是设计目标，但必须为大字体 / 横屏 / 分屏保留滚动能力。
// 通过 preference 把内容实测高度上抛，由 FocusView 决定 `.scrollDisabled` 的取值。

private struct FocusContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
struct FocusView_Previews: PreviewProvider {
    static var previews: some View {
        FocusView()
            .environmentObject(AppDependency())
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
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(TimeRecordViewModel(
                timeRecordService: TimeRecordService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif