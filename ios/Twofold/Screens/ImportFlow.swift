import SwiftUI

/// A statement file picked in Activity, waiting to be imported.
struct ImportJob: Identifiable {
    let id = UUID()
    var name: String
    var data: Data
    /// The account it was started from (pre-selected), if any.
    var account: String?
}

enum ImportFormat {
    /// Money in on the review list.
    static let moneyIn = Palette.accentText

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    /// "+AED 1,250.00" or "−AED 38.00"
    static func amount(_ x: Double, _ currency: String) -> String {
        let s = number.string(from: NSNumber(value: abs(x))) ?? String(format: "%.2f", abs(x))
        return (x < 0 ? "−" : "+") + currency + " " + s
    }

    /// Column letters: 0 → A, 26 → AA.
    static func letter(_ c: Int) -> String {
        var n = c + 1
        var s = ""
        while n > 0 {
            let r = (n - 1) % 26
            s = String(Character(Unicode.Scalar(UInt8(65 + r)))) + s
            n = (n - 1) / 26
        }
        return s
    }
}

/// Full-screen statement import: account → (PDF password) → columns → review → import.
/// The rules (columns, signs, names, categories, duplicates) live in Import/ and match the Mac.
@MainActor
struct ImportFlowView: View {
    var job: ImportJob
    /// Called after importing: the account and the month ("yyyy-MM") to show in Activity.
    var onDone: (String, String) -> Void

    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    private enum Step { case account, loading, failed, columns, review }
    private enum Filter: CaseIterable { case all, new, dupes, needs }

    @State private var step: Step = .account
    @State private var acctId = ""
    @State private var started = false
    @State private var loaded: StmtLoaded?
    @State private var failure = ""
    @State private var password = ""
    @State private var askPassword = false
    @State private var mapping = StmtMapping()
    @State private var shape = ""
    @State private var pdfRows: [StmtRawRow] = []
    @State private var posOut = false
    @State private var plan: [ImportRow] = []
    @State private var filter: Filter = .all

    init(job: ImportJob, onDone: @escaping (String, String) -> Void) {
        self.job = job
        self.onDone = onDone
    }

    var body: some View {
        Group {
            if let L = store.ledger() {
                screen(L)
            } else {
                Palette.black.ignoresSafeArea()
            }
        }
        .background(Palette.black.ignoresSafeArea())
        .onAppear {
            guard !started else { return }
            started = true
            if let a = job.account, store.accounts.contains(where: { $0.id == a && $0.type != .invest }) { acctId = a }
        }
        .sheet(isPresented: $askPassword, onDismiss: {
            // Closed without the right password: back to the first step.
            if loaded == nil && step == .loading && !StmtPDF.opens(job.data, password: password) { step = .account }
        }) {
            PasswordSheet(data: job.data, password: $password) {
                askPassword = false
                load()
            }
        }
    }

    @ViewBuilder
    private func screen(_ L: Ledger) -> some View {
        switch step {
        case .account: accountStep(L)
        case .loading: loadingStep
        case .failed: failedStep
        case .columns: columnsStep(L)
        case .review: reviewStep(L)
        }
    }

    private var isCard: Bool { store.accounts.first { $0.id == acctId }?.type == .card }

    // MARK: Frame

