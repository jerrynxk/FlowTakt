import SwiftUI

// MARK: - TimeRecordView

struct TimeRecordView: View {
    /// 嵌入专注主面板（用户反馈 2026-11-19「正计时入口应在专注主面板」）：
    /// true 时不自建 NavigationStack、不显示「计时」大标题与日期选择，
    /// 只保留「大计时 + 今日合计 + 控制 + 最近记录」，页头与导航上下文由父视图提供。
    var embedded: Bool = false

    /// 列表里最小可展示的记录时长（1 秒）。
    /// 误触「开始」随即「停止」会留下亚秒级记录，`durationText` 会渲染成「0分钟」，
    /// 连续出现时列表全是无意义条目（2026-11-19 审查）。进行中的记录不受此限。
    private static let minimumVisibleRecordDuration: TimeInterval = 1

    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n
    // 无障碍修复（2026-08-12）：尊重「减少动态效果」
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // v1.3.5（2026-11-22）：iPad（regular）正计时内容需上下铺满 detail 区——
    // 记录卡拉伸吃掉剩余高度；iPhone（compact）保持自然高度。
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTask: Task?
    @State private var elapsedTime: TimeInterval = 0
    @State private var isPulsing = false

    /// 选中日期的记录（按时间倒序）
    ///
    /// 过滤掉「已结束且时长为 0」的记录（2026-11-19 审查）：误触开始后立即停止会留下
    /// 0 分钟的记录，列表与「最近记录」会被这类噪音刷屏（实际截图可见连续三条 0 分钟）。
    /// 进行中的记录（endTime == nil）始终保留，避免正在计时却不显示。
    private var recordsForDate: [TimeRecord] {
        timeRecordViewModel.records
            .filter { $0.startTime.isSameDay(as: timeRecordViewModel.selectedDate) }
            .filter { $0.endTime == nil || $0.duration >= Self.minimumVisibleRecordDuration }
            .sorted { $0.startTime > $1.startTime }
    }

    /// 可选任务列表（仅活跃任务）
    private var availableTasks: [Task] {
        taskViewModel.activeTasks
    }

