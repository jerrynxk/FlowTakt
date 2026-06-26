import SwiftUI

// MARK: - ScheduleView

struct ScheduleView: View {
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel
    @EnvironmentObject var l10n: L10n

    @State private var showNewEventSheet = false
    @State private var editingEvent: ScheduleItem? = nil

    private let calendar = Calendar.current
    private let weekdaySymbols: [String] = {
        var syms = Calendar.current.veryShortWeekdaySymbols
        // Shift so Monday is first (system returns Sunday first)
        let sun = syms.removeFirst()
        syms.append(sun)
        return syms
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
                monthHeader
                weekdayHeader
                calendarGrid

                Divider()
                    .padding(.horizontal, 16)

                eventList
            }
            .background(Color.appBackground)
            .navigationTitle(L10n.shared.日程)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewEventSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .accessibilityLabel(L10n.shared.新建事件)
                }
            }
            .sheet(isPresented: $showNewEventSheet) {
                EventEditView(
                    isPresented: $showNewEventSheet,
                    editingEvent: nil,
                    initialDate: scheduleViewModel.selectedDate
                ) { title, startDate, endDate, isAllDay, location, notes, colorHex in
                    scheduleViewModel.createEvent(
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        location: location,
                        notes: notes,
                        colorHex: colorHex,
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
                ) { title, startDate, endDate, isAllDay, location, notes, colorHex in
                    scheduleViewModel.updateEvent(
                        event,
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        location: location,
                        notes: notes,
                        colorHex: colorHex
                    )
                }
            }
        }
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
        .accessibilityLabel(calendar.isDateInToday(date) ? L10n.shared.今日 : "\(dayNumber)")
        .accessibilityValue(hasEvents ? L10n.shared.有日程 : L10n.shared.当日无日程)
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
                            .onTapGesture {
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
        }
    }

    private func eventRow(_ event: ScheduleItem) -> some View {
        HStack(spacing: 12) {
            // Color dot
            Circle()
                .fill(Color(hex: event.colorHex ?? ScheduleColor.red.rawValue))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(event.timeRangeText)
                        .font(.caption)
                }
                .foregroundColor(.secondary)

                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin")
                            .font(.caption2)
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
        }
        .padding(.vertical, 4)
    }

    private var emptyEventState: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))

            Text(L10n.shared.当日无日程)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
        // We want Monday=0 offset, so: Sun(1)->6, Mon(2)->0, Tue(3)->1, ...
        let offset = firstWeekday == 1 ? 6 : firstWeekday - 2

        var days: [Date?] = []

        // Leading empty cells
        for _ in 0..<offset {
            days.append(nil)
        }

        // Day cells
        for day in 1...numberOfDays {
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
}
