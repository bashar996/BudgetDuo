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
            let owed = debts.reduce(0.0) { $0 + $1.balance }
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Debt", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(debts.isEmpty ? "No debt" : "Debt-free by").font(.geist(13)).foregroundStyle(Palette.mute)
                        Text(L.debtFreeLabel).font(.geist(54, .medium)).tracking(em: -0.045, size: 54)
                            .foregroundStyle(Palette.lavender).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 4)
                        Text(debts.isEmpty ? "Nothing owed. Enjoy it."
                             : plan.months >= 720 ? "\(L.money.f(owed)) owed today. The payments don’t cover the interest — add a bit more each month."
                             : "\(L.money.f(owed)) owed today · \(L.money.f(plan.interest)) interest to go")
                            .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
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
                        Text("On top of the minimums").font(.geist(13)).foregroundStyle(Palette.gray)
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
                ForEach(Array(plan.order.enumerated()), id: \.element) { k, id in
                    if let x = debts.first(where: { $0.id == id }) {
                        let loan = L.debts.first { $0.id == id }
                        Button {
                            if let loan { router.form = .debt(loan) }
                            else if let card = L.accounts.first(where: { $0.id == id }) { router.form = .account(card) }
                        } label: {
                            HStack(spacing: 12) {
                                Text("\(k + 1)").font(.geist(17, .semibold)).frame(width: 44, height: 44)
                                    .background(Palette.black, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    .foregroundStyle(Palette.white)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(x.name).font(.geist(16, .medium)).lineLimit(1)
                                    Text("\(fmt(x.apr))% · \(L.money.f(x.min)) a month").font(.geist(13)).foregroundStyle(Palette.gray)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(L.money.f(x.balance)).font(.geist(15, .medium)).lineLimit(1)
                                    Text(plan.done[id].map { "Clear by \(DateKit.monthLabel(DateKit.addMonths(L.ym, $0), short: true))" } ?? "Not cleared at this rate")
                                        .font(.geist(12.5)).foregroundStyle(Palette.gray).lineLimit(1)
                                }
                                .fixedSize()
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if debts.isEmpty {
                    EmptyNote(text: "No loans or card balances. Add a loan below; cards in the red show up on their own.").padding(.vertical, 8)
                }
                BlockButton(title: "+ Loan", fill: Palette.black, outline: true) { router.form = .debt(nil) }.padding(.top, 16)
            }
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
            let series = fc.series
            let minV = series.min() ?? 0
            let low = minV < Ledger.cushion
            let lo = min(0, minV), hi = max(Ledger.cushion, series.max() ?? 0) * 1.05
            let end = series.last ?? 0
            let minIdx = series.firstIndex(of: minV) ?? 0
            Screen(color: Palette.lavender) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Plan ahead", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Cash in 30 days").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(end), size: 54,
                                  color: low && !L.accounts.isEmpty ? Palette.badOnBlack : Palette.white).padding(.top, 4)
                        Text(L.accounts.isEmpty ? "Add an account and your bills, and the next 30 days appear here."
                             : low ? "Dips to \(L.money.f(minV)) around \(dayLabel(L, minIdx)), below your \(L.money.f(Ledger.cushion)) cushion."
                                   : "Stays above your \(L.money.f(Ledger.cushion)) cushion all month.")
                            .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                        GeometryReader { g in
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(Array(series.enumerated()), id: \.offset) { k, v in
                                    UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 5)
                                        .fill(v < Ledger.cushion ? Palette.badOnBlack : k == 0 ? Palette.lavender : Palette.cream)
                                        .frame(height: g.size.height * max(0.04, (v - lo) / max(hi - lo, 1)))
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

                sectionHeader("Planned purchases") { router.form = .planned(nil) }
                ForEach(L.planned) { p in
                    Button { router.form = .planned(p) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(.geist(16, .medium))
                                Text(L.verdict(p)).font(.geist(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                Text(votes(p, L)).font(.geist(12.5)).foregroundStyle(Palette.ink)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L.money.f(p.cost)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Hairline() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if L.planned.isEmpty { EmptyNote(text: "No planned purchases yet.", color: Palette.ink) }

                sectionHeader("Trips & events") { router.form = .trip(nil) }
                ForEach(L.trips) { t in
                    Button { router.form = .trip(t) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .lastTextBaseline) {
                                Text(t.name).font(.geist(16))
                                Spacer()
                                Text(t.when).font(.geist(13)).foregroundStyle(Palette.ink)
                            }
                            ProgressLine(ratio: t.spent / max(t.budget, 1), fill: Palette.white).padding(.top, 8)
                            Text("\(L.money.f(t.spent)) of \(L.money.f(t.budget)) spent").font(.geist(12.5)).foregroundStyle(Palette.ink).padding(.top, 6)
                        }
                        .padding(.top, 12).padding(.bottom, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if L.trips.isEmpty { EmptyNote(text: "No trips or events planned.", color: Palette.ink) }
            }
        }
    }

    private func dayLabel(_ L: Ledger, _ offset: Int) -> String {
        DateKit.dayLabel(DateKit.iso(DateKit.cal.date(byAdding: .day, value: offset, to: L.today) ?? L.today))
    }

    private func votes(_ p: Planned, _ L: Ledger) -> String {
        switch (p.A, p.B) {
        case (true, true): return "You both agreed"
        case (true, false): return "\(L.household.nameA) is in · waiting on \(L.household.nameB)"
        case (false, true): return "\(L.household.nameB) is in · waiting on \(L.household.nameA)"
        default: return "Nobody has agreed yet"
        }
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
