import Foundation

// Loan and credit-card maths. Mirrors desktop/src/data/loans.ts line by line (that
// file is the reference): same function names, formulas, defaults and edge cases,
// so the Mac and the iPhone show the same numbers. Change both together.
//
// Loans are households/{code}/debts/{id} (`Debt`). Payments are ordinary expense
// entries with `debtId` (and `debtPart`: "installment" | "extra"), so deleting an
// entry undoes the payment. Outstanding balance is never stored. A card plan's
// processing fee has debtPart "fee": it's linked to the plan but isn't a payment.
// Cards are accounts with type card (`Account`: apr, limit, statementDay, dueDay,
// minPct, minFloor).

struct LoanPayment: Equatable {
    var date: String
    var amt: Double
    /// "installment" or "extra"
    var part: String
}

struct ScheduleRow: Identifiable, Equatable {
    var n: Int
    var date: String
    var payment: Double
    var interest: Double
    var principal: Double
    var balance: Double
    /// paid (counted in paidBefore or by a payment entry)
    var paid: Bool
    var id: Int { n }
}

struct LoanState: Equatable {
    /// Outstanding principal today.
    var balance: Double
    var principal: Double
    var rate: Double
    /// "reducing" or "flat"
    var rateType: String
    /// For flat loans, the reducing-balance rate that costs the same.
    var effectiveRate: Double
    var installment: Double
    var termMonths: Int?
    var installmentsPaid: Int
    var installmentsLeft: Int
    /// Principal repaid, 0…1
    var progress: Double
    var paidSoFar: Double
    var interestPaid: Double
    var interestLeft: Double
    var totalLeft: Double
    /// "yyyy-MM-dd" of the next installment, or nil when paid off.
    var nextDue: String?
    /// "yyyy-MM" of the last installment at the current pace.
    var endsYm: String?
    /// Interest over the whole loan as originally agreed.
    var totalInterest: Double
    var settlement: Double
    var schedule: [ScheduleRow]
    /// True for older loans without amount borrowed / term / first date.
    var simple: Bool
}

/// One installment of a card plan: its number (1-based), date and what it posts.
struct PlanInstallment: Equatable {
    var n: Int
    /// "yyyy-MM-dd"
    var date: String
    var amt: Double
}

/// A card installment plan today (`Loans.planState`).
struct PlanState: Equatable {
    /// The loan maths over the plan's posted entries (schedule, interest, rate, …).
    var st: LoanState
    var term: Int
    /// Installments billed so far: billedThrough (at least paidBefore), at most the term.
    var billed: Int
    /// Paid off before the last installment was billed (the "close early" entry).
    var closed: Bool
    /// Nothing more will be billed: every installment billed, or closed early.
    var done: Bool
    /// Principal still to be billed on the card (0 when done).
    var remaining: Double
    /// The next installment Twofold will post, or nil when done.
    var next: PlanInstallment?
    /// "yyyy-MM" of the last installment, as agreed.
    var endsYm: String?
    /// Close early today: remaining × (1 + fee %).
    var settlement: Double
}

struct PrepayEffect: Equatable {
    var monthsSaved: Int
    var interestSaved: Double
}

struct CardPayoff: Equatable {
    var months: Int
    var interest: Double
    var never: Bool
}

struct CardState: Equatable {
    var owed: Double
    var limit: Double?
    var utilisation: Double?
    var apr: Double
    var minDue: Double
    /// "yyyy-MM-dd"
    var nextDue: String?
    var nextStatement: String?
    /// Interest next month if only the minimum is paid.
    var interestIfMin: Double
    /// Paying only the minimum each month.
    var minOnly: CardPayoff
}

/// A credit card with its installment plans (`Loans.cardWithPlans`): the `CardState` fields,
/// with owed, utilisation, minDue, interestIfMin and minOnly worked out with the plans, plus:
struct CardPlanState: Equatable {
    /// −balance + planRemaining (0 when in credit).
    var owed: Double
    var limit: Double?
    var utilisation: Double?
    var apr: Double
    var minDue: Double
    /// "yyyy-MM-dd"
    var nextDue: String?
    var nextStatement: String?
    var interestIfMin: Double
    var minOnly: CardPayoff
    /// On the card's balance (billed installments included), 0 when in credit.
    var owedOnCard: Double
    /// Principal of the card's plans still to be billed.
    var planRemaining: Double
    /// Plan installments and fees billed this cycle (part of the minimum, in full).
    var billedThisCycle: Double
    /// What's owed on the card apart from this cycle's installments: the part the minimum % and interest apply to.
    var revolving: Double
}

