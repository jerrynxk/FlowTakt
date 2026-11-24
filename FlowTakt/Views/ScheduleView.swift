import SwiftUI

// MARK: - ScheduleView

struct ScheduleView: View {
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n
    @EnvironmentObject var appDependency: AppDependency

    @State private var showNewEventSheet = false
    @State private var editingEvent: ScheduleItem? = nil
    /// 来自 Widget 深链（flowtakt://schedule/<id>）待高亮的事件
    @State private var highlightedEventID: UUID? = nil
    /// 视图模式：月 / 周（A4）
    @State private var viewMode: ScheduleViewMode = .month
    /// 自然语言快速添加（B2）
    @State private var showQuickAddAlert = false
    @State private var quickAddText = ""

    /// 日程视图模式
    enum ScheduleViewMode: String, CaseIterable, Identifiable {
        case month
        case week
        var id: String { rawValue }
    }

    private let calendar = Calendar.current
    private let weekdaySymbols: [String] = {
        let cal = Calendar.current
        let syms = cal.veryShortWeekdaySymbols
        let firstWeekday = cal.firstWeekday // 1=Sunday, 2=Monday, etc.
        if firstWeekday == 1 {
            // Sunday-first locale: keep as-is（已是周日开头）
            return syms
        } else {
            // Monday-first / 其他 locale：旋转到指定首日
            let prefix = Array(syms[(firstWeekday - 1)...])
            let suffix = Array(syms[..<(firstWeekday - 1)])
            return prefix + suffix
        }
    }()

