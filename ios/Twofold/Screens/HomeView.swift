import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() { content(L) }
    }

    private func content(_ L: Ledger) -> some View {
        let me = store.me, other: Who = me == .a ? .b : .a
        let safe = L.safeToSpend
        let syncNote: String = store.syncing ? " · syncing…" : ""
        let greetingSub: String = "You & \(L.name(other)) · \(L.monthName)\(syncNote)"
        let perDay: String = "About \(L.money.f(safe / Double(L.daysLeft))) a day for \(L.daysLeft) days, bills covered"
        let safeNote: String = safe > 0 ? perDay
            : (L.totalLimit > 0 ? "Budgets are used up for now — bills are still covered" : "Give your categories a limit to see what’s safe to spend")
        return Screen(color: Palette.lavender) {
            HStack(spacing: 12) {
                Text(String(L.name(me).prefix(1))).font(.geist(19, .semibold))
                    .frame(width: 46, height: 46)
                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .foregroundStyle(Palette.black)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Hi, \(L.name(me))").font(.geist(20, .medium)).tracking(em: -0.01, size: 20)
                    Text(greetingSub)
                        .font(.geist(13)).foregroundStyle(Palette.mute)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { router.open(.us) } label: {
                    HStack(spacing: -9) {
                        avatar(L.name(me), Palette.lavender)
                        avatar(L.name(other), Palette.cream)
                    }
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Us two")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 4)
        } content: {
            if !store.partnerJoined { InviteCard(name: L.name(other), code: store.householdId).padding(.bottom, 14) }
            if !L.setupDone { StartHere(L: L).padding(.bottom, 18) }

            Group {
            Text("Safe to spend this month").font(.geist(13)).foregroundStyle(Palette.ink)
            BigAmount(currency: L.money.currency, value: L.money.num(safe), color: Palette.black, currencyColor: Palette.ink)
                .padding(.top, 2)
            Text(safeNote)
                .font(.geist(13)).foregroundStyle(Palette.ink).padding(.top, 10)
            ProgressLine(ratio: L.totalSpent / max(L.totalAvail, 1), fill: Palette.black, track: Palette.black.opacity(0.16), height: 6)
                .padding(.top, 14)
            HStack {
                Text("Spent \(L.money.f(L.totalSpent))")
                Spacer()
                Text("of \(L.money.f(L.totalAvail))")
            }
            .font(.geist(12)).foregroundStyle(Palette.ink).padding(.top, 6)
            Hairline(opacity: 0.2).padding(.vertical, 18)
            }

            HStack(spacing: 8) {
                quick("↓", "Income") { router.add(store, L) { $0.type = .income; $0.cat = "income" } }
                quick("↗", "Move") { router.add(store, L) { $0.type = .transfer } }
                quick("+", "Spend") { router.add(store, L) }
                Button { router.open(.reports) } label: {
                    Text("Reports").font(.geist(15, .medium)).frame(maxWidth: .infinity).frame(height: 66)
                        .background(Palette.black, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .foregroundStyle(Palette.white)
                }
                .buttonStyle(.plain)
            }

            if L.household.coachTips ?? true {
                let tips = L.coachTips
                if !tips.isEmpty { CoachTips(tips: tips).padding(.top, 18) }
            }
            if L.settleUp.split { BetweenYou(s: L.settleUp).padding(.top, 14) }

            Group {
            SectionTitle(title: "Coming up", action: (label: "All bills →", run: { router.open(.bills) })).padding(.top, 26)
            ForEach(L.unpaidBills.prefix(2)) { b in
                HStack(spacing: 12) {
                    DateTile(day: b.dueDay, month: L.monthShort)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.bill.name).font(.geist(16, .medium)).lineLimit(1)
                        Text("\(L.billStatus(b)) · \(L.money.f(b.bill.amt))").font(.geist(13)).foregroundStyle(Palette.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Pay") { store.togglePaid(b, ym: L.ym, account: L.mainAccountId) }
                        .font(.geist(13.5, .medium)).padding(.horizontal, 16).frame(height: 44)
                        .background(Palette.black, in: Capsule()).foregroundStyle(Palette.white)
                        .buttonStyle(.plain)
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Hairline() }
            }
            if L.unpaidBills.isEmpty {
                EmptyNote(text: L.bills.isEmpty ? "No bills yet. Add rent, school fees and subscriptions in Bills." : "Every bill for this month is paid.",
                          color: Palette.ink)
            }

            SectionTitle(title: "Transactions", action: (label: "See all →", run: { router.open(.activity(account: nil)) })).padding(.top, 22)
            ForEach(L.monthTx.prefix(6)) { t in
                EntryButton(tx: t, ledger: L, tile: .white.opacity(0.55), subColor: Palette.ink, sheet: Palette.lavender)
            }
            if L.monthTx.isEmpty { EmptyNote(text: "Nothing yet this month. Tap + to add the first one.", color: Palette.ink) }
            }
        }
    }

    private func avatar(_ name: String, _ bg: Color) -> some View {
        Text(String(name.prefix(1))).font(.geist(13, .semibold))
            .frame(width: 32, height: 32).background(bg, in: Circle()).foregroundStyle(Palette.black)
            .overlay(Circle().strokeBorder(Palette.black, lineWidth: 2))
    }

    private func quick(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(icon).font(.geist(22))
                Text(label).font(.geist(11, .medium))
            }
            .frame(width: 66, height: 66)
            .background(Palette.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .foregroundStyle(Palette.black)
        }
        .buttonStyle(.plain)
    }
}

/// Up to three tips from the numbers (Settings → Coach tips; a port of the Mac's Today tips).
private struct CoachTips: View {
    var tips: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tips.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(DateKit.pad(i + 1)).font(.geist(12.5, .medium)).foregroundStyle(Palette.lavender)
                    Text(t).font(.geist(14.5)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { if i < tips.count - 1 { Rectangle().fill(Palette.white.opacity(0.12)).frame(height: 1) } }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tip \(i + 1): \(t)")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 2)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Palette.white)
    }
}

/// Split shared costs: who owes whom this month, with a way to settle up on Us two.
@MainActor
private struct BetweenYou: View {
    var s: SettleUp
    @Environment(Router.self) private var router
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Between you two").font(.geist(13.5)).foregroundStyle(Palette.mute)
            Text(s.line).font(.geist(26, .medium)).tracking(em: -0.02, size: 26).fixedSize(horizontal: false, vertical: true)
            Text(s.sub).font(.geist(13.5)).foregroundStyle(Palette.soft).fixedSize(horizontal: false, vertical: true)
            Button { router.open(.us) } label: {
                Text("Open settle-up").font(.geist(14.5, .medium)).padding(.horizontal, 18).frame(height: 46)
                    .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Palette.black)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Palette.white)
    }
}

