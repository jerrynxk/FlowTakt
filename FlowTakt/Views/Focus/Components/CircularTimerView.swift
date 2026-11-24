import SwiftUI

// MARK: - 圆形计时器（v1.3.4 视觉重设计）
//
// 设计要点（2026-10-03 重做）：
// 1. **层级收敛**：旧实现有 4 层同色系圆环叠加（外圈淡底环 + 径向渐变填充 +
//    待机引导环 + 进度环），同色叠加在浅灰背景上会形成一圈"脏粉晕"，边界模糊。
//    现收敛为 2 层：中性轨道 + 进度弧。轨道改用 systemGray4 而非同色淡粉，
//    避免"底环 / 进度环"颜色相近导致的辨识度下降。
// 2. **中心有依托**：中心区加一层极淡的品牌色圆底（替代旧版的 RadialGradient），
//    既给数字一个视觉落点，又不会在圆心堆出颜色。徽章与时间间距重新分配
//    （旧版 spacing 6 使重心偏上、下方留白过大），改为自适应间距。
// 3. **进度弧端点**：圆头线帽 + 外侧柔光，运行中随进度推进有明确的"头部"指示。
// 4. **字体**：`design: .rounded` 的等宽数字，比 `design: .monospaced` 的
//    机械感更强，视觉重心更集中。

struct CircularTimerView: View {
    @EnvironmentObject var focusViewModel: FocusViewModel
    @EnvironmentObject var l10n: L10n

    let progress: Double

    /// 进度环线宽（较旧实现 12 → 10，配合两层结构更显精致）
    private let lineWidth: CGFloat = 10

    private var phaseColor: Color {
        Color.forPhase(focusViewModel.activePhase)
    }

    /// 是否处于计时中（决定轨道/中心的呈现强度）
    private var isActive: Bool {
        progress > 0
    }

    var body: some View {
        // 尺寸自适应（2026-11-02 修复「倒计时数字溢出圆圈」）：
        // 时间字号原为固定 56pt —— 而圆环在小屏上会随可用高度收缩到 ~166pt，
        // 内盘直径仅剩约 138pt，56pt 的「00:00」实际宽度约 150pt，直接顶出盘面。
        // Text 上的 `minimumScaleFactor` 此时不生效：VStack 宽度由内容撑开，
        // 没有宽度约束就不会触发缩放。
        // 现改为按圆环实际边长计算字号（0.26 倍，56pt 封顶）并给 VStack 显式限宽。
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let timeFontSize = min(56, side * 0.26)

            ZStack {
                // MARK: 第 0 层：外圈细框（2026-11-02 新增）
                // 目的：给圆环一个"表盘外框"，让主体从纯黑背景中被明确托起。
                // 深色下仅靠轨道环（systemGray4）边界偏重、且外缘直接没入纯黑，
                // 加一圈 1pt systemGray3 细环后，主体获得完整轮廓（半径外扩 9pt，
                // 略大于轨道线宽的一半，形成"框—环—盘"三层）。
                // 注：首版用 separator 0.55 透明度，实测在黑底上几乎不可见（≈rgb46），
                // 改用 systemGray3（深色 ≈ #48484A）+ 0.75 透明度。
                //
                // ⚠️ 该外框用负 padding 溢出绘制，**不占布局高度** ——
                // 相邻元素（下方「第 N 轮」泡泡）的布局间距必须补上这 9pt，否则会被压住。
                Circle()
                    .stroke(Color(.systemGray3).opacity(0.75), lineWidth: 1)
                    .padding(-9)

                // MARK: 第 1 层：中性轨道
                // 旧实现用 phaseColor.opacity(0.18) 作底环，与进度弧同色系；
                // 现改为中性灰，仅在运行中染上极淡品牌色，保持"未开始"的静默感。
                Circle()
                    .stroke(
                        Color(.systemGray4).opacity(isActive ? 0.55 : 1.0),
                        lineWidth: lineWidth
                    )

                // MARK: 第 2 层：进度弧
                // 圆头线帽 + 柔光，运行中头部位置即当前进度落点。
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [
                                phaseColor.opacity(0.65),
                                phaseColor
                            ],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: phaseColor.opacity(0.45), radius: 8)
                    .animation(.linear(duration: 0.1), value: progress)

                // MARK: 中心圆底 + 徽章 + 时间
                // 内圆几乎撑满盘面：padding 取 lineWidth + 4（内圆半径 ≈ 外环半径的 0.83），
                // 与参考图一致 —— 仅在进度环内侧留一圈极窄的间隙，形成"环 + 盘"的完整构图。
                //
                // 历史调整记录：
                // - 初版 +14：内圆偏小，盘面中部空旷，缺少视觉实体感
                // - 曾收窄到 +24：过度收窄，内圆退化成一小块圆斑，主体感丧失（已回退）
                // 色值比外环略深，形成"环浅盘深"的层次；透明度随运行状态提升。
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                phaseColor.opacity(isActive ? 0.20 : 0.13),
                                phaseColor.opacity(isActive ? 0.13 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    // 盘面内描边（2026-11-02）：深色下渐变盘面与纯黑页面之间同样缺少硬边界，
                    // 补一圈 1pt 同色系描边，让"盘"成为有厚度的实体而不是一片雾。
                    .overlay(
                        Circle()
                            .strokeBorder(phaseColor.opacity(0.16), lineWidth: 1)
                    )
                    .padding(lineWidth + 4)

                VStack(spacing: 10) {
                    FocusPhaseBadge()

                    Text(focusViewModel.timerDisplay)
                        // rounded 设计比 monospaced 更柔和，避免机械感；
                        // .monospacedDigit() 单独保留数字等宽特性，防止时间跳动时左右抖动。
                        .font(.system(size: timeFontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.1), value: focusViewModel.timerDisplay)
                        .accessibilityHidden(true)
                }
                // 限宽到内盘可见区（扣掉环宽与内边距），让 minimumScaleFactor 真正有机会生效
                .frame(maxWidth: max(0, side - 2 * (lineWidth + 4) - 16))
                .padding(.horizontal, 8)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timerAccessibilityText)
        .accessibilityValue(
            focusViewModel.timerState == .running ? L10n.shared.进行中
            : focusViewModel.timerState == .paused ? L10n.shared.已暂停
            : focusViewModel.timerState == .finished ? L10n.shared.已完成
            : L10n.shared.准备就绪
        )
    }

