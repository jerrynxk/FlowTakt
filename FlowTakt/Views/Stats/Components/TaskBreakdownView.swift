import SwiftUI

// MARK: - 任务分解视图

struct TaskBreakdownView: View {
    @EnvironmentObject var taskViewModel: TaskViewModel

    /// 活跃任务数
    private var activeCount: Int {
        taskViewModel.activeTasks.count
    }

    /// 已完成任务数
    private var completedCount: Int {
        taskViewModel.completedTasks.count
    }

    /// 任务总数
    private var totalCount: Int {
        activeCount + completedCount
    }

    /// 活跃占比
    private var activeRatio: Double {
        totalCount > 0 ? Double(activeCount) / Double(totalCount) : 0
    }

    /// 已完成占比
    private var completedRatio: Double {
        totalCount > 0 ? Double(completedCount) / Double(totalCount) : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            HStack {
                Image(systemName: "circle.grid.2x2.fill")
                    .foregroundColor(.focusRed)
                Text("任务分解")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            HStack(spacing: 24) {
                // 圆环图
                ZStack {
                    if totalCount > 0 {
                        // 已完成（绿色）
                        DonutSlice(
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + completedRatio * 360)
                        )
                        .fill(Color.breakGreen)
                        .animation(.easeInOut(duration: 0.6), value: completedRatio)

                        // 活跃（橙色）
                        DonutSlice(
                            startAngle: .degrees(-90 + completedRatio * 360),
                            endAngle: .degrees(-90 + 360)
                        )
                        .fill(Color.orange)
                        .animation(.easeInOut(duration: 0.6), value: completedRatio)
                    } else {
                        // 无数据时显示空环
                        Circle()
                            .stroke(Color(.systemGray4), lineWidth: 16)
                    }

                    // 中心文字
                    VStack(spacing: 2) {
                        Text("\(totalCount)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("任务")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 100, height: 100)

                // 图例
                VStack(alignment: .leading, spacing: 12) {
                    legendRow(
                        color: .breakGreen,
                        label: "已完成",
                        count: completedCount,
                        ratio: completedRatio
                    )
                    legendRow(
                        color: .orange,
                        label: "活跃",
                        count: activeCount,
                        ratio: activeRatio
                    )
                }
                .padding(.leading, 8)

                Spacer()
            }
            .padding(16)
        }
        .cardStyle()
    }

    // MARK: - 图例行

    private func legendRow(color: Color, label: String, count: Int, ratio: Double) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)

            Text("(\(Int(ratio * 100))%)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(width: 140)
    }
}

// MARK: - 圆环切片

struct DonutSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius - 16

        var path = Path()
        path.addArc(center: center, radius: outerRadius,
                    startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius,
                    startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

#if DEBUG
struct TaskBreakdownView_Previews: PreviewProvider {
    static var previews: some View {
        TaskBreakdownView()
            .environmentObject(TaskViewModel(
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .padding()
            .background(Color.appBackground)
    }
}
#endif
