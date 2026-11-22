import SwiftUI
import UniformTypeIdentifiers

struct AccountsView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            Screen(color: Palette.lavender, contentPadding: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Accounts", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Net worth").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(L.netWorth), size: 54).padding(.top, 4)
                        Text("Own \(L.money.f(L.assets)) · owe \(L.money.f(L.liabilities))").font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
                if L.accounts.count > 1 {
                    BlockButton(title: "Move money between accounts") { router.add(store, L) { $0.type = .transfer } }
                        .padding(.bottom, 12)
                }
                ForEach(L.accounts) { a in
                    Button { router.drill(.activity(account: a.id)) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.type.label).font(.geist(12.5)).foregroundStyle(Palette.gray)
                                Text(a.name).font(.geist(17, .medium)).lineLimit(1)
                                Text([a.bank, a.last4.map { "•• \($0)" }, L.name(a.who)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.geist(12.5)).foregroundStyle(Palette.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(L.money.f(L.balance(a))).font(.geist(19, .medium)).tracking(em: -0.02, size: 19)
                                .foregroundStyle(L.balance(a) < 0 ? Palette.overText : Palette.black).lineLimit(1).fixedSize()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Palette.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Edit account") { router.form = .account(a) } }
                    .padding(.bottom, 8)
                }
                if L.accounts.isEmpty {
                    EmptyNote(text: "No accounts yet. Add your current account, cash, cards and savings.", color: Palette.ink)
                }
                BlockButton(title: "Add account", fill: Palette.black, outline: true) { router.form = .account(nil) }
                    .padding(.top, 4)
                if !L.accounts.isEmpty {
                    Text("Touch and hold an account to edit it.").font(.geist(12.5)).foregroundStyle(Palette.ink).padding(.top, 10)
                }
            }
        }
    }
}

struct BillsView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Bills", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Still due this month").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(L.unpaidTotal), size: 54, color: Palette.lavender).padding(.top, 4)
                        Text("\(L.money.f(L.paidTotal)) paid so far · \(L.bills.count) bills").font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
                ForEach(L.billRows) { b in
                    HStack(spacing: 12) {
                        DateTile(day: b.dueDay, month: L.monthShort)
                        Button { router.form = .bill(b.bill) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.bill.name).font(.geist(16, .medium)).lineLimit(1)
                                Text("\(L.billStatus(b)) · \(L.money.f(b.bill.amt))").font(.geist(13)).foregroundStyle(Palette.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(b.isPaid ? "Paid" : "Pay") { store.togglePaid(b, ym: L.ym, account: L.mainAccountId) }
                            .font(.geist(13.5, .medium)).padding(.horizontal, 16).frame(height: 44)
                            .foregroundStyle(b.isPaid ? Palette.black : Palette.white)
                            .background(b.isPaid ? .clear : Palette.black, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                            .buttonStyle(.plain)
                            .accessibilityHint(b.isPaid ? "Marks it unpaid and removes the entry" : "Adds the expense from your main account")
                    }
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                }
                if L.bills.isEmpty { EmptyNote(text: "No bills yet. Add the ones that come every month.").padding(.top, 8) }
                BlockButton(title: "Add bill", fill: Palette.black, outline: true) { router.form = .bill(nil) }.padding(.top, 16)
            }
        }
    }
}

