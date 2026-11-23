import SwiftUI

@MainActor
struct DebtView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            let debts = L.allDebts
            let plan = L.debtPlan()
            Screen(color: Palette.cream, mirrored: true) {
                hero(L, debts: debts, plan: plan)
            } content: {
                strategy(L)
                if !debts.isEmpty { payoffOrder(L, debts: debts, plan: plan) }

                SectionTitle(title: "Loans", action: (label: "+ Loan", run: { router.form = .debt(nil) })).padding(.top, 22)
                ForEach(L.debts) { d in loanCard(d, L).padding(.top, 10) }
                if L.debts.isEmpty {
                    EmptyNote(text: "No loans yet. Add one with its rate, term and first payment date for a full schedule.")
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionTitle(title: "Credit cards", action: (label: "+ Card", run: { router.form = .newCard })).padding(.top, 22)
                ForEach(L.cards) { a in cardPanel(a, L).padding(.top, 10) }
                if L.cards.isEmpty {
                    EmptyNote(text: "No credit cards yet.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Hero

    private func hero(_ L: Ledger, debts: [DebtLine], plan: DebtPlan) -> some View {
        let owed = debts.reduce(0.0) { $0 + $1.balance }
        let stuck = !debts.isEmpty && plan.months >= 720
        return VStack(alignment: .leading, spacing: 0) {
            NavRow(title: "Debt", showBack: showBack)
            VStack(alignment: .leading, spacing: 0) {
                Text(debts.isEmpty ? "No debt" : "Debt-free by").font(.geist(13)).foregroundStyle(Palette.mute)
                Text(L.debtFreeLabel).font(.geist(54, .medium)).tracking(em: -0.045, size: 54)
                    .foregroundStyle(Palette.lavender).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 4)
                if debts.isEmpty || stuck {
                    Text(debts.isEmpty ? "Nothing owed. Enjoy it." : "The payments don’t cover the interest — add a bit more each month.")
                        .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 8) {
                    heroStat("Owed today", L.money.f(owed))
                    heroStat("Monthly payments", L.money.f(L.debtMonthly))
                    heroStat("Interest to go", stuck ? "—" : L.money.f(debts.isEmpty ? 0 : plan.interest))
                }
                .padding(.top, 16)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
        }
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.geist(12)).foregroundStyle(Palette.mute).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.geist(16, .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plan

    private func strategy(_ L: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payoff order").font(.geist(22, .medium)).tracking(em: -0.01, size: 22).padding(.top, 4)
            FlowLayout(spacing: 6) {
                ForEach([("avalanche", "Highest interest first"), ("snowball", "Smallest balance first")], id: \.0) { s in
                    CreamChip(label: s.1, on: L.strategy == s.0) { store.setStrategy(s.0) }
                }
            }
            .padding(.top, 10)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Extra each month").font(.geist(16, .medium))
                    Text("On top of the installments and minimums").font(.geist(13)).foregroundStyle(Palette.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                step("−", "Less") { store.setExtra(L.extraPayment - 250) }
                Text(L.money.num(L.extraPayment)).font(.geist(19, .medium)).tracking(em: -0.02, size: 19)
                    .frame(minWidth: 58).monospacedDigit()
                step("+", "More") { store.setExtra(L.extraPayment + 250) }
            }
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Hairline(opacity: 0.12) }
            .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
            .padding(.top, 14)
        }
    }

    private func payoffOrder(_ L: Ledger, debts: [DebtLine], plan: DebtPlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(plan.order.enumerated()), id: \.element) { k, id in
                if let x = debts.first(where: { $0.id == id }) {
                    let clear: String = plan.done[id].map { (m: Int) -> String in "Clear by \(DateKit.monthLabel(DateKit.addMonths(L.calendarYm, m), short: true))" } ?? "Not cleared at this rate"
                    Button { openDebt(id, L) } label: {
                        HStack(spacing: 12) {
                            Text("\(k + 1)").font(.geist(15, .semibold)).frame(width: 32, height: 32)
                                .background(Palette.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(Palette.white)
                            Text(x.name).font(.geist(15, .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(clear)
                                .font(.geist(12.5)).foregroundStyle(Palette.gray).lineLimit(1).fixedSize()
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A loan opens its detail; a card its account form.
    private func openDebt(_ id: String, _ L: Ledger) {
        if L.debts.contains(where: { $0.id == id }) { router.drill(.loan(id)) }
        else if let card = L.accounts.first(where: { $0.id == id }) { router.form = .account(card) }
    }

    // MARK: Loans

    private func loanCard(_ d: Debt, _ L: Ledger) -> some View {
        let st = L.loanState(d)
        let done = st.balance <= 0.005
        return VStack(alignment: .leading, spacing: 0) {
            Button { router.drill(.loan(d.id)) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(d.name).font(.geist(18, .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Details →").font(.geist(13, .medium)).foregroundStyle(Palette.accentText)
                    }
                    Text(loanMeta(d)).font(.geist(12.5)).foregroundStyle(Palette.gray).lineLimit(1)
                    Text(L.money.f(st.balance)).font(.geist(30, .medium)).tracking(em: -0.03, size: 30)
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.top, 8)
                    Text(done ? "Paid off" : "\(L.money.f(st.installment)) / month · \(rateText(st))")
                        .font(.geist(13)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
                    ProgressLine(ratio: st.progress, fill: Palette.lavender, track: Palette.black.opacity(0.1), height: 6).padding(.top, 10)
                    Text(loanProgressText(st)).font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the schedule and payments")
            if st.simple {
                Button { router.form = .debt(d) } label: {
                    Text("Add the loan details for a full schedule →").font(.geist(13.5, .medium)).foregroundStyle(Palette.accentText)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let next = st.nextDue {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next \(DateKit.dateLabel(next))").font(.geist(14, .medium))
                        Text(L.dueStatus(next)).font(.geist(12.5))
                            .foregroundStyle(L.daysUntil(next) < 0 ? Palette.bad : Palette.gray)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button { store.payInstallment(d) } label: {
                        Text("Pay").font(.geist(13.5, .medium)).padding(.horizontal, 18).frame(height: 44)
                            .background(Palette.black, in: Capsule()).foregroundStyle(Palette.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pay installment")
                    .accessibilityHint(L.loanBill(d) == nil ? "Logs the installment as an expense" : "Marks its bill paid")
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Hairline(opacity: 0.1) }
                .padding(.top, 12)
            }
        }
        .padding(16)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func loanMeta(_ d: Debt) -> String {
        [d.lender, d.kindLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: Cards

    private func cardPanel(_ a: Account, _ L: Ledger) -> some View {
        let cs = L.cardState(a)
        let used = cs.utilisation ?? 0
        let warn = used > 0.3
        let months = cs.minOnly.months
        let minOnly: String = cs.minOnly.never
            ? "Paying only the minimum: never paid off"
            : "Paying only the minimum: \(months) month" + (months == 1 ? "" : "s") + ", \(L.money.f(cs.minOnly.interest)) interest"
        return VStack(alignment: .leading, spacing: 0) {
            Button { router.form = .account(a) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.geist(18, .medium)).lineLimit(1)
                        Text(cardMeta(a, cs)).font(.geist(12.5)).foregroundStyle(Palette.gray).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(L.money.f(cs.owed)).font(.geist(22, .medium)).tracking(em: -0.02, size: 22).lineLimit(1).fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the card")
            if let limit = cs.limit, limit > 0 {
                ProgressLine(ratio: used, fill: warn ? Palette.overFill : Palette.lavender, track: Palette.black.opacity(0.1), height: 6)
                    .padding(.top, 10)
                Text("\(Int((used * 100).rounded()))% of \(L.money.f(limit)) used").font(.geist(12.5))
                    .foregroundStyle(warn ? Palette.overText : Palette.gray).padding(.top, 6)
            }
            if cs.owed > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    if let due = cs.nextDue {
                        Text("Minimum \(L.money.f(cs.minDue)) due \(DateKit.dayLabel(due))").font(.geist(14, .medium))
                    } else {
                        Button { router.form = .account(a) } label: {
                            Text("Minimum \(L.money.f(cs.minDue)) · Set the due day →").font(.geist(14, .medium)).foregroundStyle(Palette.accentText)
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(minOnly)
                        .font(.geist(13)).foregroundStyle(cs.minOnly.never ? Palette.bad : Palette.gray)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Interest next month if you pay only the minimum: \(L.money.f(cs.interestIfMin))")
                        .font(.geist(13)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 12)
                HStack(spacing: 8) {
                    BlockButton(title: "Pay in full", height: 46, radius: 16) { payCard(a, cs.owed, L) }
                    BlockButton(title: "Pay minimum", fill: Palette.black, outline: true, height: 46, radius: 16) { payCard(a, cs.minDue, L) }
                }
                .padding(.top, 12)
            } else {
                Text("Nothing owed on this card.").font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 8)
            }
        }
        .padding(16)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func cardMeta(_ a: Account, _ cs: CardState) -> String {
        [a.bank, a.last4.map { "•• \($0)" }, "\(pctText(cs.apr))% APR"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Opens the entry keypad as a transfer from the main account to the card.
    private func payCard(_ a: Account, _ amount: Double, _ L: Ledger) {
        let from = L.mainAccountId == a.id ? L.accounts.first(where: { $0.type != .card })?.id : L.mainAccountId
        router.add(store, L) { d in
            d.type = .transfer
            d.acct = from ?? ""
            d.to = a.id
            d.amt = EntryDraft.keypadAmount(amount)
            d.name = "\(a.name) payment"
        }
    }

    private func step(_ s: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.geist(22)).frame(width: 44, height: 44)
                .background(Palette.black, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .foregroundStyle(Palette.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

@MainActor
struct PlanAheadView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            let fc = L.forecast()
            let cushion = L.cushion
            let series = fc.series
            let minV = series.min() ?? 0
            let low = minV < cushion
            let lo = min(0, minV), hi = max(cushion, series.max() ?? 0) * 1.05
            let end = series.last ?? 0
            let minIdx = series.firstIndex(of: minV) ?? 0
            let range: Double = max(hi - lo, 1)
            let dipText: String = "Dips to \(L.money.f(minV)) around \(dayLabel(L, minIdx)), below your \(L.money.f(cushion)) cushion."
            let aboveText: String = "Stays above your \(L.money.f(cushion)) cushion all month."
            let headline: String = L.accounts.isEmpty ? "Add an account and your bills, and the next 30 days appear here."
                : (low ? dipText : aboveText)
            Screen(color: Palette.lavender) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Plan ahead", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Cash in 30 days").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(end), size: 54,
                                  color: low && !L.accounts.isEmpty ? Palette.badOnBlack : Palette.white).padding(.top, 4)
                        Text(headline)
                            .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { g in
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(Array(series.enumerated()), id: \.offset) { k, v in
                                    let frac = CGFloat(max(0.04, (v - lo) / range))
                                    UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 5)
                                        .fill(v < cushion ? Palette.badOnBlack : k == 0 ? Palette.lavender : Palette.cream)
                                        .frame(height: g.size.height * frac)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                        .frame(height: 110).padding(.top, 14)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Cash forecast for the next 30 days")
                        HStack {
                            Text("Today · \(L.money.f(fc.cash))")
                            Spacer()
                            Text(dayLabel(L, 30))
                        }
                        .font(.geist(12.5)).foregroundStyle(Palette.soft).padding(.top, 6)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            } content: {
                Text("Coming in and out").font(.geist(22, .medium)).tracking(em: -0.01, size: 22).padding(.top, 4)
                ForEach(fc.events.prefix(6)) { e in
                    HStack(spacing: 12) {
                        DateTile(day: DateKit.day(e.date), month: String(DateKit.monthName(DateKit.ym(e.date), short: true)))
                        Text(e.name).font(.geist(16, .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text((e.amt > 0 ? "+" : "") + L.money.f(e.amt)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Hairline() }
                }
                if fc.events.isEmpty { EmptyNote(text: "Nothing scheduled in the next 30 days.", color: Palette.ink) }

                Group {
                    sectionHeader("Planned purchases") { router.form = .planned(nil) }
                    Text("Big buys wait until you’ve both said yes.").font(.geist(13)).foregroundStyle(Palette.ink)
                    ForEach(L.planned) { p in plannedCard(p, L).padding(.top, 10) }
                    if L.planned.isEmpty { EmptyNote(text: "No planned purchases yet.", color: Palette.ink) }
                }

                sectionHeader("Trips & events") { router.form = .trip(nil) }
                ForEach(L.trips) { t in
                    let left = t.budget - t.spent
                    let leftText: String = left < 0 ? "\(L.money.f(-left)) over" : "\(L.money.f(left)) to go"
                    let spentLine: String = "\(L.money.f(t.spent)) of \(L.money.f(t.budget)) · \(leftText)"
                    VStack(alignment: .leading, spacing: 0) {
                        Button { router.form = .trip(t) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .lastTextBaseline) {
                                    Text(t.name).font(.geist(16))
                                    Spacer()
                                    Text(t.when).font(.geist(13)).foregroundStyle(Palette.ink)
                                }
                                ProgressLine(ratio: t.spent / max(t.budget, 1), fill: left < 0 ? Palette.overFill : Palette.white).padding(.top, 8)
                            }
                            .padding(.top, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edits the trip")
                        HStack(spacing: 10) {
                            Text(spentLine)
                                .font(.geist(12.5)).foregroundStyle(left < 0 ? Palette.overText : Palette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button { router.form = .tripSpend(t) } label: {
                                Text("Log spend").font(.geist(13.5, .medium)).padding(.horizontal, 16).frame(height: 44)
                                    .background(Palette.black, in: Capsule()).foregroundStyle(Palette.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log spending on \(t.name)")
                        }
                        .padding(.top, 6).padding(.bottom, 8)
                    }
                    .overlay(alignment: .bottom) { Hairline() }
                }
                if L.trips.isEmpty { EmptyNote(text: "No trips or events planned.", color: Palette.ink) }
            }
        }
    }

    private func dayLabel(_ L: Ledger, _ offset: Int) -> String {
        DateKit.dayLabel(DateKit.iso(DateKit.cal.date(byAdding: .day, value: offset, to: L.today) ?? L.today))
    }

    /// A planned purchase: what it costs, whether it fits, each partner's yes, and
    /// Mark bought once you've both agreed (logs a Shopping expense and takes it off).
    private func plannedCard(_ p: Planned, _ L: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { router.form = .planned(p) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(p.name).font(.geist(16, .medium)).lineLimit(2)
                        Spacer(minLength: 8)
                        Text(L.money.f(p.cost)).font(.geist(19, .medium)).tracking(em: -0.02, size: 19).lineLimit(1).fixedSize()
                    }
                    Text(L.verdict(p)).font(.geist(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the planned purchase")
            FlowLayout(spacing: 6) {
                voteChip(L.household.nameA, on: p.A) { store.vote(p, who: .a) }
                voteChip(L.household.nameB, on: p.B) { store.vote(p, who: .b) }
                if p.A && p.B {
                    Button { store.buyPlanned(p, account: L.mainAccountId ?? "") } label: {
                        Text("Mark bought").font(.geist(13.5, .medium)).padding(.horizontal, 14).frame(height: 44)
                            .background(Palette.black, in: Capsule()).foregroundStyle(Palette.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Logs it as a Shopping expense and takes it off the plan")
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func voteChip(_ name: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text((on ? "✓ " : "") + name).font(.geist(13.5, .medium)).lineLimit(1).padding(.horizontal, 14).frame(height: 44)
                .foregroundStyle(on ? Palette.white : Palette.black)
                .background(on ? Palette.black : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) is in")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func sectionHeader(_ title: String, add: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            Spacer()
            Button("+ Add", action: add).font(.geist(14, .medium)).frame(minHeight: 44)
        }
        .padding(.top, 22)
    }
}
