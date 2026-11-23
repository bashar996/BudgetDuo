import Foundation

struct BudgetRow: Identifiable {
    let id: String
    let group: CatGroup
    let name: String
    /// Day-to-day spending (watched by coach tips).
    let variable: Bool
    /// Monthly limit as set.
    let limit: Double
    /// Rolled over from last month (rollover on): last month's limit minus what was spent.
    let carry: Double
    let spent: Double
    /// What can be spent this month: the limit plus anything rolled over (never below 0).
    var avail: Double { max(0, limit + carry) }
    var left: Double { avail - spent }
    var ratio: Double { avail > 0 ? spent / avail : (spent > 0 ? 1.01 : 0) }
}

/// Shared costs this month and who owes whom (the Mac's `settleUp` in tabs/us.tsx).
struct SettleUp {
    /// "Split shared costs" is on.
    let split: Bool
    /// Shared spending this month (pocket money left out) by who paid.
    let paid: [Who: Double]
    let incomeA: Double
    let incomeB: Double
    /// > 0: B owes A; < 0: A owes B (what's already settled is taken off).
    let owe: Double
    /// All square (less than 1 either way).
    let square: Bool
    /// "50 / 50" or "62 / 38"
    let rule: String
    let line: String
    let sub: String
}

/// One band of the 50/30/20 check on Budget.
struct StyleBand: Identifiable {
    let name: String
    let amount: Double
    /// 0.5, 0.3 or 0.2
    let guide: Double
    var id: String { name }
}

/// A bill in the current budget month.
struct BillRow: Identifiable {
    let bill: Bill
    /// When it's due in the budget month, "yyyy-MM-dd".
    let due: String
    let isPaid: Bool
    var id: String { bill.id }
    /// Day of the month it's due (the calendar day of `due`).
    var dueDay: Int { Int(due.suffix(2)) ?? bill.day }
    /// The calendar month of `due` ("yyyy-MM"): its key in `bill.paid` and in the payment's entry id.
    var paidKey: String { String(due.prefix(7)) }
    /// "Nov"
    var monthShort: String { DateKit.monthName(paidKey, short: true) }
}

struct DebtLine: Identifiable {
    let id: String
    let name: String
    let balance: Double
    let apr: Double
    let min: Double
}

struct DebtPlan {
    /// Months until everything is paid off (720 = gave up).
    let months: Int
    let interest: Double
    /// debt id → month it's cleared
    let done: [String: Int]
    /// ids in payoff order
    let order: [String]
}

struct ForecastEvent: Identifiable {
    let id = UUID()
    let offset: Int
    let date: Date
    let name: String
    let amt: Double
}

struct DayBar: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

/// Everything the screens show, worked out from the synced documents.
/// Pure and Firebase-free so the numbers are easy to reason about.
struct Ledger {
    let household: Household
    let tx: [Tx]
    let accounts: [Account]
    let bills: [Bill]
    let goals: [Goal]
    let debts: [Debt]
    let planned: [Planned]
    let trips: [Trip]
    /// Homes, cars, gold … valued by hand (edited in the Mac app).
    let assets: [Asset]
    let today: Date

    /// The current budget month's key ("yyyy-MM"; see `Period`). With the default
    /// start day (the 1st) it's simply this calendar month.
    let ym: String
    /// Day of the month the budget month starts (`Household.cycleStart`, 1 = calendar months).
    let cycleStart: Int
    /// The current budget month: its key, first and last day.
    let period: Period
    /// This calendar month ("yyyy-MM"), for things counted in calendar months (loans, payoff dates).
    let calendarYm: String
    /// Today's day of the calendar month.
    let todayDay: Int
    /// Days in the budget month.
    let periodDays: Int
    /// Today's day number in the budget month (1 = its first day).
    let dayIndex: Int
    let money: Money
    let balances: [String: Double]
    let potSaved: [String: Double]
    let monthTx: [Tx]
    let monthExpenses: [Tx]
    /// Last month's expenses (rollover and coach tips).
    let prevExpenses: [Tx]
    let spentByCat: [String: Double]
    let rows: [BudgetRow]
    /// "yyyy-MM-dd" of `today`.
    let todayIso: String
    /// Loan id → its state today (from the loan and its payment entries).
    let loanStates: [String: LoanState]

