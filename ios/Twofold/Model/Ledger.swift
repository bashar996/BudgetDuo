import Foundation

struct BudgetRow: Identifiable {
    let id: String
    let group: CatGroup
    let name: String
    let limit: Double
    let spent: Double
    var left: Double { limit - spent }
    var ratio: Double { limit > 0 ? spent / limit : (spent > 0 ? 1.01 : 0) }
}

struct BillRow: Identifiable {
    let bill: Bill
    let dueDay: Int
    let isPaid: Bool
    var id: String { bill.id }
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

    let ym: String
    let todayDay: Int
    let daysInMonth: Int
    let money: Money
    let balances: [String: Double]
    let potSaved: [String: Double]
    let monthTx: [Tx]
    let monthExpenses: [Tx]
    let spentByCat: [String: Double]
    let rows: [BudgetRow]

    init(household: Household, tx: [Tx], accounts: [Account], bills: [Bill], goals: [Goal],
         debts: [Debt] = [], planned: [Planned] = [], trips: [Trip] = [], assets: [Asset] = [], today: Date = Date()) {
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
        ym = DateKit.ym(today)
        todayDay = DateKit.day(today)
        daysInMonth = DateKit.daysIn(ym)
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

        let ymNow = ym
        monthTx = tx.filter { $0.month == ymNow }
        monthExpenses = monthTx.filter { $0.type == .expense }
        var sp: [String: Double] = [:]
        monthExpenses.forEach { sp[$0.cat, default: 0] += $0.amt }
        spentByCat = sp

        let names = (a: household.nameA, b: household.nameB)
        rows = Catalog.effective(household).map { c in
            let name = c.id == "allowA" ? names.a + "’s pocket money" : c.id == "allowB" ? names.b + "’s pocket money" : c.name
            return BudgetRow(id: c.id, group: c.group, name: name, limit: household.budgets[c.id] ?? 0, spent: sp[c.id] ?? 0)
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

    var monthName: String { DateKit.monthName(ym) }
    var monthShort: String { DateKit.monthName(ym, short: true) }
    var daysLeft: Int { daysInMonth - todayDay + 1 }

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
    var totalSpent: Double { rows.reduce(0) { $0 + $1.spent } }
    var income: Double { household.incomes.reduce(0) { $0 + $1.amt } }
    var goalsMonthly: Double { goals.reduce(0) { $0 + $1.monthly } }
    var leftToAssign: Double { income - totalLimit - goalsMonthly }

    func average(of cat: String, months: Int = 3) -> Double {
        var total = 0.0
        for k in 1...months {
            let m = DateKit.addMonths(ym, -k)
            total += tx.filter { $0.cat == cat && $0.type == .expense && $0.month == m }.reduce(0) { $0 + $1.amt }
        }
        return (total / Double(months) / 10).rounded() * 10
    }

    // MARK: Bills

    var billRows: [BillRow] {
        bills.map { BillRow(bill: $0, dueDay: min($0.day, daysInMonth), isPaid: $0.paid[ym] ?? false) }
            .sorted { $0.dueDay == $1.dueDay ? $0.bill.name < $1.bill.name : $0.dueDay < $1.dueDay }
    }
    var unpaidBills: [BillRow] { billRows.filter { !$0.isPaid } }
    var unpaidTotal: Double { unpaidBills.reduce(0) { $0 + $1.bill.amt } }
    var paidTotal: Double { billRows.filter(\.isPaid).reduce(0) { $0 + $1.bill.amt } }

    func billStatus(_ b: BillRow) -> String {
        if b.isPaid { return "Paid" }
        if b.dueDay < todayDay { return "Overdue" }
        if b.dueDay == todayDay { return "Due today" }
        let n = b.dueDay - todayDay
        return "Due in \(n) day" + (n == 1 ? "" : "s")
    }

    /// What's left in the category budgets once the unpaid bills are set aside.
    var safeToSpend: Double { totalLimit - totalSpent - unpaidTotal }

    // MARK: Accounts & pots

    func balance(_ a: Account) -> Double { balances[a.id] ?? a.opening }
    /// Sum of every account balance (cards count negative).
    var accountsTotal: Double { accounts.map(balance).reduce(0, +) }
    var assetsTotal: Double { assets.reduce(0) { $0 + $1.value } }
    /// Accounts in the black plus assets.
    var own: Double { accounts.map(balance).filter { $0 > 0 }.reduce(0, +) + assetsTotal }
    /// Loans plus accounts in the red.
    var liabilities: Double {
        accounts.map(balance).filter { $0 < 0 }.reduce(0) { $0 - $1 } + debts.reduce(0) { $0 + $1.balance }
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

    /// Spare change from rounding each everyday purchase up to the next 10.
    var roundUps: Double {
        let raw = monthExpenses.filter { $0.billId == nil }.reduce(0) { $0 + (($1.amt / 10).rounded(.up) * 10 - $1.amt) }
        return max(0, (raw - (household.roundSwept[ym] ?? 0)).rounded())
    }
    var roundUpPot: Goal? { goals.first { $0.id == household.roundUpPot } ?? goals.first }

    // MARK: Insights

    var lastSevenDays: [DayBar] {
        (0..<7).map { i in
            let k = 6 - i
            let d = DateKit.cal.date(byAdding: .day, value: -k, to: today) ?? today
            let iso = DateKit.iso(d)
            let v = tx.filter { $0.type == .expense && $0.billId == nil && $0.date == iso }.reduce(0) { $0 + $1.amt }
            let wd = DateKit.cal.component(.weekday, from: d) - 1
            return DayBar(id: i, label: DateKit.weekdays[wd], value: v)
        }
    }

    func spent(by w: Who) -> Double { monthExpenses.filter { $0.who == w }.reduce(0) { $0 + $1.amt } }

    // MARK: Custom categories

    func isCustom(_ id: String) -> Bool { household.custom?.contains { $0.id == id } ?? false }

    // MARK: Debt

    /// Loans plus any credit card that's in the red (APR defaults to 36%,
    /// minimum to the larger of 100 or 5% of the balance).
    var allDebts: [DebtLine] {
        debts.map { DebtLine(id: $0.id, name: $0.name, balance: $0.balance, apr: $0.apr, min: $0.min) }
            + accounts.filter { $0.type == .card && balance($0) < 0 }.map { (a: Account) -> DebtLine in
                let owed = -balance(a)
                return DebtLine(id: a.id, name: a.name, balance: owed, apr: a.apr ?? 36, min: max(100, (owed * 0.05).rounded()))
            }
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
        return plan.months >= 720 ? "Not at this rate" : DateKit.monthLabel(DateKit.addMonths(ym, plan.months), short: true)
    }

    // MARK: Plan ahead

    static let cushion: Double = 5000

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
        let daily = tx.filter { $0.type == .expense && $0.billId == nil && $0.date >= since }.reduce(0) { $0 + $1.amt } / 60
        var events: [ForecastEvent] = []
        for k in 0...30 {
            let dt = cal.date(byAdding: .day, value: k, to: today) ?? today
            let m = DateKit.ym(dt), dd = DateKit.day(dt), dm = DateKit.daysIn(m)
            for b in bills {
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
        return "Set aside \(money.f((p.cost / Double(n)).rounded(.up))) a month, yours by \(DateKit.monthLabel(DateKit.addMonths(ym, n), short: true))"
    }

    // MARK: Report

    var reportFileName: String { "twofold-report-\(ym).csv" }

    /// This month's report as CSV: totals, categories with share, who spent.
    var reportCSV: String {
        let cur = money.currency
        let cats = rows.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }
        var lines: [[String]] = [
            ["Twofold report", DateKit.monthLabel(ym)],
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

    // MARK: Start here (empty start)

    var setupSteps: [(title: String, done: Bool)] {
        [("Add your accounts", !accounts.isEmpty),
         ("Set your pay", household.incomes.contains { $0.amt > 0 }),
         ("Give categories a limit", household.budgets.values.contains { $0 > 0 }),
         ("Log a first entry", !tx.isEmpty)]
    }
    var setupDone: Bool { setupSteps.allSatisfy(\.done) }
}
