import SwiftUI

@MainActor
struct BudgetView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            let left = L.leftToAssign
            let note = L.assignNote
            // Zero-based budgets assign every bit of income; the other styles just show what's unbudgeted.
            let heading: String = "\(L.isZeroBased ? "Left to assign" : "Unbudgeted") · \(L.monthName)"
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(heading).font(.geist(13)).foregroundStyle(Palette.mute)
                    BigAmount(currency: L.money.currency, value: L.money.num(left), color: left < 0 ? Palette.badOnBlack : Palette.lavender).padding(.top, 4)
                    if !note.isEmpty {
                        Text(note).font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        stat("Income", L.money.f(L.income)) { router.form = .pay(store.me) }
                        stat("Budgeted", L.money.f(L.totalLimit), nil)
                        stat("To pots", L.money.f(L.goalsMonthly)) { router.select(.savings) }
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            } content: {
                if L.budgetStyle == "50/30/20" { styleCheck(L).padding(.bottom, 8) }
                ForEach(Catalog.groups, id: \.0) { item in
                    let g = item.0, title = item.1
                    let rs = L.rows.filter { $0.group == g }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
                            Spacer()
                            Text("\(L.money.f(rs.reduce(0) { $0 + $1.spent })) of \(L.money.f(rs.reduce(0) { $0 + $1.avail }))")
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
                Text("Tap a category to rename it, change its limit, move money in or delete it.")
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

    /// Budget style 50/30/20: what's planned for needs, wants and savings against the guide.
    private func styleCheck(_ L: Ledger) -> some View {
        let income = L.income
        return VStack(alignment: .leading, spacing: 14) {
            Text("50 / 30 / 20 check").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            ForEach(L.styleBands) { b in
                let share = income > 0 ? b.amount / income : 0
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        (Text(b.name).font(.geist(15, .medium))
                         + Text(" · \(Int((share * 100).rounded()))% of income, guide is \(Int(b.guide * 100))%").font(.geist(13)).foregroundColor(Palette.gray))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(L.money.f(b.amount)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.black.opacity(0.1))
                            Capsule().fill(b.name == "Needs" ? Palette.black : b.name == "Wants" ? Palette.accentText : Palette.lavender)
                                .frame(width: g.size.width * Money.pct(share))
                            Rectangle().fill(Palette.black).frame(width: 2, height: 18)
                                .offset(x: g.size.width * b.guide - 1)
                        }
                    }
                    .frame(height: 10)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(b.name): \(L.money.f(b.amount)), \(Int((share * 100).rounded()))% of income. Guide \(Int(b.guide * 100))%")
            }
        }
        .padding(18)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 8)
    }

    private func row(_ r: BudgetRow, _ L: Ledger) -> some View {
        let over = r.left < 0
        let tail: String = over ? "\(L.money.f(-r.left)) over" : "\(L.money.f(r.left)) left"
        let detail: String = "\(L.money.f(r.spent)) of \(L.money.f(r.avail)) · \(tail)"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(r.name).font(.geist(16))
                // Rollover on: what came over from last month.
                if abs(r.carry) >= 1 {
                    Text("rolled \(r.carry > 0 ? "+" : "")\(L.money.f(r.carry))").font(.geist(12)).foregroundStyle(Palette.gray)
                }
                Spacer()
                Text("\(Int((r.ratio * 100).rounded()))%").font(.geist(26)).tracking(em: -0.02, size: 26)
                    .foregroundStyle(over ? Palette.overText : Palette.black)
            }
            ProgressLine(ratio: r.ratio, fill: over ? Palette.overFill : Palette.lavender).padding(.top, 8)
            Text(detail)
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
            let roundOn = L.household.roundUps ?? false
            Screen(color: Palette.lavender, contentPadding: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved in your pots").font(.geist(13)).foregroundStyle(Palette.mute)
                    BigAmount(currency: L.money.currency, value: L.money.num(L.inPots)).padding(.top, 4)
                    Text("\(L.movedIntoPotsThisMonth >= 0 ? "+" : "")\(L.money.f(L.movedIntoPotsThisMonth)) moved in this month")
                        .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 4)
            } content: {
                if roundOn, L.roundUps > 0, let pot = L.roundUpPot, let from = L.mainAccountId {
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
                waysYouSave(L, roundOn: roundOn).padding(.horizontal, 4).padding(.top, 26)
                recentMoves(L).padding(.horizontal, 4).padding(.top, 26)
            }
        }
    }

    private func potCard(_ g: Goal, _ L: Ledger) -> some View {
        let saved = L.saved(g)
        let r = g.target > 0 ? saved / g.target : 0
        let rem = max(0, g.target - saved)
        let n = g.monthly > 0 ? Int((rem / g.monthly).rounded(.up)) : 0
        let a = L.accounts.first { $0.id == g.acct }
        let byText: String = "There by \(DateKit.monthLabel(DateKit.addMonths(L.ym, n), short: true))"
        let status: String = rem <= 0 ? "Reached" : (n > 0 ? byText : "Paused")
        let auto = g.auto ?? false
        let apyText: String = a?.apy.map { (x: Double) -> String in " · \(fmt(x))% a year" } ?? ""
        let keptIn: String = (a?.name ?? "Savings") + apyText
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(g.name).font(.geist(18, .medium))
                    Text(keptIn).font(.geist(12.5)).foregroundStyle(Palette.ink)
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
            // Auto-save each payday, as on the Mac (the amount is set in Edit).
            Toggle(isOn: Binding(get: { auto }, set: { store.setGoalAuto(g.id, $0) })) {
                Text(auto ? "Auto-save on · \(L.money.f(g.monthly)) each payday" : "Auto-save off").font(.geist(13.5))
            }
            .tint(Palette.black)
            .padding(.top, 8)
            .overlay(alignment: .top) { Hairline(opacity: 0.1) }
            .padding(.top, 8)
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

    /// Payday auto-save, round-ups, month-end sweep and where extra money goes (the Mac's "Ways you save").
    private func waysYouSave(_ L: Ledger, roundOn: Bool) -> some View {
        let autoPots = L.goals.filter { $0.auto ?? false }
        let autoTotal = autoPots.reduce(0) { $0 + $1.monthly }
        let sweepOn = L.household.sweep ?? false
        let pot = L.roundUpPot
        return VStack(alignment: .leading, spacing: 0) {
            Text("Ways you save").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Payday auto-save").font(.geist(16, .medium))
                Text(autoTotal > 0
                     ? "Right after payday, \(L.money.f(autoTotal)) moves from \(L.accountName(L.mainAccountId)) into \(autoPots.count) pot\(autoPots.count == 1 ? "" : "s"). Switch any pot on or off above."
                     : "No pot is on auto-save yet. Switch one on above and it fills itself.")
                    .font(.geist(13.5)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
            Toggle(isOn: Binding(get: { roundOn }, set: { store.updateHousehold(["roundUps": $0]) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Round-ups").font(.geist(16, .medium))
                    Text(roundOn
                         ? (L.roundUps > 0 ? "\(L.money.f(L.roundUps)) of spare change from \(DateKit.monthLabel(L.ym)) is ready to move."
                                           : "All round-ups for \(DateKit.monthLabel(L.ym)) are already moved.")
                         : "Rounds each purchase up to the next 10 and saves the difference.")
                        .font(.geist(13.5)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.black)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
            Toggle(isOn: Binding(get: { sweepOn }, set: { store.updateHousehold(["sweep": $0]) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Month-end sweep").font(.geist(16, .medium))
                    Text(sweepOn
                         ? "On the last day of the month, whatever is left in safe-to-spend moves to \(pot?.name ?? "a pot"). Today that would be about \(L.money.f(max(0, L.safeToSpend.rounded())))."
                         : "Moves whatever is left in safe-to-spend into a pot on the last day of the month.")
                        .font(.geist(13.5)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Palette.black)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
            if !L.goals.isEmpty {
                Text("Extra money goes to").font(.geist(13)).foregroundStyle(Palette.ink).padding(.top, 14).padding(.bottom, 8)
                FlowLayout(spacing: 6) {
                    ForEach(L.goals) { g in
                        CreamChip(label: g.name, on: pot?.id == g.id) { store.setRoundUpPot(g.id) }
                    }
                }
            }
        }
    }

    /// The latest deposits and withdrawals across every pot.
    private func recentMoves(_ L: Ledger) -> some View {
        let moves = Array(L.tx.filter { $0.type == .transfer && $0.pot != nil }.prefix(7))
        return VStack(alignment: .leading, spacing: 0) {
            Text("Recent moves").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            ForEach(moves) { t in
                EntryButton(tx: t, ledger: L, tile: .white.opacity(0.55), subColor: Palette.ink, sheet: Palette.lavender)
            }
            if moves.isEmpty { EmptyNote(text: "Deposits and withdrawals will show here.", color: Palette.ink) }
        }
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
                ("Settings", "Names, budget style, look, invite code", .settings),
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