    /// VoiceOver 友好时间：避免读成 "25比0"，转为 "剩余 25 分 0 秒"
    /// 无障碍补齐（2026-11-02）：圆心内容被 `children: .ignore` 整体吞掉，
    /// 阶段名（专注 / 短休息 / 长休息）此前完全丢失 —— 读屏只听到「剩余 25 分」，
    /// 无法判断当前处于专注还是休息。现把阶段名前置到标签。
    private var timerAccessibilityText: String {
        let phaseName: String
        switch focusViewModel.activePhase {
        case .focus:      phaseName = L10n.shared.focus
        case .shortBreak: phaseName = L10n.shared.短休息
        case .longBreak:  phaseName = L10n.shared.长休息
        }

        let parts = focusViewModel.timerDisplay.split(separator: ":")
        if parts.count == 2, let minutes = Int(parts[0]), let seconds = Int(parts[1]) {
            return phaseName + "，" + L10n.shared.计时剩余(minutes, seconds)
        }
        return phaseName + "，" + focusViewModel.timerDisplay
    }
}

#if DEBUG
struct CircularTimerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            // 待机
            previewRing(label: "待机 · 0%")
                .environmentObject(makeVM())

            // 运行中
            previewRing(label: "专注中 · 62%")
                .environmentObject(makeVM())

            // 休息阶段
            previewRing(label: "短休息 · 30%")
                .environmentObject(makeVM())
        }
        .padding()
        .environmentObject(L10n.shared)
    
}

    @ViewBuilder
    private static func previewRing(label: String) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.caption).foregroundColor(.secondary)
            CircularTimerView(progress: label.contains("62") ? 0.62 : (label.contains("30") ? 0.3 : 0))
                .frame(width: 220, height: 220)
        }
    }

    private static func makeVM() -> FocusViewModel {
        FocusViewModel(
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
        )
    }
}
#endif
