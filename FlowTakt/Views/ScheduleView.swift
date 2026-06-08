import SwiftUI

// MARK: - ScheduleView

struct ScheduleView: View {
    @EnvironmentObject var scheduleViewModel: ScheduleViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel

    @State private var showNewEventSheet = false
    @State private var editingEvent: ScheduleItem? = nil

    private let calendar = Calendar.current
    private let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]

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
            .navigationTitle("日程")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewEventSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
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
                        scheduleViewModel.refreshForDate(scheduleViewModel.selectedDate)
                    }
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.focusRed)
            }

            Spacer()

            Text(monthYearText)
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if let nextMonth = calendar.date(byAdding: .month, value: 1, to: scheduleViewModel.currentMonth) {
                        scheduleViewModel.refreshForMonth(nextMonth)
                        scheduleViewModel.refreshForDate(scheduleViewModel.selectedDate)
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.focusRed)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var monthYearText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter.string(from: scheduleViewModel.currentMonth)
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

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(days.indices, id: \.self) { index in
                if let date = days[index] {
                    dayCell(date: date)
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func dayCell(date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: scheduleViewModel.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isCurrentMonth = calendar.isDate(date, equalTo: scheduleViewModel.currentMonth, toGranularity: .month)
        let dayNumber = calendar.component(.day, from: date)
        let hasEvents = !eventsOnDate(date).isEmpty

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

                VStack(spacing: 3) {
                    Text("\(dayNumber)")
                        .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                        .foregroundColor(
                            isSelected ? .white
                            : isCurrentMonth ? .primary
                            : .secondary.opacity(0.4)
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

            Text("当日无日程")
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
            return "今天"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "M 月 d 日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    private var eventsOnSelectedDate: [ScheduleItem] {
        scheduleViewModel.events
            .filter { calendar.isDate($0.startDate, inSameDayAs: scheduleViewModel.selectedDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    private func eventsOnDate(_ date: Date) -> [ScheduleItem] {
        scheduleViewModel.events
            .filter { calendar.isDate($0.startDate, inSameDayAs: date) }
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

// MARK: - Event Color

private enum ScheduleColor: String, CaseIterable {
    case red = "#FF3B30"
    case blue = "#007AFF"
    case green = "#34C759"
    case orange = "#FF9500"
    case purple = "#AF52DE"

    var color: Color {
        Color(hex: rawValue)
    }

    var displayName: String {
        switch self {
        case .red: return "红色"
        case .blue: return "蓝色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .purple: return "紫色"
        }
    }
}

// MARK: - EventEditView

private struct EventEditView: View {
    @Binding var isPresented: Bool

    let editingEvent: ScheduleItem?
    let initialDate: Date
    let onSave: (String, Date, Date?, Bool, String?, String?, String?) -> Void

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var hasEndDate: Bool = true
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedColor: ScheduleColor = .red

    @FocusState private var focusedField: Field?

    private enum Field {
        case title, location, notes
    }

    private var isEditing: Bool { editingEvent != nil }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    init(
        isPresented: Binding<Bool>,
        editingEvent: ScheduleItem?,
        initialDate: Date,
        onSave: @escaping (String, Date, Date?, Bool, String?, String?, String?) -> Void
    ) {
        self._isPresented = isPresented
        self.editingEvent = editingEvent
        self.initialDate = initialDate
        self.onSave = onSave

        if let event = editingEvent {
            _title = State(initialValue: event.title)
            _startDate = State(initialValue: event.startDate)
            _endDate = State(initialValue: event.endDate ?? event.startDate.addingTimeInterval(3600))
            _hasEndDate = State(initialValue: event.endDate != nil)
            _isAllDay = State(initialValue: event.isAllDay)
            _location = State(initialValue: event.location ?? "")
            _notes = State(initialValue: event.notes ?? "")
            _selectedColor = State(
                initialValue: ScheduleColor.allCases.first(where: { $0.rawValue == event.colorHex }) ?? .red
            )
        } else {
            // Default start time: selected date at current hour
            let calendar = Calendar.current
            let now = Date()
            let baseDate = initialDate
            let hour = calendar.component(.hour, from: now)
            let minute = calendar.component(.minute, from: now)
            let roundedMinute = (minute / 15) * 15
            if let defaultStart = calendar.date(bySettingHour: hour, minute: roundedMinute, second: 0, of: baseDate) {
                _startDate = State(initialValue: defaultStart)
                _endDate = State(initialValue: defaultStart.addingTimeInterval(3600))
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Title
                Section {
                    TextField("事件标题", text: $title)
                        .font(.body)
                        .focused($focusedField, equals: .title)
                        .onAppear {
                            if !isEditing {
                                focusedField = .title
                            }
                        }
                }

                // Date & Time
                Section("时间") {
                    DatePicker(
                        "开始",
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    Toggle("结束时间", isOn: $hasEndDate)
                        .onChange(of: hasEndDate) { _, newValue in
                            if !newValue {
                                // endDate will be nil on save
                            }
                        }

                    if hasEndDate {
                        DatePicker(
                            "结束",
                            selection: $endDate,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }

                    Toggle("全天", isOn: $isAllDay)
                }

                // Location
                Section {
                    HStack {
                        Image(systemName: "mappin")
                            .foregroundColor(.secondary)
                        TextField("地点", text: $location)
                            .focused($focusedField, equals: .location)
                    }
                }

                // Notes
                Section("备注") {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("添加备注...")
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .focused($focusedField, equals: .notes)
                    }
                }

                // Color Picker
                Section("颜色") {
                    HStack(spacing: 16) {
                        ForEach(ScheduleColor.allCases, id: \.self) { colorOption in
                            Button {
                                selectedColor = colorOption
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(colorOption.color)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == colorOption ? Color.primary : Color.clear, lineWidth: 2)
                                        )
                                        .overlay(
                                            Image(systemName: "checkmark")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .opacity(selectedColor == colorOption ? 1 : 0)
                                        )

                                    Text(colorOption.displayName)
                                        .font(.caption2)
                                        .foregroundColor(selectedColor == colorOption ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? "编辑事件" : "新建事件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard isValid else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
        let finalEndDate = hasEndDate ? endDate : nil

        onSave(trimmedTitle, startDate, finalEndDate, isAllDay, trimmedLocation, trimmedNotes, selectedColor.rawValue)
        isPresented = false
    }
}

// MARK: - Preview

#Preview {
    ScheduleView()
        .environmentObject(AppDependency().scheduleViewModel)
        .environmentObject(AppDependency().taskViewModel)
}