    private func stepFrame<C: View>(kicker: String, title: String, sub: String = "", button: String? = nil, hint: String? = nil,
                                enabled: Bool = true, action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Screen(color: Palette.cream, mirrored: true) {
            header(kicker: kicker, title: title, sub: sub)
        } content: {
            content()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let button {
                VStack(spacing: 8) {
                    if let hint {
                        Text(hint).font(.geist(13, .medium)).foregroundStyle(Palette.overText)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    }
                    BlockButton(title: button, height: 54, action: action)
                        .disabled(!enabled).opacity(enabled ? 1 : 0.4)
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
                .background(LinearGradient(colors: [Palette.cream.opacity(0), Palette.cream, Palette.cream], startPoint: .top, endPoint: .bottom))
                .foregroundStyle(Palette.black)
            }
        }
    }

    private var canGoBack: Bool { step == .columns || step == .review }

    private func header(kicker: String, title: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { back() } label: { Text("←").font(.geist(24)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .opacity(canGoBack ? 1 : 0).disabled(!canGoBack).accessibilityHidden(!canGoBack)
                    .accessibilityLabel("Back")
                Text("Import statement").font(.geist(17, .medium)).lineLimit(1).frame(maxWidth: .infinity)
                Button { dismiss() } label: { Text("×").font(.geist(26)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
            }
            .padding(.horizontal, 12).padding(.top, 8)
            VStack(alignment: .leading, spacing: 6) {
                Text(kicker).font(.geist(13)).foregroundStyle(Palette.mute).lineLimit(1)
                Text(title).font(.geist(30, .medium)).tracking(em: -0.03, size: 30)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !sub.isEmpty {
                    Text(sub).font(.geist(14)).foregroundStyle(Palette.mute).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 4)
        }
    }

    private func back() {
        switch step {
        case .columns: step = .account
        case .review: step = .columns
        case .account, .loading, .failed: break
        }
    }

    // MARK: Step 1: account

    private func accountStep(_ L: Ledger) -> some View {
        let accounts = L.accounts.filter { $0.type != .invest }
        return stepFrame(kicker: "Step 1 of 3 · " + job.name, title: "Which account is this statement for?",
                     button: "Continue", enabled: !acctId.isEmpty, action: { accountChosen() }) {
            VStack(spacing: 8) {
                ForEach(accounts) { a in
                    let on = acctId == a.id
                    Button { acctId = a.id } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(a.type.label).font(.geist(12.5)).foregroundStyle(Palette.gray)
                                Text(a.name).font(.geist(17, .medium)).lineLimit(1)
                                let meta = [a.bank, a.last4.map { "•• \($0)" }].compactMap { $0 }.filter { !$0.isEmpty }
                                if !meta.isEmpty {
                                    Text(meta.joined(separator: " · ")).font(.geist(12.5)).foregroundStyle(Palette.gray)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(on ? Palette.black : .clear, in: Circle())
                                .overlay(Circle().strokeBorder(Palette.black.opacity(on ? 1 : 0.25), lineWidth: 1.5))
                                .foregroundStyle(on ? Palette.white : .clear)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Palette.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.black, lineWidth: on ? 2 : 0))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if accounts.isEmpty {
                EmptyNote(text: "Add the account under More → Accounts first, then import its statement.")
            }
            Text(isCard
                 ? "A card statement: charges become expenses on the card; a payment to the card can be recorded as a transfer from your current account."
                 : "Money out becomes expenses and money in becomes income on this account. Nothing is saved until you import.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func accountChosen() {
        guard !acctId.isEmpty else { return }
        if loaded != nil { prepareColumns() } else { load() }
    }

    // MARK: Reading the file

    private var loadingStep: some View {
        stepFrame(kicker: job.name, title: "Reading the statement…", action: {}) {
            ProgressView().tint(Palette.black).frame(maxWidth: .infinity).padding(.top, 30)
        }
    }

    private var failedStep: some View {
        stepFrame(kicker: job.name, title: "This file couldn’t be imported", sub: failure,
              button: "Choose another file", action: { dismiss() }) {
            Text("Statements import from CSV, Excel (.xlsx) and PDF files with text. Most banks offer a CSV or Excel download next to the PDF.")
                .font(.geist(14)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        step = .loading
        let data = job.data, name = job.name
        let pw: String? = password.isEmpty ? nil : password
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<StmtLoaded, StmtFileError> in
                do {
                    return .success(try StmtFile.load(data, name: name, password: pw))
                } catch let e as StmtFileError {
                    return .failure(e)
                } catch {
                    return .failure(.message("This file couldn’t be read (\(error.localizedDescription))."))
                }
            }.value
            switch result {
            case .success(let l):
                loaded = l
                prepareColumns()
            case .failure(.needPassword):
                askPassword = true
            case .failure(.message(let m)):
                failure = m
                step = .failed
            }
        }
    }

    /// Detects the columns (or reads the PDF lines) for the chosen account, then applies
    /// what was remembered for this account and file shape.
    private func prepareColumns() {
        switch loaded {
        case .table(let t)?:
            var m = StmtDetect.detect(t, isCard: isCard)
            shape = StmtDetect.shapeOf(t, m)
            if var saved = ImportMemory.load(acct: acctId, shape: shape) {
                let w = StmtDetect.width(t)
                if saved.columns.allSatisfy({ $0 < w }) && (saved.date >= 0 || saved.vdate >= 0) {
                    saved.header = m.header
                    m = saved
                }
            }
            mapping = m
            posOut = m.posOut
        case .pdf(let lines)?:
            let r = StmtPDF.rows(lines, isCard: isCard)
            pdfRows = r.rows
            shape = "pdf"
            mapping = StmtMapping()
            posOut = StmtDetect.inferSign(r.rows, isCard: isCard).posOut
            if let saved = ImportMemory.load(acct: acctId, shape: shape) { posOut = saved.posOut }
        case nil:
            step = .account
            return
        }
        step = .columns
    }

    // MARK: Step 2: columns

    private func currentRaw() -> [StmtRawRow] {
        switch loaded {
        case .table(let t)?:
            var r = StmtDetect.rawRows(t, mapping)
            StmtDetect.prepare(&r, isCard: isCard)
            return r
        case .pdf?:
            return pdfRows
        case nil:
            return []
        }
    }

    private func columnsStep(_ L: Ledger) -> some View {
        let raw = currentRaw()
        let rows = StmtDetect.finalize(raw, posOut: posOut)
        let guess = StmtDetect.inferSign(raw, isCard: isCard)
        let table: [[String]]
        if case .table(let t)? = loaded { table = t } else { table = [] }
        let isPdf = table.isEmpty
        let showSign = guess.show && (isPdf || mapping.amount >= 0)
        return stepFrame(kicker: "Step 2 of 3 · " + L.accountName(acctId),
                     title: isPdf ? "Check what was read" : "Check the columns",
                     sub: isPdf ? "Read from the PDF’s text. Untick anything that looks wrong on the next step." : "Picked automatically. Change any that are wrong.",
                     button: "Continue", hint: rows.isEmpty ? (isPdf ? "No transactions found in this PDF." : "Pick the Date and Amount columns.") : nil,
                     enabled: !rows.isEmpty, action: { buildPlan(rows) }) {
            if !isPdf {
                let cols = min(StmtDetect.width(table), 60)
                previewGrid(table, cols: min(cols, 12))
                VStack(alignment: .leading, spacing: 0) {
                    picker("Date", mapping.date, optional: false, table, cols: cols) { c in update { $0.date = c } }
                    picker("Description", mapping.desc, optional: true, table, cols: cols) { c in update { $0.desc = c } }
                    FormLabel("Amounts").padding(.top, 12)
                    HStack(spacing: 6) {
                        CreamChip(label: "One amount column", on: mapping.amount >= 0 || (mapping.debit < 0 && mapping.credit < 0)) {
                            update { m in
                                if m.amount < 0 { m.amount = m.debit >= 0 ? m.debit : m.credit }
                                m.debit = -1; m.credit = -1
                            }
                        }
                        CreamChip(label: "Money out + money in", on: mapping.amount < 0 && (mapping.debit >= 0 || mapping.credit >= 0)) {
                            update { m in
                                if m.debit < 0 && m.credit < 0 { m.debit = m.amount >= 0 ? m.amount : 0 }
                                m.amount = -1
                            }
                        }
                    }
                    if mapping.amount >= 0 || (mapping.debit < 0 && mapping.credit < 0) {
                        picker("Amount", mapping.amount, optional: false, table, cols: cols) { c in update { $0.amount = c } }
                    } else {
                        picker("Money out (debit)", mapping.debit, optional: true, table, cols: cols) { c in update { $0.debit = c } }
                        picker("Money in (credit)", mapping.credit, optional: true, table, cols: cols) { c in update { $0.credit = c } }
                    }
                    picker("Balance", mapping.balance, optional: true, table, cols: cols) { c in update { $0.balance = c } }
                }
                .padding(.top, 14)
            }
            if showSign {
                FormLabel("In this file, money out is shown as").padding(.top, 16)
                HStack(spacing: 6) {
                    CreamChip(label: "Negative (−120.00)", on: !posOut) { posOut = false; mapping.posOut = false }
                    CreamChip(label: "Positive (120.00)", on: posOut) { posOut = true; mapping.posOut = true }
                }
                Text(guess.sure ? "Worked out from the file; change it if the preview looks the wrong way round."
                     : "Couldn’t tell from the file. Check the preview below: purchases should show −.")
                    .font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            parsedPreview(rows, L).padding(.top, 20)
        }
    }

    /// Changes the mapping, then re-reads the date order and the sign convention.
    private func update(_ change: (inout StmtMapping) -> Void) {
        guard case .table(let t)? = loaded else { return }
        var m = mapping
        change(&m)
        let dateCol = m.date >= 0 ? m.date : m.vdate
        m.order = StmtDates.detectOrder(t.dropFirst(max(0, m.header + 1)).map { StmtDetect.cell($0, dateCol) })
        var r = StmtDetect.rawRows(t, m)
        StmtDetect.prepare(&r, isCard: isCard)
        m.posOut = StmtDetect.inferSign(r, isCard: isCard).posOut
        mapping = m
        posOut = m.posOut
    }

    private func role(_ c: Int) -> String? {
        if c == mapping.date { return "Date" }
        if c == mapping.vdate { return "Value date" }
        if c == mapping.desc { return "Description" }
        if c == mapping.amount { return "Amount" }
        if c == mapping.debit { return "Money out" }
        if c == mapping.credit { return "Money in" }
        if c == mapping.balance { return "Balance" }
        if c == mapping.dir { return "Cr/Dr" }
        return nil
    }

    private func headerText(_ c: Int, _ t: [[String]]) -> String {
        guard mapping.header >= 0, mapping.header < t.count else { return "" }
        return StmtDetect.cell(t[mapping.header], c)
    }

    private func colLabel(_ c: Int, _ t: [[String]]) -> String {
        let letter = ImportFormat.letter(c)
        let h = headerText(c, t)
        if !h.isEmpty { return letter + " · " + h }
        let sample = t.dropFirst(max(0, mapping.header + 1)).prefix(30).map { StmtDetect.cell($0, c) }.first { !$0.isEmpty } ?? ""
        return sample.isEmpty ? "Column " + letter : letter + " · " + String(sample.prefix(18))
    }

    private func picker(_ title: String, _ value: Int, optional: Bool, _ t: [[String]], cols: Int,
                        set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.geist(15)).frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                if optional { Button("None") { set(-1) } }
                ForEach(0..<cols, id: \.self) { c in
                    Button(colLabel(c, t)) { set(c) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(value >= 0 ? colLabel(value, t) : "None").font(.geist(14, .medium)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Palette.white, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black.opacity(0.15), lineWidth: 1))
                .foregroundStyle(Palette.black)
            }
            .accessibilityLabel("\(title) column")
            .accessibilityValue(value >= 0 ? colLabel(value, t) : "None")
        }
        .padding(.vertical, 3)
    }

    /// The first rows of the file, with the columns in use highlighted.
    private func previewGrid(_ t: [[String]], cols: Int) -> some View {
        let sample = Array(t.dropFirst(max(0, mapping.header + 1)).prefix(6))
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        let r = role(c)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ImportFormat.letter(c) + (r.map { " · " + $0 } ?? "")).font(.geist(11.5, .semibold)).lineLimit(1)
                            Text(headerText(c, t)).font(.geist(12)).lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .frame(width: 128, alignment: .leading)
                        .background(r != nil ? Palette.lavender : Palette.tile)
                    }
                }
                ForEach(Array(sample.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            Text(StmtDetect.cell(row, c)).font(.geist(12.5)).lineLimit(1)
                                .padding(.horizontal, 8).frame(width: 128, height: 34, alignment: .leading)
                        }
                    }
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.08) }
                }
            }
            .background(Palette.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityHidden(true)
    }

