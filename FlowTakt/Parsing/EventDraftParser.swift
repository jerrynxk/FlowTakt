import Foundation

// MARK: - 日程草稿（B2 自然语言解析产物）

struct EventDraft {
    let title: String
    let startDate: Date
    let endDate: Date?
}

// MARK: - 自然语言快速建日程解析器（B2）
// 支持常见中文表达：
//   "明天下午3点 开会"      → 标题「开会」，明天 15:00
//   "今天 20:00 看电影"     → 标题「看电影」，今天 20:00
//   "下周一上午9点半 晨会"   → 标题「晨会」，下周一 09:30
//   "后天 12:30 午餐"       → 标题「午餐」，后天 12:30
//   "3月15日 体检"          → 标题「体检」，3/15 09:00（缺时间默认 9 点）
//   "下午3点 写方案"        → 标题「写方案」，今天 15:00
// 解析不成功返回 nil（调用方回退到完整表单）。

enum EventDraftParser {

    private static let chineseWeekdays: [Character: Int] = [
        "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1
    ]

    static func parse(_ input: String, now: Date = Date()) -> EventDraft? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let calendar = Calendar.current

        // 1. 解析日期词（今天/明天/周几/月日），从文本中移除
        let baseDate = extractDay(from: &text, now: now, calendar: calendar)

        // 2. 解析时间词（上午/下午/X点/X:XX），从文本中移除
        let timeComponents = extractTime(from: &text, baseDate: baseDate, calendar: calendar)

