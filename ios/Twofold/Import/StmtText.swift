import Foundation

// Statement import, the pure part (no SwiftUI, no Firebase). These files mirror the Mac's
// desktop/src/import/*.ts rule for rule (same patterns, keywords and thresholds), so a
// statement reads the same on both. Offsets are UTF-16, as in JavaScript.

/// A compiled regular expression with the few JS-style helpers the import code needs.
/// Patterns are fixed strings, so a bad one is a programming error.
struct RX {
    let re: NSRegularExpression

    init(_ pattern: String, ci: Bool = false) {
        // swiftlint:disable:next force_try
        re = try! NSRegularExpression(pattern: pattern, options: ci ? [.caseInsensitive] : [])
    }

    static func whole(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    func test(_ s: String) -> Bool { re.firstMatch(in: s, options: [], range: RX.whole(s)) != nil }

    func match(_ s: String) -> RXMatch? {
        guard let m = re.firstMatch(in: s, options: [], range: RX.whole(s)) else { return nil }
        return RXMatch(m, s)
    }

    func matches(_ s: String) -> [RXMatch] {
        re.matches(in: s, options: [], range: RX.whole(s)).map { RXMatch($0, s) }
    }

    /// Replaces every match with `with` (taken literally).
    func replace(_ s: String, _ with: String) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: RX.whole(s),
                                    withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }
}

struct RXMatch {
    /// UTF-16 offset and length of the whole match.
    let index: Int
    let length: Int
    /// groups[0] is the whole match; nil for a group that took no part.
    let groups: [String?]
    var end: Int { index + length }

    init(_ m: NSTextCheckingResult, _ s: String) {
        let ns = s as NSString
        index = m.range.location
        length = m.range.length
        groups = (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
}

extension String {
    /// JS `slice(from, to)` on UTF-16 offsets.
    func u16(_ from: Int, _ to: Int? = nil) -> String {
        let ns = self as NSString
        let a = Swift.max(0, Swift.min(from, ns.length))
        let b = Swift.max(a, Swift.min(to ?? ns.length, ns.length))
        return ns.substring(with: NSRange(location: a, length: b - a))
    }

    /// JS `length`.
    var u16Count: Int { (self as NSString).length }

    /// JS `trim()`.
    var jsTrim: String { trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))) }
}

// MARK: Dates

/// Day-first (UAE default) or month-first.
enum DateOrder: String, Codable { case dmy, mdy }

/// Statement dates: dd/mm/yyyy, dd-mm-yyyy, dd.mm.yyyy, yyyy-mm-dd, dd MMM yyyy, dd-MMM-yy,
/// dd/mm/yy, MMM dd, yyyy and Excel serial numbers. Port of desktop/src/import/dates.ts.
enum StmtDates {
    static let months = "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"
    private static let monthNumbers: [String: Int] = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    private static func monthNo(_ s: String) -> Int { monthNumbers[String(s.lowercased().prefix(3))] ?? 0 }
    private static func int(_ s: String?) -> Int { Int(s ?? "") ?? 0 }
    private static func year(_ s: String?) -> Int { let v = s ?? ""; return v.count == 2 ? 2000 + int(v) : int(v) }

    static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func iso(_ y: Int, _ m: Int, _ d: Int) -> String? {
        guard (1990...2100).contains(y), (1...12).contains(m), d >= 1, d <= daysIn(y, m) else { return nil }
        return "\(y)-\(DateKit.pad(m))-\(DateKit.pad(d))"
    }

    /// Days since 1970-01-01 → (year, month, day). Plain arithmetic, no time zones.
    static func civil(_ days: Int) -> (Int, Int, Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400
        return (m <= 2 ? y + 1 : y, m, d)
    }