    init(household: Household, tx: [Tx], accounts: [Account], bills: [Bill], goals: [Goal],
         debts: [Debt] = [], planned: [Planned] = [], trips: [Trip] = [], assets: [Asset] = [], today: Date = Date(),
         loanStates: [String: LoanState]? = nil) {
        self.household = household
        self.tx = tx
        self.accounts = accounts
        self.bills = bills
        self.goals = goals
        self.debts = debts
        self.planned = planned
        self.trips = trips
        self.assets = assets
        self.today = today
        let iso = DateKit.iso(today)
        todayIso = iso
        let start = Period.start(of: household)
        let cur = Period(containing: iso, start: start)
        cycleStart = start
        period = cur
        ym = cur.key
        calendarYm = DateKit.ym(today)
        todayDay = DateKit.day(today)
        periodDays = cur.days
        dayIndex = cur.dayIndex(iso)
        money = Money(currency: household.currency)

        var bal: [String: Double] = [:]
        accounts.forEach { bal[$0.id] = $0.opening }
        var saved: [String: Double] = [:]
        goals.forEach { saved[$0.id] = $0.startSaved }
        for t in tx {
            switch t.type {
            case .expense: bal[t.acct, default: 0] -= t.amt
            case .income: bal[t.acct, default: 0] += t.amt
            case .transfer:
                bal[t.acct, default: 0] -= t.amt
                if let to = t.to { bal[to, default: 0] += t.amt }
                if let pot = t.pot { saved[pot, default: 0] += (t.potDir == .out ? -t.amt : t.amt) }
            }
        }
        balances = bal
        potSaved = saved.mapValues { max(0, $0) }

        monthTx = tx.filter { cur.contains($0.date) }
        monthExpenses = monthTx.filter { $0.type == .expense }
        var sp: [String: Double] = [:]
        monthExpenses.forEach { sp[$0.cat, default: 0] += $0.amt }
        spentByCat = sp
        let prev = cur.previous
        let pExp = tx.filter { $0.type == .expense && prev.contains($0.date) }
        prevExpenses = pExp
        var psp: [String: Double] = [:]
        pExp.forEach { psp[$0.cat, default: 0] += $0.amt }
        // Rollover (Settings, shared with the Mac): last budget month's unspent limit (or
        // overspend) carries into this one, once there was spending last budget month.
        let roll = (household.rollover ?? false) && !pExp.isEmpty

        self.loanStates = loanStates ?? Ledger.computeLoanStates(debts, tx, today: iso)

        let names = (a: household.nameA, b: household.nameB)
        rows = Catalog.effective(household).map { c in
            let name = c.id == "allowA" ? names.a + "’s pocket money" : c.id == "allowB" ? names.b + "’s pocket money" : c.name
            let limit = household.budgets[c.id] ?? 0
            return BudgetRow(id: c.id, group: c.group, name: name, variable: c.variable, limit: limit,
                             carry: roll ? limit - (psp[c.id] ?? 0) : 0, spent: sp[c.id] ?? 0)
        }
    }

    // MARK: Names

    func name(_ w: Who) -> String {
        switch w {
        case .a: return household.nameA
        case .b: return household.nameB
        case .joint: return "Joint"
        }
    }

    func categoryName(_ id: String) -> String {
        if id == "income" { return "Income" }
        if id == "transfer" { return "Transfer" }
        return rows.first { $0.id == id }?.name ?? "Other"
    }

    func accountName(_ id: String?) -> String {
        accounts.first { $0.id == id }?.name ?? "Account"
    }

