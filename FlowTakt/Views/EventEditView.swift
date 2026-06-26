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

// MARK: - EventEditView

/// 日程事件编辑视图（从 ScheduleView 拆分出来以控制文件行数）
struct EventEditView: View {
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
            .environment(\.locale, Locale.current)
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