    private func parsedPreview(_ rows: [StmtRow], _ L: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(rows.isEmpty ? "No transactions yet" : "\(rows.count) transaction\(rows.count == 1 ? "" : "s") found")
                .font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            ForEach(Array(rows.prefix(6).enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(DateKit.dateLabel(r.date)).font(.geist(12.5)).foregroundStyle(Palette.gray).frame(width: 84, alignment: .leading)
                    Text(r.desc).font(.geist(14)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(ImportFormat.amount(r.amount, L.money.currency)).font(.geist(14, .medium))
                        .foregroundStyle(r.amount > 0 ? ImportFormat.moneyIn : Palette.black).lineLimit(1).fixedSize()
                }
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) { Hairline(opacity: 0.1) }
                .accessibilityElement(children: .combine)
            }
            if rows.count > 6 {
                Text("and \(rows.count - 6) more").font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 8)
            }
        }
    }

    private func buildPlan(_ rows: [StmtRow]) {
        guard let L = store.ledger(), !rows.isEmpty else { return }
        let ids = StmtDedupe.importIds(acct: acctId, rows: rows)
        plan = ImportPlanner.plan(rows, ids: ids, acctId: acctId, L: L)
        filter = .all
        step = .review
    }

    // MARK: Step 3: review

    private func matches(_ r: ImportRow, _ f: Filter) -> Bool {
        switch f {
        case .all: return true
        case .new: return !r.isDuplicate
        case .dupes: return r.isDuplicate
        case .needs: return r.kind == .expense && r.cat == nil
        }
    }

    private func filterLabel(_ f: Filter) -> String {
        switch f {
        case .all: return "All"
        case .new: return "New"
        case .dupes: return "Duplicates"
        case .needs: return "Needs category"
        }
    }

    private func reviewStep(_ L: Ledger) -> some View {
        let fresh = plan.filter { !$0.isDuplicate }.count
        let dupes = plan.count - fresh
        let needs = plan.filter { !$0.isDuplicate && $0.kind == .expense && $0.cat == nil }.count
        let ready = plan.filter { $0.on && $0.ready }.count
        let blocked = plan.filter { $0.on && !$0.ready }.count
        let shown = plan.indices.filter { matches(plan[$0], filter) }
        let summary = "\(fresh) new · \(dupes) already in Twofold · \(needs) need\(needs == 1 ? "s" : "") a category"
        return stepFrame(kicker: "Step 3 of 3 · " + L.accountName(acctId), title: "Check and import", sub: summary,
                     button: ready == 0 ? "Nothing ticked to import" : "Import \(ready) \(ready == 1 ? "entry" : "entries")",
                     hint: blocked > 0 ? "\(blocked) ticked without a category won’t be imported. Pick one, or choose Other." : nil,
                     enabled: ready > 0, action: { runImport() }) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        let n = plan.filter { matches($0, f) }.count
                        CreamChip(label: "\(filterLabel(f)) · \(n)", on: filter == f) { filter = f }
                    }
                }
            }
            HStack(spacing: 4) {
                Button("Select all") { for i in shown { plan[i].on = true } }
                    .frame(minHeight: 44)
                Text("·").foregroundStyle(Palette.gray)
                Button("None") { for i in shown { plan[i].on = false } }
                    .frame(minHeight: 44)
                Spacer(minLength: 8)
                Menu {
                    ForEach(L.rows) { r in Button(r.name) { setCategory(r.id) } }
                    Button("Other") { setCategory("other") }
                } label: {
                    Text("Set category for selected").font(.geist(13.5, .medium)).lineLimit(1)
                        .padding(.horizontal, 14).frame(height: 40)
                        .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
            }
            .font(.geist(14, .medium))
            .foregroundStyle(Palette.black)
            .buttonStyle(.plain)
            .padding(.top, 8)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown, id: \.self) { i in
                    ImportRowView(row: $plan[i], L: L)
                }
            }
            if shown.isEmpty {
                EmptyNote(text: "Nothing in this list.").padding(.top, 8)
            }
        }
    }

    /// Sets the category of every ticked expense.
    private func setCategory(_ id: String) {
        for i in plan.indices where plan[i].on && plan[i].kind == .expense {
            plan[i].cat = id
            plan[i].catHow = "user"
            if plan[i].status == .needsCat { plan[i].status = .new; plan[i].note = "" }
        }
    }

    private func runImport() {
        let chosen = plan.filter { $0.on && $0.ready }
        guard !chosen.isEmpty else { return }
        let entries = chosen.map { ImportPlanner.entry($0, acctId: acctId) }
        let undo = store.importEntries(entries)
        var m = mapping
        m.posOut = posOut
        ImportMemory.save(m, acct: acctId, shape: shape)
        router.imported(undo)
        let latest = entries.map { $0.tx.month }.max() ?? DateKit.ym(Date())
        onDone(acctId, latest)
        dismiss()
    }
}