    /// The budget month's name ("December").
    var monthName: String { DateKit.monthName(ym) }
    var monthShort: String { DateKit.monthName(ym, short: true) }
    /// "December", plus " · 25 Nov – 24 Dec" when the budget month doesn't start on the 1st.
    var periodName: String { period.name }
    /// "December 2026", plus " · 25 Nov – 24 Dec" when the budget month doesn't start on the 1st.
    var periodLabel: String { period.label() }
    /// First and last day of the budget month ("yyyy-MM-dd").
    var periodFrom: String { period.from }
    var periodTo: String { period.to }
    /// Days left in the budget month, today included.
    var daysLeft: Int { max(1, periodDays - dayIndex + 1) }

    /// `preferred` if the household still has that category, otherwise the first
    /// one it has (used for defaults such as Groceries on a new entry).
    func catOr(_ preferred: String) -> String {
        if rows.contains(where: { $0.id == preferred }) { return preferred }
        return (rows.first(where: { $0.group != .personal }) ?? rows.first)?.id ?? preferred
    }

    /// How many entries and bills use a category (all months).
    func usage(of cat: String) -> (entries: Int, bills: Int) {
        (tx.filter { $0.cat == cat }.count, bills.filter { $0.cat == cat }.count)
    }

    /// The everyday account new entries default to.
    var mainAccountId: String? { (accounts.first { $0.type == .current } ?? accounts.first)?.id }

    // MARK: Budget

    var totalLimit: Double { rows.reduce(0) { $0 + $1.limit } }
    /// Limits plus anything rolled over: what can be spent this month.
    var totalAvail: Double { rows.reduce(0) { $0 + $1.avail } }
    var totalSpent: Double { rows.reduce(0) { $0 + $1.spent } }
    var income: Double { household.incomes.reduce(0) { $0 + $1.amt } }
    var goalsMonthly: Double { goals.reduce(0) { $0 + $1.monthly } }
    var leftToAssign: Double { income - totalLimit - goalsMonthly }

    func average(of cat: String, months: Int = 3) -> Double {
        var total = 0.0
        for k in 1...months {
            let p = period.shifted(-k)
            total += tx.filter { $0.cat == cat && $0.type == .expense && p.contains($0.date) }.reduce(0) { $0 + $1.amt }
        }
        return (total / Double(months) / 10).rounded() * 10
    }

    // MARK: Bills

    /// A paid-off loan's bill stops coming due (months it was paid still show).
    func billEnded(_ b: Bill) -> Bool {
        guard let id = b.debtId, let d = debts.first(where: { $0.id == id }) else { return false }
        return loanState(d).balance <= 0.005
    }

    /// Each bill once in the budget month: due on its day inside the period, paid
    /// according to the calendar month of that date (`paid["yyyy-MM"]`).
    var billRows: [BillRow] {
        let p = period
        let all: [BillRow] = bills.map { (b: Bill) -> BillRow in
            let due: String = p.billDue(day: b.day)
            return BillRow(bill: b, due: due, isPaid: b.paid[String(due.prefix(7))] ?? false)
        }
        return all.filter { $0.isPaid || !billEnded($0.bill) }
            .sorted { $0.due == $1.due ? $0.bill.name < $1.bill.name : $0.due < $1.due }
    }
    var unpaidBills: [BillRow] { billRows.filter { !$0.isPaid } }
    var unpaidTotal: Double { unpaidBills.reduce(0) { $0 + $1.bill.amt } }
    var paidTotal: Double { billRows.filter(\.isPaid).reduce(0) { $0 + $1.bill.amt } }

    func billStatus(_ b: BillRow) -> String {
        if b.isPaid { return "Paid" }
        return dueStatus(b.due)
    }

    /// What's left in the category budgets once the unpaid bills are set aside.
    var safeToSpend: Double { totalAvail - totalSpent - unpaidTotal }

    // MARK: Accounts & pots

