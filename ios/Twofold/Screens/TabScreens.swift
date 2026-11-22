import SwiftUI

@MainActor
struct BudgetView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            let left = L.leftToAssign
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(left < 0 ? "Over-assigned this month" : "Left to assign · \(L.monthName)").font(.geist(13)).foregroundStyle(Palette.mute)
                    BigAmount(currency: L.money.currency, value: L.money.num(left), color: Palette.lavender).padding(.top, 4)
                    Text(left < 0 ? "You’ve planned more than comes in. Trim a category to get back to zero."
                         : left == 0 ? "Every bit of income has a job." : "Give it a job — a category or a pot.")
                        .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    HStack(alignment: .top, spacing: 8) {
                        stat("Income", L.money.f(L.income)) { router.form = .pay(store.me) }
                        stat("Budgeted", L.money.f(L.totalLimit), nil)
                        stat("To pots", L.money.f(L.goalsMonthly)) { router.select(.savings) }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            } content: {
                ForEach(Catalog.groups, id: \.0) { item in
                    let g = item.0, title = item.1
                    let rs = L.rows.filter { $0.group == g }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
                            Spacer()
                            Text("\(L.money.f(rs.reduce(0) { $0 + $1.spent })) of \(L.money.f(rs.reduce(0) { $0 + $1.limit }))")
                                .font(.geist(13)).foregroundStyle(Palette.gray)
                        }
                        ForEach(rs) { r in
                            Button { router.form = .budget(r.id) } label: { row(r, L) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 14)
                }
                BlockButton(title: "+ New category", fill: Palette.black, outline: true) { router.form = .newCategory }
                    .padding(.top, 22)
                Text("Tap a category to rename it, change its limit or delete it.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.geist(12)).foregroundStyle(Palette.mute)
                Text(value).font(.geist(16, .medium)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func row(_ r: BudgetRow, _ L: Ledger) -> some View {
        let over = r.left < 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(r.name).font(.geist(16))
                Spacer()
                Text("\(Int((r.ratio * 100).rounded()))%").font(.geist(26)).tracking(em: -0.02, size: 26)
                    .foregroundStyle(over ? Palette.overText : Palette.black)
            }
            ProgressLine(ratio: r.ratio, fill: over ? Palette.overFill : Palette.lavender).padding(.top, 8)
            Text("\(L.money.f(r.spent)) of \(L.money.f(r.limit)) · " + (over ? "\(L.money.f(-r.left)) over" : "\(L.money.f(r.left)) left"))
                .font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 6)
        }
        .padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}