    /// (year, month, day) → days since 1970-01-01.
    static func dayNumber(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let y2 = m <= 2 ? y - 1 : y
        let era = (y2 >= 0 ? y2 : y2 - 399) / 400
        let yoe = y2 - era * 400
        let mm = m > 2 ? m - 3 : m + 9
        let doy = (153 * mm + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// "yyyy-MM-dd" → days since 1970-01-01.
    static func dayNumber(_ iso: String) -> Int {
        let p = iso.split(separator: "-").map { Int($0) ?? 0 }
        return dayNumber(p.count > 0 ? p[0] : 2000, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }

    /// Excel's day count (1900 system) → ISO date.
    static func fromSerial(_ n: Double) -> String? {
        guard n > 20000 && n < 80000 else { return nil }
        let (y, m, d) = civil(Int(n.rounded(.down)) - 25569)
        return iso(y, m, d)
    }

    private static let reISO = RX(#"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:$|[T\s])"#)
    private static let reNUM = RX(#"^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?:$|\s)"#)
    private static let reDMON = RX(#"^(\d{1,2})[-/. ]?("# + months + #")\.?[-/., ]?\s*(\d{4}|\d{2})?(?:$|\s|,)"#, ci: true)
    private static let reMOND = RX(#"^("# + months + #")\.?[ -](\d{1,2})(?:st|nd|rd|th)?,?[ -](\d{4})(?:$|\s)"#, ci: true)
    private static let reSerial = RX(#"^\d{5}(\.\d+)?$"#)

    /// Two numeric parts that could be either way round, for `detectOrder`.
    static func numericParts(_ s: String) -> (Int, Int)? {
        guard let m = reNUM.match(s.jsTrim) else { return nil }
        return (int(m[1]), int(m[2]))
    }

    /// dmy unless some value only makes sense as mm/dd.
    static func detectOrder(_ values: [String]) -> DateOrder {
        var firstBig = false, secondBig = false
        for v in values {
            guard let p = numericParts(v) else { continue }
            if p.0 > 12 { firstBig = true }
            if p.1 > 12 { secondBig = true }
        }
        return secondBig && !firstBig ? .mdy : .dmy
    }

    /// "yyyy-MM-dd", or nil. `fallbackYear` is for dates printed without a year ("12 Nov").
    static func parse(_ input: String, _ order: DateOrder = .dmy, fallbackYear: Int? = nil) -> String? {
        let s = input.replacingOccurrences(of: "\u{00A0}", with: " ").jsTrim
        if s.isEmpty { return nil }
        if let m = reISO.match(s) { return iso(int(m[1]), int(m[2]), int(m[3])) }
        if let m = reNUM.match(s) {
            let a = int(m[1]), b = int(m[2]), y = year(m[3])
            return order == .mdy ? iso(y, a, b) : iso(y, b, a)
        }
        if let m = reDMON.match(s) {
            let y: Int? = m[3] != nil ? year(m[3]) : fallbackYear
            guard let y else { return nil }
            return iso(y, monthNo(m[2] ?? ""), int(m[1]))
        }
        if let m = reMOND.match(s) { return iso(int(m[3]), monthNo(m[1] ?? ""), int(m[2])) }
        if reSerial.test(s), let n = Double(s) { return fromSerial(n) }
        return nil
    }

    static func isDateLike(_ s: String, _ order: DateOrder = .dmy) -> Bool { parse(s, order, fallbackYear: 2000) != nil }

    /// Date tokens at the start of a line of PDF text.
    private static let lead = RX(#"^\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[-/.]\d{1,2}[-/.](?:\d{4}|\d{2})|\d{1,2}[-/ ]?(?:"# + months
        + #")\.?(?:[-/ ,]\s?(?:\d{4}|\d{2}))?|(?:"# + months + #")\.? \d{1,2},? \d{4})(?=\s|$)"#, ci: true)

    /// Up to two dates at the start of a line (transaction date, then value date) and the rest.
    static func leadingDates(_ line: String) -> (dates: [String], rest: String) {
        var dates: [String] = []
        var rest = line
        for _ in 0..<2 {
            guard let m = lead.match(rest) else { break }
            dates.append((m[1] ?? "").jsTrim)
            rest = rest.u16(m.end)
        }
        return (dates, rest.jsTrim)
    }
}

// MARK: Amounts

enum StmtMark: String, Codable { case cr, dr }

struct StmtAmount: Equatable {
    var value: Double
    var mark: StmtMark?
}

/// A money amount in a line of statement text, with where it sits (UTF-16 offsets).
struct StmtToken {
    var text: String
    var index: Int
    var end: Int
    var amount: StmtAmount
}

/// Money amounts as banks print them: "1,234.50", "(1,234.50)", "-1234.5", "1,234.50 Cr",
/// "AED 1,234.50-", "1.234,50". Port of desktop/src/import/amounts.ts.
enum StmtAmounts {
    private static let currency = RX(#"\b(AED|USD|EUR|GBP|SAR|QAR|KWD|BHD|OMR|INR|DHS?|DH)\b|د\.إ|[$€£₹]"#, ci: true)
    private static let markRe = RX(#"(?:(?<=[\d)])|\s+)(CR|DR)\.?$"#, ci: true)
    private static let markRe2 = RX(#"\s+(C|D)$"#, ci: true)
    private static let digit = RX(#"\d"#)
    private static let parens = RX(#"^\(.*\)$"#)
    private static let leadDash = RX(#"^[−–]"#)
    private static let trailDash = RX(#"[−–]$"#)
    private static let euro1 = RX(#"^\d{1,3}(\.\d{3})+,\d{1,2}$"#)
    private static let euro2 = RX(#"^\d+,\d{1,2}$"#)
    private static let spaced = RX(#"^\d{1,3}( \d{3})+(\.\d+)?$"#)
    private static let plain = RX(#"^\d+(\.\d+)?$|^\.\d+$"#)
    private static let oddSpaces = RX("[\u{00A0}\u{2007}\u{202F}]")

    /// One cell or token; nil when it isn't an amount.
    static func parse(_ input: String) -> StmtAmount? {
        var s = oddSpaces.replace(input, " ").jsTrim
        if s.isEmpty { return nil }
        var mark: StmtMark?
        if let m = markRe.match(s) ?? markRe2.match(s), digit.test(s.u16(0, m.index)) {
            let k = (m[1] ?? "").lowercased()
            mark = k == "cr" || k == "c" ? .cr : .dr
            s = s.u16(0, m.index).jsTrim
        }
        s = currency.replace(s, "").jsTrim
        var neg = false
        if parens.test(s) { neg = true; s = s.u16(1, s.u16Count - 1).jsTrim }
        s = leadDash.replace(s, "-")
        s = trailDash.replace(s, "-")
        if s.hasPrefix("-") { neg.toggle(); s = String(s.dropFirst()).jsTrim }
        else if s.hasSuffix("-") { neg.toggle(); s = String(s.dropLast()).jsTrim }
        else if s.hasPrefix("+") { s = String(s.dropFirst()).jsTrim }
        s = currency.replace(s, "").jsTrim
        if s.isEmpty { return nil }
        if euro1.test(s) || euro2.test(s) {
            s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if spaced.test(s) {
            s = s.replacingOccurrences(of: " ", with: "")
        } else {
            s = s.replacingOccurrences(of: ",", with: "")
        }
        guard plain.test(s), let v = Double(s.hasPrefix(".") ? "0" + s : s), v.isFinite else { return nil }
        return StmtAmount(value: neg ? -v : v, mark: mark)
    }

    /// + money in, − money out. A Cr/Dr mark wins over the sign.
    static func signed(_ a: StmtAmount, posIsOut: Bool = false) -> Double {
        let v = abs(a.value)
        if a.mark == .cr { return v }
        if a.mark == .dr { return -v }
        return posIsOut ? -a.value : a.value
    }

    /// JS `Math.round(n * 100) / 100`.
    static func round2(_ n: Double) -> Double { (n * 100 + 0.5).rounded(.down) / 100 }

    private static let token = RX(#"(?:(?:AED|USD|EUR|GBP|SAR)\s?)?\(?[-−]?\s?(?:\d{1,3}(?:,\d{3})+|\d+)\.\d{2}\)?(?:-|\s?(?:CR|DR|Cr|Dr|cr|dr)\b)?"#)
    private static let gluedBefore = RX(#"^[A-Za-z0-9./]$"#)
    private static let gluedAfter = RX(#"^[A-Za-z0-9/]$"#)

    /// Amounts in a line of statement text (PDF), left to right. Only numbers with two
    /// decimals count, so reference numbers and dates are left alone.
    static func tokens(_ line: String) -> [StmtToken] {
        let ns = line as NSString
        var out: [StmtToken] = []
        for m in token.matches(line) {
            if m.index > 0, gluedBefore.test(ns.substring(with: NSRange(location: m.index - 1, length: 1))) { continue }
            if m.end < ns.length, gluedAfter.test(ns.substring(with: NSRange(location: m.end, length: 1))) { continue }
            let text = m[0] ?? ""
            if let a = parse(text) { out.append(StmtToken(text: text, index: m.index, end: m.end, amount: a)) }
        }
        return out
    }
}
