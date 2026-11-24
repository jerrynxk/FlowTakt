import Foundation

// MARK: - Numeric Helpers

extension Int {
    /// 若值为 0 则返回 fallback，否则返回自身
    /// 注意：非零即返（包含负数），不是仅正数才返
    func nonZeroElse(_ fallback: Int) -> Int {
        return self != 0 ? self : fallback
    }
}

extension Double {
    /// 若值为 0 则返回 fallback，否则返回自身
    /// 注意：非零即返（包含负数），不是仅正数才返
    func nonZeroElse(_ fallback: Double) -> Double {
        return self != 0 ? self : fallback
    }

    /// 崩溃修复（2026-10-02）：是否为有限值（排除 NaN / ±infinity）。
    /// JSON 可合法解码出 `1e300` 这类极大值或 `NaN`，
    /// 后续 `Int(value)` 转换会触发 `Fatal error`（Swift 的 Int 初始化对越界值 trap）。
    /// 所有从持久化数据 / 外部文件读入的 Double 在转换前都应先用此校验。
    var isFiniteValue: Bool {
        return isFinite
    }

    /// 崩溃修复（2026-10-02）：是否为有限值且落在 `[0, maxSaneDuration]` 区间。
    /// 上限取 Int32.max 秒（约 68 年），确保 Int 转换永不 trap，既覆盖任何真实使用场景，又远低于 Int64.max。
    var isSaneValue: Bool {
        return isFinite && self >= 0 && self <= Double(Int32.max)
    }
}
