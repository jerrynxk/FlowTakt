import SwiftUI
import UIKit

// MARK: - View 扩展

extension View {
    /// 条件应用修饰符（v1.3.5 iPad 复查新增）：条件为真才执行 transform。
    /// 用于 sizeClass 分支——避免把整段视图复制进 if/else。
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// 卡片样式（全项目统一：卡片底色 + 12 圆角 + 极细描边 + 轻阴影）
    ///
    /// 深色模式修复（2026-11-02）：
    /// 旧实现用 `systemBackground` 作卡片底 —— 深色下该色为纯黑 #000000，
    /// 而页面背景 `appBackground`（= systemGroupedBackground）深色下**同样是纯黑**，
    /// 两者色差为 0，卡片边界只能靠 8% 黑阴影表达（在黑底上同样不可见）。
    /// 像素实测：页面背景 rgb(0,0,0)、关联任务卡内部 rgb(0,0,0)，卡片实际"隐形"。
    ///
    /// 改为 `secondarySystemGroupedBackground`：深色 = #1C1C1E（与纯黑页面形成一级层次），
    /// 浅色 = 纯白（与 #F2F2F7 页面同样保持原有对比），两种模式语义一致。
    /// 另补 0.5pt `separator` 描边：深色下 #1C1C1E 与纯黑的亮度差约 7%，
    /// 单靠填充在大面积纯黑上仍偏弱，细描边给出明确的"片"边界。
    func cardStyle() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(Color(.separator).opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 5, x: 0, y: 2)
    }

    /// 让内容不足一屏的页面「拉不动」（禁用 UIScrollView 的空内容拖动），
    /// 同时**保留**内容超一屏时的原生滚动与边缘橡皮筋回弹。
    /// 注：名称沿用历史。2026-11-02 起不再关闭 `bounces`（那会移除边缘回弹），
    /// 只关 `alwaysBounceVertical`，详见 `DisableBounceFinder` 注释。
    func disableBounce() -> some View {
        self.modifier(DisableScrollViewBounceModifier())
    }

    /// 左右滑动切换顶部分段标签（不影响竖向滚动：竖向手势由内部 ScrollView 优先消费）。
    /// - Parameters:
    ///   - onSwipeLeft: 向左滑动（切换到右侧相邻标签）
    ///   - onSwipeRight: 向右滑动（切换到左侧相邻标签）
    ///   - triggerDistance: 触发切换所需的最小横向位移（默认 40pt）。
    ///     含列表行的页面（如计划页带 swipeActions）应传更大值，
    ///     否则横滑某一行时会连带把整页切走。
    func swipeToSwitchTab(
        triggerDistance: CGFloat = 40,
        onSwipeLeft: @escaping () -> Void,
        onSwipeRight: @escaping () -> Void
    ) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onEnded { value in
                    // 读屏模式不响应（2026-11-02 无障碍复核补）：
                    // VoiceOver 用「左右轻扫」在可访问元素间移动焦点，若这里也消费横滑，
                    // 读屏用户想移动焦点时整页会突然切换，等于抢走了系统导航手势。
                    // 读屏用户改用顶部分段控件切换 —— 它本身是标准 Picker，可正常操作。
                    guard !UIAccessibility.isVoiceOverRunning else { return }

                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) else { return } // 仅处理横向滑动
                    guard abs(dx) > triggerDistance else { return } // 忽略微小位移（如点按抖动 / 行内滑动）
                    if dx < 0 {
                        onSwipeLeft()
                    } else {
                        onSwipeRight()
                    }
                }
        )
    }
}

// MARK: - 滚动行为调整

struct DisableScrollViewBounceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DisableBounceFinder())
    }
}

/// 通过 background 注入一个 UIView，在**首次上屏时**扫描一次整个窗口子树，
/// 仅关闭其中所有 UIScrollView 的 `alwaysBounceVertical`（空内容拖动），
/// 保留 `bounces`（边缘橡皮筋回弹）为系统默认。
///
/// 历史沿革：
/// - 2026-10-31 为「禁止下拉露白」曾同时关闭 `bounces`，副作用是滚动到顶/底**硬停**、
///   完全没有回弹（用户 2026-11-02 反馈「撞墙还是没弹」）。
/// - 2026-11-02 修正：只关空内容拖动，恢复原生边缘回弹。
///
/// 性能修复（2026-11-02）：旧实现把扫描写在 `updateUIView`，每次 SwiftUI 刷新都会递归
/// 遍历整个窗口视图树并重设属性。专注页计时每秒刷新一次 body，等于每秒全树遍历一次。
/// 现改为：① 仅 `makeUIView`（视图上屏）触发一次；② weak 缓存已处理过的滚动容器；
/// ③ 赋值前先比较当前值；④ 跳过选择器滚轮（UIPickerView 内部）。
private struct DisableBounceFinder: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        DisableBounceFinder.scheduleDisableIfNeeded()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // 刻意留空（2026-11-02 手感修复）：幂等扫描只在上屏时做一次。
        // 旧实现在此每次 body 重算都全树遍历并重设 bounces —— 专注页计时 1Hz 刷新，
        // 等于每秒全场重设一次，会打断 UIScrollView 的减速动画，造成滚动顿挫。
    }

    /// 已处理过的滚动容器（weak，避免持有视图导致泄漏）
    @MainActor private static let handled = NSHashTable<UIScrollView>.weakObjects()

    @MainActor
    static func scheduleDisableIfNeeded() {
        // 延后一拍：等 SwiftUI 完成本轮布局、滚动容器真正进入视图树后再扫描
        DispatchQueue.main.async {
            guard let window = activeWindow() else { return }
            walk(window)
        }
    }

    @MainActor
    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return scenes
            .first(where: { $0.windows.contains(where: { $0.isKeyWindow }) })?
            .windows
            .first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
    }

    @MainActor
    private static func walk(_ view: UIView) {
        if let scroll = view as? UIScrollView,
           !isInsidePicker(scroll),
           !handled.contains(scroll) {
            handled.add(scroll)
            // 只关「空内容拖动」，不碰 bounces（2026-11-02 二次修正）：
            // bounces=false 会移除边缘橡皮筋，是「撞墙没弹」的直接原因，已撤销。
            // 现在保留原生回弹，仅保证内容不足一屏的短页面拖不动。
            if scroll.alwaysBounceVertical { scroll.alwaysBounceVertical = false }
        }
        for subview in view.subviews {
            walk(subview)
        }
    }

    /// 日期/选项选择器的滚轮内部也是 UIScrollView（UIPickerTableView）。
    /// 它们不承担「页面下拉露白」问题，禁掉弹性只会让拨轮手感变差，故排除。
    @MainActor
    private static func isInsidePicker(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let node = current {
            if node is UIPickerView { return true }
            current = node.superview
        }
        return false
    }
}