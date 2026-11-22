import Foundation

/// Which column is which. Port of `Mapping` in desktop/src/import/detect.ts.
struct StmtMapping: Codable, Equatable {
    /// Row index of the header, −1 when the file has none.
    var header = -1
    var date = -1
    /// Value date, used when the transaction date is empty.
    var vdate = -1
    var desc = -1
    /// Single signed amount column (−1 when Debit + Credit are used).
    var amount = -1
    var debit = -1
    var credit = -1
    var balance = -1
    /// A "Cr/Dr" column next to the amount.
    var dir = -1
    var order: DateOrder = .dmy
    /// Single amount column: positive amounts are money out (card statements).
    var posOut = false

    /// Every column this mapping uses.
    var columns: [Int] { [date, vdate, desc, amount, debit, credit, balance, dir] }
}

/// A parsed line before the sign convention is applied.
struct StmtRawRow {
    /// Index in the source (table row or PDF line).
    var i: Int
    var date: String
    var desc: String
    var money: StmtAmount
    /// Direction already known (+1 in, −1 out) from Debit/Credit columns or the running balance.
    var fixed: Int?
    var balance: Double?
    var raw: String
}

/// A statement row: + money in, − money out.
struct StmtRow: Equatable {
    var i: Int
    var date: String
    var desc: String
    var amount: Double
    var balance: Double?
    var raw: String
}

/// How unsigned amounts should be read.
struct SignGuess {
    var posOut: Bool
    var sure: Bool
    /// False when every row's direction is already decided (no toggle needed).
    var show: Bool
}

