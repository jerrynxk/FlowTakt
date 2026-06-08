import SwiftUI
import Combine

// MARK: - TimeRecordView

struct TimeRecordView: View {
    @EnvironmentObject var timeRecordViewModel: TimeRecordViewModel
    @EnvironmentObject var taskViewModel: TaskViewModel

    @State private var selectedTask: Task?
    @State private var elapsedTime: TimeInterval = 0
    @State private var isPulsing = false

    /// 选中日期的记录（按时间倒序）
    private var recordsForDate: [TimeRecord] {
        timeRecordViewModel.records
            .filter { $0.startTime.isSameDay(as: timeRecordViewModel.selectedDate) }
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
    private var formattedTotal: String {
        let total = timeRecordViewModel.totalDurationToday
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                todayTotalSection
                datePickerSection
                recordingSection
                recordsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("计时")
            .navigationBarTitleDisplayMode(.large)
            .onReceive(timer) { _ in
                updateElapsedTime()
            }
            .onChange(of: timeRecordViewModel.selectedDate) { _ in
                timeRecordViewModel.refreshTodayTotal()
                elapsedTime = 0
            }
            .onChange(of: timeRecordViewModel.isRecording) { isRecording in
                if !isRecording {
                    elapsedTime = 0
                    isPulsing = false
                }
            }
        }
    }

    // MARK: - 今日总时长

    private var todayTotalSection: some View {
        Section {
            VStack(spacing: 6) {
                Text(formattedTotal)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.top, 12)

                Text("今日总计")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - 日期选择器

    private var datePickerSection: some View {
        Section {
            DatePicker(
                "选择日期",
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
            Picker("关联任务", selection: $selectedTask) {
                Text("无任务").tag(nil as Task?)
                if availableTasks.isEmpty {
                    Text("无可用任务").tag(nil as Task?)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(availableTasks) { task in
                        Text(task.title).tag(task as Task?)
                    }
                }
            }
            .pickerStyle(.menu)

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
                        Text("开始计时")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
                    .fill(Color.focusRed)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.4 : 0.8)
                    .opacity(isPulsing ? 0.5 : 1.0)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        ) {
                            isPulsing = true
                        }
                    }

                Text("正在计时...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                Text(elapsedTimeDisplay)
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(.focusRed)
                    .contentTransition(.numericText())
            }

            Divider()

            // 停止计时按钮
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - 记录列表

    private var recordsSection: some View {
        Section {
            if recordsForDate.isEmpty {
                emptyRecordsView
            } else {
                ForEach(recordsForDate) { record in
                    TimeRecordRowView(record: record)
                }
                .onDelete { indexSet in
                    deleteRecords(at: indexSet)
                }
            }
        } header: {
            Text("记录")
        }
    }

    private var emptyRecordsView: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))

            Text("暂无记录")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("点击上方按钮开始计时")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    // MARK: - Helpers

    private func updateElapsedTime() {
        guard timeRecordViewModel.isRecording,
              let record = timeRecordViewModel.currentRecord else {
            return
        }
        elapsedTime = Date().timeIntervalSince(record.startTime)
    }

    private func deleteRecords(at indexSet: IndexSet) {
        for index in indexSet {
            let record = recordsForDate[index]
            timeRecordViewModel.deleteRecord(record)
        }
    }
}

// MARK: - TimeRecordRowView

private struct TimeRecordRowView: View {
    let record: TimeRecord

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
                        Text(task.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else {
                        Text("无任务")
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
                }

                // 时长
                Text(record.durationText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .monospacedDigit()
            }

            // 第二行：项目 + 时间范围
            HStack(spacing: 12) {
                if let project = record.project, !project.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.caption2)
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
    }
}
#endif