    func balance(_ a: Account) -> Double { balances[a.id] ?? a.opening }
    /// Sum of every account balance (cards count negative).
    var accountsTotal: Double { accounts.map(balance).reduce(0, +) }
    var assetsTotal: Double { assets.reduce(0) { $0 + $1.value } }
    /// Accounts in the black plus assets.
    var own: Double { accounts.map(balance).filter { $0 > 0 }.reduce(0, +) + assetsTotal }
    /// Loans (outstanding today), what card installment plans still have to bill, plus accounts
    /// in the red (cards).
    var liabilities: Double {
        accounts.map(balance).filter { $0 < 0 }.reduce(0) { $0 - $1 } + loansOwed + plansOwed
    }
    var netWorth: Double { own - liabilities }

    private func positive(_ types: [AccountType]) -> Double {
        accounts.filter { types.contains($0.type) }.map(balance).filter { $0 > 0 }.reduce(0, +)
    }

    /// What you own in four groups, in display order: Cash, Savings, Investments, Property & other assets.
    var ownGroups: [(label: String, value: Double)] {
        [("Cash", positive([.current, .cash, .card])), ("Savings", positive([.save])),
         ("Investments", positive([.invest])), ("Property & other assets", assetsTotal)]
    }

    var investments: [Account] { accounts.filter { $0.type == .invest } }

    /// Balance minus what was put in; nil when no amount put in is recorded.
    func gain(_ a: Account) -> Double? {
        guard a.type == .invest, let c = a.cost, c > 0 else { return nil }
        return balance(a) - c
    }

    func saved(_ g: Goal) -> Double { potSaved[g.id] ?? g.startSaved }
    var inPots: Double { goals.map(saved).reduce(0, +) }
    var movedIntoPotsThisMonth: Double {
        monthTx.filter { $0.type == .transfer && $0.pot != nil }.reduce(0) { $0 + ($1.potDir == .out ? -$1.amt : $1.amt) }
    }

    /// Everyday spending: expenses that aren't a bill or a loan payment.
    static func isEveryday(_ t: Tx) -> Bool { t.type == .expense && t.billId == nil && t.debtId == nil }

    /// Spare change from rounding each everyday purchase up to the next 10.
    var roundUps: Double {
        let raw = monthExpenses.filter(Ledger.isEveryday).reduce(0) { $0 + (($1.amt / 10).rounded(.up) * 10 - $1.amt) }
        return max(0, (raw - (household.roundSwept[ym] ?? 0)).rounded())
    }
    var roundUpPot: Goal? { goals.first { $0.id == household.roundUpPot } ?? goals.first }

    // MARK: Insights

    var lastSevenDays: [DayBar] {
        (0..<7).map { i in
            let k = 6 - i
            let d = DateKit.cal.date(byAdding: .day, value: -k, to: today) ?? today
            let iso = DateKit.iso(d)
            let v = tx.filter { Ledger.isEveryday($0) && $0.date == iso }.reduce(0) { $0 + $1.amt }
            let wd = DateKit.cal.component(.weekday, from: d) - 1
            return DayBar(id: i, label: DateKit.weekdays[wd], value: v)
        }
    }

    func spent(by w: Who) -> Double { monthExpenses.filter { $0.who == w }.reduce(0) { $0 + $1.amt } }

    // MARK: Custom categories

    func isCustom(_ id: String) -> Bool { household.custom?.contains { $0.id == id } ?? false }

    // MARK: Loans & cards

    /// A loan's payments for `Loans.loanState`: entries with its debtId (a card plan's
    /// processing fee, debtPart "fee", isn't a payment).
    static func payments(of debtId: String, in tx: [Tx]) -> [LoanPayment] {
        tx.filter { $0.debtId == debtId && $0.debtPart != "fee" }
            .map { LoanPayment(date: $0.date, amt: $0.amt, part: $0.debtPart == "extra" ? "extra" : "installment") }
    }

