import Foundation
import CryptoKit

// Statement rows → proposed entries (desktop/src/import/plan.ts and dedupe.ts).

// MARK: Import IDs and duplicates

enum StmtDedupe {
    private static let ws = RX(#"\s+"#)

    /// Raw description as it goes into the import ID: upper case, single spaces, trimmed.
    static func idDesc(_ s: String) -> String { ws.replace(s.uppercased(), " ").jsTrim }

    /// The amount as it goes into the import ID: exactly 2 decimals, "." separator, "-" for money out.
    static func idAmount(_ x: Double) -> String { String(format: "%.2f", x) }

    /// Stable ID of a statement line, the same on the Mac:
    /// "imp_" + lowercase hex of the first 8 bytes of
    /// SHA-256("{accountId}|{yyyy-MM-dd}|{-38.00}|{DESCRIPTION}|{n}") (UTF-8), where n counts
    /// identical lines (same date, amount and description) earlier in the same file, from 0.
    static func importId(acct: String, date: String, amount: Double, desc: String, occurrence: Int) -> String {
        let text = [acct, date, idAmount(amount), idDesc(desc), String(occurrence)].joined(separator: "|")
        let digest = SHA256.hash(data: Data(text.utf8))
        return "imp_" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Import IDs for a file's rows, numbering identical lines.
    static func importIds(acct: String, rows: [StmtRow]) -> [String] {
        var seen: [String: Int] = [:]
        return rows.map { (r: StmtRow) -> String in
            let k = [r.date, idAmount(r.amount), idDesc(r.desc)].joined(separator: "|")
            let n = seen[k] ?? 0
            seen[k] = n + 1
            return importId(acct: acct, date: r.date, amount: r.amount, desc: r.desc, occurrence: n)
        }
    }

    /// The existing entry a row probably is: same amount (±0.01) in the same direction, dated
    /// within 3 days. On the same account it also needs one of: the same date, a similar name
    /// (word overlap ≥ 0.5), a bill payment, or the category the row would get; on another
    /// account, a similar name. Best score wins; each entry matches at most one row (`used`).
    static func likelyDuplicate(_ tx: [Tx], acct: String, date: String, amount: Double, name: String, desc: String,
                                cat: String?, used: Set<String>) -> Tx? {
        let amt = abs(amount), inflow = amount > 0, d = StmtDates.dayNumber(date)
        var best: Tx?
        var bestScore = -1.0
        for t in tx {
            if used.contains(t.id) || abs(t.amt - amt) > 0.011 { continue }
            let dd = abs(StmtDates.dayNumber(t.date) - d)
            if dd > 3 { continue }
            let sameAcct = inflow
                ? (t.type == .income && t.acct == acct) || (t.type == .transfer && t.to == acct)
                : (t.type == .expense && t.acct == acct) || (t.type == .transfer && t.acct == acct)
            let dirOk = inflow ? t.type != .expense : t.type != .income
            if !dirOk { continue }
            let sim = max(StmtClean.similarity(name, t.name), StmtClean.similarity(desc, t.name))
            let alike = dd == 0 || sim >= 0.5 || t.billId != nil || (cat != nil && cat == t.cat)
            let keep = sameAcct ? alike : sim >= 0.5
            if !keep { continue }
            let base: Double = sameAcct ? 2 : 0
            let score = base + sim - Double(dd) * 0.1
            if score > bestScore { best = t; bestScore = score }
        }
        return best
    }
}

// MARK: Plan

enum ImportStatus: String {
    case new, needsCat, imported, dupe, transfer, cardPayment, refund, bill, loan, income, salary
}

/// One statement line in the review list: what it will become, and whether it's ticked.
struct ImportRow: Identifiable {
    struct BillMatch: Equatable {
        var id: String
        /// The calendar month of the bill's due date: its `paid` key.
        var ym: String
        var name: String
    }

    let id: Int
    let row: StmtRow
    let importId: String
    /// Ticked for import.
    var on = true
    var status: ImportStatus = .new
    /// Badge text: "Matches bill Rent", "Already in Twofold · Carrefour", …
    var note = ""
    var kind: TxType
    var name: String
    var cat: String?
    /// "history", "rule" or "user".
    var catHow: String?
    var who: Who
    var bill: BillMatch?
    var debtId: String?
    /// Transfers: from → to.
    var from: String?
    var to: String?

    var isDuplicate: Bool { status == .imported || status == .dupe }
    /// A ticked expense needs a category before it can be imported.
    var ready: Bool { !(kind == .expense && cat == nil) }
}

/// What the store writes for one imported line.
struct ImportEntry {
    var tx: Tx
    /// The bill it pays: marked paid for that month.
    var bill: BillMonth?
}

struct BillMonth: Equatable, Hashable {
    var id: String
    var ym: String
}

/// What Undo takes back: the entries an import wrote and the bills it marked paid.
struct ImportUndo: Identifiable, Equatable {
    let id = UUID()
    var txIds: [String]
    var bills: [BillMonth]
    var count: Int { txIds.count }
}

enum ImportPlanner {
    private static let salary = RX(#"\b(salary|payroll|sal|wages|wps)\b"#, ci: true)
    private static let xfer = RX(#"\b(transfer|trf|tfr|ft|own account|own acc|xfer|fund transfer|funds transfer)\b"#, ci: true)
    private static let cardPay = RX(#"\b(payment|thank you|thankyou|pymt|pmt|paid)\b"#, ci: true)
    private static let cardOut = RX(#"\b(card payment|cc payment|credit card payment|card pymt|cc pymt|card settlement)\b"#, ci: true)
    private static let refund = RX(#"\b(refund|reversal|reversed|cashback|cash back|chargeback|return)\b"#, ci: true)

    /// Another account of yours that a description names (by name or last four digits).
    private static func ownAccount(_ desc: String, _ accounts: [Account], _ me: String) -> Account? {
        let d = desc.lowercased()
        return accounts.first { a in
            guard a.id != me else { return false }
            if let l4 = a.last4, !l4.isEmpty,
               RX("(^|[^0-9])" + NSRegularExpression.escapedPattern(for: l4) + "($|[^0-9])").test(d) { return true }
            return a.name.u16Count >= 5 && d.contains(a.name.lowercased())
        }
    }

    static func plan(_ rows: [StmtRow], ids: [String], acctId: String, L: Ledger) -> [ImportRow] {
        let acct = L.accounts.first { $0.id == acctId }
        let isCard = acct?.type == .card
        let catIds = Set(L.rows.map(\.id))
        let has: (String) -> Bool = { catIds.contains($0) }
        let history = StmtCategory.historyIndex(L.tx, has: has)
        let known = Set(L.tx.compactMap(\.importId))
        var used = Set<String>(), usedBills = Set<String>()
        let who: Who = acct?.who == .a || acct?.who == .b ? (acct?.who ?? .joint) : .joint
        let main = (L.accounts.first { $0.type == .current && $0.id != acctId }
            ?? L.accounts.first { ($0.type == .current || $0.type == .cash) && $0.id != acctId })
        let firstCard = L.accounts.first { $0.type == .card }

        var out: [ImportRow] = []
        for (key, row) in rows.enumerated() {
            let name = StmtClean.name(row.desc)
            let isOut = row.amount < 0, amt = abs(row.amount)
            // The budget month the line falls in; a bill's due date in it gives the month it pays
            // (its calendar month is the `paid` key). With the 1st as start day that's the line's month.
            let rowPeriod = Period(containing: row.date, start: L.cycleStart)
            var p = ImportRow(id: key, row: row, importId: key < ids.count ? ids[key] : "", kind: isOut ? .expense : .income,
                              name: name, who: who)

            if isOut {
                let bill = L.bills.first { (b: Bill) -> Bool in
                    let due: String = rowPeriod.billDue(day: b.day)
                    let billKey = String(due.prefix(7))
                    if b.paid[billKey] ?? false { return false }
                    if usedBills.contains(b.id + billKey) { return false }
                    let tolerance: Double = max(0.011, b.amt * 0.01)
                    if abs(b.amt - amt) > tolerance { return false }
                    if StmtClean.similarity(name, b.name) >= 0.5 { return true }
                    if StmtClean.similarity(row.desc, b.name) >= 0.5 { return true }
                    return abs(Period.daysBetween(due, row.date)) <= 3
                }
                var loan: Debt?
                if bill == nil {
                    loan = L.debts.first { (l: Debt) -> Bool in
                        let inst = Loans.installmentOf(l)
                        let lender = l.lender ?? ""
                        let named = StmtClean.similarity(row.desc, l.name) >= 0.5
                            || (!lender.isEmpty && StmtClean.similarity(row.desc, lender) >= 0.5)
                        let tolerance: Double = max(1, inst * 0.02)
                        return named && inst > 0 && abs(inst - amt) <= tolerance
                    }
                }
                let other = isCard ? nil : ownAccount(row.desc, L.accounts, acctId)
                if let bill {
                    let billKey = String(rowPeriod.billDue(day: bill.day).prefix(7))
                    usedBills.insert(bill.id + billKey)
                    p.status = .bill; p.note = "Matches bill " + bill.name
                    p.bill = ImportRow.BillMatch(id: bill.id, ym: billKey, name: bill.name)
                    p.name = bill.name; p.cat = bill.cat; p.catHow = "rule"; p.who = .joint; p.debtId = bill.debtId
                } else if let loan {
                    p.status = .loan; p.note = "Installment on " + loan.name; p.debtId = loan.id
                    p.name = loan.name + " · installment"
                    p.cat = has("debt") ? "debt" : (L.rows.first?.id ?? "debt"); p.catHow = "rule"
                } else if let to = other ?? (!isCard && cardOut.test(row.desc) ? firstCard : nil) {
                    p.status = .transfer; p.on = false; p.kind = .transfer
                    p.note = "Looks like a transfer to " + to.name
                    p.from = acctId; p.to = to.id; p.cat = "transfer"; p.name = "Transfer to " + to.name
                } else if let s = StmtCategory.suggest(raw: row.desc, name: name, history: history, has: has) {
                    p.cat = s.cat; p.catHow = s.how
                } else {
                    p.status = .needsCat; p.note = "Needs a category"
                }
            } else if isCard {
                if cardPay.test(row.desc) && !refund.test(row.desc) {
                    p.status = .cardPayment; p.on = false; p.name = "Card payment"
                    if let main {
                        p.kind = .transfer; p.note = "Card payment — record it as a transfer from " + main.name + "?"
                        p.from = main.id; p.to = acctId; p.cat = "transfer"
                    } else {
                        p.kind = .income; p.note = "Card payment"; p.cat = "income"
                    }
                } else {
                    let cleaned = StmtClean.name(refund.replace(row.desc, " "))
                    let merchant = cleaned.isEmpty ? name : cleaned
                    p.status = .refund; p.note = "Refund"; p.kind = .income; p.cat = "income"
                    p.name = String(("Refund · " + merchant).prefix(48))
                }
            } else if salary.test(row.desc) {
                p.status = .salary; p.note = "Salary"; p.cat = "income"; p.name = "Salary"; p.who = .joint
            } else if xfer.test(row.desc) || ownAccount(row.desc, L.accounts, acctId) != nil {
                p.status = .transfer; p.on = false; p.note = "Looks like a transfer"; p.cat = "income"
            } else {
                p.status = .income; p.note = "Income"; p.cat = "income"
            }

            // Duplicates.
            if known.contains(p.importId) {
                p.on = false; p.status = .imported; p.note = "Already imported"
            } else if let dupe = StmtDedupe.likelyDuplicate(L.tx, acct: acctId, date: row.date, amount: row.amount,
                                                            name: name, desc: row.desc, cat: p.cat, used: used) {
                used.insert(dupe.id)
                if let b = p.bill { usedBills.remove(b.id + b.ym) }
                p.on = false; p.status = .dupe; p.note = "Already in Twofold · " + dupe.name
            }
            out.append(p)
        }
        return out
    }

    /// The entry a ticked row becomes. A bill match uses the bill's fixed entry id
    /// ("bill-{billId}-{ym}") so it can't count twice; a loan match carries debtId.
    static func entry(_ p: ImportRow, acctId: String) -> ImportEntry {
        let trimmed = p.name.jsTrim
        let isTransfer = p.kind == .transfer, isIncome = p.kind == .income
        let name: String = trimmed.isEmpty ? (isIncome ? "Income" : "Expense") : trimmed
        let cat: String = isTransfer ? "transfer" : (isIncome ? "income" : (p.cat ?? "other"))
        let from: String = isTransfer ? (p.from ?? acctId) : acctId
        let to: String? = isTransfer ? p.to : nil
        var t = Tx(id: "", date: p.row.date, name: name, cat: cat,
                   amt: StmtAmounts.round2(abs(p.row.amount)), who: p.who, type: p.kind, note: p.row.desc,
                   billId: nil, acct: from, to: to, pot: nil, potDir: nil, createdAt: Date(),
                   debtId: nil, debtPart: nil, importId: p.importId, source: "import")
        if p.kind == .expense, let d = p.debtId { t.debtId = d; t.debtPart = "installment" }
        if p.kind == .expense, let b = p.bill {
            t.id = "bill-\(b.id)-\(b.ym)"
            t.billId = b.id
            return ImportEntry(tx: t, bill: BillMonth(id: b.id, ym: b.ym))
        }
        return ImportEntry(tx: t, bill: nil)
    }
}

// MARK: Remembered columns

/// The column mapping and sign convention per account and file shape, kept on this phone
/// (the Mac keeps its own in localStorage `twofold:importMap:{acctId}`).
enum ImportMemory {
    private static func key(_ acct: String) -> String { "twofold.importMap.\(acct)" }

    private static func all(_ acct: String) -> [String: StmtMapping] {
        guard let d = UserDefaults.standard.data(forKey: key(acct)),
              let m = try? JSONDecoder().decode([String: StmtMapping].self, from: d) else { return [:] }
        return m
    }

    static func load(acct: String, shape: String) -> StmtMapping? { all(acct)[shape] }

    static func save(_ m: StmtMapping, acct: String, shape: String) {
        var list = all(acct)
        list[shape] = m
        if let d = try? JSONEncoder().encode(list) { UserDefaults.standard.set(d, forKey: key(acct)) }
    }
}
