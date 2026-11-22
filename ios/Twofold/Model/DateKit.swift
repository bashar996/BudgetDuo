import Foundation

/// Month and day keys are plain strings ("2026-11", "2026-11-21") in the
/// user's local calendar, so both phones file an entry under the same day.
enum DateKit {
    static let months = ["January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December"]
    static let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    static var cal: Calendar { Calendar(identifier: .gregorian) }

    static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    static func ym(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month], from: d)
        return "\(c.year!)-\(pad(c.month!))"
    }

    static func iso(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return "\(c.year!)-\(pad(c.month!))-\(pad(c.day!))"
    }

    static func parts(_ ym: String) -> (Int, Int) {
        let p = ym.split(separator: "-").compactMap { Int($0) }
        return (p.count > 0 ? p[0] : 2000, p.count > 1 ? p[1] : 1)
    }

    static func date(_ iso: String) -> Date {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        let comps = DateComponents(year: p.count > 0 ? p[0] : 2000, month: p.count > 1 ? p[1] : 1, day: p.count > 2 ? p[2] : 1)
        return cal.date(from: comps) ?? Date()
    }

    static func addMonths(_ ym: String, _ n: Int) -> String {
        let (y, m) = parts(ym)
        let total = y * 12 + (m - 1) + n
        return "\(total / 12)-\(pad(total % 12 + 1))"
    }

    static func daysIn(_ ym: String) -> Int {
        let d = date(ym + "-01")
        return cal.range(of: .day, in: .month, for: d)?.count ?? 30
    }

    static func day(_ d: Date) -> Int { cal.component(.day, from: d) }

    static func monthName(_ ym: String, short: Bool = false) -> String {
        let m = months[parts(ym).1 - 1]
        return short ? String(m.prefix(3)) : m
    }

    static func monthLabel(_ ym: String, short: Bool = false) -> String {
        "\(monthName(ym, short: short)) \(parts(ym).0)"
    }

    /// "Sat 21 Nov"
    static func dayLabel(_ iso: String) -> String {
        let d = date(iso)
        let wd = cal.component(.weekday, from: d) - 1
        let m = cal.component(.month, from: d) - 1
        return "\(weekdays[wd]) \(day(d)) \(months[m].prefix(3))"
    }

    /// "5 Mar 2027"
    static func dateLabel(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, (1...12).contains(p[1]) else { return iso }
        return "\(p[2]) \(months[p[1] - 1].prefix(3)) \(p[0])"
    }
}

struct Money {
    var currency: String

    /// 12,345 or −12,345 (rounded, true minus sign)
    func num(_ n: Double) -> String {
        let r = n.rounded()
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        let s = f.string(from: NSNumber(value: abs(r))) ?? "\(Int(abs(r)))"
        return (r < 0 ? "−" : "") + s
    }

    /// AED 12,345 or −AED 12,345
    func f(_ n: Double) -> String {
        let s = num(n)
        if s.hasPrefix("−") { return "−" + currency + " " + s.dropFirst() }
        return currency + " " + s
    }

    static func pct(_ x: Double) -> Double { max(0, min(1, x.isFinite ? x : 0)) }
}
