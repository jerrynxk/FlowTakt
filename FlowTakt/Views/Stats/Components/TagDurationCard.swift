import SwiftUI

// MARK: - 按标签耗时分布卡（用户反馈 2026-11-19 / 扩展 2026-11-22）
//
// 展示「时间去哪了」：全部 / 年 / 月 / 周 / 自定义 五个档位，按标签聚合专注时长并给出占比。
// 单归属语义（判据在 StatsViewModel.aggregateTagDurations）：各标签时长之和 == 该档总时长，
// 用户可自行核对；无标签的会话与正计时归入「未分类」，不隐瞒。

struct TagDurationCard: View {
    @EnvironmentObject var statsViewModel: StatsViewModel
    @EnvironmentObject var l10n: L10n

    /// 统计档位（默认「全部」：测试用户反馈长周期项目需要看从开始到现在的累计）
    private enum Range: String, CaseIterable {
        case all
        case year
        case month
        case week
        case custom
    }

    @State private var range: Range = .all
    @State private var showCustomRangeSheet = false
    /// 自定义默认取最近 30 天，点选「自定义」即有数据，不出现空白档
    @State private var customStartDate: Date = Calendar.current.date(
        byAdding: .day, value: -29, to: Date().startOfDay
    ) ?? Date()
    @State private var customEndDate: Date = Date()
    /// 弹窗里的临时草稿：取消即丢弃，确定才写入 customStartDate/EndDate 与 ViewModel
    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()

    private var entries: [TagDuration] {
        switch range {
        case .all: return statsViewModel.allTagDurations
        case .year: return statsViewModel.yearTagDurations
        case .month: return statsViewModel.monthTagDurations
        case .week: return statsViewModel.weekTagDurations
        case .custom: return statsViewModel.customTagDurations
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.focusRed)
                    .accessibilityHidden(true)
                Text(L10n.shared.按标签统计)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .accessibilityHeading(.h2)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Picker("", selection: $range) {
                Text(L10n.shared.全部).tag(Range.all)
                Text(L10n.shared.统计年).tag(Range.year)
                Text(L10n.shared.统计月).tag(Range.month)
                Text(L10n.shared.统计周).tag(Range.week)
                Text(L10n.shared.统计自定义).tag(Range.custom)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            // 无障碍：分段控件补用途标签与专属 identifier（勿与统计页 topTabPicker 同名）
            .accessibilityLabel(L10n.shared.按标签统计)
            .accessibilityIdentifier("tagRangePicker")
            .onChange(of: range) { _, newValue in
                guard newValue == .custom else { return }
                // 先按默认（最近 30 天）落一份数据，再弹出起止日期选择
                statsViewModel.updateCustomTagDurations(start: customStartDate, end: customEndDate)
                openCustomRangeSheet()
            }

            // 「自定义」再次点同一分段不会触发 onChange，补常驻入口可重复打开日期面板
            if range == .custom {
                Button(action: openCustomRangeSheet) {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .accessibilityHidden(true)
                        Text("\(customStartDate.shortDateString) - \(customEndDate.shortDateString)")
                            .monospacedDigit()
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundColor(.focusRed)
                    .contentShape(Rectangle())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // 读屏用本地化长日期，避免 "2026/11/22" 被逐字符念出；Button 自带 isButton 不再重复添加
                .accessibilityLabel("\(L10n.shared.自定义统计范围) \(customStartDate.formatted(date: .long, time: .omitted)) - \(customEndDate.formatted(date: .long, time: .omitted))")
                .accessibilityHint(L10n.shared.自定义范围提示)
            }

            if entries.isEmpty {
                Text(L10n.shared.暂无标签数据)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                VStack(spacing: 12) {
                    ForEach(entries) { entry in
                        row(for: entry)
                    }
                }
                .padding(16)
            }

            Text(L10n.shared.标签耗时说明)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .cardStyle()
        .sheet(isPresented: $showCustomRangeSheet) {
            NavigationStack {
                Form {
                    DatePicker(L10n.shared.开始日期,
                               selection: $draftStartDate,
                               in: ...draftEndDate,
                               displayedComponents: .date)
                    DatePicker(L10n.shared.结束日期,
                               selection: $draftEndDate,
                               in: draftStartDate...,
                               displayedComponents: .date)
                }
                .navigationTitle(L10n.shared.自定义统计范围)
                .navigationBarTitleDisplayMode(.inline)
                // 防止手势下拉静默丢弃未确认的草稿修改，只能走「取消/确定」
                .interactiveDismissDisabled(true)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.shared.取消) { showCustomRangeSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.shared.确定) {
                            customStartDate = draftStartDate
                            customEndDate = draftEndDate
                            statsViewModel.updateCustomTagDurations(start: customStartDate,
                                                                    end: customEndDate)
                            showCustomRangeSheet = false
                        }
                    }
                }
            }
        }
    }

    private func openCustomRangeSheet() {
        draftStartDate = customStartDate
        draftEndDate = customEndDate
        showCustomRangeSheet = true
    }

    // MARK: - 单标签行

    private func row(for entry: TagDuration) -> some View {
        let color = entry.colorHex.flatMap { Color(hex: $0) } ?? .focusRed
        // 「未分类」的显示名在此动态解析（2026-11-19 审查）：聚合时缓存的名称不会随
        // 语言切换刷新，用固定 id 判定后在 View 层取当前语言文案，切语言即时生效。
        let displayName = entry.id == StatsViewModel.uncategorizedTagID
            ? L10n.shared.未分类
            : entry.name
        return VStack(spacing: 5) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)

                Text(displayName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(entry.duration.formattedDuration)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Text("\(Int(entry.ratio * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }

            // 占比条：背景用 systemGray5（深色下在 #1C1C1E 卡片上仍可辨），最小 4pt 保证可视
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    Capsule()
                        .fill(color)
                        .frame(width: max(4, geo.size.width * entry.ratio), height: 6)
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        // 无障碍：整行合并为「工作 3小时20分钟 45%」
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName) \(entry.duration.formattedDuration) \(Int(entry.ratio * 100))%")
    }
}

#if DEBUG
struct TagDurationCard_Previews: PreviewProvider {
    static var previews: some View {
        TagDurationCard()
            .environmentObject(StatsViewModel(
                focusService: FocusService(
                    persistenceController: PersistenceController.shared,
                    notificationService: NotificationService()
                ),
                taskService: TaskService(persistenceController: PersistenceController.shared),
                persistenceController: PersistenceController.shared
            ))
            .padding()
            .background(Color.appBackground)
            .environmentObject(L10n.shared)
    }
}
#endif
