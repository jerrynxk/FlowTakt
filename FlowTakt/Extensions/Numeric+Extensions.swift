import Foundation

// MARK: - Numeric Helpers

extension Int {
    /// 若值为 0 则返回 fallback，否则返回自身
    func nonZeroElse(_ fallback: Int) -> Int {
        return self > 0 ? self : fallback
    }
}

extension Double {
    /// 若值为 0 则返回 fallback，否则返回自身
    func nonZeroElse(_ fallback: Double) -> Double {
        return self > 0 ? self : fallback
    }
}