enum StmtDetect {
    static let noiseRow = RX(#"\b(opening|closing|previous|available|ledger|statement|brought|carried|beginning|ending)\s+(balance|forward|bal)\b|\bbalance\s+(b/f|c/f|brought|carried|forward)\b|^\s*(sub\s*)?totals?\b|^\s*b/f\b|^\s*c/f\b"#, ci: true)

    // MARK: Header detection

    enum Role { case date, vdate, desc, amount, debit, credit, balance, dir }

    private static let spaces = RX(#"[_\s]+"#)
    private static let trailPunct = RX(#"[.:]+$"#)

    static func norm(_ s: String) -> String {
        trailPunct.replace(spaces.replace(s.lowercased(), " "), "").jsTrim
    }

    private static let rBalance = RX("balance")
    private static let rDir = RX(#"^(cr ?/ ?dr|dr ?/ ?cr|debit ?/ ?credit|credit ?/ ?debit|d ?/ ?c|c ?/ ?d|dc|cd|sign)$"#)
    private static let rVdate = RX(#"value date|^val(ue)? dt$"#)
    private static let rDate1 = RX(#"^(transaction|trans|txn|tran|posting|post|posted|booking|book|entry|effective)?\s?(date|dt)( posted)?$"#)
    private static let rDate2 = RX(#"^date( of transaction| \(.*\))?$"#)
    private static let rDebit = RX(#"^(debit|debits|withdrawal|withdrawals|dr|money out|paid out|out|debit amount|withdrawal amount|amount debited|debit \(.*\)|withdrawals? \(.*\))$"#)
    private static let rCredit = RX(#"^(credit|credits|deposit|deposits|cr|money in|paid in|in|credit amount|deposit amount|amount credited|credit \(.*\)|deposits? \(.*\))$"#)
    private static let rAmount = RX(#"^(amount|transaction amount|txn amount|amount \(.*\)|amount [a-z]{3}|billing amount|billed amount|local amount|amount in [a-z]{3}|net amount|value)$"#)
    private static let rDesc1 = RX(#"^(description|details|narration|narrative|particulars|merchant|merchant name|transaction details|transaction description|remarks|memo|payee|transaction|description / narration|beneficiary|details of transaction|reference|transaction narration)$"#)
    private static let rDesc2 = RX(#"description|narration|particulars|details"#)

    static func roleOf(_ cell: String) -> Role? {
        let c = norm(cell)
        if c.isEmpty || c.u16Count > 40 { return nil }
        if rBalance.test(c) { return .balance }
        if rDir.test(c) { return .dir }
        if rVdate.test(c) { return .vdate }
        if rDate1.test(c) || rDate2.test(c) { return .date }
        if rDebit.test(c) { return .debit }
        if rCredit.test(c) { return .credit }
        if rAmount.test(c) { return .amount }
        if rDesc1.test(c) { return .desc }
        if rDesc2.test(c) { return .desc }
        return nil
    }

    private static func headerScore(_ row: [String]) -> Double {
        let roles = row.map(roleOf)
        func has(_ r: Role) -> Bool { roles.contains { $0 == r } }
        let money = has(.amount) || has(.debit) || has(.credit)
        return (has(.date) || has(.vdate) ? 2 : 0) + (money ? 2 : 0) + (has(.desc) ? 1 : 0) + (has(.balance) ? 0.5 : 0)
    }

    static func cell(_ r: [String], _ c: Int) -> String { c >= 0 && c < r.count ? r[c].jsTrim : "" }

    private static func slice(_ table: [[String]], _ from: Int, _ to: Int) -> [[String]] {
        let a = max(0, min(from, table.count)), b = max(a, min(to, table.count))
        return Array(table[a..<b])
    }

    /// Columns from a header row (first within the first 30 that names a date and an
    /// amount), else by content.
    static func detect(_ table: [[String]], isCard: Bool) -> StmtMapping {
        var found: StmtMapping?
        for r in 0..<min(30, table.count) where headerScore(table[r]) >= 4 {
            found = fromHeader(table, r)
            break
        }
        var m = found ?? StmtMapping()
        if found == nil || (m.date < 0 && m.vdate < 0) { m = byContent(table) }
        let dateCol = m.date >= 0 ? m.date : m.vdate
        m.order = StmtDates.detectOrder(slice(table, m.header + 1, table.count).map { cell($0, dateCol) })
        m.posOut = false
        var rows = rawRows(table, m)
        prepare(&rows, isCard: isCard)
        m.posOut = inferSign(rows, isCard: isCard).posOut
        return m
    }

    private static let localAmount = RX(#"aed|billing|billed|local|د\.إ"#, ci: true)
    private static let dirValue = RX(#"^(cr|dr|c|d|credit|debit)$"#)

    private static func fromHeader(_ table: [[String]], _ r: Int) -> StmtMapping {
        var m = StmtMapping()
        m.header = r
        var amounts: [Int] = []
        for (i, c) in table[r].enumerated() {
            guard let role = roleOf(c) else { continue }
            switch role {
            case .amount: amounts.append(i)
            case .date: if m.date < 0 { m.date = i }
            case .vdate: if m.vdate < 0 { m.vdate = i }
            case .desc: if m.desc < 0 { m.desc = i }
            case .debit: if m.debit < 0 { m.debit = i }
            case .credit: if m.credit < 0 { m.credit = i }
            case .balance: if m.balance < 0 { m.balance = i }
            case .dir: if m.dir < 0 { m.dir = i }
            }
        }
        // Several amount columns (card statements: original currency + AED): prefer the local one.
        if let last = amounts.last {
            m.amount = amounts.first { localAmount.test(table[r][$0]) } ?? last
        }
        if m.amount >= 0 && m.debit >= 0 && m.credit >= 0 { m.amount = -1 }
        if m.amount < 0 && m.debit >= 0 && m.credit < 0 { m.amount = m.debit; m.debit = -1 }
        if m.amount < 0 && m.credit >= 0 && m.debit < 0 { m.amount = m.credit; m.credit = -1 }
        if m.date < 0 && m.vdate >= 0 { m.date = m.vdate; m.vdate = -1 }
        // A "Cr/Dr" column only counts if its values look like it.
        if m.dir >= 0 {
            let vals = slice(table, r + 1, r + 40).map { norm(cell($0, m.dir)) }.filter { !$0.isEmpty }
            if vals.isEmpty || Double(vals.filter { dirValue.test($0) }.count) < Double(vals.count) * 0.8 { m.dir = -1 }
        }
        if m.desc < 0 { m.desc = widestText(table, r + 1, skip: [m.date, m.vdate, m.amount, m.debit, m.credit, m.balance, m.dir]) }
        return m
    }

    static func width(_ rows: [[String]]) -> Int { rows.map(\.count).max() ?? 0 }

    private static func widestText(_ table: [[String]], _ from: Int, skip: [Int]) -> Int {
        let rows = slice(table, from, from + 60)
        var best = -1
        var bestLen = 0.0
        for c in 0..<width(rows) where !skip.contains(c) {
            let vals = rows.map { cell($0, c) }.filter { !$0.isEmpty }
            if vals.isEmpty { continue }
            let text = vals.filter { StmtAmounts.parse($0) == nil && !StmtDates.isDateLike($0) }
            let len = Double(text.reduce(0) { $0 + $1.u16Count }) / Double(vals.count)
            if Double(text.count) >= Double(vals.count) * 0.6 && len > bestLen { bestLen = len; best = c }
        }
        return best
    }

    /// No header row: a date-like column, the widest text column, and the numeric columns.
    private static func byContent(_ table: [[String]]) -> StmtMapping {
        var m = StmtMapping()
        let rows = slice(table, 0, 200)
        let w = width(rows)
        guard !rows.isEmpty, w > 0 else { return m }
        struct Stat { var dateF: Double; var numF: Double; var filled: Int }
        let stats: [Stat] = (0..<w).map { c in
            let filled = rows.map { cell($0, c) }.filter { !$0.isEmpty }
            let dates = filled.filter { StmtDates.isDateLike($0) }.count
            let nums = filled.filter { StmtAmounts.parse($0) != nil && !StmtDates.isDateLike($0) }.count
            return Stat(dateF: filled.isEmpty ? 0 : Double(dates) / Double(rows.count),
                        numF: filled.isEmpty ? 0 : Double(nums) / Double(max(1, filled.count)),
                        filled: filled.count)
        }
        var dateBest = 0.0
        for (c, s) in stats.enumerated() where s.dateF > dateBest + 0.05 { dateBest = s.dateF; m.date = c }
        if m.date < 0 { return m }
        // The data starts at the first row with a date.
        let first = rows.firstIndex { StmtDates.isDateLike(cell($0, m.date)) } ?? 0
        m.header = first - 1
        let nums = stats.indices.filter { c in c != m.date && stats[c].numF > 0.8 && stats[c].filled >= 1 && !(stats[c].dateF > 0.5) }
        m.desc = widestText(table, first, skip: [m.date] + nums)
        let data = slice(table, first, table.count)
        if nums.count == 1 {
            m.amount = nums[0]
        } else if nums.count == 2 {
            // Debit + Credit when each row fills only one of them, else Amount + Balance.
            let both = data.filter { !cell($0, nums[0]).isEmpty && !cell($0, nums[1]).isEmpty }.count
            if Double(both) < Double(data.count) * 0.2 { m.debit = nums[0]; m.credit = nums[1] } else { m.amount = nums[0]; m.balance = nums[1] }
        } else if nums.count >= 3 {
            let last3 = Array(nums.suffix(3))
            m.debit = last3[0]; m.credit = last3[1]; m.balance = last3[2]
        }
        return m
    }

    /// The file's "shape" (its header names, or its column count), the key a remembered
    /// mapping is stored under.
    static func shapeOf(_ table: [[String]], _ m: StmtMapping) -> String {
        if m.header >= 0 && m.header < table.count { return "h:" + table[m.header].map(norm).joined(separator: "|") }
        return "c:\(width(slice(table, 0, 20)))"
    }

    // MARK: Rows

    private static let dirCr = RX(#"^(cr|c|credit)$"#)
    private static let dirDr = RX(#"^(dr|d|debit)$"#)

    static func rawRows(_ table: [[String]], _ m: StmtMapping) -> [StmtRawRow] {
        var out: [StmtRawRow] = []
        let used = m.columns
        var i = m.header + 1
        while i < table.count {
            defer { i += 1 }
            if i < 0 { continue }
            let r = table[i]
            guard let date = StmtDates.parse(cell(r, m.date), m.order) ?? StmtDates.parse(cell(r, m.vdate), m.order) else { continue }
            var desc = cell(r, m.desc)
            if desc.isEmpty {
                desc = r.enumerated().filter { c, v in !v.isEmpty && !used.contains(c) && StmtAmounts.parse(v) == nil }
                    .map { $0.element }.joined(separator: " ")
            }
            if noiseRow.test(desc) { continue }
            var money: StmtAmount?
            var fixed: Int?
            if m.amount >= 0 {
                money = StmtAmounts.parse(cell(r, m.amount))
                if money != nil && m.dir >= 0 {
                    let d = norm(cell(r, m.dir))
                    if dirCr.test(d) { money?.mark = .cr } else if dirDr.test(d) { money?.mark = .dr }
                }
            } else {
                let dv = abs(StmtAmounts.parse(cell(r, m.debit))?.value ?? 0)
                let cv = abs(StmtAmounts.parse(cell(r, m.credit))?.value ?? 0)
                if dv != 0 || cv != 0 {
                    money = StmtAmount(value: abs(cv - dv), mark: nil)
                    fixed = cv >= dv ? 1 : -1
                }
            }
            guard let mv = money, mv.value != 0 else { continue }
            let b = StmtAmounts.parse(cell(r, m.balance))
            out.append(StmtRawRow(i: i, date: date, desc: desc, money: mv, fixed: fixed,
                                  balance: b.map { StmtAmounts.signed($0) },
                                  raw: r.filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        return out
    }

    private static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.015 }

    /// Sets the direction of unsigned amounts from the running balance. Works whichever
    /// way round the statement is sorted. For a card whose balance is shown as the amount
    /// owed, a rising balance is money out.
    static func balanceSigns(_ rows: inout [StmtRawRow], isCard: Bool) {
        let withBal = rows.filter { $0.balance != nil }
        guard withBal.count >= 2 else { return }
        let owedPositive = isCard && Double(withBal.filter { ($0.balance ?? 0) > 0 }.count) > Double(withBal.count) / 2
        let flip = owedPositive ? -1 : 1
        func tryOrder(_ list: [Int]) -> [Int: Int] {
            var res: [Int: Int] = [:]
            for k in stride(from: 1, to: list.count, by: 1) {
                let p = rows[list[k - 1]], r = rows[list[k]]
                guard let pb = p.balance, let rb = r.balance else { continue }
                let d = rb - pb, v = abs(r.money.value)
                if near(d, v) { res[list[k]] = flip } else if near(d, -v) { res[list[k]] = -flip }
            }
            return res
        }
        let fwd = tryOrder(Array(rows.indices)), rev = tryOrder(Array(rows.indices.reversed()))
        let best = rev.count > fwd.count ? rev : fwd
        for (idx, s) in best where rows[idx].fixed == nil { rows[idx].fixed = s }
    }

    /// Sign convention for amounts whose direction isn't known yet.
    static func inferSign(_ rows: [StmtRawRow], isCard: Bool) -> SignGuess {
        let open = rows.filter { $0.fixed == nil && $0.money.mark == nil }
        if open.isEmpty { return SignGuess(posOut: isCard, sure: true, show: false) }
        let neg = open.filter { $0.money.value < 0 }.count, pos = open.count - neg
        // Running balance as evidence when the amounts carry signs.
        var a = 0, b = 0
        let withBal = rows.filter { $0.balance != nil }
        if withBal.count >= 3 {
            let owedPositive = isCard && Double(withBal.filter { ($0.balance ?? 0) > 0 }.count) > Double(withBal.count) / 2
            for list in [Array(rows.indices), Array(rows.indices.reversed())] {
                var a1 = 0, b1 = 0
                for k in stride(from: 1, to: list.count, by: 1) {
                    let p = rows[list[k - 1]], r = rows[list[k]]
                    guard let pb = p.balance, let rb = r.balance, r.fixed == nil, r.money.mark == nil else { continue }
                    let d = rb - pb
                    if near(d, r.money.value) { a1 += 1 } else if near(d, -r.money.value) { b1 += 1 }
                }
                if a1 + b1 > a + b { a = a1; b = b1 }
            }
            if owedPositive { swap(&a, &b) }
            if a + b >= 2 { return SignGuess(posOut: b > a, sure: true, show: true) }
        }
        if neg == 0 { return SignGuess(posOut: true, sure: false, show: true) }
        if isCard { return SignGuess(posOut: pos >= neg, sure: false, show: true) }
        return SignGuess(posOut: false, sure: true, show: true)
    }

    /// Unsigned amounts (no minus, brackets or Cr/Dr anywhere) take their direction from the balance.
    static func prepare(_ rows: inout [StmtRawRow], isCard: Bool) {
        if !rows.contains(where: { $0.fixed == nil && ($0.money.value < 0 || $0.money.mark != nil) }) {
            balanceSigns(&rows, isCard: isCard)
        }
    }

    private static let ws = RX(#"\s+"#)

    /// Applies the sign convention: + money in, − money out.
    static func finalize(_ rows: [StmtRawRow], posOut: Bool) -> [StmtRow] {
        rows.map { r in
            let amt = r.fixed.map { Double($0) * abs(r.money.value) } ?? StmtAmounts.signed(r.money, posIsOut: posOut)
            return StmtRow(i: r.i, date: r.date, desc: ws.replace(r.desc, " ").jsTrim, amount: StmtAmounts.round2(amt),
                           balance: r.balance, raw: r.raw)
        }
    }
}