    // 缓存 DateFormatter 实例（避免 body 重绘时重复创建）
    private static let monthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
        return formatter
    }()

    private static let selectedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEE")
        return formatter
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 标题行：「日程」大标题与操作按钮（⚡快速添加 / ＋新建事件）并排一行，
                // 紧贴顶部分段控件（2026-10-14）。
                // 原先两个按钮挂在导航栏 primaryAction、大标题由 .large 模式渲染，
                // 系统把按钮渲染在标题上方并额外预留导航栏高度，视觉上下分离；
                // 现改为内容区自绘标题行，与「任务」页（TaskListView）保持同构。
                titleRow

                // 月 / 周 视图切换
                Picker("", selection: $viewMode) {
                    Text(L10n.shared.月视图).tag(ScheduleViewMode.month)
                    Text(L10n.shared.周视图).tag(ScheduleViewMode.week)
                }
                .pickerStyle(.segmented)
                // 修复（P2-40）：与今日已补的四处分段控件保持同一无障碍约定
                .accessibilityLabel(L10n.shared.视图切换)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .onChange(of: viewMode) { _, mode in
                    if mode == .week {
                        scheduleViewModel.refreshForWeek(containing: scheduleViewModel.selectedDate)
                    }
                }

                if viewMode == .month {
                    monthHeader
                    weekdayHeader
                    calendarGrid
                } else {
                    weekView
                }

                Divider()
                    .padding(.horizontal, 16)

                eventList
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.日程)
            // 隐藏系统导航栏，标题行成为内容首项、紧贴顶部分段控件（2026-10-14）。
            // 保留 navigationTitle 供 VoiceOver / 深链标题使用。
            .toolbar(.hidden, for: .navigationBar)
            // 消费来自 Widget 深链的具体事件定位（flowtakt://schedule/<id>）
            .onReceive(appDependency.$pendingScheduleItemID) { id in
                guard let id, !id.isEmpty else { return }
                guard let uuid = UUID(uuidString: id) else {
                    appDependency.pendingScheduleItemID = nil
                    return
                }
                // 先查当前已加载（当月）事件；若目标事件在下月（如生日/纪念日），
                // 经 Service 按 ID 全库定位后切换月份再高亮，避免深链静默丢失
                guard let event = scheduleViewModel.events.first(where: { $0.id == uuid })
                    ?? scheduleViewModel.findEvent(byID: uuid) else {
                    appDependency.pendingScheduleItemID = nil
                    return
                }
                if !scheduleViewModel.events.contains(where: { $0.id == event.id }) {
                    scheduleViewModel.refreshForMonth(event.startDate)
                }
                scheduleViewModel.refreshForDate(event.startDate)
                // 先清后设，确保连续两次点击 Widget 中同一事件也能重新高亮
                highlightedEventID = nil
                DispatchQueue.main.async { highlightedEventID = event.id }
                appDependency.pendingScheduleItemID = nil
            }
            .alert(L10n.shared.快速添加日程, isPresented: $showQuickAddAlert) {
                TextField(L10n.shared.快速添加提示, text: $quickAddText)
                Button(L10n.shared.取消, role: .cancel) {}
                Button(L10n.shared.确定) {
                    handleQuickAdd()
                }
            } message: {
                Text(L10n.shared.快速添加提示)
            }
            .sheet(isPresented: $showNewEventSheet) {
                EventEditView(
                    isPresented: $showNewEventSheet,
                    editingEvent: nil,
                    initialDate: scheduleViewModel.selectedDate
                ) { data in
                    scheduleViewModel.createEvent(
                        title: data.title,
                        startDate: data.startDate,
                        endDate: data.endDate,
                        isAllDay: data.isAllDay,
                        location: data.location,
                        notes: data.notes,
                        colorHex: data.colorHex,
                        category: data.category,
                        repeatRule: data.category.repeatsYearly ? .yearly : RepeatRule.none,
                        reminderEnabled: data.reminderEnabled,
                        reminderLeadMinutes: data.reminderLeadMinutes,
                        task: nil
                    )
                }
            }
            .sheet(item: $editingEvent) { event in
                EventEditView(
                    isPresented: Binding(
                        get: { editingEvent != nil },
                        set: { if !$0 { editingEvent = nil } }
                    ),
                    editingEvent: event,
                    initialDate: scheduleViewModel.selectedDate
                ) { data in
                    scheduleViewModel.updateEvent(
                        event,
                        title: data.title,
                        startDate: data.startDate,
                        endDate: data.endDate,
                        isAllDay: data.isAllDay,
                        location: data.location,
                        notes: data.notes,
                        colorHex: data.colorHex,
                        category: data.category,
                        repeatRule: data.category.repeatsYearly ? .yearly : RepeatRule.none,
                        reminderEnabled: data.reminderEnabled,
                        reminderLeadMinutes: data.reminderLeadMinutes
                    )
                }
            }
        }
    }

    // MARK: - Title Row

    /// 标题行：「日程」大标题 + 「⚡快速添加」「＋新建事件」按钮（同一行）。
    /// 规格对齐 TaskListView.titleRow：largeTitle.bold、水平边距 16、按钮 44×44 命中区、focusRed 着色。
    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.shared.日程)
                .font(.largeTitle.weight(.bold))
                // 无障碍（2026-10-14）：大标题标记为一级标题（VoiceOver 转子可按标题跳转）
                .accessibilityHeading(.h1)
            Spacer(minLength: 12)

            // 自然语言快速添加（B2）
            Button {
                quickAddText = ""
                showQuickAddAlert = true
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.focusRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.快速添加日程)

            Button {
                showNewEventSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.focusRed)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.新建事件)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let prevMonth = calendar.date(byAdding: .month, value: -1, to: scheduleViewModel.currentMonth) {
                        scheduleViewModel.refreshForMonth(prevMonth)
                        // 切月后，如果 selectedDate 不在新月份内，自动调整到新月份的 1 号
                        let adjusted = adjustSelectedDate(to: prevMonth)
                        scheduleViewModel.refreshForDate(adjusted)
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.focusRed)
            }
            .accessibilityLabel(L10n.shared.上一月)

            Spacer()

            VStack(spacing: 2) {
                Text(monthYearText)
                    .font(.title2)
                    .fontWeight(.bold)

                if let lunarText = LunarCalendar.lunarDateString(from: scheduleViewModel.currentMonth) {
                    Text(lunarText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: scheduleViewModel.currentMonth) {
                        scheduleViewModel.refreshForMonth(nextMonth)
                        let adjusted = adjustSelectedDate(to: nextMonth)
                        scheduleViewModel.refreshForDate(adjusted)
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.focusRed)
            }
            .accessibilityLabel(L10n.shared.下一月)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// 调整 selectedDate 到目标月份（若 selectedDate 不在目标月份内）
    private func adjustSelectedDate(to month: Date) -> Date {
        if calendar.isDate(scheduleViewModel.selectedDate, equalTo: month, toGranularity: .month) {
            return scheduleViewModel.selectedDate
        }
        // 切到新月份，默认选中该月 1 号
        let components = calendar.dateComponents([.year, .month], from: month)
        return calendar.date(from: components) ?? month
    }

    private var monthYearText: String {
        Self.monthYearFormatter.string(from: scheduleViewModel.currentMonth)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = generateDays()
        // 预计算事件按天分组字典，将网格内 O(n×m) 降为 O(1) 查询
        let eventsByDay = eventsByDayDictionary

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            // 动态格数（审查修复：注释不再声称"固定 42 格"——generateDays() 依月份首日
            // 周位置生成 28~42 格，月末最后一行可能不满 7 格）；索引作 id 在此场景安全
            ForEach(days.indices, id: \.self) { index in
                if let date = days[index] {
                    dayCell(date: date, hasEvents: eventsByDay[calendar.startOfDay(for: date)] != nil)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Week View（A4）

    /// 周视图：一周 7 天分区，每天列出事件（可点击编辑）
    private var weekView: some View {
        VStack(spacing: 0) {
            // 周导航头部
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleViewModel.shiftWeek(by: -1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.focusRed)
                }
                .accessibilityLabel(L10n.shared.上一周)

                Spacer()

                Text(weekRangeText)
                    .font(.headline)
                    .fontWeight(.bold)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scheduleViewModel.shiftWeek(by: 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.focusRed)
                }
                .accessibilityLabel(L10n.shared.下一周)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            List {
                ForEach(0..<7, id: \.self) { offset in
                    if let day = calendar.date(byAdding: .day, value: offset, to: scheduleViewModel.currentWeekStart) {
                        let dayEvents = scheduleViewModel.weekEvents
                            .filter { calendar.isDate($0.startDate, inSameDayAs: day) }
                        Section {
                            if dayEvents.isEmpty {
                                Text(L10n.shared.当日无日程)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            } else {
                                ForEach(dayEvents) { event in
                                    eventRow(event)
                                        .contentShape(Rectangle())
                                        .background(
                                            highlightedEventID == event.id
                                                ? Color.focusRed.opacity(0.12)
                                                : Color.clear
                                        )
                                        .onTapGesture {
                                            highlightedEventID = nil
                                            scheduleViewModel.refreshForDate(event.startDate)
                                            editingEvent = event
                                        }
                                        // 无障碍：读屏可操作（onTapGesture 对 VoiceOver 不可达）
                                        .accessibilityAddTraits(.isButton)
                                        .accessibilityAction {
                                            highlightedEventID = nil
                                            scheduleViewModel.refreshForDate(event.startDate)
                                            editingEvent = event
                                        }
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                }
                                .onDelete { indexSet in
                                    for index in indexSet {
                                        scheduleViewModel.deleteEvent(dayEvents[index])
                                    }
                                }
                            }
                        } header: {
                            DateSectionHeader(date: day)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
            .disableBounce()
        }
    }

    /// 周范围文本（如 8/10 – 8/16）
    private var weekRangeText: String {
        let start = scheduleViewModel.currentWeekStart
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(Self.weekRangeFormatter.string(from: start)) – \(Self.weekRangeFormatter.string(from: end))"
    }

    /// 周范围日期格式化器（静态缓存，审查 #11）
    private static let weekRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "M/d"
        return f
    }()

    // MARK: - 自然语言快速添加（B2）

    /// 解析输入并创建事件；解析失败时回退到完整新建表单
    private func handleQuickAdd() {
        guard let draft = EventDraftParser.parse(quickAddText) else {
            showNewEventSheet = true   // 无法识别 → 打开完整表单让用户手填
            return
        }
        scheduleViewModel.createEvent(
            title: draft.title,
            startDate: draft.startDate,
            endDate: draft.endDate,
            isAllDay: false,
            location: nil,
            notes: nil,
            colorHex: nil,
            category: .event,
            repeatRule: .none,
            reminderEnabled: false,
            reminderLeadMinutes: 0,
            task: nil
        )
        scheduleViewModel.refreshForMonth(draft.startDate)
        scheduleViewModel.refreshForDate(draft.startDate)
        scheduleViewModel.refreshForWeek(containing: draft.startDate)
    }

    /// 按天分组的事件字典，避免每个日历单元格重复遍历全部事件
    private var eventsByDayDictionary: [Date: [ScheduleItem]] {
        var dict: [Date: [ScheduleItem]] = [:]
        for event in scheduleViewModel.events {
            let key = calendar.startOfDay(for: event.startDate)
            dict[key, default: []].append(event)
        }
        return dict
    }

    private func dayCell(date: Date, hasEvents: Bool) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: scheduleViewModel.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: scheduleViewModel.currentMonth, toGranularity: .month)
        let dayNumber = calendar.component(.day, from: date)

        return Button {
            highlightedEventID = nil
            scheduleViewModel.refreshForDate(date)
        } label: {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.focusRed)
                        .frame(width: 36, height: 36)
                } else if isToday {
                    Circle()
                        .stroke(Color.focusRed, lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                }

                VStack(spacing: 2) {
                    Text("\(dayNumber)")
                        .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                        .foregroundColor(
                            isSelected ? .white
                            : isCurrentMonth ? .primary
                            : .secondary.opacity(0.4)
                        )

                    Text(date.lunarCellText)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(
                            isSelected ? .white.opacity(0.8)
                            : isCurrentMonth ? .secondary
                            : .secondary.opacity(0.3)
                        )

                    if hasEvents {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.8) : Color.focusRed.opacity(0.6))
                            .frame(width: 4, height: 4)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayCellAccessibilityLabel(date: date, dayNumber: dayNumber))
        .accessibilityValue(dayCellAccessibilityValue(hasEvents: hasEvents, date: date,
                                                        eventDays: eventsByDayDictionary.keys.map { calendar.startOfDay(for: $0) }.reduce(into: Set<Date>()) { $0.insert($1) }))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Event List

    @ViewBuilder
    private var eventList: some View {
        let events = eventsOnSelectedDate

        if events.isEmpty {
            emptyEventState
        } else {
            List {
                Section {
                ForEach(events) { event in
                    eventRow(event)
                        .contentShape(Rectangle())
                        .background(
                            highlightedEventID == event.id
                                ? Color.focusRed.opacity(0.12)
                                : Color.clear
                        )
                        .onTapGesture {
                            editingEvent = event
                        }
                        // 无障碍：读屏可操作
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            editingEvent = event
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let event = events[index]
                            withAnimation {
                                scheduleViewModel.deleteEvent(event)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.caption)
                        Text(selectedDateText)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if let lunarText = LunarCalendar.lunarDateString(from: scheduleViewModel.selectedDate) {
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(lunarText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
            .disableBounce()
        }
    }

    private func eventRow(_ event: ScheduleItem) -> some View {
        HStack(spacing: 12) {
            // Color dot（纯装饰：颜色语义已由标题文本承载）
            Circle()
                .fill(Color(hex: event.colorHex ?? ScheduleColor.red.rawValue))
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if event.reminderEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .accessibilityHidden(true)
                    }
                    Text(event.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .accessibilityHidden(true)
                    Text(event.timeRangeText)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.caption2)
                            .accessibilityHidden(true)
                        Text(location)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        // 无障碍补齐（2026-11-02）：整行此前被拆成「时钟」「10:00 – 11:00」「定位」等多个
        // 碎片元素，装饰图标还会读出符号名。合并为一句：标题，时间，地点，已开启提醒。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(eventAccessibilityLabel(event))
    }

    /// 日程行合并读屏文案
    private func eventAccessibilityLabel(_ event: ScheduleItem) -> String {
        var parts = [event.title, event.timeRangeText]
        if let location = event.location, !location.isEmpty { parts.append(location) }
        if event.reminderEnabled { parts.append(L10n.shared.已开启提醒) }
        return parts.joined(separator: "，")
    }

    private var emptyEventState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))
                // 无障碍（2026-10-14）：空状态装饰图标不单独朗读
                .accessibilityHidden(true)

            Text(L10n.shared.当日无日程)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// 日历单元格无障碍标签（包含日期、农历、事件数）
    private func dayCellAccessibilityLabel(date: Date, dayNumber: Int) -> String {
        let lunarText = date.lunarCellText
        var parts: [String] = [calendar.isDateInToday(date) ? L10n.shared.今日 : "\(dayNumber)"]
        if !lunarText.isEmpty {
            parts.append(lunarText)
        }
        return parts.joined(separator: "，")
    }

    /// 修复（2026-10-14 P2）：传入**已预算好的**事件日集合 —— 原实现在每个格子内重建
    /// `eventsByDayDictionary`（42 格 = 42 次全量字典重建，预计算成果完全没被利用）。
    private func dayCellAccessibilityValue(hasEvents: Bool, date: Date,
                                            eventDays: Set<Date>) -> String {
        let eventsOnDay = eventsByDayDictionary[calendar.startOfDay(for: date)]?.count ?? 0
        if hasEvents {
            return L10n.shared.dayEventCount(eventsOnDay)
        }
        return L10n.shared.当日无日程
    }

    private var selectedDateText: String {
        let date = scheduleViewModel.selectedDate
        if calendar.isDateInToday(date) {
            return L10n.shared.今日
        }
        if calendar.isDateInTomorrow(date) {
            return L10n.shared.明日
        }
        if calendar.isDateInYesterday(date) {
            return L10n.shared.昨日
        }
        return Self.selectedDateFormatter.string(from: date)
    }

    private var eventsOnSelectedDate: [ScheduleItem] {
        scheduleViewModel.events
            .filter { calendar.isDate($0.startDate, inSameDayAs: scheduleViewModel.selectedDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func generateDays() -> [Date?] {
        let monthStart = scheduleViewModel.currentMonth.startOfMonth
        guard let numberOfDays = calendar.range(of: .day, in: .month, for: monthStart)?.count else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: monthStart)
        // Gregorian: 1=Sun, 2=Mon, ... , 7=Sat
        // 根据 calendar.firstWeekday 计算相对于网格第一列的偏移
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = []

        // Leading empty cells
        for _ in 0..<offset {
            days.append(nil)
        }

        // Day cells
        // 崩溃修复（2026-10-02）：`ClosedRange` 要求 lower <= upper，
        // numberOfDays 为 0 时 `1...0` 会 trap。max(1, ...) 兜底。
        for day in 1...max(1, numberOfDays) {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                days.append(date)
            }
        }

        return days
    }
}

// MARK: - Preview

#Preview {
    ScheduleView()
        .environmentObject(AppDependency().scheduleViewModel)
        .environmentObject(AppDependency().taskViewModel)
        .environmentObject(AppDependency())
        .environmentObject(L10n.shared)
}
