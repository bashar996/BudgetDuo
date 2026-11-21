import SwiftUI

/// Full-screen keypad entry. Folded/phone: one column. Unfolded/wide: amount,
/// category and account on the left half, a large keypad on the right.
@MainActor
struct AddEntryView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var d: EntryDraft
    @State private var confirmDelete = false

    init(draft: EntryDraft) { _d = State(initialValue: draft) }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            if let L = store.ledger() {
                Group {
                    if wide {
                        HStack(spacing: 10) {
                            VStack(spacing: 0) {
                                top(L).clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                                    .padding(.top, 44)
                                edge
                                ScrollView { categoryTiles(L, grid: true).padding(.horizontal, 14).padding(.bottom, 20) }
                                    .scrollIndicators(.hidden)
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 10) {
                                chipRows(L, split: true)
                                Spacer(minLength: 10)
                                keypad(keyHeight: 80)
                            }
                            .padding(.horizontal, 18).padding(.top, 64).padding(.bottom, 30)
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            top(L)
                            edge
                            VStack(spacing: 10) {
                                categoryTiles(L, grid: false)
                                chipRows(L, split: false)
                                Spacer(minLength: 0)
                                keypad(keyHeight: geo.size.height < 700 ? 46 : 54)
                            }
                            .padding(.horizontal, 14).padding(.bottom, 12)
                        }
                    }
                }
            }
        }
        .background(Palette.black.ignoresSafeArea())
        .foregroundStyle(Palette.white)
        .sensoryFeedback(.impact(weight: .light), trigger: d.amt)
        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let t = store.tx.first(where: { $0.id == d.txId }) { store.deleteEntry(t) }
                dismiss()
            }
        } message: {
            Text("It disappears from both phones.")
        }
    }

    private var edge: some View {
        BlobEdge(fill: Palette.black, hole: Palette.lavender, height: 60).background(Palette.lavender)
    }

    private var pot: Goal? { d.pot.flatMap { id in store.goals.first { $0.id == id } } }

    private var title: String {
        if let pot { return (d.potDir == .out ? "Withdraw from " : "Add to ") + pot.name }
        if !d.txId.isEmpty { return "Edit entry" }
        switch d.type {
        case .transfer: return "Move money"
        case .income: return "New income"
        case .expense: return "New expense"
        }
    }

    private var saveLabel: String {
        if let pot { return d.potDir == .out ? "Withdraw" : "Add to \(pot.name)" }
        if !d.txId.isEmpty { return "Save changes" }
        switch d.type {
        case .transfer: return "Move money"
        case .income: return "Save income"
        case .expense: return "Save expense"
        }
    }

    // MARK: Lavender top: title, type, amount, name

    private func top(_ L: Ledger) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Text("×").font(.geist(26)).frame(width: 64, height: 44, alignment: .leading).padding(.leading, 10) }
                    .accessibilityLabel("Close")
                Text(title).font(.geist(19, .medium)).lineLimit(1).frame(maxWidth: .infinity)
                Button("Delete") { confirmDelete = true }.font(.geist(14, .medium)).frame(width: 64, height: 44)
                    .opacity(d.txId.isEmpty ? 0 : 1).disabled(d.txId.isEmpty)
            }
            if pot == nil {
                HStack(spacing: 6) {
                    ForEach([(TxType.expense, "Expense"), (.income, "Income"), (.transfer, "Transfer")], id: \.0) { t in
                        let on = d.type == t.0
                        Button {
                            d.type = t.0; d.error = ""
                            if t.0 == .income { d.cat = "income" } else if d.cat == "income" || d.cat == "transfer" { d.cat = "groceries" }
                        } label: {
                            Text(t.1).font(.geist(14, .medium)).padding(.horizontal, 16).frame(height: 44)
                                .foregroundStyle(on ? Palette.white : Palette.black)
                                .background(on ? Palette.black : .clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.top, 4)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L.money.currency).font(.geist(24, .medium)).foregroundStyle(Palette.ink)
                Text(d.amt.isEmpty ? "0" : d.amt).font(.geist(68, .medium)).tracking(em: -0.045, size: 68)
                    .foregroundStyle(d.amt.isEmpty ? Palette.amountPlaceholder : Palette.black)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
            }
            .padding(.top, 14)
            .accessibilityElement(children: .combine)
            TextField("", text: $d.name, prompt: Text(placeholder).foregroundColor(Palette.ink.opacity(0.7)))
                .font(.geist(16, .medium)).multilineTextAlignment(.center).frame(height: 44).padding(.top, 4)
                .onChange(of: d.name) { _, _ in d.error = "" }
            Text(d.error).font(.geist(13, .semibold)).frame(minHeight: 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(Palette.lavender)
        .foregroundStyle(Palette.black)
    }

    private var placeholder: String { d.type == .transfer ? "Add a note" : d.type == .income ? "Where from?" : "What was it?" }

    // MARK: Black area: categories, who, accounts, date

    // Phone: one scrolling row of tiles, one scrolling row of chips.
    // Unfolded: all tiles in a 6-across grid on the left; who and account
    // chips as two scrolling rows at the top of the right pane. Chips never wrap.

    @ViewBuilder
    private func categoryTiles(_ L: Ledger, grid: Bool) -> some View {
        if d.type != .income && pot == nil {
            if d.type == .transfer {
                let dests = L.accounts.filter { $0.id != d.acct }
                tiles(dests.map { ($0.id, $0.name) }, selected: d.to, grid: grid) { d.to = $0 }
                if dests.isEmpty { Text("Add a second account to move money between them.").font(.geist(13)).foregroundStyle(Palette.mute) }
            } else {
                tiles(L.rows.map { ($0.id, $0.name) }, selected: d.cat, grid: grid) { d.cat = $0 }
            }
        }
    }

    @ViewBuilder
    private func chipRows(_ L: Ledger, split: Bool) -> some View {
        let liquid = L.accounts.filter { $0.type == .current || $0.type == .cash }
        let usable = L.accounts.filter { $0.type != .invest }
        VStack(alignment: .leading, spacing: 8) {
            if pot != nil {
                chipRow {
                    ForEach(liquid) { a in
                        let key = d.potDir == .out ? d.to : d.acct
                        Chip(label: a.name, on: key == a.id) { if d.potDir == .out { d.to = a.id } else { d.acct = a.id } }
                    }
                }
            } else if d.type == .transfer {
                chipRow {
                    ForEach(L.accounts) { a in Chip(label: a.name, on: d.acct == a.id) { d.acct = a.id; if d.to == a.id { d.to = "" } } }
                }
            } else if split {
                chipRow { whoChips(L) }
                chipRow { ForEach(usable) { a in Chip(label: a.name, on: d.acct == a.id) { d.acct = a.id } } }
            } else {
                chipRow {
                    whoChips(L)
                    ForEach(usable) { a in Chip(label: a.name, on: d.acct == a.id) { d.acct = a.id } }
                }
            }
            if L.accounts.isEmpty {
                Button { dismiss(); router.form = .account(nil) } label: {
                    Text("Add an account first →").font(.geist(14, .medium)).foregroundStyle(Palette.lavender).frame(minHeight: 44)
                }
            }
            DatePicker("Date", selection: $d.date, displayedComponents: .date)
                .font(.geist(14, .medium)).foregroundStyle(Palette.mute)
                .tint(Palette.lavender)
                .frame(minHeight: 44)
        }
    }

    private func whoChips(_ L: Ledger) -> some View {
        ForEach([Who.joint, .a, .b]) { w in Chip(label: L.name(w), on: d.who == w, selected: Palette.lavender) { d.who = w } }
    }

    private func chipRow<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) { content() }.padding(.horizontal, 1) }
    }

    @ViewBuilder
    private func tiles(_ items: [(String, String)], selected: String, grid: Bool, pick: @escaping (String) -> Void) -> some View {
        if grid {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 10) {
                ForEach(items, id: \.0) { item in tile(item, on: selected == item.0, width: 61, square: 54) { pick(item.0) } }
            }
            .padding(.top, 3)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.0) { item in tile(item, on: selected == item.0, width: 68, square: 60) { pick(item.0) } }
                }
                .padding(.horizontal, 3).padding(.top, 3)
            }
        }
    }

    private func tile(_ item: (String, String), on: Bool, width: CGFloat, square: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(abbrev(item.1)).font(.geist(17, .semibold)).frame(width: square, height: square)
                    .background(on ? Palette.lavender : Palette.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(on ? Palette.lavender : .clear, lineWidth: 2).padding(-2))
                    .foregroundStyle(Palette.black)
                Text(item.1).font(.geist(12)).lineLimit(1).truncationMode(.tail).frame(maxWidth: width)
                    .foregroundStyle(on ? Palette.lavender : Palette.white)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func abbrev(_ s: String) -> String {
        let letters = s.filter { $0.isLetter }
        return letters.isEmpty ? "•" : String(letters.prefix(2))
    }

    // MARK: Keypad

    private func keypad(keyHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "0", "⌫"], id: \.self) { k in
                    let plain = k == "." || k == "⌫"
                    Button { key(k) } label: {
                        Text(k).font(.geist(26, .medium)).frame(maxWidth: .infinity).frame(height: keyHeight)
                            .background(plain ? .clear : Palette.white, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .foregroundStyle(plain ? Palette.white : Palette.black)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(k == "⌫" ? "Delete digit" : k == "." ? "Decimal point" : k)
                }
            }
            BlockButton(title: saveLabel, fill: Palette.lavender, text: Palette.black, height: 58, radius: 20) { save() }
        }
    }

    private func key(_ k: String) {
        var a = d.amt
        if k == "⌫" {
            if !a.isEmpty { a.removeLast() }
        } else if k == "." {
            if !a.contains(".") { a = (a.isEmpty ? "0" : a) + "." }
        } else if a == "0" {
            a = k
        } else if let dot = a.firstIndex(of: ".") {
            if a.distance(from: dot, to: a.endIndex) < 3 { a += k }
        } else if a.count < 7 {
            a += k
        }
        withAnimation(.snappy(duration: 0.15)) { d.amt = a }
        d.error = ""
    }

    // MARK: Save

    private func save() {
        guard let L = store.ledger() else { return }
        guard let amt = Double(d.amt), amt > 0 else { d.error = "Enter an amount first"; return }
        guard !d.acct.isEmpty else { d.error = L.accounts.isEmpty ? "Add an account first" : "Pick an account"; return }
        let isX = d.type == .transfer, isInc = d.type == .income
        if isX && (d.acct.isEmpty || d.to.isEmpty || d.acct == d.to) { d.error = "Pick two different accounts"; return }
        let cat = isX ? "transfer" : isInc ? "income" : (d.cat == "income" || d.cat == "transfer") ? "groceries" : d.cat
        let trimmed = d.name.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? (isX ? "Transfer" : isInc ? "Income" : L.categoryName(cat)) : trimmed
        let existing = store.tx.first { $0.id == d.txId }
        let t = Tx(id: d.txId, date: DateKit.iso(d.date), name: name, cat: cat, amt: amt, who: d.who, type: d.type,
                   note: d.note, billId: d.billId, acct: d.acct, to: isX ? d.to : nil, pot: isX ? d.pot : nil,
                   potDir: isX ? d.potDir : nil, createdAt: existing?.createdAt)
        store.save(t)
        dismiss()
    }
}

/// Wrapping row layout for chips on the wide (unfolded) screen.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > w { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
