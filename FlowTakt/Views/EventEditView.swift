import SwiftUI

// MARK: - Event Color

enum ScheduleColor: String, CaseIterable {
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
        case .red:    return L10n.shared.红色
        case .blue:   return L10n.shared.蓝色
        case .green:  return L10n.shared.绿色
        case .orange: return L10n.shared.橙色
        case .purple: return L10n.shared.紫色
        }
    }
}

// MARK: - EventData

/// 封装事件编辑的所有数据字段，替代原本 10 个参数的 closure
struct EventData {
    var title: String
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var location: String?
    var notes: String?
    var colorHex: String?
    var category: ScheduleCategory
    var reminderEnabled: Bool
    var reminderLeadMinutes: Int
}

// MARK: - EventEditView

/// 提前提醒时间预设（分钟）
fileprivate let reminderLeadPresets: [Int] = [0, 5, 10, 15, 30, 60, 1440, 2880, 10080]

/// 根据提前分钟数生成本地化的提醒标签
fileprivate func reminderLeadLabel(minutes: Int) -> String {
    switch minutes {
    case 0: return L10n.shared.准时
    case 60: return L10n.shared.提前一小时
    case 1440: return L10n.shared.提前一天
    case 2880: return L10n.shared.提前两天
    case 10080: return L10n.shared.提前一周
    default: return L10n.shared.提前分钟(minutes)
    }
}

/// 日程事件编辑视图（从 ScheduleView 拆分出来以控制文件行数）
struct EventEditView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var l10n: L10n

    let editingEvent: ScheduleItem?
    let initialDate: Date
    let onSave: (EventData) -> Void

    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var hasEndDate: Bool = true
    @State private var isAllDay: Bool = false
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var selectedColor: ScheduleColor = .red

    // 提醒相关状态
    @State private var category: ScheduleCategory = .event
    @State private var reminderEnabled: Bool = false
    @State private var reminderLeadIndex: Int = 0
    /// 审查修复（2026-08-12）：编辑时提醒分钟数不在预设列表时保留原值（自定义选项）
    @State private var customReminderLead: Int?

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
        onSave: @escaping (EventData) -> Void
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
            _category = State(initialValue: event.categoryEnum)
            _reminderEnabled = State(initialValue: event.reminderEnabled)
            let lead = event.reminderLeadMinutesInt
            // 审查修复（2026-08-12）：编辑时若提醒分钟数不在预设列表，不再静默回退到 index 0
            //（否则保存会把自定义提醒静默改成「准时」）；改为追加一个自定义选项并保留原值
            if let idx = reminderLeadPresets.firstIndex(of: lead) {
                _reminderLeadIndex = State(initialValue: idx)
            } else {
                _reminderLeadIndex = State(initialValue: reminderLeadPresets.count)
                _customReminderLead = State(initialValue: lead)
            }
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
                    TextField(L10n.shared.事件标题, text: $title)
                        .font(.body)
                        .focused($focusedField, equals: .title)
                        .onAppear {
                            if !isEditing {
                                focusedField = .title
                            }
                        }
                        .accessibilityLabel(L10n.shared.事件标题)
                }

                // Date & Time
                Section(L10n.shared.时间) {
                    DatePicker(
                        L10n.shared.开始,
                        selection: $startDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    Toggle(L10n.shared.结束时间, isOn: $hasEndDate)

                    if hasEndDate {
                        DatePicker(
                            L10n.shared.结束,
                            selection: $endDate,
                            displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                        )
                    }

                    Toggle(L10n.shared.全天, isOn: $isAllDay)
                }

                // 类型
                Section(L10n.shared.类型) {
                    Picker(L10n.shared.类型, selection: $category) {
                        ForEach(ScheduleCategory.allCases) { cat in
                            Label(cat.displayName, systemImage: cat.iconName).tag(cat)
                        }
                    }
                }

                // 提醒
                Section {
                    Toggle(L10n.shared.提醒, isOn: $reminderEnabled)

                    if reminderEnabled {
                        Picker(L10n.shared.提前提醒, selection: $reminderLeadIndex) {
                            ForEach(reminderLeadPresets.indices, id: \.self) { index in
                                Text(reminderLeadLabel(minutes: reminderLeadPresets[index])).tag(index)
                            }
                            // 审查修复：自定义分钟数不在预设列表时保留原值
                            if let custom = customReminderLead {
                                Text(reminderLeadLabel(minutes: custom)).tag(reminderLeadPresets.count)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text(L10n.shared.提醒设置标题)
                } footer: {
                    Text(L10n.shared.提醒设置说明)
                }

                // Location
                Section {
                    HStack {
                        Image(systemName: "mappin")
                            .foregroundColor(.secondary)
                            .accessibilityHidden(true)
                        TextField(L10n.shared.地点, text: $location)
                            .focused($focusedField, equals: .location)
                            .accessibilityLabel(L10n.shared.地点)
                    }
                }

                // Notes
                Section(L10n.shared.备注) {
                    ZStack(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text(L10n.shared.添加备注)
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                            .focused($focusedField, equals: .notes)
                            .accessibilityLabel(L10n.shared.备注)
                    }
                }

                // Color Picker
                Section(L10n.shared.颜色) {
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
                            .accessibilityLabel(colorOption.displayName)
                            .accessibilityAddTraits(selectedColor == colorOption ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(isEditing ? L10n.shared.编辑事件 : L10n.shared.新建事件)
            .navigationBarTitleDisplayMode(.inline)
            // 滚动统一调整（2026-11-02）：禁用弹性 + 柔化撞停减速
            .disableBounce()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.shared.取消) {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.shared.保存) {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            // 让 DatePicker 跟随应用内语言（而非强制设备语言），与 App 中英切换一致
            .environment(\.locale, Locale(identifier: L10n.shared.appLanguage))
        }
    }

    private func save() {
        guard isValid else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes.trimmingCharacters(in: .whitespaces)
        let finalEndDate = hasEndDate ? endDate : nil
        // 审查修复：自定义分钟数优先于预设索引，避免静默改写用户设置
        let leadMinutes: Int
        if let custom = customReminderLead, reminderLeadIndex == reminderLeadPresets.count {
            leadMinutes = custom
        } else {
            leadMinutes = reminderLeadPresets[reminderLeadIndex]
        }

        let data = EventData(
            title: trimmedTitle,
            startDate: startDate,
            endDate: finalEndDate,
            isAllDay: isAllDay,
            location: trimmedLocation,
            notes: trimmedNotes,
            colorHex: selectedColor.rawValue,
            category: category,
            reminderEnabled: reminderEnabled,
            reminderLeadMinutes: leadMinutes
        )
        onSave(data)
        isPresented = false
    }
}
