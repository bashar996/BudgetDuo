import SwiftUI

/// A rate with up to two decimals: "3.5", "12", "6.25".
func pctText(_ x: Double) -> String {
    var s = String(format: "%.2f", x)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

/// "3.5% flat ≈ 6.6% reducing" or "4.25% interest".
func rateText(_ st: LoanState) -> String {
    st.rateType == "flat"
        ? "\(pctText(st.rate))% flat ≈ \(String(format: "%.1f", st.effectiveRate))% reducing"
        : "\(pctText(st.rate))% interest"
}

/// "12 of 60 paid · ends Mar 2030"
func loanProgressText(_ st: LoanState) -> String {
    if st.balance <= 0.005 { return "All repaid" }
    let ends = st.endsYm.map { "ends " + DateKit.monthLabel($0, short: true) } ?? "not paid off at this rate"
    if let term = st.termMonths { return "\(st.installmentsPaid) of \(term) paid · \(ends)" }
    return "\(Int((st.progress * 100).rounded()))% repaid · \(ends)"
}

/// "60 months (5 years)"
func termText(_ n: Int) -> String {
    let y = n / 12, m = n % 12
    var parts: [String] = []
    if y > 0 { parts.append("\(y) year" + (y == 1 ? "" : "s")) }
    if m > 0 { parts.append("\(m) month" + (m == 1 ? "" : "s")) }
    return y > 0 ? "\(n) months (\(parts.joined(separator: " ")))" : "\(n) month" + (n == 1 ? "" : "s")
}

// MARK: Loan detail (pushed from Debt)

@MainActor
struct LoanDetailView: View {
    var id: String
    var showBack = true
    /// Schedule row height; grows with the text size so rows aren't clipped.
    @ScaledMetric(relativeTo: .body) private var scheduleRowHeight: CGFloat = 60
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var extraOpen = false
    @State private var extra = ""
    @State private var confirmSettle = false
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let L = store.ledger() {
                if let d = L.debts.first(where: { $0.id == id }) {
                    // A card installment plan has its own screen (no Pay; it bills itself).
                    if Loans.isPlan(d) {
                        PlanDetailView(plan: d, ledger: L, showBack: showBack)
                    } else {
                        detail(d, L)
                    }
                } else {
                    Screen(color: Palette.cream, mirrored: true) {
                        NavRow(title: "Loan", showBack: showBack)
                    } content: {
                        EmptyNote(text: "This loan has been deleted.").padding(.top, 8)
                    }
                }
            }
        }
        // Deleted here, in its form or on the other phone: go back to Debt.
        .onChange(of: store.debts.contains(where: { $0.id == id })) { _, exists in
            if !exists && showBack { router.back(dismiss) }
        }
    }

    private func detail(_ d: Debt, _ L: Ledger) -> some View {
        let st = L.loanState(d)
        return Screen(color: Palette.cream, mirrored: true) {
            hero(d, st, L)
        } content: {
            actions(d, st, L)
            summary(d, st, L).padding(.top, 24)
            scheduleSection(st, L).padding(.top, 24)
            paymentsSection(d, L).padding(.top, 24)
        }
        .confirmationDialog("Settle \(d.name) early?", isPresented: $confirmSettle, titleVisibility: .visible) {
            Button("Pay \(L.money.f(st.settlement))") { store.payLoan(d, amount: st.settlement, part: "extra") }
        } message: {
            Text(settleMessage(d, st, L))
        }
        .confirmationDialog("Delete \(d.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete loan", role: .destructive) { store.deleteLoan(d) }
        } message: {
            Text(L.loanBill(d) == nil ? "Payments already logged stay in Activity."
                 : "Its bill goes too. Payments already logged stay in Activity.")
        }
    }

    // MARK: Hero

    private func hero(_ d: Debt, _ st: LoanState, _ L: Ledger) -> some View {
        let meta = [d.lender, d.kindLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            NavRow(title: d.name, showBack: showBack)
            VStack(alignment: .leading, spacing: 0) {
                Text("Outstanding").font(.geist(13)).foregroundStyle(Palette.mute)
                BigAmount(currency: L.money.currency, value: L.money.num(st.balance), size: 54, color: Palette.lavender).padding(.top, 4)
                Text("\(meta) · \(rateText(st))").font(.geist(14)).foregroundStyle(Palette.mute).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressLine(ratio: st.progress, fill: Palette.lavender, track: Palette.white.opacity(0.16), height: 6).padding(.top, 14)
                Text(loanProgressText(st)).font(.geist(12.5)).foregroundStyle(Palette.soft).padding(.top, 6)
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
        }
    }

    // MARK: Actions

    @ViewBuilder
    private func actions(_ d: Debt, _ st: LoanState, _ L: Ledger) -> some View {
        let done = st.balance <= 0.005
        VStack(alignment: .leading, spacing: 8) {
            if st.simple {
                Button { router.form = .debt(d) } label: {
                    Text("Add the loan details for a full schedule →").font(.geist(14, .medium)).foregroundStyle(Palette.accentText)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let next = st.nextDue {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next installment").font(.geist(13)).foregroundStyle(Palette.gray)
                        Text("\(DateKit.dateLabel(next)) · \(L.dueStatus(next))").font(.geist(16, .medium))
                            .foregroundStyle(L.daysUntil(next) < 0 ? Palette.bad : Palette.black)
                    }
                    Spacer()
                    Text(L.money.f(st.installment)).font(.geist(19, .medium)).tracking(em: -0.02, size: 19)
                }
                .accessibilityElement(children: .combine)
            }
            if done {
                Text("Paid off. Nothing more to pay.").font(.geist(15, .medium)).padding(.vertical, 6)
            } else {
                BlockButton(title: "Pay installment", height: 54) { store.payInstallment(d) }
                    .accessibilityHint(L.loanBill(d) == nil ? "Logs the installment as an expense" : "Marks its bill paid")
                HStack(spacing: 8) {
                    BlockButton(title: "Extra payment", fill: Palette.black, outline: !extraOpen, height: 50, radius: 16) {
                        extraOpen.toggle()
                    }
                    BlockButton(title: "Settle early", fill: Palette.black, outline: true, height: 50, radius: 16) { confirmSettle = true }
                }
                if extraOpen { extraPanel(d, st, L) }
            }
            HStack(spacing: 8) {
                BlockButton(title: "Edit", fill: Palette.black, outline: true, height: 46, radius: 16) { router.form = .debt(d) }
                BlockButton(title: "Delete", fill: Palette.bad, outline: true, height: 46, radius: 16) { confirmDelete = true }
            }
            .padding(.top, 4)
        }
        .padding(.top, 4)
    }

    private func extraPanel(_ d: Debt, _ st: LoanState, _ L: Ledger) -> some View {
        let amount = max(0, parseAmount(extra) ?? 0)
        let effect = Loans.prepayEffect(d, Ledger.payments(of: d.id, in: L.tx), today: L.todayIso, amount)
        return VStack(alignment: .leading, spacing: 0) {
            FormLabel("Extra payment (\(L.money.currency))")
            CreamField(placeholder: "0", text: $extra, keyboard: .decimalPad)
            Text(amount > 0 ? previewText(effect, L) : "Goes straight off what you owe; the installment stays the same.")
                .font(.geist(13.5, .medium)).padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
            if amount > st.balance + 0.005 {
                Text("That’s more than the \(L.money.f(st.balance)) still owed. Settle early pays it off.")
                    .font(.geist(13)).foregroundStyle(Palette.bad).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BlockButton(title: amount > 0 ? "Pay \(L.money.f(amount)) extra" : "Pay extra", height: 50, radius: 16) {
                store.payLoan(d, amount: amount, part: "extra")
                extra = ""
                extraOpen = false
            }
            .disabled(amount <= 0).opacity(amount > 0 ? 1 : 0.4)
            .padding(.top, 12)
        }
        .padding(14)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// "Saves AED 1,200 interest and 3 months"
    private func previewText(_ e: PrepayEffect, _ L: Ledger) -> String {
        "Saves \(L.money.f(e.interestSaved)) interest and \(e.monthsSaved) month" + (e.monthsSaved == 1 ? "" : "s")
    }

    private func settleMessage(_ d: Debt, _ st: LoanState, _ L: Ledger) -> String {
        let fee = d.fee ?? 0
        return "Pays \(L.money.f(st.settlement)) now as an extra payment: the \(L.money.f(st.balance)) still owed"
            + (fee > 0 ? " plus a \(pctText(fee))% early-settlement fee." : ".")
    }

    // MARK: Summary

    private func summary(_ d: Debt, _ st: LoanState, _ L: Ledger) -> some View {
        let start = st.schedule.first.map { DateKit.monthLabel(String($0.date.prefix(7)), short: true) } ?? "—"
        let endYm = st.endsYm ?? st.schedule.last.map { String($0.date.prefix(7)) }
        let end = endYm.map { DateKit.monthLabel($0, short: true) } ?? "—"
        let fee = d.fee ?? 0
        let rateNow = Loans.rateAt(d, L.calendarYm)
        var rows: [(String, String)] = [
            ("Borrowed", L.money.f(st.principal)),
            ("Outstanding", L.money.f(st.balance)),
            ("Installment", "\(L.money.f(st.installment)) / month"),
            ("Rate", rateText(st)),
        ]
        if !(d.rateChanges ?? []).isEmpty && rateNow != st.rate { rows.append(("Rate now", "\(pctText(rateNow))%")) }
        rows += [
            ("Term", st.termMonths.map(termText) ?? "Not set"),
            ("Runs", "\(start) → \(end)"),
            ("Interest paid", L.money.f(st.interestPaid)),
            ("Interest to go", L.money.f(st.interestLeft)),
            ("Total left to pay", L.money.f(st.totalLeft)),
            ("Settle today", L.money.f(st.settlement) + (fee > 0 ? " incl. \(pctText(fee))% fee" : "")),
        ]
        let list = rows
        return VStack(alignment: .leading, spacing: 0) {
            Text("Summary").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { k, r in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(r.0).font(.geist(14)).foregroundStyle(Palette.gray)
                        Spacer(minLength: 8)
                        Text(r.1).font(.geist(14.5, .medium)).multilineTextAlignment(.trailing)
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

    // MARK: Schedule

    private func scheduleSection(_ st: LoanState, _ L: Ledger) -> some View {
        let rows = st.schedule
        let rowHeight: CGFloat = scheduleRowHeight
        let next: Int? = st.balance > 0.005 && st.installmentsPaid < rows.count ? rows[st.installmentsPaid].n : nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Schedule").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
                Spacer()
                Text("\(rows.count) payment\(rows.count == 1 ? "" : "s") · ✓ paid").font(.geist(13)).foregroundStyle(Palette.gray)
            }
            if st.simple {
                Text("Estimated from the balance and monthly payment. Add the loan details for the bank’s schedule.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if rows.isEmpty {
                EmptyNote(text: "Nothing left to schedule.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { r in
                                scheduleRow(r, isNext: r.n == next, L).frame(height: rowHeight).id(r.n)
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
        }
    }

    private func scheduleRow(_ r: ScheduleRow, isNext: Bool, _ L: Ledger) -> some View {
        HStack(spacing: 10) {
            Text(r.paid ? "✓" : "\(r.n)").font(.geist(13, .semibold)).frame(width: 34, height: 34)
                .background(r.paid ? Palette.black : isNext ? Palette.lavender : Palette.tile,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(r.paid ? Palette.white : Palette.black)
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
        .opacity(r.paid ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(r.paid ? "Paid" : isNext ? "Next" : ""))
    }

    // MARK: Payments

    private func paymentsSection(_ d: Debt, _ L: Ledger) -> some View {
        let list = L.loanPayments(d)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Payments made").font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
                Spacer()
                Text(L.money.f(list.reduce(0.0) { $0 + $1.amt })).font(.geist(13)).foregroundStyle(Palette.gray)
            }
            ForEach(list) { t in
                EntryButton(tx: t, ledger: L, tile: Palette.tile, subColor: Palette.gray, sheet: Palette.cream, line: 0.12)
            }
            if list.isEmpty {
                EmptyNote(text: (d.paidBefore ?? 0) > 0
                          ? "No payments logged in Twofold yet (\(d.paidBefore ?? 0) were paid before)."
                          : "No payments logged yet.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap a payment to edit it; touch and hold to delete it.").font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 10)
            }
        }
    }
}

// MARK: Loan form

@MainActor
struct LoanForm: View {
    var editing: Debt?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var kind = "personal"
    @State private var lender = ""
    @State private var principal = ""
    @State private var rate = ""
    @State private var rateType = "reducing"
    @State private var years = ""
    @State private var months = ""
    @State private var firstDue = Date()
    @State private var installment = ""
    @State private var paidBefore = ""
    @State private var acct = ""
    @State private var showInBills = false
    @State private var fee = ""
    @State private var changes: [RateChangeRow] = []
    @State private var loaded = false

    private struct RateChangeRow: Identifiable {
        let id = UUID()
        /// "yyyy-MM"
        var from: String
        var rate: String
    }

    private static let kinds: [(String, String)] = [
        ("personal", "Personal"), ("car", "Car"), ("mortgage", "Mortgage"), ("student", "Student"), ("other", "Other"),
    ]

    private var term: Int {
        let y = Int(years.trimmingCharacters(in: .whitespaces)) ?? 0
        let m = Int(months.trimmingCharacters(in: .whitespaces)) ?? 0
        return max(0, y) * 12 + max(0, m)
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if (parseAmount(principal) ?? 0) > 0 && term > 0 { return true }
        // An older simple loan can be renamed or moved without adding the full details.
        if let e = editing, Loans.isSimple(e), (parseAmount(principal) ?? 0) <= 0, term == 0 { return true }
        return false
    }

    var body: some View {
        let L = store.ledger()
        let cur = L?.money.currency ?? ""
        let d = draft()
        FormSheetFrame(kicker: editing == nil ? "New loan" : "Edit loan", title: name.isEmpty ? "Loan" : name,
                       canSave: canSave, onSave: save,
                       onDelete: editing.map { loan in { store.deleteLoan(loan) } },
                       deleteMessage: "Payments already logged stay in Activity. A bill for it goes too.") {
            Group {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Car loan", text: $name)
            FormLabel("Kind").padding(.top, 16)
            FlowLayout(spacing: 6) {
                ForEach(Self.kinds, id: \.0) { k in CreamChip(label: k.1, on: kind == k.0) { kind = k.0 } }
            }
            FormLabel("Lender").padding(.top, 16)
            CreamField(placeholder: "Optional", text: $lender)
            FormLabel("Amount borrowed (\(cur))").padding(.top, 16)
            CreamField(placeholder: "0", text: $principal, keyboard: .decimalPad)
            }

            Group {
            FormLabel("Interest rate (% a year)").padding(.top, 16)
            CreamField(placeholder: "0", text: $rate, keyboard: .decimalPad)
            HStack(spacing: 6) {
                CreamChip(label: "Reducing balance", on: rateType == "reducing") { rateType = "reducing" }
                CreamChip(label: "Flat", on: rateType == "flat") { rateType = "flat" }
            }
            .padding(.top, 8)
            Text(rateHint(d)).font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            FormLabel("Term").padding(.top, 16)
            HStack(spacing: 10) {
                CreamField(placeholder: "Years", text: $years, keyboard: .numberPad)
                CreamField(placeholder: "Months", text: $months, keyboard: .numberPad)
            }
            Text(term > 0 ? "\(termText(term)) in all" : "Years and months, or just months.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
            FormLabel("Installments already paid").padding(.top, 16)
            CreamField(placeholder: "0", text: $paidBefore, keyboard: .numberPad)
            // The date asked for is installment (already paid + 1): the next one, paid in Twofold.
            DatePicker(selection: $firstDue, displayedComponents: .date) {
                Text(paidN > 0 ? "Installment \(paidN + 1) due (your next)" : "First installment due").font(.geist(15))
            }
            .environment(\.colorScheme, .light)
            .tint(Palette.black)
            .frame(minHeight: 44)
            .padding(.top, 12)
            }

            Group {
            FormLabel("Installment").padding(.top, 16)
            CreamField(placeholder: calculatedPlaceholder(d, L), text: $installment, keyboard: .decimalPad)
            Text("Leave it empty to use the calculated figure, or enter it as on your bank statement.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            FormLabel("Pays from").padding(.top, 16)
            FlowLayout(spacing: 6) {
                ForEach(payFrom(L)) { a in CreamChip(label: a.name, on: acct == a.id) { acct = a.id } }
            }
            Toggle(isOn: $showInBills) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show installments in Bills").font(.geist(15))
                    Text("A monthly bill on day \(DateKit.day(firstDue)); paying it logs the installment.")
                        .font(.geist(12.5)).foregroundStyle(Palette.gray)
                }
            }
            .tint(Palette.black).padding(.top, 16)
            FormLabel("Early settlement fee (%)").padding(.top, 16)
            CreamField(placeholder: "0", text: $fee, keyboard: .decimalPad)
            }

            if rateType == "reducing" { rateChanges(d) }

            summaryLine(d, L)
                .padding(.top, 20)
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    // MARK: Pieces

    private func payFrom(_ L: Ledger?) -> [Account] {
        (L?.accounts ?? []).filter { $0.type != .card && $0.type != .invest }
    }

    private func rateHint(_ d: Debt) -> String {
        if rateType == "flat" {
            let r = d.rate ?? 0
            if r > 0 && term > 0 {
                return "Interest on the full amount for the whole term: about \(String(format: "%.1f", Loans.flatToReducing(r, term)))% on a reducing balance."
            }
            return "Interest on the full amount for the whole term."
        }
        return "Interest on what’s still owed, as most banks charge."
    }

    private func calculatedPlaceholder(_ d: Debt, _ L: Ledger?) -> String {
        var calc = d
        calc.installment = nil
        guard let L, !Loans.isSimple(calc) else { return "Calculated" }
        return "\(L.money.f(Loans.installmentOf(calc))) calculated"
    }

    @ViewBuilder
    private func rateChanges(_ d: Debt) -> some View {
        FormLabel("Rate changes").padding(.top, 16)
        ForEach($changes) { $c in
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Button { $c.wrappedValue.from = DateKit.addMonths(c.from, -1) } label: {
                        Text("‹").font(.geist(22)).frame(width: 34, height: 44)
                    }
                    .accessibilityLabel("Earlier month")
                    Text(DateKit.monthLabel(c.from, short: true)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    Button { $c.wrappedValue.from = DateKit.addMonths(c.from, 1) } label: {
                        Text("›").font(.geist(22)).frame(width: 34, height: 44)
                    }
                    .accessibilityLabel("Later month")
                }
                .buttonStyle(.plain)
                CreamField(placeholder: "Rate %", text: $c.rate, keyboard: .decimalPad)
                Button { changes.removeAll { $0.id == c.id } } label: {
                    Text("×").font(.geist(24)).frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove rate change")
            }
            .padding(.bottom, 8)
        }
        Button {
            let start = changes.last?.from ?? DateKit.addMonths(DateKit.ym(Date()), 1)
            changes.append(RateChangeRow(from: changes.isEmpty ? start : DateKit.addMonths(start, 1), rate: rate))
        } label: {
            Text("+ Add a rate change").font(.geist(14, .medium)).frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        Text("For a variable rate: from that month on, the installment is worked out again over the months left.")
            .font(.geist(13)).foregroundStyle(Palette.gray)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func summaryLine(_ d: Debt, _ L: Ledger?) -> some View {
        if let L, !Loans.isSimple(d) {
            let st = Loans.loanState(d, editing.map { Ledger.payments(of: $0.id, in: L.tx) } ?? [], today: L.todayIso)
            let endYm = st.endsYm ?? st.schedule.last.map { String($0.date.prefix(7)) }
            let ends = endYm.map { DateKit.monthLabel($0, short: true) } ?? "—"
            let total = d.termMonths ?? st.schedule.count
            let next: String = st.nextDue.map { (due: String) -> String in "Installment \(st.installmentsPaid + 1) of \(total) due \(DateKit.dayLabel(due)) \(due.prefix(4))" }
                ?? "All \(total) installments paid"
            let first: String = d.firstDue.map { (f: String) -> String in " · first one \(DateKit.dayLabel(f)) \(f.prefix(4))" } ?? ""
            VStack(alignment: .leading, spacing: 4) {
                Text("\(L.money.f(Loans.installmentOf(d)))/month · \(L.money.f(st.totalInterest)) interest · ends \(ends)")
                    .font(.geist(15, .medium))
                Text(next + first).font(.geist(13)).foregroundStyle(Palette.ink)
            }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.lavender, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Add the amount, term and first payment to see the installment.")
                .font(.geist(13)).foregroundStyle(Palette.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Load & save

    private func load() {
        guard !loaded else { return }
        loaded = true
        let L = store.ledger()
        guard let d = editing else {
            acct = L?.mainAccountId ?? ""
            firstDue = DateKit.cal.date(byAdding: .month, value: 1, to: Date()) ?? Date()
            return
        }
        name = d.name
        kind = d.kind ?? "personal"
        lender = d.lender ?? ""
        principal = fmt(d.principal ?? d.balance)
        rate = pctText(d.rate ?? d.apr)
        rateType = d.rateType ?? "reducing"
        if let n = d.termMonths, n > 0 {
            years = n / 12 > 0 ? "\(n / 12)" : ""
            months = n % 12 > 0 ? "\(n % 12)" : ""
        }
        if let f = d.firstDue, !f.isEmpty {
            // Show the date of the installment after the ones already paid.
            firstDue = DateKit.date(Loans.nthDue(f, d.paidBefore ?? 0))
        } else {
            firstDue = DateKit.cal.date(byAdding: .month, value: 1, to: Date()) ?? Date()
        }
        installment = (d.installment ?? 0) > 0 ? fmt(d.installment ?? 0) : ""
        paidBefore = (d.paidBefore ?? 0) > 0 ? "\(d.paidBefore ?? 0)" : ""
        acct = d.acct ?? ""
        showInBills = L?.loanBill(d) != nil
        fee = (d.fee ?? 0) > 0 ? pctText(d.fee ?? 0) : ""
        changes = (d.rateChanges ?? []).map { RateChangeRow(from: $0.from, rate: pctText($0.rate)) }
    }

    /// The loan as typed (legacy fields are filled in by the store when saving).
    private func draft() -> Debt {
        var d = editing ?? Debt(id: "", name: "", balance: 0, apr: 0, min: 0, createdAt: nil)
        d.name = name.trimmingCharacters(in: .whitespaces)
        d.kind = kind
        let l = lender.trimmingCharacters(in: .whitespaces)
        d.lender = l.isEmpty ? nil : l
        d.principal = parseAmount(principal).flatMap { $0 > 0 ? $0 : nil }
        d.rate = max(0, parseAmount(rate) ?? 0)
        d.rateType = rateType
        d.termMonths = term > 0 ? term : nil
        d.firstDue = Self.backDate(DateKit.iso(firstDue), paidN)
        d.installment = parseAmount(installment).flatMap { $0 > 0 ? $0 : nil }
        d.paidBefore = paidN > 0 ? paidN : nil
        let rc: [RateChange] = rateType == "reducing"
            ? changes.compactMap { c in parseAmount(c.rate).map { RateChange(from: c.from, rate: max(0, $0)) } }.sorted { $0.from < $1.from }
            : []
        d.rateChanges = rc.isEmpty ? nil : rc
        d.fee = parseAmount(fee).flatMap { $0 > 0 ? $0 : nil }
        d.acct = acct.isEmpty ? nil : acct
        return d
    }

    private func save() {
        store.saveLoan(draft(), showInBills: showInBills)
    }

    /// Installments already paid before Twofold (never more than the term).
    private var paidN: Int {
        let n = max(0, Int(paidBefore.trimmingCharacters(in: .whitespaces)) ?? 0)
        return term > 0 ? min(n, term) : n
    }

    /// The first installment's date, given the date of installment n + 1.
    static func backDate(_ due: String, _ n: Int) -> String {
        let ym = DateKit.addMonths(String(due.prefix(7)), -n)
        let day = min(Int(due.suffix(2)) ?? 1, DateKit.daysIn(ym))
        return ym + "-" + DateKit.pad(day)
    }
}
