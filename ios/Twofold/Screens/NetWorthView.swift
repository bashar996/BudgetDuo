import SwiftUI

/// Everything you own (accounts in the black, investments, assets) minus everything
/// you owe. Assets and investments are added and edited here, as on the Mac.
@MainActor
struct NetWorthView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    /// Cash, Savings, Investments, Property & other assets. Computed, so it follows the accent.
    private static var groupColors: [Color] { [Palette.black, Palette.lavender, Palette.accentText, Palette.gray] }

    var body: some View {
        if let L = store.ledger() {
            let own = L.own
            let groups = L.ownGroups
            let owing = oweRows(L)
            let segments: [(value: Double, color: Color)] = groups.enumerated().map { k, g in (value: g.value, color: Self.groupColors[k]) }
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Net worth", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Net worth").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(L.netWorth), size: 54).padding(.top, 4)
                        Text("Own \(L.money.f(own)) · owe \(L.money.f(L.liabilities))").font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
                titleRow("What you own", total: L.money.f(own)).padding(.top, 4)
                SplitBar(segments: segments)
                    .padding(.top, 12).padding(.bottom, 4)
                ForEach(Array(groups.enumerated()), id: \.offset) { k, g in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Self.groupColors[k]).frame(width: 14, height: 14)
                        Text(g.label).font(.geist(16)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(percent(g.value, of: own)).font(.geist(13)).foregroundStyle(Palette.gray)
                        Text(L.money.f(g.value)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                    .accessibilityElement(children: .combine)
                }

                Group {
                SectionTitle(title: "Assets", action: (label: "+ Add asset", run: { router.form = .asset(nil) })).padding(.top, 18)
                ForEach(L.assets) { a in
                    Button { router.form = .asset(a) } label: {
                        row(initial: a.kindLabel, title: a.name, meta: a.kindLabel) {
                            Text(L.money.f(a.value)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edits the asset")
                }
                if L.assets.isEmpty {
                    EmptyNote(text: "Add a home, a car, gold or anything else of value that doesn’t sit in an account.")
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
                }

                SectionTitle(title: "Investments", action: (label: "+ Add investment", run: { router.form = .newInvestment })).padding(.top, 18)
                ForEach(L.investments) { a in
                    Button { router.form = .account(a) } label: {
                        row(initial: a.name, title: a.name, meta: [L.name(a.who), a.bank ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")) {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(L.money.f(L.balance(a))).font(.geist(15, .medium)).lineLimit(1)
                                if let g = L.gain(a), let cost = a.cost {
                                    Text(gainText(g, cost: cost, money: L.money))
                                        .font(.geist(12.5)).foregroundStyle(g < 0 ? Palette.bad : Palette.accentText).lineLimit(1)
                                } else {
                                    Text("Add what you put in to see the gain").font(.geist(12.5)).foregroundStyle(Palette.gray).lineLimit(1)
                                }
                            }
                            .fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Edits the investment: its value now and what you put in")
                }
                if L.investments.isEmpty {
                    EmptyNote(text: "Add a brokerage, fund or long-term plan with what it’s worth today.")
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 2)
                }

                }

                Group {
                titleRow("What you owe", total: L.money.f(L.liabilities)).padding(.top, 24)
                ForEach(owing, id: \.id) { o in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(o.name).font(.geist(16, .medium)).lineLimit(1)
                            Text(o.meta).font(.geist(13)).foregroundStyle(Palette.gray)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L.money.f(o.amount)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                    .accessibilityElement(children: .combine)
                }
                if owing.isEmpty { EmptyNote(text: "Nothing owed.").padding(.vertical, 2) }
                Button { router.drill(.debt) } label: {
                    Text("Payoff plan →").font(.geist(14, .medium)).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
                }
            }

        }
    }

    private func percent(_ v: Double, of total: Double) -> String {
        let r = v / (total > 0 ? total : 1) * 100
        return "\(Int(r.rounded()))%"
    }

    /// "+AED 12,000 · +23%" or "−AED 1,000 · −5%"
    private func gainText(_ g: Double, cost: Double, money: Money) -> String {
        let pct = Int(abs((g / cost * 100).rounded()))
        let sign = g >= 0 ? "+" : "−"
        let amount = g >= 0 ? "+\(money.f(g))" : money.f(g)
        return "\(amount) · \(sign)\(pct)%"
    }

    private struct OweRow {
        let id: String
        let name: String
        let meta: String
        let amount: Double
    }

    /// Accounts below zero (cards) — a card also owes what its installment plans still have to
    /// bill, shown under it — then loans.
    private func oweRows(_ L: Ledger) -> [OweRow] {
        var inPlans: [String: Double] = [:]
        for p in L.plans {
            if let acct = p.acct { inPlans[acct, default: 0] += L.planState(p).remaining }
        }
        let cards: [OweRow] = L.accounts.compactMap { (a: Account) -> OweRow? in
            let bal = L.balance(a)
            let plan = inPlans[a.id] ?? 0
            guard bal < 0 || plan > 0.005 else { return nil }
            let meta: String = plan > 0.005 ? a.type.label + " · incl. \(L.money.f(plan)) in installment plans" : a.type.label
            return OweRow(id: "a-" + a.id, name: a.name, meta: meta, amount: max(0, -bal) + plan)
        }
        let loans: [OweRow] = L.loans.compactMap { (d: Debt) -> OweRow? in
            let st = L.loanState(d)
            guard st.balance > 0.005 else { return nil }
            return OweRow(id: "d-" + d.id, name: d.name, meta: "\(d.kindLabel) · \(rateText(st))", amount: st.balance)
        }
        return cards + loans
    }

    private func titleRow(_ title: String, total: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            Spacer(minLength: 0)
            Text(total).font(.geist(13)).foregroundStyle(Palette.gray).lineLimit(1)
        }
    }

    private func row<Trailing: View>(initial: String, title: String, meta: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            InitialTile(name: initial, background: Palette.tile)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.geist(16, .medium)).lineLimit(1)
                Text(meta).font(.geist(13)).foregroundStyle(Palette.gray).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
        .accessibilityElement(children: .combine)
    }
}

/// Proportional bar: 3pt gaps, 5pt corners, at least 6pt per segment; empty groups are left out.
struct SplitBar: View {
    var segments: [(value: Double, color: Color)]
    var height: CGFloat = 14

    var body: some View {
        let shown = segments.filter { $0.value > 0 }
        let total = shown.reduce(0) { $0 + $1.value }
        GeometryReader { geo in
            let avail = max(0, geo.size.width - 3 * CGFloat(max(0, shown.count - 1)))
            HStack(spacing: 3) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, s in
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(s.color)
                        .frame(width: max(6, avail * CGFloat(s.value / max(total, 1))))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}