/// One statement line on the review list: tick, date, editable name, amount, category,
/// who and its status.
@MainActor
private struct ImportRowView: View {
    @Binding var row: ImportRow
    var L: Ledger

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { row.on.toggle() } label: {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(row.on ? Palette.white : .clear)
                    .frame(width: 26, height: 26)
                    .background(row.on ? Palette.black : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.black, lineWidth: 1.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.on ? "Will be imported" : "Skipped")
            .accessibilityHint("Ticks or unticks \(row.name)")
            .accessibilityAddTraits(row.on ? .isSelected : [])
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DateKit.dateLabel(row.row.date)).font(.geist(12.5)).foregroundStyle(Palette.gray)
                    Spacer(minLength: 8)
                    Text(ImportFormat.amount(row.row.amount, L.money.currency)).font(.geist(15, .medium))
                        .foregroundStyle(row.row.amount > 0 ? ImportFormat.moneyIn : Palette.black)
                        .lineLimit(1).fixedSize()
                }
                TextField("", text: $row.name, prompt: Text("Name").foregroundColor(Palette.gray))
                    .font(.geist(16, .medium))
                    .submitLabel(.done)
                    .accessibilityLabel("Name")
                Text(row.row.desc).font(.geist(12)).foregroundStyle(Palette.gray).lineLimit(2)
                HStack(spacing: 6) {
                    kindControl
                    Menu {
                        ForEach([Who.joint, .a, .b]) { w in Button(L.name(w)) { row.who = w } }
                    } label: { pill(L.name(row.who), strong: false) }
                    .accessibilityLabel("Who: \(L.name(row.who))")
                }
                .padding(.top, 2)
                if !row.note.isEmpty {
                    Text(row.note).font(.geist(12, .medium)).foregroundStyle(badgeText)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(badgeFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline(opacity: 0.12) }
        .opacity(row.on ? 1 : 0.62)
    }

    @ViewBuilder
    private var kindControl: some View {
        switch row.kind {
        case .expense:
            Menu {
                ForEach(L.rows) { r in Button(r.name) { pick(r.id) } }
                Button("Other") { pick("other") }
            } label: {
                pill(row.cat.map { L.categoryName($0) } ?? "Pick a category", strong: row.cat == nil)
            }
            .accessibilityLabel("Category: \(row.cat.map { L.categoryName($0) } ?? "none")")
        case .income:
            pill("Income", strong: false)
        case .transfer:
            pill(L.accountName(row.from) + " → " + L.accountName(row.to), strong: false)
        }
    }

    private func pill(_ text: String, strong: Bool) -> some View {
        Text(text).font(.geist(13, .medium)).lineLimit(1)
            .padding(.horizontal, 12).frame(height: 34)
            .background(strong ? Palette.overText.opacity(0.1) : Palette.white, in: Capsule())
            .overlay(Capsule().strokeBorder(strong ? Palette.overText : Palette.black.opacity(0.15), lineWidth: 1))
            .foregroundStyle(strong ? Palette.overText : Palette.black)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
    }

    private func pick(_ id: String) {
        row.cat = id
        row.catHow = "user"
        if row.status == .needsCat { row.status = .new; row.note = "" }
    }

    private var badgeFill: Color {
        switch row.status {
        case .needsCat: return Palette.overText.opacity(0.1)
        case .imported, .dupe: return Palette.black.opacity(0.07)
        case .bill, .loan: return Palette.lavender
        case .transfer, .cardPayment: return Palette.tile
        case .income, .salary, .refund: return ImportFormat.moneyIn.opacity(0.12)
        case .new: return .clear
        }
    }

    private var badgeText: Color {
        switch row.status {
        case .needsCat: return Palette.overText
        case .income, .salary, .refund: return ImportFormat.moneyIn
        default: return Palette.black
        }
    }
}

