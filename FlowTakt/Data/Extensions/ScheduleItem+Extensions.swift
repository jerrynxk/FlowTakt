import Foundation
import CoreData

extension ScheduleItem {
    // MARK: - 缓存

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    // MARK: - 计算属性
    var timeRangeText: String {
        if isAllDay {
            return L10n.shared.全天
        }
        if let end = endDate {
            return "\(Self.timeFormatter.string(from: startDate)) - \(Self.timeFormatter.string(from: end))"
        }
        return Self.timeFormatter.string(from: startDate)
    }

    /// 日期简短描述（审查修复：复用 Date.shortDateString，删除重复的 MM/dd formatter）
    var dateText: String {
        if Calendar.current.isDateInToday(startDate) {
            return L10n.shared.今日
        }
        if Calendar.current.isDateInTomorrow(startDate) {
            return L10n.shared.明日
        }
        return startDate.shortDateString
    }

    // MARK: - 提醒相关辅助

    /// 分类枚举
    var categoryEnum: ScheduleCategory {
        ScheduleCategory(rawValue: category) ?? .event
    }

    /// 重复规则枚举
    var repeatRuleEnum: RepeatRule {
        RepeatRule(rawValue: repeatRule ?? "") ?? .none
    }

    /// 提前量（分钟，Int 形式便于 UI 使用）
    var reminderLeadMinutesInt: Int {
        Int(reminderLeadMinutes)
    }

    /// 下一次发生的日期：
    /// - 生日/纪念日：下一个匹配的月/日（全天默认 09:00，否则取原时间）
    /// - 事件/客户拜访：原定 startDate
    var nextOccurrenceDate: Date? {
        let cal = Calendar.current
        if categoryEnum.repeatsYearly {
            let md = cal.dateComponents([.month, .day], from: startDate)
            let reference = isAllDay
                ? (cal.date(bySettingHour: 9, minute: 0, second: 0, of: startDate) ?? startDate)
                : startDate
            let time = cal.dateComponents([.hour, .minute], from: reference)
            let thisYear = cal.component(.year, from: Date())
            // 2/29 生日在平年不存在 → 回退到 2/28（保持「每年 2 月底」语义，避免 date(from:) nil 回退原始 startDate 显示错误年份）
            var targetDay = md.day ?? 1
            if md.month == 2, md.day == 29,
               cal.date(from: DateComponents(year: thisYear, month: 2, day: 29)) == nil {
                targetDay = 28
            }
            var base = cal.date(from: DateComponents(
                year: thisYear,
                month: md.month,
                day: targetDay,
                hour: time.hour ?? 9,
                minute: time.minute ?? 0,
                second: 0
            )) ?? startDate
            // 展示语义：以「今天 0 点」为界，仅当月/日已早于今天才翻到明年；
            // 整个生日当天（含下午）仍视为「本次发生」，避免显示「还有 365 天」。
            // 通知触发不受影响——yearly 触发器只取 month/day/hour/minute，由系统计算下一次未来时刻。
            if base < cal.startOfDay(for: Date()) {
                base = cal.date(byAdding: .year, value: 1, to: base) ?? base
            }
            return base
        }
        return startDate
    }

    /// 距离下一次发生还有多少整天（含今天为 0）
    var daysUntilNext: Int? {
        guard let next = nextOccurrenceDate else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: Date()),
                                  to: cal.startOfDay(for: next)).day
    }
}
