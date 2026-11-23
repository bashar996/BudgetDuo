import SwiftUI

// Card installment plans (Easy Payment Plan, Flexi installments): the row under a card, the
// plan's own screen and its form. The Mac's panels/PlanPanel.tsx and PlanForm.tsx; the maths is
// in Loans.swift ("Card installment plans") and the billing in HouseholdStore.billPlans.

/// "1st", "2nd", "3rd", "4th", "11th", "21st" …
func ordinal(_ n: Int) -> String {
    let t = n % 100
    if t >= 11 && t <= 13 { return "\(n)th" }
    switch n % 10 {
    case 1: return "\(n)st"
    case 2: return "\(n)nd"
    case 3: return "\(n)rd"
    default: return "\(n)th"
    }
}

/// "0% · interest-free" or the loan wording ("3.5% flat ≈ 6.6% reducing").
func planRateText(_ st: LoanState) -> String {
    st.rate > 0 ? rateText(st) : "0% · interest-free"
}

/// The category a plan's installments go in: its own, else Shopping (or the first one left).
func planCategory(_ p: Debt, _ L: Ledger) -> String {
    let c = (p.cat ?? "").isEmpty ? "shopping" : (p.cat ?? "shopping")
    return L.catOr(c)
}

/// "4 of 12 · AED 400/month · ends Jul 2027", "Closed early" or "All 12 billed".
func planMeta(_ ps: PlanState, _ money: Money) -> String {
    if ps.closed { return "Closed early" }
    if ps.done { return "All \(ps.term) billed" }
    let ends: String = ps.endsYm.map { DateKit.monthLabel($0, short: true) } ?? "—"
    return "\(ps.billed) of \(ps.term) · \(money.f(ps.st.installment))/month · ends \(ends)"
}

// MARK: Plan row (under its card)

/// A plan under its card: name, "4 of 12 · AED 400/month · ends Jul 2027", what's still to be
/// billed and a thin progress line. Opens the plan.
@MainActor
struct PlanRowButton: View {
    var plan: Debt
    var ledger: Ledger
    var line: Double = 0.1
    @Environment(Router.self) private var router

    var body: some View {
        let ps = ledger.planState(plan)
        let ratio: Double = ps.closed ? 1 : Double(ps.billed) / Double(max(ps.term, 1))
        Button { router.drill(.loan(plan.id)) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.name).font(.geist(15, .medium)).lineLimit(1)
                        Text(planMeta(ps, ledger.money)).font(.geist(12.5)).foregroundStyle(Palette.gray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !ps.done {
                        Text(ledger.money.f(ps.remaining)).font(.geist(14.5, .medium)).lineLimit(1).fixedSize()
                    }
                }
                ProgressLine(ratio: ratio, fill: Palette.lavender, track: Palette.black.opacity(0.1), height: 3)
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Hairline(opacity: line) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the installment plan")
    }
}

// MARK: Plan detail (pushed: Route.loan with a plan's id)

/// One card installment plan: what's still to be billed, the next installment Twofold will post
/// on the card, close early, edit and delete, the summary, the entries posted on the card and the
/// schedule. There's no Pay button: each installment bills itself (HouseholdStore.billPlans).
@MainActor
struct PlanDetailView: View {
    var plan: Debt
    var ledger: Ledger
    var showBack = true
    /// Schedule row height; grows with the text size so rows aren't clipped.
    @ScaledMetric(relativeTo: .body) private var scheduleRowHeight: CGFloat = 60
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var confirmClose = false
    @State private var confirmDelete = false

    private struct SummaryRow {
        let k: String
        let v: String
        let sub: String?
    }