enum Loans {
    static let MAX = 600

    // MARK: Date helpers (same as lib/dates.ts; plain arithmetic, no Calendar, as these run in loops)

    /// JS `s.slice(a, b)` for the ASCII date strings.
    private static func slice(_ s: String, _ a: Int, _ b: Int) -> String {
        let u = Array(s.utf8)
        let lo = min(max(0, a), u.count), hi = min(max(lo, b), u.count)
        return String(decoding: u[lo..<hi], as: UTF8.self)
    }

    /// "yyyy-MM" of a "yyyy-MM-dd".
    private static func monthOf(_ iso: String) -> String { slice(iso, 0, 7) }

    /// Days in a month ("yyyy-MM").
    static func dim(_ ym: String) -> Int {
        let (y, m) = DateKit.parts(ym)
        switch m {
        case 2: return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    // MARK: Loans

    /// Same day each month, clamped to the month's length.
    static func nthDue(_ firstDue: String, _ k: Int) -> String {
        let ym = DateKit.addMonths(monthOf(firstDue), k)
        let d0 = Int(slice(firstDue, 8, 10)) ?? 0
        let day = min(d0 != 0 ? d0 : 1, dim(ym))
        return ym + "-" + DateKit.pad(day)
    }

    /// Equal monthly installment on a reducing balance.
    static func emi(_ principal: Double, _ ratePct: Double, _ months: Int) -> Double {
        if months <= 0 { return principal }
        let r = ratePct / 1200
        if r == 0 { return principal / Double(months) }
        return (principal * r) / (1 - pow(1 + r, -Double(months)))
    }

    /// Flat rate: interest on the full amount borrowed for the whole term.
    static func flatInstallment(_ principal: Double, _ ratePct: Double, _ months: Int) -> Double {
        months > 0 ? principal / Double(months) + (principal * ratePct) / 1200 : principal
    }

    /// The reducing rate with the same installment as a flat-rate loan.
    static func flatToReducing(_ ratePct: Double, _ months: Int) -> Double {
        if months <= 0 || ratePct <= 0 { return ratePct }
        let target = flatInstallment(1, ratePct, months)
        var lo = 0.0, hi = 200.0
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            if emi(1, mid, months) > target { hi = mid } else { lo = mid }
        }
        return (lo + hi) / 2
    }

    /// Annual rate for a month ("yyyy-MM"), after any rate changes.
    static func rateAt(_ loan: Debt, _ ym: String) -> Double {
        var r = loan.rate ?? loan.apr
        guard let all = loan.rateChanges, !all.isEmpty else { return r }
        // Stable sort by month, as Array.prototype.sort is.
        let changes = all.enumerated()
            .sorted { $0.element.from != $1.element.from ? $0.element.from < $1.element.from : $0.offset < $1.offset }
            .map(\.element)
        for c in changes where c.from <= ym { r = c.rate }
        return r
    }

    static func isSimple(_ l: Debt) -> Bool {
        guard let p = l.principal, p > 0, let n = l.termMonths, n > 0, let f = l.firstDue, !f.isEmpty else { return true }
        return false
    }

    /// The bank's installment was entered.
    private static func hasFixedInstallment(_ l: Debt) -> Bool { (l.installment ?? 0) > 0 }

    /// Installment: the bank's figure if given, otherwise calculated.
    static func installmentOf(_ l: Debt) -> Double {
        if let i = l.installment, i > 0 { return i }
        if isSimple(l) { return l.min.isNaN ? 0 : l.min }
        let rate = l.rate ?? l.apr
        let p = l.principal ?? 0, n = l.termMonths ?? 0
        return (l.rateType ?? "reducing") == "flat" ? flatInstallment(p, rate, n) : emi(p, rate, n)
    }

    /// Everything about a loan today.
    /// - Parameters:
    ///   - payments: entries with this loan's debtId, any order
    ///   - today: "yyyy-MM-dd"
    static func loanState(_ l: Debt, _ payments: [LoanPayment], today: String) -> LoanState {
        let simple = isSimple(l)
        let rateType = simple ? "reducing" : (l.rateType ?? "reducing")
        let flat = rateType == "flat"
        let P = simple ? l.balance : (l.principal ?? 0)
        let n: Int? = simple ? nil : l.termMonths
        let nn = n ?? 0
        let hasN = nn != 0
        let fixed = hasFixedInstallment(l)
        // Older loans have no first date: assume the month after they were added.
        let added = l.createdAt ?? DateKit.date(today)
        let first = l.firstDue ?? (DateKit.addMonths(DateKit.ym(added), 1) + "-" + DateKit.pad(min(28, DateKit.day(added))))
        let baseRate = l.rate ?? l.apr
        var inst = installmentOf(l)
        let flatInt = flat ? (P * baseRate) / 1200 : 0
        let flatPrin = flat && hasN ? P / Double(nn) : 0

        // The schedule as agreed (with rate changes on reducing loans: the installment
        // is recalculated over the remaining months, as banks do).
        var schedule: [ScheduleRow] = []
        var bal = P, instNow = inst, totalInterest = 0.0
        /// Installment level in force for each period (reducing loans).
        var instAt: [Double] = []
        var k = 0
        let rows = n ?? MAX
        while k < rows && bal > 0.005 {
            let date = nthDue(first, k)
            let interest: Double
            var principal: Double
            if flat {
                interest = flatInt
                principal = min(bal, flatPrin)
            } else {
                let r = rateAt(l, monthOf(date))
                if k > 0 && r != rateAt(l, monthOf(nthDue(first, k - 1))) && hasN && !fixed { instNow = emi(bal, r, nn - k) }
                instAt.append(instNow)
                interest = (bal * r) / 1200
                principal = min(bal, max(0, instNow - interest))
                if hasN && k == nn - 1 { principal = bal }
                if principal <= 0 && interest > 0 {
                    schedule.append(ScheduleRow(n: k + 1, date: date, payment: interest, interest: interest, principal: 0, balance: bal, paid: false))
                    break
                }
            }
            bal -= principal
            totalInterest += interest
            schedule.append(ScheduleRow(n: k + 1, date: date, payment: principal + interest, interest: interest,
                                        principal: principal, balance: max(0, bal), paid: false))
            k += 1
        }

        // Replay what's actually been paid.
        let before = max(0, min(l.paidBefore ?? 0, schedule.count))
        bal = before > 0 ? schedule[before - 1].balance : P
        var interestPaid = schedule.prefix(before).reduce(0.0) { $0 + $1.interest }
        var paidSoFar = schedule.prefix(before).reduce(0.0) { $0 + $1.payment }
        var count = before
        let sorted = payments.enumerated()
            .sorted { $0.element.date != $1.element.date ? $0.element.date < $1.element.date : $0.offset < $1.offset }
            .map(\.element)
        for p in sorted {
            if bal <= 0.005 { break }
            paidSoFar += p.amt
            if p.part == "extra" { bal = max(0, bal - p.amt); continue }
            let interest = flat ? flatInt : (bal * rateAt(l, monthOf(p.date))) / 1200
            interestPaid += min(interest, p.amt)
            bal = max(0, bal - max(0, p.amt - interest))
            count += 1
        }
        for i in schedule.indices { schedule[i].paid = i < count }

        // From here on, at the installment the schedule has reached. Extra payments
        // keep the installment and shorten the loan (the usual bank default).
        let recalc = !simple && rateType == "reducing" && !fixed
        if recalc && !instAt.isEmpty { inst = instAt[min(count, instAt.count - 1)] }
        let instToday = inst
        var b = bal, months = 0, interestLeft = 0.0
        while b > 0.005 && months < MAX {
            let date = nthDue(first, count + months)
            // A future rate change resets the installment so the loan still ends when it
            // would have at the old rate.
            if recalc && months > 0 {
                let rOld = rateAt(l, monthOf(nthDue(first, count + months - 1))), rNew = rateAt(l, monthOf(date))
                if rNew != rOld { inst = emi(b, rNew, monthsToPay(b, rOld, inst)) }
            }
            let interest: Double
            if flat {
                let share: Double = b / (flatPrin != 0 ? flatPrin : 1)
                interest = b >= flatPrin - 0.005 ? flatInt : flatInt * share
            } else {
                interest = (b * rateAt(l, monthOf(date))) / 1200
            }
            let pay = flat ? min(b, flatPrin) + interest : min(inst, b + interest)
            if pay - interest <= 0 { months = MAX; break }
            interestLeft += interest
            b -= pay - interest
            months += 1
        }
        let done = bal <= 0.005
        // Worked out one by one, so the big initializer call stays cheap to type-check.
        let effectiveRate: Double = flat && hasN ? flatToReducing(baseRate, nn) : baseRate
        let progress: Double = P > 0 ? 1 - bal / P : 1
        let nextDue: String? = done ? nil : nthDue(first, count)
        let endsYm: String? = done || months >= MAX ? nil : monthOf(nthDue(first, count + months - 1))
        let feePct: Double = l.fee ?? 0
        let settlement: Double = bal * (1 + feePct / 100)
        return LoanState(
            balance: bal, principal: P, rate: baseRate, rateType: rateType,
            effectiveRate: effectiveRate,
            installment: instToday, termMonths: n,
            installmentsPaid: count, installmentsLeft: done ? 0 : months,
            progress: progress,
            paidSoFar: paidSoFar, interestPaid: interestPaid, interestLeft: interestLeft, totalLeft: bal + interestLeft,
            nextDue: nextDue,
            endsYm: endsYm,
            totalInterest: totalInterest, settlement: settlement,
            schedule: schedule, simple: simple)
    }

    /// Months to clear `bal` at a fixed annual rate and installment (MAX if never).
    static func monthsToPay(_ bal: Double, _ ratePct: Double, _ inst: Double) -> Int {
        var b = bal, m = 0
        while b > 0.005 && m < MAX {
            let i = (b * ratePct) / 1200
            if inst <= i { return MAX }
            b -= inst - i
            m += 1
        }
        return max(1, m)
    }

    /// What an extra payment today would save. Worked out by replaying the loan with
    /// that payment added, so the preview always matches what happens after paying.
    static func prepayEffect(_ l: Debt, _ payments: [LoanPayment], today: String, _ extra: Double) -> PrepayEffect {
        let now = loanState(l, payments, today: today)
        if extra <= 0 || now.balance <= 0 { return PrepayEffect(monthsSaved: 0, interestSaved: 0) }
        let then = loanState(l, payments + [LoanPayment(date: today, amt: min(extra, now.balance), part: "extra")], today: today)
        return PrepayEffect(monthsSaved: max(0, now.installmentsLeft - then.installmentsLeft),
                            interestSaved: max(0, now.interestLeft - then.interestLeft))
    }

    // MARK: Credit cards (accounts with type card)

    static let cardDefaults = (apr: 36.0, minPct: 5.0, minFloor: 100.0)

    /// Next date with this day of the month, from today on.
    static func nextDay(_ day: Int, _ today: String) -> String {
        let ym = monthOf(today), d = min(day, dim(ym))
        if (Int(slice(today, 8, 10)) ?? 0) <= d { return ym + "-" + DateKit.pad(d) }
        let nx = DateKit.addMonths(ym, 1)
        return nx + "-" + DateKit.pad(min(day, dim(nx)))
    }

    static func minPayment(_ owed: Double, _ c: Account) -> Double {
        if owed <= 0 { return 0 }
        let pct = c.minPct ?? cardDefaults.minPct, atLeast = c.minFloor ?? cardDefaults.minFloor
        return min(owed, max(atLeast, (owed * pct) / 100))
    }

    /// Months and interest to clear `owed`, paying `pay(balance)` each month.
    static func cardPayoff(_ owed: Double, _ apr: Double, _ pay: (Double) -> Double) -> CardPayoff {
        var b = owed, m = 0, interest = 0.0
        while b > 0.005 && m < MAX {
            let i = (b * apr) / 1200
            let p = min(b + i, pay(b))
            if p <= i { return CardPayoff(months: MAX, interest: interest, never: true) }
            interest += i; b = b + i - p; m += 1
        }
        return CardPayoff(months: m, interest: interest, never: false)
    }

    static func cardState(_ c: Account, _ balance: Double, today: String) -> CardState {
        let owed = max(0, -balance)
        let apr = c.apr ?? cardDefaults.apr
        let minDue = minPayment(owed, c)
        let limit = c.limit ?? 0
        let dueDay = c.dueDay ?? 0, statementDay = c.statementDay ?? 0
        return CardState(
            owed: owed, limit: c.limit,
            utilisation: limit != 0 ? owed / limit : nil,
            apr: apr, minDue: minDue,
            nextDue: dueDay != 0 ? nextDay(dueDay, today) : nil,
            nextStatement: statementDay != 0 ? nextDay(statementDay, today) : nil,
            interestIfMin: ((owed - minDue) * apr) / 1200,
            minOnly: cardPayoff(owed, apr) { minPayment($0, c) })
    }

    /// The latest date with this day of the month, on or before today ("yyyy-MM-dd").
    static func lastDay(_ day: Int, _ today: String) -> String {
        let ym = monthOf(today), d = min(day, dim(ym))
        if (Int(slice(today, 8, 10)) ?? 0) >= d { return ym + "-" + DateKit.pad(d) }
        let pv = DateKit.addMonths(ym, -1)
        return pv + "-" + DateKit.pad(min(day, dim(pv)))
    }

    // MARK: Card installment plans (Easy Payment Plan, Flexi installments, …)
    //
    // A purchase on a credit card turned into monthly installments. It is a debts/{id} document with
    // kind "cardplan" and `acct` = the card, so the loan maths above (schedule, flat / reducing rate,
    // paidBefore, early-closure fee) is reused as is. Defaults: rate 0, rateType "flat".
    //
    // Each month Twofold posts that month's installment as an expense on the card, in the plan's
    // category (`cat`), so the budget counts the installment, not the full price:
    //   entry id   "plan-{planId}-{n}"   (n = 1-based installment number; same id on every device)
    //   date       nthDue(firstDue, n - 1)
    //   amount     planInstallmentAmount(plan, n)
    //   debtId     the plan, debtPart "installment"
    // and sets billedThrough = n in the same write. A deleted installment is never posted again
    // (billedThrough already covers it). Other entries a plan can have:
    //   "plan-{planId}-fee"    the processing fee      (debtPart "fee": not a payment, see Ledger.payments)
    //   "plan-{planId}-close"  closed early: the quote (debtPart "extra", clears what's left)
    // Until an installment is posted, its principal is "still in plans": the bank has blocked it on
    // the card (it counts in what's owed and the limit used) but it isn't on the card's balance yet.

    /// JS `Math.round(n * 100) / 100`.
    private static func r2(_ n: Double) -> Double { (n * 100 + 0.5).rounded(.down) / 100 }

    static func isPlan(_ l: Debt) -> Bool { l.kind == "cardplan" }

    /// The id of a plan's entry for installment n.
    static func planEntryId(_ planId: String, _ n: Int) -> String { "plan-" + planId + "-" + String(n) }
    /// The id of a plan's processing fee ("fee") or early closure ("close") entry.
    static func planEntryId(_ planId: String, _ which: String) -> String { "plan-" + planId + "-" + which }

    /// What installment n (1-based) of a plan posts. The schedule's payments are rounded to cents so
    /// that together they add up to the rounded total, never a cent more or less:
    /// 1,000 over 3 months → 333.33, 333.34, 333.33.
    static func planInstallmentAmount(_ p: Debt, _ n: Int) -> Double {
        if isSimple(p) || n < 1 { return 0 }
        // As agreed; payments don't change it.
        let rows = loanState(p, [], today: p.firstDue ?? "").schedule
        var before = 0.0, upTo = 0.0
        let count = min(n, rows.count)
        var i = 0
        while i < count {
            if i < n - 1 { before += rows[i].payment }
            upTo += rows[i].payment
            i += 1
        }
        return r2(r2(upTo) - r2(before))
    }

    /// Everything about a plan today.
    /// - Parameter payments: `Ledger.payments(of:in:)` of its entries: installments and the
    ///   closing payment (not the fee)
    static func planState(_ p: Debt, _ payments: [LoanPayment], today: String) -> PlanState {
        planState(p, st: loanState(p, payments, today: today))
    }

    /// `planState` from the plan's loan state already worked out (the same payments and day).
    static func planState(_ p: Debt, st: LoanState) -> PlanState {
        let term = p.termMonths ?? 0
        let billed = max(0, min(term, max(p.billedThrough ?? 0, p.paidBefore ?? 0)))
        let closed = !st.simple && billed < term && st.balance <= 0.005
        let done = st.simple || closed || billed >= term
        let remaining: Double = done ? 0 : st.balance
        let first = p.firstDue ?? ""
        let next: PlanInstallment? = done ? nil
            : PlanInstallment(n: billed + 1, date: nthDue(first, billed), amt: planInstallmentAmount(p, billed + 1))
        let endsYm: String? = st.simple || term == 0 ? nil : monthOf(nthDue(first, term - 1))
        let feePct: Double = p.fee ?? 0
        let settlement: Double = remaining * (1 + feePct / 100)
        return PlanState(st: st, term: term, billed: billed, closed: closed, done: done, remaining: remaining,
                         next: next, endsYm: endsYm, settlement: settlement)
    }

    /// The installments to post now: from billedThrough + 1 on, each one due on or before today.
    /// Posting them (with their fixed ids) and setting billedThrough to the last n is idempotent, so
    /// two devices doing it at once write the same documents.
    static func planChargesDue(_ p: Debt, _ payments: [LoanPayment], today: String) -> [PlanInstallment] {
        let ps = planState(p, payments, today: today)
        var out: [PlanInstallment] = []
        if ps.done { return out }
        let first = p.firstDue ?? ""
        var n = ps.billed + 1
        while n <= ps.term {
            let date = nthDue(first, n - 1)
            if date > today { break }
            out.append(PlanInstallment(n: n, date: date, amt: planInstallmentAmount(p, n)))
            n += 1
        }
        return out
    }

    /// The processing fee's date: the day before the first installment, or today if that's later on.
    static func planFeeDate(_ p: Debt, _ today: String) -> String {
        guard let f = p.firstDue, !f.isEmpty else { return today }
        let d = Int(slice(f, 8, 10)) ?? 1
        let iso: String
        if d > 1 {
            iso = monthOf(f) + "-" + DateKit.pad(d - 1)
        } else {
            let pv = DateKit.addMonths(monthOf(f), -1)
            iso = pv + "-" + DateKit.pad(dim(pv))
        }
        return iso < today ? iso : today
    }

    /// A credit card with its installment plans. With no plans it's exactly `cardState`.
    ///   owed        = −balance + planRemaining       (the bank blocks the whole remaining plan amount)
    ///   utilisation = owed / limit
    ///   minDue      = minPayment(revolving) + billedThisCycle, where billedThisCycle = installments and
    ///                 fees dated after the last statement (or in this calendar month when there's no
    ///                 statement day) and on or before today, and revolving = owedOnCard − that.
    ///   interestIfMin and minOnly use the revolving part only.
    /// - Parameters:
    ///   - balance: the card account's balance from entries (negative = owed)
    ///   - planRemaining: Σ planState(plan).remaining over the card's plans
    ///   - charges: the card's plan installment and fee entries
    static func cardWithPlans(_ c: Account, _ balance: Double, planRemaining: Double,
                              charges: [(date: String, amt: Double)], today: String) -> CardPlanState {
        let base = cardState(c, balance, today: today)
        let owedOnCard = max(0, -balance)
        let statementDay = c.statementDay ?? 0
        let after: String = statementDay != 0 ? lastDay(statementDay, today) : monthOf(today) + "-00"
        var billed = 0.0
        for x in charges where x.date > after && x.date <= today { billed += x.amt }
        let billedThisCycle = min(owedOnCard, billed)
        let revolving = owedOnCard - billedThisCycle
        let minRev = minPayment(revolving, c)
        let owed = max(0, -balance + planRemaining)
        let limit = c.limit ?? 0
        let utilisation: Double? = limit != 0 ? owed / limit : nil
        let interestIfMin: Double = ((revolving - minRev) * base.apr) / 1200
        let minOnly = cardPayoff(revolving, base.apr) { minPayment($0, c) }
        return CardPlanState(
            owed: owed, limit: base.limit, utilisation: utilisation, apr: base.apr,
            minDue: minRev + billedThisCycle,
            nextDue: base.nextDue, nextStatement: base.nextStatement,
            interestIfMin: interestIfMin, minOnly: minOnly,
            owedOnCard: owedOnCard, planRemaining: planRemaining,
            billedThisCycle: billedThisCycle, revolving: revolving)
    }
}
