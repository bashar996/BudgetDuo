import Foundation

/// A budget month that starts on a chosen day (`Household.cycleStart`, 1–28; 1 = calendar months).
///
/// A period is keyed "yyyy-MM" like a calendar month (so `checks`, `roundSwept`, `settled` …
/// keep working) and is named after the month most of its days are in: with start 25,
/// "2026-12" runs 25 Nov – 24 Dec; with start 10, "2026-11" runs 10 Nov – 9 Dec.
/// Same rules as the Mac (desktop/src/lib/period.ts).
struct Period: Equatable {
    /// "yyyy-MM"
    let key: String
    /// Day of the month it starts (1…28).
    let start: Int
    /// First day, "yyyy-MM-dd" (inclusive).
    let from: String
    /// Last day, "yyyy-MM-dd" (inclusive).
    let to: String

    init(key: String, start: Int) {
        let s = Period.clamp(start)
        let r = Period.range(key, start: s)
        self.key = key
        self.start = s
        self.from = r.from
        self.to = r.to
    }

    /// The period a "yyyy-MM-dd" date falls in.
    init(containing iso: String, start: Int) {
        self.init(key: Period.key(iso, start: start), start: start)
    }

    // MARK: Rules

    /// A start day kept to 1…28 (missing = 1).
    static func clamp(_ start: Int?) -> Int { max(1, min(28, start ?? 1)) }

    /// The household's start day.
    static func startDay(of h: Household) -> Int { clamp(h.cycleStart) }

    /// Key of the period containing `iso` ("yyyy-MM-dd").
    static func key(_ iso: String, start: Int) -> String {
        let s = clamp(start)
        let ym = String(iso.prefix(7))
        if s <= 1 { return ym }
        let day = Int(iso.dropFirst(8).prefix(2)) ?? 1
        let startMonth = day >= s ? ym : DateKit.addMonths(ym, -1)
        return s <= 15 ? startMonth : DateKit.addMonths(startMonth, 1)
    }

    private static func startDate(_ month: String, _ s: Int) -> String {
        month + "-" + DateKit.pad(min(s, DateKit.daysIn(month)))
    }

    /// First and last day of period `key`, both inclusive.
    static func range(_ key: String, start: Int) -> (from: String, to: String) {
        let s = clamp(start)
        if s <= 1 { return (key + "-01", key + "-" + DateKit.pad(DateKit.daysIn(key))) }
        let startMonth = s <= 15 ? key : DateKit.addMonths(key, -1)
        let next = startDate(DateKit.addMonths(startMonth, 1), s)
        return (startDate(startMonth, s), addDays(next, -1))
    }

    /// The period `n` periods later (earlier when negative): the same as adding months to the key.
    static func shift(_ key: String, _ n: Int) -> String { DateKit.addMonths(key, n) }

    static func addDays(_ iso: String, _ n: Int) -> String {
        let d = DateKit.date(iso)
        return DateKit.iso(DateKit.cal.date(byAdding: .day, value: n, to: d) ?? d)
    }

    /// Whole days from `a` to `b` ("yyyy-MM-dd"; b − a).
    static func daysBetween(_ a: String, _ b: String) -> Int {
        DateKit.cal.dateComponents([.day], from: DateKit.date(a), to: DateKit.date(b)).day ?? 0
    }

    // MARK: This period

    /// Days in the period.
    var days: Int { Period.daysBetween(from, to) + 1 }

    /// 1-based day number of `iso` in the period (1 = `from`).
    func dayIndex(_ iso: String) -> Int { Period.daysBetween(from, iso) + 1 }

    func contains(_ iso: String) -> Bool { iso >= from && iso <= to }

    func shifted(_ n: Int) -> Period { Period(key: Period.shift(key, n), start: start) }

    var previous: Period { shifted(-1) }

    /// Every day of the period in order, "yyyy-MM-dd".
    var dates: [String] { (0..<max(1, days)).map { Period.addDays(from, $0) } }

    /// When a bill on `day` of the month is due inside the period: the date with day
    /// min(day, days in that month) that falls in the range (the start month or the next).
    /// Its calendar month (first 7 characters) is the bill's `paid` key.
    func billDue(day: Int) -> String {
        for m in [String(from.prefix(7)), String(to.prefix(7))] {
            let iso = m + "-" + DateKit.pad(min(max(1, day), DateKit.daysIn(m)))
            if contains(iso) { return iso }
        }
        return from
    }

    /// The date in the period whose day of the month is `day` (unique: a period never
    /// holds the same day number twice), or nil.
    func date(forDay day: Int) -> String? {
        for m in [String(from.prefix(7)), String(to.prefix(7))] where day >= 1 && day <= DateKit.daysIn(m) {
            let iso = m + "-" + DateKit.pad(day)
            if contains(iso) { return iso }
        }
        return nil
    }

    // MARK: Labels

    /// "25 Nov"
    static func dayMonth(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        let month: String = String(DateKit.months[p[1] - 1].prefix(3))
        return "\(p[2]) \(month)"
    }

    /// "25 Nov – 24 Dec"
    var rangeLabel: String { Period.dayMonth(from) + " – " + Period.dayMonth(to) }

    /// "December", plus " · 25 Nov – 24 Dec" when the budget month doesn't start on the 1st.
    var name: String {
        let month: String = DateKit.monthName(key)
        return start > 1 ? month + " · " + rangeLabel : month
    }

    /// "December 2026", plus " · 25 Nov – 24 Dec" when the budget month doesn't start on the 1st.
    func label(short: Bool = false) -> String {
        let month: String = DateKit.monthLabel(key, short: short)
        return start > 1 ? month + " · " + rangeLabel : month
    }
}