@MainActor
struct SavingsView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            Screen(color: Palette.lavender, contentPadding: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved in your pots").font(.geist(13)).foregroundStyle(Palette.mute)
                    BigAmount(currency: L.money.currency, value: L.money.num(L.inPots)).padding(.top, 4)
                    Text("\(L.movedIntoPotsThisMonth >= 0 ? "+" : "")\(L.money.f(L.movedIntoPotsThisMonth)) moved in this month")
                        .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            } content: {
                if L.roundUps > 0, let pot = L.roundUpPot, let from = L.mainAccountId {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(L.money.f(L.roundUps)) of spare change from this month’s purchases is ready to save.")
                            .font(.geist(15)).fixedSize(horizontal: false, vertical: true)
                        BlockButton(title: "Move to \(pot.name)", fill: Palette.lavender, text: Palette.black, height: 48, radius: 16) {
                            store.moveRoundUps(L.roundUps, to: pot, from: from, ym: L.ym, today: DateKit.iso(L.today))
                        }
                    }
                    .padding(16)
                    .background(Palette.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .foregroundStyle(Palette.white)
                    .padding(.bottom, 12)
                }
                ForEach(L.goals) { g in potCard(g, L) }
                if L.goals.isEmpty {
                    EmptyNote(text: "No pots yet. Start one for anything you’re saving toward.", color: Palette.ink)
                        .padding(.horizontal, 4)
                }
                BlockButton(title: "+ New pot", fill: Palette.black, outline: true) { router.form = .pot(nil) }
                    .padding(.top, 6)
            }
        }
    }

    private func potCard(_ g: Goal, _ L: Ledger) -> some View {
        let saved = L.saved(g)
        let r = g.target > 0 ? saved / g.target : 0
        let rem = max(0, g.target - saved)
        let n = g.monthly > 0 ? Int((rem / g.monthly).rounded(.up)) : 0
        let a = L.accounts.first { $0.id == g.acct }
        let status = rem <= 0 ? "Reached" : n > 0 ? "There by \(DateKit.monthLabel(DateKit.addMonths(L.ym, n), short: true))" : "Paused"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.name).font(.geist(18, .medium))
                    Text((a?.name ?? "Savings") + (a?.apy.map { " · \(fmt($0))% a year" } ?? "")).font(.geist(12.5)).foregroundStyle(Palette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 6) {
                    Button { router.form = .pot(g) } label: {
                        Text("Edit").font(.geist(13.5, .medium)).padding(.horizontal, 16).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit \(g.name)")
                    Text("\(Int((r * 100).rounded()))%").font(.geist(30)).tracking(em: -0.03, size: 30)
                }
                .fixedSize()
            }
            ProgressLine(ratio: r, fill: Palette.white).padding(.top, 12)
            HStack {
                Text("\(L.money.f(saved)) of \(L.money.f(g.target))")
                Spacer()
                Text(status).font(.geist(13, .medium))
            }
            .font(.geist(13)).padding(.top, 8)
            HStack(spacing: 8) {
                BlockButton(title: "Deposit", height: 46, radius: 16) {
                    router.add(store, L) { $0.type = .transfer; $0.to = g.acct; $0.pot = g.id; $0.potDir = .into; $0.name = "Deposit · \(g.name)" }
                }
                BlockButton(title: "Withdraw", fill: Palette.black, outline: true, height: 46, radius: 16) {
                    router.add(store, L) { $0.type = .transfer; $0.acct = g.acct; $0.to = L.mainAccountId ?? ""; $0.pot = g.id; $0.potDir = .out; $0.name = "Withdrawal · \(g.name)" }
                }
            }
            .padding(.top, 12)
        }
        .padding(16)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.bottom, 12)
    }
}

func fmt(_ x: Double) -> String { x == x.rounded() ? String(Int(x)) : String(format: "%.2f", x) }

@MainActor
struct MoreView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            let other: Who = store.me == .a ? .b : .a
            // Same order as the web navigation.
            let rows: [(String, String, Route)] = [
                ("Activity", "\(L.monthTx.count) entries this month", .activity(account: nil)),
                ("Bills", L.unpaidBills.isEmpty ? (L.bills.isEmpty ? "Add your monthly bills" : "All paid this month") : "\(L.money.f(L.unpaidTotal)) still due this month", .bills),
                ("Accounts", L.accounts.count == 1 ? "1 account" : "\(L.accounts.count) accounts and cards", .accounts),
                ("Net worth", "\(L.money.f(L.netWorth)) across everything you own", .worth),
                ("Debt", L.allDebts.isEmpty ? "Nothing owed" : "Debt-free by \(L.debtFreeLabel)", .debt),
                ("Reports", "Where the money went", .reports),
                ("Plan ahead", "Next 30 days and big purchases", .plan),
                ("Us two", "Pay, pocket money and money date", .us),
                ("Settings", "Names, currency, invite code", .settings),
            ]
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("More").font(.geist(34, .medium)).tracking(em: -0.03, size: 34)
                    Text("\(L.name(store.me)) & \(L.name(other)) · shared budget").font(.geist(14)).foregroundStyle(Palette.mute)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            } content: {
                ForEach(rows, id: \.0) { r in
                    // Unfolded: the row whose detail is open on the right gets a filled arrow.
                    let open = router.isWide && router.detail == r.2
                    Button { router.open(r.2) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(r.0).font(.geist(20, .medium)).tracking(em: -0.01, size: 20)
                                Text(r.1).font(.geist(13.5)).foregroundStyle(Palette.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text("→").font(.geist(20)).frame(width: 38, height: 38)
                                .background(open ? Palette.black : .clear, in: Circle())
                                .foregroundStyle(open ? Palette.white : Palette.black)
                        }
                        .padding(.vertical, 16)
                        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