    /// Every loan's state today (loan id → state).
    static func computeLoanStates(_ debts: [Debt], _ tx: [Tx], today: String) -> [String: LoanState] {
        var states: [String: LoanState] = [:]
        for d in debts { states[d.id] = Loans.loanState(d, payments(of: d.id, in: tx), today: today) }
        return states
    }

    func loanState(_ d: Debt) -> LoanState {
        loanStates[d.id] ?? Loans.loanState(d, Ledger.payments(of: d.id, in: tx), today: todayIso)
    }

    /// Entries that paid this loan (a card plan: every entry it posted), newest first.
    func loanPayments(_ d: Debt) -> [Tx] { tx.filter { $0.debtId == d.id } }

    /// Loans, without card installment plans (those show under their card).
    var loans: [Debt] { debts.filter { !Loans.isPlan($0) } }
    /// Loans with something still owed.
    var activeLoans: [Debt] { loans.filter { loanState($0).balance > 0.005 } }
    var loansOwed: Double { loans.reduce(0) { $0 + loanState($1).balance } }

    /// The bill that shows this loan's installment, if any.
    func loanBill(_ d: Debt) -> Bill? {
        bills.first { $0.debtId == d.id && (d.billId == nil || $0.id == d.billId) }
    }

    // Card installment plans (Loans.swift, "Card installment plans").

    /// Every card installment plan.
    var plans: [Debt] { debts.filter(Loans.isPlan) }
    /// A plan's installments billed, what's left and what's next, today.
    func planState(_ p: Debt) -> PlanState { Loans.planState(p, st: loanState(p)) }
    /// The installment plans on a card.
    func plansOnCard(_ card: String) -> [Debt] { plans.filter { $0.acct == card } }
    /// What every plan still has to bill (part of what's owed on the cards).
    var plansOwed: Double { plans.reduce(0) { $0 + planState($1).remaining } }

    var cards: [Account] { accounts.filter { $0.type == .card } }

    /// A card's numbers with its installment plans (`Loans.cardWithPlans`).
    func cardState(_ a: Account) -> CardPlanState {
        let mine = plansOnCard(a.id)
        let ids = Set(mine.map(\.id))
        let remaining: Double = mine.reduce(0) { $0 + planState($1).remaining }
        let charges: [(date: String, amt: Double)] = tx.compactMap { (t: Tx) -> (date: String, amt: Double)? in
            guard let id = t.debtId, ids.contains(id), t.acct == a.id, t.debtPart != "extra" else { return nil }
            return (date: t.date, amt: t.amt)
        }
        return Loans.cardWithPlans(a, balance(a), planRemaining: remaining, charges: charges, today: todayIso)
    }

    /// Installments (loans and card plans) plus card minimums due each month: what the payoff
    /// plan pays before any extra (as the Mac's "Monthly payments").
    var debtMonthly: Double { allDebts.reduce(0) { $0 + $1.min } }

    /// Whole days from today to a "yyyy-MM-dd" (negative when it's past).
    func daysUntil(_ iso: String) -> Int {
        DateKit.cal.dateComponents([.day], from: DateKit.date(todayIso), to: DateKit.date(iso)).day ?? 0
    }

    /// "Due today", "Overdue" or "Due in 3 days".
    func dueStatus(_ iso: String) -> String {
        let n = daysUntil(iso)
        if n < 0 { return "Overdue" }
        if n == 0 { return "Due today" }
        return "Due in \(n) day" + (n == 1 ? "" : "s")
    }

    // MARK: Debt plan

