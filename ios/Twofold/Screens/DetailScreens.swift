import SwiftUI
import UniformTypeIdentifiers

@MainActor
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
                        Text("Across your accounts").font(.geist(13)).foregroundStyle(Palette.mute)
                        BigAmount(currency: L.money.currency, value: L.money.num(L.accountsTotal), size: 54).padding(.top, 4)
                        Text("\(L.accounts.count) account\(L.accounts.count == 1 ? "" : "s") · the full picture is under Net worth")
                            .font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
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
                    .contextMenu {
                        Button { router.form = .account(a) } label: { Label("Edit account", systemImage: "pencil") }
                        Button { router.drill(.activity(account: a.id)) } label: { Label("Entries", systemImage: "list.bullet") }
                    }
                    .accessibilityHint("Shows its entries, with Edit")
                    .padding(.bottom, 8)
                }
                if L.accounts.isEmpty {
                    EmptyNote(text: "No accounts yet. Add your current account, cash, cards and savings.", color: Palette.ink)
                }
                if !router.isWide {
                    BlockButton(title: "Add account", fill: Palette.black, outline: true) { router.form = .account(nil) }
                        .padding(.top, 4)
                }
                if !L.accounts.isEmpty {
                    Text("Tap an account for its entries and to edit it.").font(.geist(12.5)).foregroundStyle(Palette.ink).padding(.top, 10)
                }
            }
            .wideDockedAction("Add account", sheet: Palette.lavender) { router.form = .account(nil) }
        }
    }
}