    var body: some View {
        let L = ledger
        let d = plan
        let ps = L.planState(d)
        let card = L.accountName(d.acct)
        let settle: String = L.money.f(ps.settlement)
        Screen(color: Palette.cream, mirrored: true) {
            hero(d, ps, L, card)
        } content: {
            if let next = ps.next { nextCard(d, next, ps, L, card) }
            actions(d, ps, L).padding(.top, ps.next == nil ? 4 : 16)
            summary(d, ps, L).padding(.top, 24)
            postedSection(d, ps, L, card).padding(.top, 24)
            scheduleSection(ps, L).padding(.top, 24)
        }
        .confirmationDialog("Close \(d.name) early?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Post \(settle) on \(card)") { _ = store.closePlan(d) }
        } message: {
            Text(closeMessage(d, ps, L, card))
        }
        .confirmationDialog("Delete \(d.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete plan", role: .destructive) { store.deleteLoan(d) }
        } message: {
            Text(deleteMessage(d, L, card))
        }
    }

    // MARK: Hero

    private func hero(_ d: Debt, _ ps: PlanState, _ L: Ledger, _ card: String) -> some View {
        let label: String = ps.closed ? "Closed early" : ps.done ? "All billed" : "Still to be billed"
        let ratio: Double = ps.closed ? 1 : Double(ps.billed) / Double(max(ps.term, 1))
        let meta: String = "Installment plan on \(card) · \(termText(ps.term))"
        let progress: String = "\(ps.billed) of \(ps.term) billed · \(L.money.f(ps.st.principal)) in all"
        return VStack(alignment: .leading, spacing: 0) {
            NavRow(title: d.name, showBack: showBack)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.geist(13)).foregroundStyle(Palette.mute)
                BigAmount(currency: L.money.currency, value: L.money.num(ps.remaining), size: 54, color: Palette.lavender).padding(.top, 4)
                Text(meta).font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressLine(ratio: ratio, fill: Palette.lavender, track: Palette.white.opacity(0.16), height: 6).padding(.top, 14)
                Text(progress).font(.geist(12.5)).foregroundStyle(Palette.soft).padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
        }
    }

    // MARK: Next installment and actions

    private func nextCard(_ d: Debt, _ next: PlanInstallment, _ ps: PlanState, _ L: Ledger, _ card: String) -> some View {
        let day = Int(next.date.suffix(2)) ?? 1
        let catName = L.categoryName(planCategory(d, L))
        let title: String = "Next: \(L.money.f(next.amt)) on \(DateKit.dateLabel(next.date))"
        let note: String = "Twofold posts it on \(card) on the \(ordinal(day)), under \(catName), so each month’s budget counts one installment."
        return VStack(alignment: .leading, spacing: 6) {
            Text("Installment \(next.n) of \(ps.term)").font(.geist(13)).foregroundStyle(Palette.gray)
            Text(title).font(.geist(19, .medium)).fixedSize(horizontal: false, vertical: true)
            Text(note).font(.geist(13)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func actions(_ d: Debt, _ ps: PlanState, _ L: Ledger) -> some View {
        let fee = d.fee ?? 0
        let closeLine: String = "Close early: everything left goes on the card at once, \(L.money.f(ps.settlement))"
            + (fee > 0 ? ", fee included." : ".")
        VStack(alignment: .leading, spacing: 8) {
            if ps.done {
                Text(ps.closed ? "Closed early. Nothing more is billed." : "Every installment is billed. Nothing more to post.")
                    .font(.geist(15, .medium)).padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(closeLine).font(.geist(13.5)).foregroundStyle(Palette.gray)
                    .fixedSize(horizontal: false, vertical: true)
                BlockButton(title: "Close early", fill: Palette.black, outline: true, height: 50, radius: 16) { confirmClose = true }
                    .accessibilityHint("Asks before posting what’s left on the card")
            }
            HStack(spacing: 8) {
                BlockButton(title: "Edit", fill: Palette.black, outline: true, height: 46, radius: 16) { router.form = .cardPlan(d, nil) }
                BlockButton(title: "Delete", fill: Palette.bad, outline: true, height: 46, radius: 16) { confirmDelete = true }
            }
            .padding(.top, 4)
        }
    }

    private func closeMessage(_ d: Debt, _ ps: PlanState, _ L: Ledger, _ card: String) -> String {
        let fee = d.fee ?? 0
        let what: String = fee > 0 ? "the \(L.money.f(ps.remaining)) still to be billed plus a \(pctText(fee))% early-closure fee"
            : "the \(L.money.f(ps.remaining)) still to be billed"
        return "Posts \(L.money.f(ps.settlement)) on \(card) now (\(what)) and stops the installments."
    }

    private func deleteMessage(_ d: Debt, _ L: Ledger, _ card: String) -> String {
        let n = L.loanPayments(d).count
        let entries: String = n == 1 ? "Its 1 entry stays" : "Its \(n) entries stay"
        return "\(entries) on \(card) as ordinary expenses, and nothing more is billed."
    }

    // MARK: Summary

    private func summary(_ d: Debt, _ ps: PlanState, _ L: Ledger) -> some View {
        let st = ps.st
        let m = L.money
        let startYm: String? = st.schedule.first.map { String($0.date.prefix(7)) }
        let catName = L.categoryName(planCategory(d, L))
        let fee = d.fee ?? 0
        let procFee = d.procFee ?? 0
        var runs: String?
        if let s = startYm, let e = ps.endsYm {
            runs = DateKit.monthLabel(s, short: true) + " → " + DateKit.monthLabel(e, short: true)
        }
        let first: String? = startYm.map { "first installment " + DateKit.monthLabel($0, short: true) }
        var rows: [SummaryRow] = [
            SummaryRow(k: "Bought for", v: m.f(st.principal), sub: first),
            SummaryRow(k: "Still to be billed", v: m.f(ps.remaining), sub: ps.done ? nil : "held against the card’s limit"),
            SummaryRow(k: "Installment", v: "\(m.f(st.installment)) / month", sub: catName),
            SummaryRow(k: "Rate", v: planRateText(st), sub: nil),
            SummaryRow(k: "Term", v: termText(ps.term), sub: runs),
        ]
        if st.totalInterest > 0.005 {
            rows.append(SummaryRow(k: "Interest", v: m.f(st.totalInterest), sub: "over the whole plan"))
        }
        if procFee > 0 {
            rows.append(SummaryRow(k: "Processing fee", v: m.f(procFee), sub: "posted once, when the plan was added"))
        }
        if !ps.done {
            let feeNote: String = fee > 0 ? "includes a \(pctText(fee))% early-closure fee" : "no early-closure fee"
            rows.append(SummaryRow(k: "Close today", v: m.f(ps.settlement), sub: feeNote))
        }
        let list = rows
        return VStack(alignment: .leading, spacing: 0) {
            Text("Summary").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { k, r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(r.k).font(.geist(14)).foregroundStyle(Palette.gray)
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(r.v).font(.geist(14.5, .medium)).multilineTextAlignment(.trailing)
                            if let sub = r.sub {
                                Text(sub).font(.geist(12)).foregroundStyle(Palette.gray).multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) { if k < list.count - 1 { Hairline(opacity: 0.08) } }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 2)
            .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.top, 10)
        }
    }

    // MARK: Posted on the card

    private func postedSection(_ d: Debt, _ ps: PlanState, _ L: Ledger, _ card: String) -> some View {
        let list = L.loanPayments(d)
        let total: Double = list.reduce(0.0) { $0 + $1.amt }
        let before = d.paidBefore ?? 0
        let postedHere = list.filter { ($0.debtPart ?? "installment") == "installment" }.count
        var foot: String = before > 0 ? "Plus \(before) billed before the plan was added. " : ""
        if ps.billed - before > postedHere { foot += "A deleted installment isn’t posted again." }
        let note = foot
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Posted on \(card)").font(.geist(22, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                if !list.isEmpty {
                    Text(L.money.f(total)).font(.geist(13)).foregroundStyle(Palette.gray).lineLimit(1).fixedSize()
                }
            }
            ForEach(list) { t in
                EntryButton(tx: t, ledger: L, tile: Palette.tile, subColor: Palette.gray, sheet: Palette.cream, line: 0.12)
            }
            if list.isEmpty {
                EmptyNote(text: "Nothing posted yet. Each installment is posted on the card on its date.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.isEmpty {
                Text(note).font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Schedule

    /// The schedule as agreed: rows up to `billed` ticked (none overdue: they bill themselves),
    /// the next one highlighted.
    private func scheduleSection(_ ps: PlanState, _ L: Ledger) -> some View {
        let rows = ps.st.schedule
        let rowHeight: CGFloat = scheduleRowHeight
        let billed = ps.billed
        let next: Int? = ps.done ? nil : rows.first(where: { $0.n > billed })?.n
        let foot: String = "In \(L.money.currency). Ticked rows are billed on the card" + (ps.closed ? "; the plan was closed early." : ".")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Installments").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
                Spacer()
                Text("\(rows.count) installment\(rows.count == 1 ? "" : "s") · ✓ billed").font(.geist(13)).foregroundStyle(Palette.gray)
            }
            if rows.isEmpty {
                EmptyNote(text: "Nothing to schedule.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { r in
                                scheduleRow(r, paid: r.n <= billed, isNext: r.n == next, L).frame(height: rowHeight).id(r.n)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(rows.count) * rowHeight, 420))
                    .onAppear {
                        if let next { proxy.scrollTo(max(1, next - 1), anchor: .top) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.top, 10)
            }
            Text(foot).font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func scheduleRow(_ r: ScheduleRow, paid: Bool, isNext: Bool, _ L: Ledger) -> some View {
        HStack(spacing: 10) {
            Text(paid ? "✓" : "\(r.n)").font(.geist(13, .semibold)).frame(width: 34, height: 34)
                .background(paid ? Palette.black : isNext ? Palette.lavender : Palette.tile,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(paid ? Palette.white : Palette.black)
            VStack(alignment: .leading, spacing: 1) {
                Text(DateKit.dateLabel(r.date) + (isNext ? " · next" : "")).font(.geist(14, .medium)).lineLimit(1)
                Text("Interest \(L.money.f(r.interest)) · principal \(L.money.f(r.principal))")
                    .font(.geist(12)).foregroundStyle(Palette.gray).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(L.money.f(r.payment)).font(.geist(14, .medium))
                Text("Left \(L.money.f(r.balance))").font(.geist(12)).foregroundStyle(Palette.gray)
            }
            .lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
        .background(isNext ? Palette.lavender.opacity(0.35) : Color.clear)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.08) }
        .opacity(paid ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(paid ? "Billed" : isNext ? "Next" : ""))
    }
}

// MARK: Plan form

/// New / edit card installment plan: what was bought, on which card, the amount, months and
/// rate, the processing fee, how many were billed before, the date of the next one, the
/// category and the early-closure fee. The live box at the end shows the installment, interest
/// and end date, and what Twofold will post on the card straight away.
@MainActor
struct PlanForm: View {
    var editing: Debt?
    /// The card a new plan starts on.
    var card: String?
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var name = ""
    @State private var acct = ""
    @State private var principal = ""
    @State private var months = ""
    @State private var rate = ""
    @State private var rateType = "flat"
    @State private var procFee = ""
    @State private var paidBefore = ""
    /// As in the loan form, the date asked for is the first installment Twofold posts.
    @State private var due = Date()
    @State private var cat = ""
    @State private var fee = ""
    @State private var loaded = false

    /// JS `Math.round(n * 100) / 100`.
    private static func cents(_ n: Double) -> Double { (n * 100 + 0.5).rounded(.down) / 100 }

    /// The whole number typed (digits only).
    private static func digits(_ s: String) -> Int {
        let only: String = s.filter { $0.isASCII && $0.isNumber }
        return Int(only) ?? 0
    }

    private var term: Int { Self.digits(months) }

    /// Installments already billed before Twofold (never more than the term).
    private var paidN: Int {
        let n = Self.digits(paidBefore)
        return term > 0 ? min(n, term) : n
    }

    private var ready: Bool { (parseAmount(principal) ?? 0) > 0 && term > 0 }

    var body: some View {
        let L = store.ledger()
        let cur = L?.money.currency ?? ""
        let cards: [Account] = (L?.accounts ?? []).filter { $0.type == .card }
        let d = draft()
        let issue = problem(cards)
        FormSheetFrame(kicker: editing == nil ? "New installment plan" : "Edit installment plan",
                       title: name.isEmpty ? "Installment plan" : name,
                       canSave: issue == nil, onSave: save,
                       onDelete: editing.map { p in { store.deleteLoan(p) } },
                       deleteMessage: "What’s been posted stays on the card as ordinary expenses, and nothing more is billed.") {
            Group {
                Text("A purchase your bank split into monthly installments on the card. Each installment is posted on the card in its month, so your budget counts it then, not the full price at once.")
                    .font(.geist(13.5)).fixedSize(horizontal: false, vertical: true).padding(.bottom, 14)
                FormLabel("What you bought")
                CreamField(placeholder: "e.g. Phone", text: $name)
                FormLabel("Card").padding(.top, 16)
                if cards.isEmpty {
                    Text("Add the credit card under Accounts first.").font(.geist(13.5)).foregroundStyle(Palette.overText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(cards) { a in CreamChip(label: a.name, on: acct == a.id) { acct = a.id } }
                    }
                }
            }

            Group {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Amount (\(cur))")
                        CreamField(placeholder: "0", text: $principal, keyboard: .decimalPad)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Months")
                        CreamField(placeholder: "e.g. 12", text: $months, keyboard: .numberPad)
                    }
                }
                .padding(.top, 16)
                FormLabel("Rate (% a year)").padding(.top, 16)
                CreamField(placeholder: "0", text: $rate, keyboard: .decimalPad)
                HStack(spacing: 6) {
                    CreamChip(label: "Flat", on: rateType == "flat") { rateType = "flat" }
                    CreamChip(label: "Reducing", on: rateType == "reducing") { rateType = "reducing" }
                }
                .padding(.top, 8)
                Text("Most plans are 0%. With a rate, flat charges it on the full amount for every month, reducing only on what’s left.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                FormLabel("Processing fee (\(cur), optional)").padding(.top, 16)
                CreamField(placeholder: "0", text: $procFee, keyboard: .decimalPad)
                FormLabel("Installments already billed").padding(.top, 16)
                CreamField(placeholder: "0", text: $paidBefore, keyboard: .numberPad)
                // The date asked for is installment (already billed + 1): the next one, posted by Twofold.
                DatePicker(selection: $due, displayedComponents: .date) {
                    Text(paidN > 0 ? "Installment \(paidN + 1) due (your next)" : "First installment due").font(.geist(15))
                }
                .environment(\.colorScheme, .light)
                .tint(Palette.black)
                .frame(minHeight: 44)
                .padding(.top, 12)
                suggestPill(d, L)
            }

            Group {
                FormLabel("Category").padding(.top, 16)
                FlowLayout(spacing: 6) {
                    ForEach(L?.rows ?? []) { r in CreamChip(label: r.name, on: cat == r.id) { cat = r.id } }
                }
                FormLabel("Early-closure fee (% of what’s left, optional)").padding(.top, 16)
                CreamField(placeholder: "0", text: $fee, keyboard: .decimalPad)
                summaryBox(d, L).padding(.top, 20)
                if let issue, ready {
                    Text(issue).font(.geist(13, .semibold)).foregroundStyle(Palette.overText).padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    // MARK: Pieces

    /// Installments due before today by the schedule: offers to count them as billed before Twofold.
    @ViewBuilder
    private func suggestPill(_ d: Debt, _ L: Ledger?) -> some View {
        if let L, editing == nil, ready {
            let first: String = d.firstDue ?? ""
            let suggest = dueSoFar(first, L.todayIso)
            if suggest > paidN {
                Button {
                    paidBefore = String(suggest)
                    due = DateKit.date(Loans.nthDue(first, suggest))
                } label: {
                    Text("Mark \(suggest) as already billed: the ones due before today")
                        .font(.geist(13.5, .medium)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.black, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func dueSoFar(_ first: String, _ today: String) -> Int {
        var n = 0
        while n < term && Loans.nthDue(first, n) < today { n += 1 }
        return n
    }

    @ViewBuilder
    private func summaryBox(_ d: Debt, _ L: Ledger?) -> some View {
        if let L, ready {
            let lines = summaryLines(d, L)
            VStack(alignment: .leading, spacing: 4) {
                Text(lines.0).font(.geist(15, .medium))
                Text(lines.1).font(.geist(13)).foregroundStyle(Palette.ink)
                Text(lines.2).font(.geist(13)).foregroundStyle(Palette.ink)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Add the amount, months and first installment to see the monthly amount and when it ends.")
                .font(.geist(13)).foregroundStyle(Palette.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The live summary: "AED 400/month · no interest · ends Nov 2027", the term and total, and
    /// what's posted on saving.
    private func summaryLines(_ d: Debt, _ L: Ledger) -> (String, String, String) {
        let m = L.money
        let p = d.principal ?? 0
        let r = d.rate ?? 0
        let first = d.firstDue ?? ""
        let inst = Loans.installmentOf(d)
        // Σ Loans.planInstallmentAmount(d, n) over the term, from one schedule.
        let rows = Loans.loanState(d, [], today: first).schedule
        var cum = 0.0, prev = 0.0, total = 0.0
        for row in rows.prefix(term) {
            cum += row.payment
            let c = Self.cents(cum)
            total += Self.cents(c - prev)
            prev = c
        }
        let interest = Self.cents(total - p)
        let endYm = String(Loans.nthDue(first, term - 1).prefix(7))
        let interestText: String = interest > 0.005 ? "\(m.f(interest)) interest" : "no interest"
        let line1: String = "\(m.f(inst))/month · \(interestText) · ends \(DateKit.monthLabel(endYm, short: true))"
        var line2: String = "\(termText(term)) · \(m.f(p + interest)) in total"
        if r > 0 { line2 += " · \(pctText(r))% \(rateType)" }
        let pf = d.procFee ?? 0
        if pf > 0 { line2 += " · plus \(m.f(pf)) processing fee" }
        let payments: [LoanPayment] = editing.map { Ledger.payments(of: $0.id, in: L.tx) } ?? []
        let sched = Loans.planChargesDue(d, payments, today: L.todayIso)
        // Editing: installments Twofold already posted count as billed too (as in Loans.planState).
        let billedN: Int = max(paidN, d.billedThrough ?? 0)
        let line3: String
        if billedN >= term {
            line3 = "All \(term) installments already billed."
        } else if !sched.isEmpty {
            let n = sched.count
            let what: String = n == 1 ? "1 installment due by today" : "\(n) installments due by today"
            let verb: String = editing == nil ? (n == 1 ? "is" : "are") : "will be"
            let day = Int(first.suffix(2)) ?? 1
            line3 = (editing == nil ? "On saving, " : "") + "\(what) \(verb) posted on the card; then one on the \(ordinal(day)) each month."
        } else {
            let nx = Loans.nthDue(first, billedN)
            let when: String = DateKit.dayLabel(nx) + " " + String(nx.prefix(4))
            line3 = "Installment \(billedN + 1) of \(term) is posted \(when), in \(L.categoryName(cat))."
        }
        return (line1, line2, line3)
    }

    /// What's still missing or off (the Mac's save errors); nil when it can be saved.
    private func problem(_ cards: [Account]) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Add what you bought." }
        if acct.isEmpty { return cards.isEmpty ? "Add the credit card under Accounts first." : "Pick the card it’s on." }
        if !((parseAmount(principal) ?? 0) > 0) { return "Add the amount." }
        if term <= 0 { return "Add the number of months." }
        let r = parseAmount(rate) ?? 0
        if r < 0 || r > 100 { return "The rate looks off. Use a yearly % like 0 or 12." }
        return nil
    }

    // MARK: Load & save

    private func load() {
        guard !loaded else { return }
        loaded = true
        let L = store.ledger()
        let cards: [Account] = (L?.accounts ?? []).filter { $0.type == .card }
        guard let p = editing else {
            acct = card ?? cards.first?.id ?? ""
            cat = L?.catOr("shopping") ?? "shopping"
            due = DateKit.cal.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            return
        }
        name = p.name
        acct = p.acct ?? card ?? cards.first?.id ?? ""
        principal = (p.principal ?? 0) > 0 ? fmt(p.principal ?? 0) : ""
        months = (p.termMonths ?? 0) > 0 ? String(p.termMonths ?? 0) : ""
        rate = (p.rate ?? 0) > 0 ? pctText(p.rate ?? 0) : ""
        rateType = p.rateType ?? "flat"
        procFee = (p.procFee ?? 0) > 0 ? fmt(p.procFee ?? 0) : ""
        paidBefore = (p.paidBefore ?? 0) > 0 ? String(p.paidBefore ?? 0) : ""
        if let f = p.firstDue, !f.isEmpty {
            // Show the date of the installment after the ones billed before Twofold.
            due = DateKit.date(Loans.nthDue(f, p.paidBefore ?? 0))
        }
        if let L { cat = planCategory(p, L) } else { cat = p.cat ?? "shopping" }
        fee = (p.fee ?? 0) > 0 ? pctText(p.fee ?? 0) : ""
    }

    /// The plan as typed (the store fills in the legacy fields and billedThrough when saving).
    private func draft() -> Debt {
        var d = editing ?? Debt(id: "", name: "", balance: 0, apr: 0, min: 0, createdAt: nil)
        let p = parseAmount(principal) ?? 0
        let r = parseAmount(rate) ?? 0
        let pf = parseAmount(procFee) ?? 0
        let f = parseAmount(fee) ?? 0
        let n = paidN
        d.name = name.trimmingCharacters(in: .whitespaces)
        d.kind = "cardplan"
        d.acct = acct.isEmpty ? nil : acct
        d.principal = p > 0 ? p : nil
        d.rate = r
        d.rateType = rateType
        d.termMonths = term > 0 ? term : nil
        d.firstDue = LoanForm.backDate(DateKit.iso(due), n)
        d.installment = nil
        d.paidBefore = n > 0 ? n : nil
        d.fee = f > 0 ? f : nil
        d.cat = cat.isEmpty ? nil : cat
        d.procFee = pf > 0 ? pf : nil
        d.billedThrough = max(n, editing?.billedThrough ?? editing?.paidBefore ?? 0)
        d.balance = p > 0 ? p : 0
        d.apr = r
        d.min = 0
        return d
    }

    private func save() {
        let isNew = editing == nil
        let id = store.savePlan(draft())
        // A new plan opens, as on the Mac.
        if isNew { router.drill(.loan(id)) }
    }
}