    /// Loans still owing (outstanding today, effective rate, current installment), each card
    /// installment plan on its own (what's left to bill, at its installment), plus cards in the
    /// red: only what's on the card, at the minimum on that (the plans are their own lines).
    var allDebts: [DebtLine] {
        let owingLoans: [DebtLine] = loans.compactMap { (d: Debt) -> DebtLine? in
            let st = loanState(d)
            guard st.balance > 0.005 else { return nil }
            return DebtLine(id: d.id, name: d.name, balance: st.balance, apr: st.effectiveRate, min: st.installment)
        }
        let owingPlans: [DebtLine] = plans.compactMap { (p: Debt) -> DebtLine? in
            let ps = planState(p)
            guard ps.remaining > 0.005 else { return nil }
            return DebtLine(id: p.id, name: p.name, balance: ps.remaining, apr: ps.st.effectiveRate, min: ps.st.installment)
        }
        let owingCards: [DebtLine] = cards.compactMap { (a: Account) -> DebtLine? in
            let cs = cardState(a)
            guard cs.owedOnCard > 0 else { return nil }
            return DebtLine(id: a.id, name: a.name, balance: cs.owedOnCard, apr: cs.apr, min: Loans.minPayment(cs.owedOnCard, a))
        }
        return owingLoans + owingPlans + owingCards
    }

    var strategy: String { household.strat ?? "avalanche" }
    var extraPayment: Double { household.extra ?? 0 }

    /// Month-by-month payoff: interest = balance × APR / 12, pay the minimums,
    /// then the extra plus freed-up minimums go to the first debt in order.
    func debtPlan() -> DebtPlan {
        var ds = allDebts.map { (id: $0.id, b: $0.balance, apr: $0.apr, min: $0.min) }
        let order = ds.sorted { strategy == "snowball" ? $0.b < $1.b : $0.apr > $1.apr }.map { $0.id }
        var months = 0, interest = 0.0
        var done: [String: Int] = [:]
        while ds.contains(where: { $0.b > 0.01 }) && months < 720 {
            months += 1
            var pool = extraPayment
            for i in ds.indices {
                if ds[i].b > 0.01 {
                    let int = ds[i].b * ds[i].apr / 1200
                    interest += int
                    ds[i].b += int
                    let p = min(ds[i].b, ds[i].min)
                    ds[i].b -= p
                    pool += ds[i].min - p
                } else {
                    pool += ds[i].min
                }
            }
            for id in order {
                guard pool > 0 else { break }
                if let i = ds.firstIndex(where: { $0.id == id }), ds[i].b > 0.01 {
                    let p = min(ds[i].b, pool)
                    ds[i].b -= p
                    pool -= p
                }
            }
            for d in ds where d.b <= 0.01 && done[d.id] == nil { done[d.id] = months }
        }
        return DebtPlan(months: months, interest: interest, done: done, order: order)
    }

    var debtFreeLabel: String {
        if allDebts.isEmpty { return "Debt-free" }
        let plan = debtPlan()
        return plan.months >= 720 ? "Not at this rate" : DateKit.monthLabel(DateKit.addMonths(calendarYm, plan.months), short: true)
    }

    // MARK: Plan ahead

    /// The cash cushion from Settings (shared with the Mac).
    var cushion: Double { household.cushion ?? 5000 }

    struct Forecast {
        let series: [Double]
        let events: [ForecastEvent]
        let cash: Double
    }

    /// Cash in current and cash accounts over the next 30 days: scheduled bills
    /// and pay, minus the average daily everyday spending of the last 60 days.
    func forecast() -> Forecast {
        let cal = DateKit.cal
        let cash = accounts.filter { $0.type == .current || $0.type == .cash }.map(balance).reduce(0, +)
        let since = DateKit.iso(cal.date(byAdding: .day, value: -60, to: today) ?? today)
        let daily = tx.filter { Ledger.isEveryday($0) && $0.date >= since }.reduce(0) { $0 + $1.amt } / 60
        var events: [ForecastEvent] = []
        for k in 0...30 {
            let dt = cal.date(byAdding: .day, value: k, to: today) ?? today
            let m = DateKit.ym(dt), dd = DateKit.day(dt), dm = DateKit.daysIn(m)
            for b in bills where !billEnded(b) {
                let bd = min(b.day, dm)
                if !(b.paid[m] ?? false) && (bd == dd || (k == 0 && bd < dd)) {
                    events.append(ForecastEvent(offset: k, date: dt, name: b.name, amt: -b.amt))
                }
            }
            if k > 0 {
                for inc in household.incomes where inc.amt > 0 && min(inc.day, dm) == dd {
                    events.append(ForecastEvent(offset: k, date: dt, name: name(inc.who) + "’s salary", amt: inc.amt))
                }
            }
        }
        var bal = cash
        var series: [Double] = []
        for k in 0...30 {
            for e in events where e.offset == k { bal += e.amt }
            if k > 0 { bal -= daily }
            series.append(bal)
        }
        return Forecast(series: series, events: events, cash: cash)
    }