@MainActor
struct BillsView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var deleting: Bill?

    var body: some View {
        if let L = store.ledger() {
            // Unfolded with Bills opened from the left: the calendar is on the left pane.
            let showCalendar = !(router.isWide && router.billsSplit && !showBack)
            let day = router.billDay
            let rows = L.billRows.filter { day == nil || $0.dueDay == day }
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
                if showCalendar { BillCalendar(L: L, hint: "Tap a day to see its bills").padding(.bottom, 10) }
                if let day {
                    Button { router.billDay = nil } label: {
                        Text("\(day) \(L.monthShort) only  ×").font(.geist(13.5, .medium)).padding(.horizontal, 14).frame(height: 44)
                            .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    .accessibilityLabel("Only bills on \(day) \(L.monthShort). Show all bills")
                }
                ForEach(rows) { b in
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
                        .accessibilityHint("Edits the bill")
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
                    .background(Palette.cream)
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contextMenu {
                        Button { router.form = .bill(b.bill) } label: { Label("Edit", systemImage: "pencil") }
                        Button { store.togglePaid(b, ym: L.ym, account: L.mainAccountId) } label: {
                            Label(b.isPaid ? "Mark unpaid" : "Mark paid", systemImage: b.isPaid ? "arrow.uturn.backward" : "checkmark")
                        }
                        Button(role: .destructive) { deleting = b.bill } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                if L.bills.isEmpty { EmptyNote(text: "No bills yet. Add the ones that come every month.").padding(.top, 8) }
                if !L.bills.isEmpty {
                    Text("Tap a bill to edit it; touch and hold to delete it.").font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 10)
                }
                if !router.isWide {
                    BlockButton(title: "Add bill", fill: Palette.black, outline: true) { router.form = .bill(nil) }.padding(.top, 16)
                }
            }
            .wideDockedAction("Add bill", sheet: Palette.cream) { router.form = .bill(nil) }
            .confirmationDialog("Delete \(deleting?.name ?? "this bill")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { b in
                Button("Delete", role: .destructive) { store.deleteBill(b.id) }
            } message: { _ in
                Text("Payments already logged stay in Activity.")
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

@MainActor
struct UsTwoView: View {
    var showBack = true
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var confirmSettle = false

    var body: some View {
        if let L = store.ledger() {
            let s = L.settleUp
            Screen(color: Palette.lavender) {
                VStack(alignment: .leading, spacing: 0) {
                    NavRow(title: "Us two", showBack: showBack)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(L.household.nameA) & \(L.household.nameB)").font(.geist(38, .medium)).tracking(em: -0.035, size: 38)
                        Text(s.split ? s.sub : "One joint pot. Everything you both add lands in the same budget.")
                            .font(.geist(14)).foregroundStyle(Palette.mute).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
                }
            } content: {
                if s.split { settleCard(s, L).padding(.bottom, 22) }
                whoPaid(s, L).padding(.top, s.split ? 0 : 4)

                Text("Income coming in").font(.geist(22, .medium)).padding(.top, 22)
                ForEach([Who.a, .b]) { w in
                    let inc = L.household.incomes.first { $0.who == w }
                    Button { router.form = .pay(w) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(L.name(w)).font(.geist(16))
                                Text(inc.map { $0.amt > 0 ? "Paid on day \($0.day) · \(Int(($0.amt / max(L.income, 1) * 100).rounded()))% of income" : "Tap to set monthly pay" } ?? "Tap to set monthly pay")
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
                    .accessibilityHint("Edits \(L.name(w))’s pay and payday")
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
                                Text("\(L.money.f(r.spent)) of \(L.money.f(r.avail)) spent").font(.geist(12.5)).foregroundStyle(Palette.ink).padding(.top, 6)
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
            .confirmationDialog(s.line + "?", isPresented: $confirmSettle, titleVisibility: .visible) {
                Button("Mark as settled") { store.setSettled(ym: L.ym, amount: s.owe) }
            } message: {
                Text("Once the money has moved between you. Shared spending after this still counts.")
            }
        }
    }

    /// Split shared costs: who owes whom this month, with Mark as settled.
    private func settleCard(_ s: SettleUp, _ L: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settle up · split \(s.rule)").font(.geist(13.5)).foregroundStyle(Palette.mute)
            Text(s.line).font(.geist(30, .medium)).tracking(em: -0.03, size: 30)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.sub).font(.geist(14)).foregroundStyle(Palette.soft).fixedSize(horizontal: false, vertical: true)
            if !s.square {
                BlockButton(title: "Mark as settled", fill: Palette.lavender, text: Palette.black, height: 52) { confirmSettle = true }
                    .padding(.top, 6)
            }
            Text(L.household.splitRule == "By income" ? "Split by income. Change it in Settings." : "Split 50/50. Change it in Settings.")
                .font(.geist(12.5)).foregroundStyle(Palette.mute).padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .foregroundStyle(Palette.white)
    }

    /// Who paid for shared things this month (pocket money left out).
    private func whoPaid(_ s: SettleUp, _ L: Ledger) -> some View {
        let colors: [Who: Color] = [.a: Palette.white, .b: Palette.black, .joint: Palette.ink.opacity(0.45)]
        let order: [Who] = [.a, .b, .joint]
        let segments: [(value: Double, color: Color)] = order.map { (value: s.paid[$0] ?? 0, color: colors[$0] ?? Palette.gray) }
        return VStack(alignment: .leading, spacing: 0) {
            Text("Who paid for shared things").font(.geist(22, .medium))
            SplitBar(segments: segments).padding(.top, 12).padding(.bottom, 4)
            ForEach(order) { w in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(colors[w] ?? Palette.gray).frame(width: 14, height: 14)
                    Text(L.name(w) + (w == .joint ? " account" : "")).font(.geist(16)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L.money.f(s.paid[w] ?? 0)).font(.geist(15, .medium))
                }
                .padding(.vertical, 11)
                .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

@MainActor
struct ActivityView: View {
    var showBack = true
    var account: String?
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var who: Who?
    @State private var acct: String?
    @State private var cat: String?
    @State private var month = DateKit.ym(Date())
    @State private var seeded = false
    /// Statement import: the file picker, then the import flow for the picked file.
    @State private var picking = false
    @State private var job: ImportJob?

    /// CSV, Excel and PDF (types the system doesn't know are left out).
    private static let statementTypes: [UTType] = {
        let types: [UTType?] = [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf,
                                UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls")]
        return types.compactMap { $0 }
    }()

    var body: some View {
        if let L = store.ledger() {
            let list = filtered(L)
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
                        HStack(spacing: 8) {
                            TextField("", text: $query, prompt: Text("Search name, note or category").foregroundColor(Palette.mute))
                                .font(.geist(15, .medium)).padding(.horizontal, 16).frame(height: 46)
                                .background(Palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Button { picking = true } label: {
                                Text("Import").font(.geist(14, .medium)).padding(.horizontal, 14).frame(height: 46)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.white.opacity(0.3), lineWidth: 1))
                                    .foregroundStyle(Palette.white)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Import statement")
                            .accessibilityHint("Adds entries from a bank statement: CSV, Excel or PDF")
                            ShareLink(item: ReportFile(name: "twofold-\(month).csv", text: L.activityCSV(list)),
                                      preview: SharePreview("Twofold entries · \(DateKit.monthLabel(month))")) {
                                Text("Export").font(.geist(14, .medium)).padding(.horizontal, 14).frame(height: 46)
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.white.opacity(0.3), lineWidth: 1))
                                    .foregroundStyle(Palette.white)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Export CSV")
                            .accessibilityHint("Shares the entries shown as a spreadsheet file")
                        }
                        chipRow {
                            Chip(label: "Everyone", on: who == nil) { who = nil }
                            ForEach(Who.allCases) { w in Chip(label: L.name(w), on: who == w) { who = w } }
                        }
                        chipRow {
                            Chip(label: "All accounts", on: acct == nil) { acct = nil }
                            ForEach(L.accounts.filter { $0.type != .invest }) { a in Chip(label: a.name, on: acct == a.id) { acct = a.id } }
                        }
                        chipRow {
                            Chip(label: "All categories", on: cat == nil) { cat = nil }
                            ForEach(L.rows) { r in Chip(label: r.name, on: cat == r.id) { cat = r.id } }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } content: {
                if let id = account, let a = L.accounts.first(where: { $0.id == id }) { accountCard(a, L).padding(.bottom, 6) }
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
                            EntryButton(tx: t, ledger: L, tile: Palette.tile, subColor: Palette.gray, sheet: Palette.cream, line: 0.12)
                        }
                    }
                    .padding(.top, 14)
                }
                if list.isEmpty {
                    EmptyNote(text: "Nothing matches.").padding(.vertical, 18)
                } else {
                    Text("Touch and hold an entry to edit or delete it.").font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 14)
                }
            }
            .onAppear { if !seeded { acct = account; seeded = true } }
            .fileImporter(isPresented: $picking, allowedContentTypes: ActivityView.statementTypes) { picked($0) }
            .fullScreenCover(item: $job) { j in
                ImportFlowView(job: j) { acctId, ym in
                    // Show what was just imported: that account, the latest month in the file.
                    acct = acctId
                    month = min(ym, L.ym)
                    seeded = true
                }
            }
        }
    }

    /// Reads the picked file (inside its security scope) and opens the import flow.
    private func picked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            if (e as? CocoaError)?.code != .userCancelled { store.error = e.localizedDescription }
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard data.count <= StmtFile.maxBytes else {
                    store.error = "That file is too big for a statement (over 40 MB)."
                    return
                }
                let next = ImportJob(name: url.lastPathComponent, data: data, account: acct ?? account)
                // Let the file picker finish closing before the import screen opens.
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    job = next
                }
            } catch {
                store.error = "That file couldn’t be opened (\(error.localizedDescription))."
            }
        }
    }

    /// This month's entries after the search and filters, newest first (as the Mac's `filtered`).
    private func filtered(_ L: Ledger) -> [Tx] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return L.tx.filter { t in
            t.month == month && (who == nil || t.who == who) && (cat == nil || t.cat == cat)
                && (acct == nil || t.acct == acct || t.to == acct)
                && (q.isEmpty || (t.name + " " + (t.note ?? "") + " " + L.categoryName(t.cat)).lowercased().contains(q))
        }
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { content() } }
    }

    /// Opened from Accounts: the account's balance with + Entry, Transfer out and Edit.
    private func accountCard(_ a: Account, _ L: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(a.type.label) · \(a.name)").font(.geist(13)).foregroundStyle(Palette.gray)
            Text(L.money.f(L.balance(a))).font(.geist(30, .medium)).tracking(em: -0.03, size: 30)
                .foregroundStyle(L.balance(a) < 0 ? Palette.overText : Palette.black).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 8) {
                BlockButton(title: "+ Entry", height: 46, radius: 16) { router.add(store, L) { $0.acct = a.id } }
                BlockButton(title: "Transfer out", fill: Palette.black, outline: true, height: 46, radius: 16) {
                    router.add(store, L) { $0.type = .transfer; $0.acct = a.id; $0.to = "" }
                }
                BlockButton(title: "Edit", fill: Palette.black, outline: true, height: 46, radius: 16) { router.form = .account(a) }
                    .accessibilityLabel("Edit \(a.name)")
            }
            .padding(.top, 12)
            BlockButton(title: "Import statement", fill: Palette.black, outline: true, height: 46, radius: 16) {
                acct = a.id
                picking = true
            }
            .accessibilityHint("Adds entries to \(a.name) from a CSV, Excel or PDF statement")
            .padding(.top, 8)
        }
        .padding(16)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