    /// 当前计时经过时间的显示文本
    private var elapsedTimeDisplay: String {
        let totalSeconds = Int(elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// 今日总时长的显示文本
    /// 修复（P2）：标题随所选日期变化 —— 原标题恒为「今日总计」，
    /// 数字却是所选那天的合计（选中历史日期时文案与数据不符）。
    private var totalTitle: String {
        Calendar.current.isDateInToday(timeRecordViewModel.selectedDate)
            ? L10n.shared.今日总计
            : L10n.shared.所选日期总计
    }

    private var formattedTotal: String {
        // 统一走 TimeInterval.formattedDuration（2026-11-19 审查）：
        // 旧实现硬拼「X小时Y分钟」，0 时长会显示成「0小时0分钟」，
        // 且不足 1 分钟时也显示 0，与其它页的时长文案不一致。
        timeRecordViewModel.totalDurationToday.formattedDuration
    }

    @State private var elapsedTimer: Timer?

    // MARK: - Body

    var body: some View {
        Group {
            if embedded {
                embeddedBody
            } else {
                standaloneBody
            }
        }
        // 生命周期统一挂在外层（两种形态语义相同）：
        // 切走时不清零显示、开始/停止时启停秒表、视图重建时补建计时器。
        .onDisappear {
            stopElapsedTimer(resetElapsed: false)
        }
        .onChange(of: timeRecordViewModel.selectedDate) { _, _ in
            timeRecordViewModel.refreshTodayTotal()
            // 修复（2026-10-14 P2）：录制中切换日期时不应把大数字清零
            // （计时仍在继续，清零会造成「闪 00:00」的误导）
            if !timeRecordViewModel.isRecording { elapsedTime = 0 }
        }
        .onChange(of: timeRecordViewModel.isRecording) { _, isRecording in
            if isRecording {
                startElapsedTimer()
            } else {
                stopElapsedTimer()
            }
        }
        // 修复（2026-10-14 审查 P1-11）：从「习惯 / 热力图」子标签切回时本视图被销毁重建，
        // isRecording 值未变化 → onChange 不触发 → 计时器永不重建，大数字永久冻结在 00:00
        //（计时本身未停、数据未丢，属显示误导）。onAppear 补建。
        .onAppear {
            if timeRecordViewModel.isRecording { startElapsedTimer() }
        }
    }

    // MARK: - Body（独立页形态：自带导航栈与日期选择）

    private var standaloneBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题行：「计时」大标题（本页无操作按钮），紧贴顶部分段控件（2026-10-14）。
                // 消除系统 .large 大标题在分段控件下方留下的导航栏空档。
                titleRow

                List {
                    todayTotalSection
                    datePickerSection
                    recordingSection
                    recordsSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
                .disableBounce()
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.计时)
            // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件。
            // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Body（嵌入形态：专注主面板内的正计时）

    private var embeddedBody: some View {
        // v1.3.5 iPad 复查 H1（2026-11-22）：移除自带的 ScrollView ——
        // 嵌套 ScrollView 会撑满父级剩余空间，导致外层（FocusView.stopwatchContent）的
        // minHeight 垂直居中失效（iPad 上正计时贴顶、底部大留白）。
        // 滚动统一交给外层 stopwatchContent 的 ScrollView（compact/regular 两个分支都有）。
        VStack(spacing: 12) {
            embeddedTimerCard
            embeddedControlCard
            // 2026-11-22：补回独立页独有的「查看历史日期 + 删除记录」能力
            // ——习惯 tab 计时页移除后，这两项能力只保留在本嵌入形态。
            embeddedDatePickerCard
            embeddedRecentCard
                // v1.3.5（2026-11-22）：iPad（regular）正计时上下铺满 ——
                // 记录卡是列表区，让其拉伸吃掉剩余高度，从日期卡底部一直铺到屏幕底部；
                // 顶部三张卡保持自然高度。iPhone（compact）保持原样。
                .if(horizontalSizeClass == .regular) {
                    $0.frame(maxHeight: .infinity, alignment: .top)
                }
        }
        .if(horizontalSizeClass == .regular) {
            // VStack 本身撑满外层（stopwatchInner）分配的高度，记录卡才有剩余空间可吃
            $0.frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color.appBackground)
    }

    /// 嵌入形态的日期选择器：切换后记录列表与合计跟随所选日期（与独立页同一 selectedDate）。
    private var embeddedDatePickerCard: some View {
        DatePicker(
            L10n.shared.选择日期,
            selection: $timeRecordViewModel.selectedDate,
            in: ...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .cardStyle()
    }

    /// 嵌入形态的大计时卡：净计时（扣除暂停段）+ 今日合计
    private var embeddedTimerCard: some View {
        VStack(spacing: 4) {
            Text(elapsedTimeDisplay)
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(timeRecordViewModel.isRecording ? .primary : .secondary)
                .contentTransition(.numericText())
                // 无障碍：等宽数字读屏会被念成「0 冒号 0」，改为语义化时长
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityLabel(L10n.shared.已计时(Int(elapsedTime)))

            Text(recordingStateText)
                .font(.caption.weight(.medium))
                .foregroundColor(timeRecordViewModel.isRecording && !timeRecordViewModel.isPaused
                                 ? .focusRed : .secondary)

            Divider()
                .padding(.vertical, 6)

            HStack {
                Text(embeddedTotalTitle)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                Text(todayTotalDuration.formattedDuration)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        // 2026-11-22：并入 recordingStateText —— 空闲态的引导说明（正计时说明）
        // 在 embedded 形态无其它出口，漏并入会导致读屏用户听不到任何引导。
        .accessibilityLabel(
            "\(L10n.shared.正计时)，\(recordingStateText)，\(L10n.shared.已计时(Int(elapsedTime)))，\(embeddedTotalTitle) \(todayTotalDuration.formattedDuration)"
        )
    }

    /// 嵌入形态合计标题：今日=今日专注时长，历史日期=所选日期总计
    private var embeddedTotalTitle: String {
        Calendar.current.isDateInToday(timeRecordViewModel.selectedDate)
            ? L10n.shared.今日专注时长
            : L10n.shared.所选日期总计
    }

    /// 嵌入形态的控制卡：复用独立页的开始 / 暂停继续 / 停止控件，保证两种入口手感一致
    private var embeddedControlCard: some View {
        Group {
            if timeRecordViewModel.isRecording {
                recordingActiveView
            } else {
                recordingIdleView
            }
        }
        // 2026-11-22：固定卡片尺寸 —— idle 态（选择器+提示+开始）与计时态（状态+按钮组）
        // 内容高度不同，切换时会跳动。统一给最小高度并垂直居中，两态卡片大小一致。
        // 用 minHeight 而非 height：内容（大字体/任务名）超出时不裁切，仍可自然撑开。
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        .padding(12)
        .cardStyle()
    }

    /// 嵌入形态的记录列表：跟随 selectedDate（2026-11-22 补历史日期查看能力）。
    /// 判定与独立页 recordsForDate 同一套（最小可见时长 + 进行中记录始终保留）。
    private var todayRecords: [TimeRecord] {
        timeRecordViewModel.records
            .filter { $0.startTime.isSameDay(as: timeRecordViewModel.selectedDate) }
            .filter { $0.endTime == nil || $0.duration >= Self.minimumVisibleRecordDuration }
            .sorted { $0.startTime > $1.startTime }
    }

    /// 嵌入形态的合计：跟随 selectedDate。
    /// 今日=走 Service 精确口径（扣暂停段）；历史日期=按记录 duration 汇总。
    private var todayTotalDuration: TimeInterval {
        let calendar = Calendar.current
        if calendar.isDateInToday(timeRecordViewModel.selectedDate) {
            return timeRecordViewModel.totalDurationToday
        }
        return timeRecordViewModel.records
            .filter { $0.startTime.isSameDay(as: timeRecordViewModel.selectedDate) }
            .reduce(0) { $0 + $1.duration }
    }

    private var embeddedRecentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(embeddedRecordSectionTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.primary)
                    .accessibilityHeading(.h2)
                Spacer(minLength: 8)
            }

            if todayRecords.isEmpty {
                Text(L10n.shared.暂无记录)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(todayRecords) { record in
                    HStack(spacing: 6) {
                        TimeRecordRowView(
                            record: record,
                            isCurrentRecord: record == timeRecordViewModel.currentRecord,
                            liveElapsed: record == timeRecordViewModel.currentRecord ? elapsedTime : nil
                        )
                        // 2026-11-22：嵌入形态补回删除能力（独立页原靠左滑删除）。
                        // 进行中的记录不提供删除按钮，避免计时中误删导致状态混乱。
                        if record != timeRecordViewModel.currentRecord {
                            Button {
                                HapticManager.shared.selectionFeedback()
                                timeRecordViewModel.deleteRecord(record)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                                    .frame(width: 30, height: 30)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // 2026-11-22：删除是破坏性操作，label 需可区分——
                            // 原仅「删除+时长」，同日多条等长记录时读屏无法分辨删哪条，
                            // 且英文直接拼接无分隔（"Delete5 min"）。补任务名/时间范围并用逗号分隔。
                            .accessibilityLabel(
                                "\(L10n.shared.删除)，\(record.task?.title ?? L10n.shared.无任务)，\(record.durationText)，\(record.timeRangeText)"
                            )
                        }
                    }
                    if record.id != todayRecords.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .padding(12)
        .cardStyle()
    }

    /// 记录卡标题：今日=最近记录，历史日期=记录
    private var embeddedRecordSectionTitle: String {
        Calendar.current.isDateInToday(timeRecordViewModel.selectedDate)
            ? L10n.shared.最近记录
            : L10n.shared.记录
    }

    /// 正计时状态文案（未开始 / 计时中 / 已暂停）
    private var recordingStateText: String {
        if !timeRecordViewModel.isRecording { return L10n.shared.正计时说明 }
        return timeRecordViewModel.isPaused ? L10n.shared.已暂停 : L10n.shared.正在计时
    }

    // MARK: - Title Row

    /// 创建/重建秒级计时器（幂等）。录制开始、视图重新出现时调用。
    private func startElapsedTimer() {
        guard elapsedTimer == nil else { return }
        // 用户反馈 2026-11-17：显示净计时（扣除暂停段），与结束时落库的 duration 同判据。
        // 每次 tick 经 ViewModel → Service 计算，暂停时数值冻结、继续后接着走。
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.elapsedTime = self.timeRecordViewModel.currentNetElapsed()
        }
        // 立即显示一次
        self.elapsedTime = timeRecordViewModel.currentNetElapsed()
    }

    /// 停止计时器；`resetElapsed` 为 true 时同时清零显示（录制结束时清、切走时不清）
    private func stopElapsedTimer(resetElapsed: Bool = true) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        if resetElapsed {
            elapsedTime = 0
            isPulsing = false
        }
    }

    /// 标题行：「计时」大标题（本页无操作按钮）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.计时)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - 今日总时长

    private var todayTotalSection: some View {
        Section {
            VStack(spacing: 6) {
                Text(formattedTotal)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.top, 12)
                    // 无障碍：计时大数字限制动态字体放大（避免大字号模式溢出），值由下方合并元素朗读
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

                Text(totalTitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            // 无障碍：合并朗读；标题跟随所选日期（2026-11-22 补：选中历史日期时
            // 可视文案已是「所选日期总计」，label 原硬编码「今日总计」会造成文案矛盾）。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(totalTitle) \(formattedTotal)")
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 日期选择器

    private var datePickerSection: some View {
        Section {
                DatePicker(
                    L10n.shared.选择日期,
                    selection: $timeRecordViewModel.selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
            .datePickerStyle(.compact)
        }
    }

    // MARK: - 计时控制

    @ViewBuilder
    private var recordingSection: some View {
        Section {
            if timeRecordViewModel.isRecording {
                recordingActiveView
            } else {
                recordingIdleView
            }
        }
    }

    /// 未计时状态：任务选择器 + 开始按钮
    private var recordingIdleView: some View {
        VStack(spacing: 16) {
            // 任务选择器
            Picker(L10n.shared.关联任务, selection: $selectedTask) {
                Text(L10n.shared.无任务).tag(nil as Task?)
                ForEach(availableTasks) { task in
                    Text(task.title).tag(task as Task?)
                }
            }
            .pickerStyle(.menu)

            // 无可用任务时提示
            if availableTasks.isEmpty {
                Text(L10n.shared.无可用任务)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // 开始计时按钮
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    timeRecordViewModel.startRecording(task: selectedTask)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 80, height: 80)
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                    VStack(spacing: 2) {
                        Image(systemName: "play.fill")
                            .font(.title3)
                        Text(L10n.shared.开始计时)
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("startTimeRecordButton")
            .accessibilityLabel(L10n.shared.开始计时)
        }
    }

    /// 计时中状态：脉冲指示器 + 经过时间 + 停止按钮
    private var recordingActiveView: some View {
        VStack(spacing: 16) {
            // 当前任务名
            if let task = timeRecordViewModel.currentRecord?.task {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.caption)
                        .foregroundColor(Color.forPriority(task.priority))
                    Text(task.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 计时指示器
            HStack(spacing: 10) {
                Circle()
                    .fill(timeRecordViewModel.isPaused ? Color.secondary : Color.focusRed)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.4 : 0.8)
                    .opacity(isPulsing ? 0.5 : 1.0)
                    .onAppear {
                        // 无障碍修复：减少动态效果时静态显示，不启动 repeatForever 脉冲
                        if reduceMotion {
                            isPulsing = true
                        } else {
                            withAnimation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            ) {
                                isPulsing = true
                            }
                        }
                    }

                Text(timeRecordViewModel.isPaused ? L10n.shared.已暂停 : L10n.shared.正在计时)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // 2026-11-22：嵌入形态（正计时页）上方大计时卡已有大号计时，
                // 这里的红色小计时重复（用户反馈），仅在嵌入形态隐藏。
                // 独立计时页里它是唯一的当前计时显示，保留。
                if !embedded {
                    Spacer()

                    Text(elapsedTimeDisplay)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(timeRecordViewModel.isPaused ? .secondary : .focusRed)
                        .contentTransition(.numericText())
                        // 无障碍补齐（2026-11-02）：等宽数字会被读成「05 冒号 32」，
                        // 改为语义化时长文本「已计时 5 分 32 秒」
                        .accessibilityLabel(L10n.shared.已计时(Int(elapsedTime)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // 控制按钮组：暂停/继续（用户反馈 2026-11-17）+ 停止
            HStack(spacing: 40) {
                // 暂停 / 继续
                Button {
                    if timeRecordViewModel.isPaused {
                        timeRecordViewModel.resumeRecording()
                    } else {
                        timeRecordViewModel.pauseRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color(.secondarySystemGroupedBackground))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle().strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                            )
                        Image(systemName: timeRecordViewModel.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pauseResumeTimeRecordButton")
                .accessibilityLabel(timeRecordViewModel.isPaused ? L10n.shared.恢复 : L10n.shared.暂停)

                // 停止计时
                Button {
                    timeRecordViewModel.stopRecording()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.focusRed)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.focusRed.opacity(0.3), radius: 8, x: 0, y: 4)

                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stopTimeRecordButton")
                .accessibilityLabel(L10n.shared.停止)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .transition(.scale.combined(with: .opacity))

            // 暂停态说明：明确告知用户暂停段不计入时长
            // 2026-11-22：用 opacity 隐藏而非 if 移除 —— 始终占位，保持两态内容高度一致，
            // 否则外层居中布局下按钮组会在「正在计时 / 已暂停」切换时上下跳动（用户反馈）。
            Text(L10n.shared.暂停段不计入时长)
                .font(.caption)
                .foregroundColor(.secondary)
                .opacity(timeRecordViewModel.isPaused ? 1 : 0)
                .accessibilityHidden(!timeRecordViewModel.isPaused)
        }
    }

    // MARK: - 记录列表

    private var recordsSection: some View {
        Section {
            if recordsForDate.isEmpty {
                emptyRecordsView
            } else {
                ForEach(recordsForDate) { record in
                    TimeRecordRowView(
                        record: record,
                        isCurrentRecord: record == timeRecordViewModel.currentRecord,
                        liveElapsed: record == timeRecordViewModel.currentRecord ? elapsedTime : nil
                    )
                }
                .onDelete { indexSet in
                    deleteRecords(at: indexSet)
                }
            }
        } header: {
            Text(L10n.shared.记录)
        }
    }

    private var emptyRecordsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
                // 无障碍（2026-10-14）：空状态装饰图标不单独朗读
                .accessibilityHidden(true)

            Text(L10n.shared.暂无记录)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(L10n.shared.点击上方按钮开始计时)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    /// 删除指定索引集合的记录。
    ///
    /// 崩溃修复（2026-10-02）：`recordsForDate` 是**计算属性**，每次访问都会基于最新的
    /// `timeRecordViewModel.records` 重新 filter + sort。而 `deleteRecord` 内部会调
    /// `loadRecords()` 把 `records` 整体替换为新数组，导致同一轮删除中后续索引对应的
    /// 记录已被移除 → `recordsForDate[index]` 越界，触发 `Fatal error: Index out of range`。
    ///
    /// 修复（2026-10-14 审查 T1）：守卫下沉到 `TimeRecordViewModel.deleteRecords(at:in:)`，
    /// View 只传快照 —— 使该崩溃点可被单元测试直接覆盖（原先守卫写在 View 的 private 方法里，
    /// 测试只能自己复刻一遍逻辑，形成「自证循环」的假绿用例）。
    private func deleteRecords(at indexSet: IndexSet) {
        timeRecordViewModel.deleteRecords(at: indexSet, in: recordsForDate)
    }
}

// MARK: - TimeRecordRowView

private struct TimeRecordRowView: View {
    let record: TimeRecord
    var isCurrentRecord: Bool = false
    var liveElapsed: TimeInterval? = nil

    private var liveDurationText: String {
        if let elapsed = liveElapsed {
            let totalMinutes = Int(elapsed) / 60
            if totalMinutes >= 60 {
                let hours = totalMinutes / 60
                let mins = totalMinutes % 60
                if mins > 0 { return "\(hours)h \(mins)m" }
                return "\(hours)h"
            }
            let seconds = Int(elapsed) % 60
            if totalMinutes > 0 { return "\(totalMinutes)m \(seconds)s" }
            return "\(seconds)s"
        }
        return record.durationText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：任务名 + 计费标记 + 时长
            HStack(spacing: 0) {
                // 任务名
                HStack(spacing: 4) {
                    if let task = record.task {
                        Circle()
                            .fill(Color.forPriority(task.priority))
                            .frame(width: 8, height: 8)
                            // 2026-11-22 审查 M6：纯装饰色点不单独朗读
                            .accessibilityHidden(true)
                        Text(task.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else {
                        Text(L10n.shared.无任务)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                // 计费标记
                if record.isBillable {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.trailing, 6)
                        // 2026-11-22 审查 M6：计费标记靠 label 语义表达，图标装饰隐藏
                        .accessibilityHidden(true)
                }

                // 时长
                HStack(spacing: 4) {
                    if isCurrentRecord {
                        Circle()
                            .fill(Color.focusRed)
                            .frame(width: 8, height: 8)
                            // 2026-11-22 审查 M6：进行中标记装饰隐藏（状态由行 label 表达）
                            .accessibilityHidden(true)
                    }
                    Text(liveDurationText)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isCurrentRecord ? .focusRed : .primary)
                        .monospacedDigit()
                }
            }

            // 第二行：项目 + 时间范围
            HStack(spacing: 12) {
                if let project = record.project, !project.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.caption2)
                            // 2026-11-22 审查 M6：装饰图标不单独朗读
                            .accessibilityHidden(true)
                        Text(project)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Text(record.timeRangeText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // 备注
            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#if DEBUG
struct TimeRecordView_Previews: PreviewProvider {
    static var previews: some View {
        TimeRecordView()
            .environmentObject(TimeRecordViewModel(
                timeRecordService: TimeRecordService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .environmentObject(L10n.shared)
    
}
}
#endif