    /// "Fits in this month’s safe-to-spend", or how long to save for it.
    func verdict(_ p: Planned) -> String {
        if safeToSpend >= p.cost { return "Fits in this month’s safe-to-spend" }
        let surplus = max(0, leftToAssign)
        guard surplus > 0 else { return "Needs room in the budget first" }
        let n = Int((p.cost / surplus).rounded(.up))
        return "Set aside \(money.f((p.cost / Double(n)).rounded(.up))) a month, yours by \(DateKit.monthLabel(DateKit.addMonths(calendarYm, n), short: true))"
    }

    // MARK: Report

    var reportFileName: String { "twofold-report-\(ym).csv" }

    /// This budget month's report as CSV: totals, categories with share, who spent.
    var reportCSV: String {
        let cur = money.currency
        let cats = rows.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }
        var lines: [[String]] = [
            ["Twofold report", periodLabel],
            ["Household", household.nameA + " & " + household.nameB],
            [],
            ["Spent (\(cur))", String(Int(totalSpent.rounded()))],
            ["Income (\(cur))", String(Int(income.rounded()))],
            [],
            ["Category", "Spent (\(cur))", "Share"],
        ]
        lines += cats.map { [$0.name, String(Int($0.spent.rounded())), "\(Int(($0.spent / max(totalSpent, 1) * 100).rounded()))%"] }
        lines += [[], ["Who", "Spent (\(cur))"]]
        lines += [Who.a, .b, .joint].map { [name($0), String(Int(spent(by: $0).rounded()))] }
        return lines.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\n")
    }

    // MARK: Settings (shared with the Mac)

    /// "Zero-based", "Category limits" or "50/30/20".
    var budgetStyle: String { household.budgetStyle ?? "Zero-based" }
    var isZeroBased: Bool { budgetStyle == "Zero-based" }

    /// The line under "Left to assign" (the Mac's `note` in tabs/budget.tsx); empty for
    /// the other styles once nothing is over-assigned.
    var assignNote: String {
        if income == 0 { return "Set your monthly pay under Us two, then give every bit of it a job here." }
        if leftToAssign < 0 { return "You’ve planned \(money.f(-leftToAssign)) more than comes in. Trimming one or two categories will bring it back." }
        if isZeroBased {
            return leftToAssign == 0 ? "Every bit of income has a job. That’s the whole method."
                : "Give the remaining \(money.f(leftToAssign)) a job — a category or a goal — so nothing drifts."
        }
        return ""
    }

    /// 50/30/20 check: what's planned for needs, wants (with pocket money) and savings.
    var styleBands: [StyleBand] {
        func limits(_ gs: [CatGroup]) -> Double { rows.filter { gs.contains($0.group) }.reduce(0) { $0 + $1.limit } }
        return [StyleBand(name: "Needs", amount: limits([.needs]), guide: 0.5),
                StyleBand(name: "Wants", amount: limits([.wants, .personal]), guide: 0.3),
                StyleBand(name: "Savings", amount: goalsMonthly, guide: 0.2)]
    }

    /// Up to four day-to-day categories with a limit, busiest first (Mac `tips().watch`).
    var watchRows: [BudgetRow] {
        Array(rows.filter { $0.variable && $0.avail > 0 }.sorted { $0.ratio > $1.ratio }.prefix(4))
    }

    /// Up to three coach tips for Home (a port of `tips()` in desktop/src/tabs/home.tsx).
    var coachTips: [String] {
        var out: [String] = []
        if let over = rows.filter({ $0.left < 0 }).min(by: { $0.left < $1.left }) {
            out.append("\(over.name) went \(money.f(-over.left)) past its limit. No stress — move a little from a category with room and you’re square.")
        }
        if let tight = watchRows.first(where: { $0.left >= 0 && $0.ratio > 0.75 }) {
            out.append("\(tight.name) has \(money.f(tight.left)) left for the next \(daysLeft) days — about \(money.f((tight.left / Double(daysLeft)).rounded())) a day keeps it on track.")
        }
        if !prevExpenses.isEmpty {
            // The same number of days into last budget month.
            let prev = period.previous
            let idx = dayIndex
            let lastMonthSoFar = prevExpenses.filter { prev.dayIndex($0.date) <= idx }.reduce(0) { $0 + $1.amt }
            let diff = lastMonthSoFar - totalSpent
            out.append(diff >= 0 ? "You’ve spent \(money.f(diff)) less than at this point last month. Nicely done, you two."
                                 : "Spending is \(money.f(-diff)) ahead of this point last month — worth a quick look together.")
        }
        if leftToAssign > 0 {
            out.append("\(money.f(leftToAssign)) of income isn’t assigned yet. Sending it to a goal now means it won’t quietly disappear.")
        }
        return Array(out.prefix(3))
    }

    /// Who owes whom this month when you split shared costs.
    var settleUp: SettleUp {
        let split = (household.splitMode ?? "One joint pot") != "One joint pot"
        var pd: [Who: Double] = [.a: 0, .b: 0, .joint: 0]
        monthExpenses.filter { !Catalog.isPocketMoney($0.cat) }.forEach { pd[$0.who, default: 0] += $0.amt }
        let incA = household.incomes.filter { $0.who == .a }.reduce(0) { $0 + $1.amt }
        let incB = income - incA
        let rA = (household.splitRule ?? "50/50") == "By income" ? incA / (income != 0 ? income : 1) : 0.5
        let pA = pd[.a] ?? 0, pB = pd[.b] ?? 0
        let owe = pA - rA * (pA + pB) - (household.settled?[ym] ?? 0)
        let sq = abs(owe) < 1
        let A = household.nameA, B = household.nameB
        let who = owe > 0 ? "\(B) owes \(A)" : "\(A) owes \(B)"
        let line = sq ? "You’re all square" : who + " " + money.f(abs(owe).rounded())
        let sub = sq ? "Nothing to move between you this month."
            : "\(A) covered \(money.f(pA)) and \(B) covered \(money.f(pB)) of shared costs from personal cards."
        return SettleUp(split: split, paid: pd, incomeA: incA, incomeB: incB, owe: owe, square: sq,
                        rule: "\(Int((rA * 100).rounded())) / \(Int(((1 - rA) * 100).rounded()))", line: line, sub: sub)
    }

    // MARK: Activity export

    /// Entries as CSV, the same columns as the Mac's Activity export.
    func activityCSV(_ list: [Tx]) -> String {
        var lines: [[String]] = [["Date", "Name", "Category", "Who", "Type", "Amount", "Note"]]
        lines += list.map { [$0.date, $0.name, $0.cat, $0.who.rawValue, $0.type.rawValue, fmt($0.amt), $0.note ?? ""] }
        return lines.map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            .joined(separator: "\n")
    }

    // MARK: Start here (empty start)

    var setupSteps: [(title: String, done: Bool)] {
        [("Add your accounts", !accounts.isEmpty),
         ("Set your pay", household.incomes.contains { $0.amt > 0 }),
         ("Give categories a limit", household.budgets.values.contains { $0 > 0 }),
         ("Log a first entry", !tx.isEmpty)]
    }
    var setupDone: Bool { setupSteps.allSatisfy(\.done) }
}