/// The password for a locked PDF statement. Checked here, so a wrong one stays on the sheet.
private struct PasswordSheet: View {
    var data: Data
    @Binding var password: String
    var onUnlock: () -> Void
    @State private var wrong = false
    @FocusState private var focused: Bool

    var body: some View {
        FitSheet {
            Text("Password-protected PDF").font(.geist(13)).foregroundStyle(Palette.gray)
            Text("Enter the statement’s password").font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
            Text("Banks often use part of your date of birth, card or account number. It’s only used to open the file on this phone.")
                .font(.geist(13.5)).foregroundStyle(Palette.gray).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            SecureField("", text: $password, prompt: Text("Password").foregroundColor(Palette.gray))
                .font(.geist(17, .medium))
                .textContentType(.password)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { tryUnlock() }
                .onChange(of: password) { _, _ in wrong = false }
                .padding(.horizontal, 16).frame(height: 52)
                .background(Palette.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.black.opacity(focused ? 1 : 0), lineWidth: 2))
                .foregroundStyle(Palette.black)
                .padding(.top, 14)
            Text(wrong ? "That password didn’t open it. Try again." : " ")
                .font(.geist(13, .semibold)).foregroundStyle(Palette.overText).padding(.top, 8)
            BlockButton(title: "Open statement", height: 54) { tryUnlock() }
                .disabled(password.isEmpty).opacity(password.isEmpty ? 0.4 : 1)
                .padding(.top, 4)
        }
        .onAppear { focused = true }
    }

    private func tryUnlock() {
        guard !password.isEmpty else { return }
        if StmtPDF.opens(data, password: password) { onUnlock() } else { wrong = true }
    }
}