@MainActor
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
            Group {
            sectionTitle("Household", note: "Shared by both of you.").padding(.top, 4)
            FormLabel("Names").padding(.top, 12)
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
            BlockButton(title: "Save names and currency", height: 54) {
                store.updateSettings(nameA: nameA.trimmingCharacters(in: .whitespaces), nameB: nameB.trimmingCharacters(in: .whitespaces), currency: currency)
            }
            .padding(.top, 18)
            .disabled(nameA.trimmingCharacters(in: .whitespaces).isEmpty || nameB.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let h = store.household { budgeting(h).padding(.top, 30) }
            look.padding(.top, 30)

            BlockButton(title: "Sign out", fill: Palette.black, outline: true, height: 54) { session.signOut() }.padding(.top, 30)
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

    private func sectionTitle(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22).accessibilityAddTraits(.isHeader)
            Text(note).font(.geist(13)).foregroundStyle(Palette.gray)
        }
    }

    /// The Mac's Budgeting tweaks, shared through the household document. Each one
    /// applies (and syncs) as soon as it's changed.
    private func budgeting(_ h: Household) -> some View {
        let style = h.budgetStyle ?? "Zero-based"
        let rollover = h.rollover ?? false
        let cushion = h.cushion ?? 5000
        let tips = h.coachTips ?? true
        let mode = h.splitMode ?? "One joint pot"
        let rule = h.splitRule ?? "50/50"
        let money = Money(currency: h.currency)
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Budgeting", note: "Shared by both of you; changes apply straight away.")
            FormLabel("Budget style").padding(.top, 14)
            FlowLayout(spacing: 6) {
                ForEach(Household.budgetStyles, id: \.self) { v in
                    CreamChip(label: v, on: style == v) { store.updateHousehold(["budgetStyle": v]) }
                }
            }
            Text(style == "Zero-based" ? "Every bit of income gets a job: Budget shows what’s left to assign."
                 : style == "50/30/20" ? "Budget checks needs, wants and savings against 50%, 30% and 20% of income."
                 : "Just limits per category: Budget shows what’s unbudgeted.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6).fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: Binding(get: { rollover }, set: { store.updateHousehold(["rollover": $0]) })) {
                Text(rollover ? "Unspent money rolls into next month" : "Each month starts fresh").font(.geist(15))
            }
            .tint(Palette.black).padding(.top, 16)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Cash cushion").font(.geist(15))
                    Text("Plan ahead warns below this").font(.geist(12.5)).foregroundStyle(Palette.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                stepButton("−", "Less") { store.updateHousehold(["cushion": max(0, cushion - 500)]) }
                Text(money.num(cushion)).font(.geist(18, .medium)).frame(minWidth: 64).monospacedDigit()
                    .accessibilityHidden(true)
                stepButton("+", "More") { store.updateHousehold(["cushion": cushion + 500]) }
            }
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Cash cushion")
            .accessibilityValue(money.f(cushion))
            .accessibilityAdjustableAction { dir in
                if dir == .increment { store.updateHousehold(["cushion": cushion + 500]) }
                else if dir == .decrement { store.updateHousehold(["cushion": max(0, cushion - 500)]) }
            }
            Toggle(isOn: Binding(get: { tips }, set: { store.updateHousehold(["coachTips": $0]) })) {
                Text(tips ? "Coach tips on Home" : "Coach tips hidden").font(.geist(15))
            }
            .tint(Palette.black).padding(.top, 16)
            Group {
            FormLabel("How you share money").padding(.top, 16)
            HStack(spacing: 6) {
                ForEach(Household.splitModes, id: \.self) { v in
                    CreamChip(label: v, on: mode == v) { store.updateHousehold(["splitMode": v]) }
                }
            }
            if mode != "One joint pot" {
                FormLabel("Split rule").padding(.top, 14)
                HStack(spacing: 6) {
                    ForEach(Household.splitRules, id: \.self) { v in
                        CreamChip(label: v, on: rule == v) { store.updateHousehold(["splitRule": v]) }
                    }
                }
                Text("Us two shows who owes whom each month.").font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
            }
            }
        }
    }

    /// The per-phone accent (UserDefaults), like the Mac's per-Mac look.
    private var look: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Look", note: "Just on this phone.")
            FormLabel("Accent").padding(.top, 14)
            HStack(spacing: 12) {
                ForEach(Look.accents, id: \.hex) { a in
                    let on = Look.shared.accent == a.hex
                    Button { Look.shared.setAccent(a.hex) } label: {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Color(hex: a.hex))
                            .frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Palette.black, lineWidth: 2).padding(-4).opacity(on ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .accessibilityLabel("\(a.name) accent")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func stepButton(_ s: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.geist(22)).frame(width: 44, height: 44)
                .background(Palette.black, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .foregroundStyle(Palette.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