/// Shown until the partner has joined.
private struct InviteCard: View {
    var name: String
    var code: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invite \(name)").font(.geist(18, .medium))
            Text("They install Twofold, create an account and choose “Join with a code”.")
                .font(.geist(13.5)).foregroundStyle(Palette.mute).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(code).font(.geist(26, .medium)).tracking(4).textSelection(.enabled)
                Spacer()
                ShareLink(item: "Join our budget on Twofold with this code: \(code)") {
                    Text("Share").font(.geist(14, .medium)).padding(.horizontal, 16).frame(height: 44)
                        .background(Palette.lavender, in: Capsule()).foregroundStyle(Palette.black)
                }
            }
        }
        .padding(16)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Palette.white)
    }
}

/// The empty-start checklist; each step ticks itself off.
@MainActor
private struct StartHere: View {
    var L: Ledger
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Start here").font(.geist(18, .medium))
            Text("\(L.setupSteps.filter(\.done).count) of \(L.setupSteps.count) done").font(.geist(13)).foregroundStyle(Palette.ink)
                .padding(.bottom, 4)
            ForEach(Array(L.setupSteps.enumerated()), id: \.offset) { i, s in
                Button { go(i) } label: {
                    HStack(spacing: 12) {
                        Text(s.done ? "✓" : "").font(.geist(14, .semibold)).frame(width: 24, height: 24)
                            .background(s.done ? Palette.black : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.black, lineWidth: 1.5))
                            .foregroundStyle(Palette.white)
                        Text(s.title).font(.geist(15)).strikethrough(s.done).frame(maxWidth: .infinity, alignment: .leading)
                        Text("→").font(.geist(18)).opacity(s.done ? 0 : 1)
                    }
                    .frame(minHeight: 50)
                    .overlay(alignment: .bottom) { if i < L.setupSteps.count - 1 { Hairline(opacity: 0.1) } }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func go(_ i: Int) {
        switch i {
        case 0: router.form = .account(nil)
        case 1: router.form = .pay(store.me)
        case 2: router.select(.budget)
        default:
            if L.accounts.isEmpty { router.form = .account(nil) } else { router.add(store, L) }
        }
    }
}