struct ReportsView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store

    var body: some View {
        if let L = store.ledger() {
            let wk = L.lastSevenDays
            let maxV = max(1, wk.map(\.value).max() ?? 1)
            let hi = wk.firstIndex { $0.value == maxV }
            let top = L.rows.filter { $0.spent > 0 }.sorted { $0.spent > $1.spent }.prefix(5)
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Reports", showBack: showBack)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Everyday spending, last 7 days").font(.geist(13)).foregroundStyle(Palette.mute)
                        Text(L.money.f(wk.reduce(0) { $0 + $1.value })).font(.geist(30, .medium)).tracking(em: -0.03, size: 30).padding(.top, 2)
                        HStack(alignment: .bottom, spacing: 8) {
                            ForEach(wk) { b in
                                let isHi = b.id == hi
                                VStack(spacing: 6) {
                                    Text(isHi ? L.money.f(b.value) : " ").font(.geist(12, .medium)).lineLimit(1).fixedSize()
                                        .padding(.horizontal, 8).frame(height: 26)
                                        .background(Palette.cream, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Palette.black)
                                        .opacity(isHi ? 1 : 0)
                                    GeometryReader { g in
                                        UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 5, bottomTrailingRadius: 5, topTrailingRadius: 12)
                                            .fill(isHi ? Palette.lavender : Palette.cream)
                                            .frame(height: g.size.height * max(0.05, b.value / maxV))
                                            .frame(maxHeight: .infinity, alignment: .bottom)
                                    }
                                    Text(b.label).font(.geist(12.5)).foregroundStyle(Palette.soft)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(b.label): \(L.money.f(b.value))")
                            }
                        }
                        .frame(height: 200).padding(.top, 10)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            } content: {
                Text("Where it went").font(.geist(22, .medium)).padding(.top, 4)
                ForEach(top) { r in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .lastTextBaseline) {
                            Text(r.name).font(.geist(16))
                            Spacer()
                            Text("\(Int((r.spent / max(L.totalSpent, 1) * 100).rounded()))%").font(.geist(26)).tracking(em: -0.02, size: 26)
                        }
                        ProgressLine(ratio: r.spent / max(top.first?.spent ?? 1, 1)).padding(.top, 8)
                        Text("\(L.money.f(r.spent)) this month").font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 6)
                    }
                    .padding(.top, 12).padding(.bottom, 2)
                }
                if top.isEmpty { EmptyNote(text: "No spending recorded this month yet.").padding(.vertical, 2) }
                Text("Who spent").font(.geist(22, .medium)).padding(.top, 22)
                ForEach([Who.a, .b, .joint]) { w in
                    HStack(spacing: 12) {
                        Text(String(L.name(w).prefix(1))).font(.geist(14, .semibold)).frame(width: 36, height: 36)
                            .background(w == .a ? Palette.lavender : w == .b ? Palette.black : Palette.tile, in: Circle())
                            .foregroundStyle(w == .b ? Palette.white : Palette.black)
                        Text(L.name(w)).font(.geist(16)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L.money.f(L.spent(by: w))).font(.geist(15, .medium))
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                }
                ShareLink(item: ReportFile(name: L.reportFileName, text: L.reportCSV),
                          preview: SharePreview("Twofold report · \(DateKit.monthLabel(L.ym))")) {
                    Text("↓ Download this month’s report").font(.geist(15, .medium)).frame(maxWidth: .infinity).frame(height: 52)
                        .background(Palette.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(Palette.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
        }
    }
}

/// This month's report as a CSV file for the share sheet (Save to Files, Mail, …).
struct ReportFile: Transferable {
    var name: String
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { (file: ReportFile) in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

struct UsTwoView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            Screen(color: Palette.lavender) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Us two", showBack: showBack)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(L.household.nameA) & \(L.household.nameB)").font(.geist(38, .medium)).tracking(em: -0.035, size: 38)
                        Text("One joint pot. Everything you both add lands in the same budget.").font(.geist(14)).foregroundStyle(Palette.mute)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
                Text("Income coming in").font(.geist(22, .medium)).padding(.top, 4)
                ForEach([Who.a, .b]) { w in
                    let inc = L.household.incomes.first { $0.who == w }
                    Button { router.form = .pay(w) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(L.name(w)).font(.geist(16))
                                Text(inc.map { $0.amt > 0 ? "Paid on day \($0.day)" : "Tap to set monthly pay" } ?? "Tap to set monthly pay")
                                    .font(.geist(12.5)).foregroundStyle(Palette.ink)
                            }
                            Spacer()
                            Text(L.money.f(inc?.amt ?? 0)).font(.geist(18, .medium))
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Pocket money").font(.geist(22, .medium)).padding(.top, 22)
                ForEach(["allowA", "allowB"], id: \.self) { id in
                    if let r = L.rows.first(where: { $0.id == id }) {
                        Button { router.form = .budget(id) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .lastTextBaseline) {
                                    Text(id == "allowA" ? L.household.nameA : L.household.nameB).font(.geist(16))
                                    Spacer()
                                    Text(r.left < 0 ? "\(L.money.f(-r.left)) over" : "\(L.money.f(r.left)) left").font(.geist(22)).tracking(em: -0.02, size: 22)
                                }
                                ProgressLine(ratio: r.ratio, fill: Palette.white).padding(.top, 8)
                                Text("\(L.money.f(r.spent)) of \(L.money.f(r.limit)) spent").font(.geist(12.5)).foregroundStyle(Palette.ink).padding(.top, 6)
                            }
                            .padding(.top, 12).padding(.bottom, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Money date").font(.geist(22, .medium)).padding(.top, 22)
                let done = Catalog.moneyDateChecks.indices.filter { L.household.checks["\(L.ym):\($0)"] ?? false }.count
                Text("\(done) of \(Catalog.moneyDateChecks.count) done this month").font(.geist(13)).foregroundStyle(Palette.ink).padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(Catalog.moneyDateChecks.enumerated()), id: \.offset) { k, t in
                        let key = "\(L.ym):\(k)"
                        let on = L.household.checks[key] ?? false
                        Button { store.toggleCheck(key) } label: {
                            HStack(spacing: 12) {
                                Text(on ? "✓" : "").font(.geist(14, .semibold)).frame(width: 24, height: 24)
                                    .background(on ? Palette.black : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.black, lineWidth: 1.5))
                                    .foregroundStyle(Palette.white)
                                Text(t).font(.geist(15)).strikethrough(on).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(minHeight: 52)
                            .overlay(alignment: .bottom) { if k < Catalog.moneyDateChecks.count - 1 { Hairline(opacity: 0.1) } }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct ActivityView: View {
    var showBack = true
    var account: String?
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var who: Who?
    @State private var acct: String?
    @State private var month = DateKit.ym(Date())
    @State private var seeded = false

    var body: some View {
        if let L = store.ledger() {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            let list = L.tx.filter { t in
                t.month == month && (who == nil || t.who == who) && (acct == nil || t.acct == acct || t.to == acct)
                    && (q.isEmpty || (t.name + " " + L.categoryName(t.cat)).lowercased().contains(q))
            }
            let groups = Dictionary(grouping: list, by: \.date).sorted { $0.key > $1.key }
            Screen(color: Palette.cream, mirrored: true) {
                VStack(alignment: .leading, spacing: 10) {
                    NavRow(title: "Activity", showBack: showBack)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("←") { month = DateKit.addMonths(month, -1) }.frame(width: 44, height: 44).accessibilityLabel("Previous month")
                            Text(DateKit.monthLabel(month)).font(.geist(16, .medium)).frame(maxWidth: .infinity)
                            Button("→") { month = DateKit.addMonths(month, 1) }.frame(width: 44, height: 44)
                                .disabled(month >= L.ym).opacity(month >= L.ym ? 0.3 : 1).accessibilityLabel("Next month")
                        }
                        .font(.geist(20))
                        TextField("", text: $query, prompt: Text("Search").foregroundColor(Palette.mute))
                            .font(.geist(15, .medium)).padding(.horizontal, 16).frame(height: 46)
                            .background(Palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Chip(label: "Everyone", on: who == nil) { who = nil }
                                ForEach(Who.allCases) { w in Chip(label: L.name(w), on: who == w) { who = w } }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } content: {
                if let acct {
                    Button { self.acct = nil } label: {
                        Text("\(L.accountName(acct)) only  ×").font(.geist(13.5, .medium)).padding(.horizontal, 14).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                ForEach(groups, id: \.key) { g in
                    let net = g.value.reduce(0.0) { $0 + ($1.type == .income ? $1.amt : $1.type == .expense ? -$1.amt : 0) }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(DateKit.dayLabel(g.key))
                            Spacer()
                            Text((net > 0 ? "+" : "") + L.money.f(net))
                        }
                        .font(.geist(13)).foregroundStyle(Palette.gray)
                        ForEach(g.value) { t in
                            Button { router.edit(t) } label: {
                                TxRow(tx: t, ledger: L, tile: Palette.tile, subColor: Palette.gray, line: 0.12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 14)
                }
                if list.isEmpty { EmptyNote(text: "Nothing matches.").padding(.vertical, 18) }
            }
            .onAppear { if !seeded { acct = account; seeded = true } }
        }
    }
}

struct SettingsView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Session.self) private var session
    @State private var nameA = ""
    @State private var nameB = ""
    @State private var currency = "AED"
    @State private var loaded = false
    @State private var confirmLeave = false

    var body: some View {
        Screen(color: Palette.cream, mirrored: true) {
            VStack(alignment: .leading, spacing: 0) {
                NavRow(title: "Settings", showBack: showBack)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite code").font(.geist(13)).foregroundStyle(Palette.mute)
                    HStack {
                        Text(store.householdId).font(.geist(34, .medium)).tracking(4).textSelection(.enabled)
                        Spacer()
                        ShareLink(item: "Join our budget on Twofold with this code: \(store.householdId)") {
                            Text("Share").font(.geist(14, .medium)).padding(.horizontal, 16).frame(height: 44)
                                .background(Palette.lavender, in: Capsule()).foregroundStyle(Palette.black)
                        }
                    }
                    Text(store.partnerJoined ? "You’re both in. Everything syncs between your phones." : "Your partner joins with this code.")
                        .font(.geist(14)).foregroundStyle(Palette.mute)
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
            }
        } content: {
            FormLabel("Names").padding(.top, 8)
            CreamField(placeholder: "Partner who started the budget", text: $nameA)
            CreamField(placeholder: "Partner who joined", text: $nameB).padding(.top, 8)
            FormLabel("Currency").padding(.top, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Catalog.currencies, id: \.self) { c in
                        CreamChip(label: c, on: currency == c) { currency = c }
                    }
                }
            }
            BlockButton(title: "Save", height: 54) {
                store.updateSettings(nameA: nameA.trimmingCharacters(in: .whitespaces), nameB: nameB.trimmingCharacters(in: .whitespaces), currency: currency)
            }
            .padding(.top, 18)
            .disabled(nameA.isEmpty || nameB.isEmpty)
            BlockButton(title: "Sign out", fill: Palette.black, outline: true, height: 54) { session.signOut() }.padding(.top, 24)
            Button("Leave this budget") { confirmLeave = true }
                .font(.geist(14, .medium)).foregroundStyle(Palette.overText).frame(minHeight: 44).padding(.top, 8)
                .confirmationDialog("Leave this budget on this phone?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Leave", role: .destructive) { Task { await session.leaveHousehold(uid: store.uid) } }
                } message: {
                    Text("Nothing is deleted. You can join again with the invite code.")
                }
        }
        .onAppear {
            guard !loaded, let h = store.household else { return }
            nameA = h.nameA; nameB = h.nameB; currency = h.currency; loaded = true
        }
    }
}