        // 3. 剩余文本为标题
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // 4. 合成开始时间：有时间词用之；无时间词默认当天 9:00（早间日程惯例）
        let start: Date
        if let time = timeComponents {
            start = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: baseDate) ?? baseDate
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
        }
        let end = calendar.date(byAdding: .hour, value: 1, to: start)
        return EventDraft(title: title, startDate: start, endDate: end)
    }

    // MARK: - 日期词解析

    /// 从文本开头/任意位置提取日期词并移除；返回基准日期（当天 0 点）
    private static func extractDay(from text: inout String, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let dayPattern = "今天|今晚|明天|后天|大后天|下个?(周)?[一二三四五六日天]|本周[一二三四五六日天]|[0-9]{1,2}月[0-9]{1,2}[日号]|[0-9]{1,2}[日号]"
        guard let range = text.range(of: dayPattern, options: .regularExpression) else {
            return today
        }
        let token = String(text[range])
        text.removeSubrange(range)

        // 1) 具体日期词（不含数字、非周几形式）
        switch token {
        case "今天", "今晚":
            return today
        case "明天":
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case "后天":
            return calendar.date(byAdding: .day, value: 2, to: today) ?? today
        case "大后天":
            return calendar.date(byAdding: .day, value: 3, to: today) ?? today
        default:
            break
        }

        // 2) 月日（8月15日）优先于「仅日」，且先于周几判断——
        //    否则 "8月15日" 的末尾「日」会被误判为「周日」导致日期偏移一天
        if token.range(of: "[0-9]", options: .regularExpression) != nil {
            if let m = token.range(of: "([0-9]{1,2})月([0-9]{1,2})", options: .regularExpression) {
                let md = token[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if md.count == 2 {
                    let thisYear = calendar.component(.year, from: now)
                    if let date = calendar.date(from: DateComponents(year: thisYear, month: md[0], day: md[1])) {
                        return date
                    }
                }
            }
            // 仅日：定位到本月该日；若已过则取下月（简单处理）
            if let n = token.range(of: "[0-9]{1,2}", options: .regularExpression),
               let day = Int(token[n]) {
                let thisMonth = calendar.dateComponents([.year, .month], from: today)
                if let date = calendar.date(from: DateComponents(year: thisMonth.year, month: thisMonth.month, day: day)) {
                    if date >= today { return date }
                    return calendar.date(byAdding: .month, value: 1, to: date) ?? today
                }
            }
            return today
        }

        // 修复（2026-10-14 P2）：月日非法值（如「13月40日」）此前会继续 fall through 到
        // 「仅日」分支，用月份数字当日号 → 得到一个「看起来合法但完全错误」的日期。
        // 匹配到月日格式即必须返回，非法则回退今天。
        if token.range(of: "^\\d{1,2}月\\d{1,2}日?$", options: .regularExpression) != nil {
            return today
        }

        // 3) 周几（严格限定整词形式：下周一 / 本周X / 周X / 单字X，避免数字串误判）
        let weekdayWordPattern = "^(下个?|本周)?周?[一二三四五六日天]$"
        let weekdayMatch = token.range(of: weekdayWordPattern, options: .regularExpression)
        if weekdayMatch != nil,
           let weekdayChar = token.last, let target = chineseWeekdays[weekdayChar] {
            let current = calendar.component(.weekday, from: today)
            var diff = (target - current + 7) % 7
            // 修复（审查 #4）：「本周X」今天就是 X 时指向今天；「X/周X/下X」今天不当作今天 → 下一周同日
            if diff == 0 && !token.hasPrefix("本") { diff = 7 }
            return calendar.date(byAdding: .day, value: diff, to: today) ?? today
        }

        return today
    }

    // MARK: - 时间词解析

    /// 从文本提取时间词并移除；返回 hour/minute（无时间词返回 nil）
    private static func extractTime(from text: inout String, baseDate: Date, calendar: Calendar) -> (hour: Int, minute: Int)? {
        // 优先 HH:mm（token 由正则自带可选时段前缀与空格）
        let clockPattern = "(上午|下午|晚上|早上|中午)?\\s*([0-9]{1,2})[:：]([0-9]{2})"
        if let range = text.range(of: clockPattern, options: .regularExpression) {
            let token = String(text[range])
            text.removeSubrange(range)
            return parseClockToken(token)
        }
        // X点 / X点半 / X点X分
        let pointPattern = "(上午|下午|晚上|早上|中午)?\\s*([0-9]{1,2})点(半)?([0-9]{1,2})?分?"
        if let range = text.range(of: pointPattern, options: .regularExpression) {
            let token = String(text[range])
            text.removeSubrange(range)
            return parsePointToken(token)
        }
        return nil
    }

    private static func parseClockToken(_ token: String) -> (hour: Int, minute: Int)? {
        // 修复（2026-10-14 审查 P1-12）：旧实现按 ":" 拆分后 `Int("下午3")` 失败，
        // 于是 hour/minute 保持初值 0 并「成功」返回 (0, 0) —— 「下午3:30 开会」被静默
        // 建到今天 00:00，而同义的「下午3点半」却解析正确，极难察觉。
        // 现改为与 `parsePointToken` 同一策略：先抽取数字（时、分），再单独识别时段词。
        // 注意：分隔判据是「非数字即分隔符」—— 冒号本身也是分隔符，
        // 若把冒号排除在分隔之外，"20:00" 会作为整块不拆分、Int("20:00") 恒为 nil。
        let numbers = token
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return normalized(hour: numbers[0], minute: numbers[1], period: detectPeriod(token))
    }

    private static func parsePointToken(_ token: String) -> (hour: Int, minute: Int)? {
        let numbers = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard let hour = numbers.first else { return nil }
        var minute = 0
        if token.contains("半") { minute = 30 }
        if numbers.count >= 2 { minute = numbers[1] }
        let period = detectPeriod(token)
        return normalized(hour: hour, minute: minute, period: period)
    }

    /// 上午/早上 → 原样；下午/晚上/中午 → +12（12 点不调整，即「晚上12点」按 12:00 处理）
    private static func normalized(hour: Int, minute: Int, period: String?) -> (hour: Int, minute: Int) {
        var h = hour
        if let period {
            switch period {
            case "上午", "早上":
                if h == 12 { h = 0 }
            case "下午", "晚上", "中午":
                if h < 12 { h += 12 }
            default:
                break
            }
        }
        // 修复（2026-10-14 P2）：范围钳制 —— 正则允许小时 0-99 / 分钟 00-99，
        // 越界值会让 `date(bySettingHour:)` 兜底回落到当天 00:00（静默错误数据）。
        h = min(max(h, 0), 23)
        let m = min(max(minute, 0), 59)
        return (h, m)
    }

    private static func detectPeriod(_ token: String) -> String? {
        for p in ["上午", "早上", "下午", "晚上", "中午"] where token.hasPrefix(p) {
            return p
        }
        return nil
    }
}
