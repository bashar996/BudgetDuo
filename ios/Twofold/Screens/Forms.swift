import SwiftUI

// MARK: Shared form pieces (cream sheets)

struct FormLabel: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.geist(13)).foregroundStyle(Palette.gray).padding(.bottom, 6) }
}

struct CreamField: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.gray))
            .font(.geist(16, .medium))
            .keyboardType(keyboard)
            .padding(.horizontal, 16).frame(height: 52)
            .background(Palette.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.black.opacity(0.1), lineWidth: 1))
            .foregroundStyle(Palette.black)
    }
}

struct CreamChip: View {
    var label: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.geist(13.5, .medium)).lineLimit(1).padding(.horizontal, 14).frame(height: 44)
                .foregroundStyle(on ? Palette.white : Palette.black)
                .background(on ? Palette.black : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black.opacity(on ? 1 : 0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Day-of-month picker: − day +
struct DayStepper: View {
    var label: String
    @Binding var day: Int
    var body: some View {
        HStack {
            Text(label).font(.geist(15))
            Spacer()
            Button("−") { day = max(1, day - 1) }.frame(width: 44, height: 44)
            Text("\(day)").font(.geist(20, .medium)).frame(minWidth: 36)
            Button("+") { day = min(31, day + 1) }.frame(width: 44, height: 44)
        }
        .font(.geist(22))
        .foregroundStyle(Palette.black)
        .accessibilityElement(children: .combine)
        .accessibilityValue("Day \(day)")
        .accessibilityAdjustableAction { dir in
            if dir == .increment { day = min(31, day + 1) } else if dir == .decrement { day = max(1, day - 1) }
        }
    }
}

/// Title on top, fields in the middle, Save / Delete pinned at the bottom.
struct FormSheetFrame<Content: View>: View {
    var kicker: String
    var title: String
    var saveTitle = "Save"
    var canSave = true
    var onSave: () -> Void
    var onDelete: (() -> Void)? = nil
    var deleteMessage = ""
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(kicker).font(.geist(13)).foregroundStyle(Palette.gray)
                    Text(title).font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
                }
                Spacer()
                Button { dismiss() } label: { Text("×").font(.geist(26)).frame(width: 44, height: 44) }.accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 20).padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            HStack(spacing: 8) {
                if let onDelete {
                    BlockButton(title: "Delete", fill: Palette.overText, outline: true, height: 54) { confirm = true }
                        .confirmationDialog("Delete \(title.lowercased())?", isPresented: $confirm, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { onDelete(); dismiss() }
                        } message: { Text(deleteMessage) }
                }
                BlockButton(title: saveTitle, height: 54) { onSave(); dismiss() }
                    .disabled(!canSave).opacity(canSave ? 1 : 0.4)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        }
        .foregroundStyle(Palette.black)
        .presentationBackground(Palette.cream)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }
}

func parseAmount(_ s: String) -> Double? {
    Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
}

struct FormHost: View {
    var form: FormSheet
    var body: some View {
        switch form {
        case .account(let a): AccountForm(editing: a)
        case .bill(let b): BillForm(editing: b)
        case .pot(let g): PotSheet(editing: g)
        case .pay(let w): PayForm(who: w)
        case .budget(let c): BudgetSheet(cat: c)
        case .settings: NavigationStack { SettingsView(showBack: false) }
        case .newCategory: BudgetSheet(cat: nil)
        case .debt(let d): LoanForm(editing: d)
        case .planned(let p): PlannedForm(editing: p)
        case .trip(let t): TripForm(editing: t)
        case .newCard: AccountForm(editing: nil, preset: .card)
        case .newInvestment: AccountForm(editing: nil, preset: .invest)
        case .asset(let a): AssetForm(editing: a)
        case .tripSpend(let t): TripSpendSheet(trip: t)
        }
    }
}

// MARK: Bottom sheets that fit their content (category, pot)

private struct SheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Cream bottom sheet with 30pt top corners, as tall as what's in it. The system
/// caps the height at the large detent; anything taller scrolls as a whole.
struct FitSheet<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 420

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 34)
                .background(GeometryReader { g in Color.clear.preference(key: SheetHeightKey.self, value: g.size.height) })
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onPreferenceChange(SheetHeightKey.self) { h in if h > 0 { height = h } }
        .foregroundStyle(Palette.black)
        .presentationDetents([.height(height)])
        .presentationBackground(Palette.cream)
        .presentationCornerRadius(30)
        .presentationDragIndicator(.visible)
    }
}

/// White 52pt input with a 2pt black ring while typing.
struct SheetField: View {
    var placeholder: String
    @Binding var text: String
    var size: CGFloat = 17
    var keyboard: UIKeyboardType = .default
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.gray))
            .font(.geist(size, .medium))
            .keyboardType(keyboard)
            .focused($focused)
            .padding(.horizontal, 16).frame(height: 52)
            .background(Palette.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.black.opacity(focused ? 1 : 0), lineWidth: 2))
            .foregroundStyle(Palette.black)
    }
}

private func sheetLabel(_ text: String) -> some View {
    Text(text).font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 12).padding(.bottom, 6)
}

private func sheetError(_ text: String, center: Bool = false) -> some View {
    Text(text).font(.geist(13, .semibold)).foregroundStyle(Palette.overText)
        .multilineTextAlignment(center ? .center : .leading)
        .frame(maxWidth: .infinity, minHeight: 18, alignment: center ? .center : .leading)
}

// MARK: Category (bottom sheet from the design)

/// Tap a category on Budget (or "+ New category"): name, Needs / Wants, monthly
/// limit. Pocket money only has the limit. Delete swaps the sheet's content for
/// the "where should its entries go?" step.
@MainActor
struct BudgetSheet: View {
    /// nil: a new category.
    var cat: String?
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = "needs"
    @State private var limit: Double = 0
    @State private var text = "0"
    @State private var error = ""
    @State private var deleting = false
    /// "" nothing picked yet, "none" leave uncategorised, otherwise a category id.
    @State private var moveTo = ""
    /// "Or move money in from": the category giving up part of its limit ("" none).
    @State private var moveFrom = ""
    @State private var moveText = ""
    @State private var loaded = false
    @FocusState private var typing: Bool

    var body: some View {
        if let L = store.ledger() {
            FitSheet {
                if deleting, let id = cat {
                    deleteStep(L, id)
                } else {
                    form(L)
                }
            }
            .onAppear { load(L) }
        }
    }

    private var isPocketMoney: Bool { cat.map(Catalog.isPocketMoney) ?? false }

    private func form(_ L: Ledger) -> some View {
        let id = cat ?? ""
        let isNew = cat == nil
        let lock = isPocketMoney
        let avg = isNew ? 0 : L.average(of: id)
        return VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "New category" : lock ? "Monthly limit" : "Edit category").font(.geist(13)).foregroundStyle(Palette.gray)
            if lock {
                Text(L.categoryName(id)).font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SheetField(placeholder: "Category name", text: $name, size: 18)
                    HStack(spacing: 6) {
                        groupChip("Needs", "needs")
                        groupChip("Wants", "wants")
                    }
                    Text("Monthly limit").font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                }
                .padding(.top, 8)
            }
            HStack {
                stepButton("−", "Less") { set(limit - 50) }
                Spacer()
                VStack(spacing: 0) {
                    Text(L.money.currency).font(.geist(13)).foregroundStyle(Palette.gray)
                    TextField("0", text: $text)
                        .font(.geist(52, .medium)).tracking(em: -0.04, size: 52)
                        .multilineTextAlignment(.center).keyboardType(.numberPad).focused($typing)
                        .onChange(of: text) { _, v in if typing { limit = max(0, parseAmount(v) ?? 0) } }
                        .accessibilityLabel("Monthly limit")
                }
                Spacer()
                stepButton("+", "More") { set(limit + 50) }
            }
            .padding(.top, 14).padding(.bottom, 12)
            Text(isNew ? "What you plan to spend on it each month" : "Spent \(L.money.f(L.spentByCat[id] ?? 0)) so far this month")
                .font(.geist(13.5)).foregroundStyle(Palette.gray).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            if !isNew { extras(L, id) }
            sheetError(error, center: true).padding(.top, 6)
            HStack(spacing: 8) {
                BlockButton(title: "3-month avg · \(L.money.num(avg))", fill: Palette.black, outline: true, height: 54) { set(avg) }
                BlockButton(title: "Save", height: 54) { save(L) }
            }
            .padding(.top, 6)
            if !isNew && !lock {
                Button { deleting = true; moveTo = ""; error = "" } label: {
                    Text("Delete category").font(.geist(14, .medium)).foregroundStyle(Palette.overText)
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    /// Existing categories: move money in from one with room, and the latest entries
    /// (as the Mac's category panel).
    private func extras(_ L: Ledger, _ id: String) -> some View {
        let from = Array(L.rows.filter { $0.id != id && $0.left > 0 }.sorted { $0.left > $1.left }.prefix(6))
        let latest = Array(L.monthExpenses.filter { $0.cat == id }.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            if !from.isEmpty {
                sheetLabel("Or move money in from")
                FlowLayout(spacing: 6) {
                    ForEach(from) { r in
                        CreamChip(label: "\(r.name) · \(L.money.f(r.left))", on: moveFrom == r.id) {
                            moveFrom = moveFrom == r.id ? "" : r.id; error = ""
                        }
                    }
                }
                if !moveFrom.isEmpty {
                    SheetField(placeholder: "Amount to move", text: $moveText, size: 16, keyboard: .decimalPad).padding(.top, 8)
                    Text("Comes off \(L.categoryName(moveFrom))’s limit and goes on top of this one when you save.")
                        .font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !latest.isEmpty {
                sheetLabel("Latest in this category")
                ForEach(latest) { t in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(String(DateKit.dayLabel(t.date).dropFirst(4))).font(.geist(13)).foregroundStyle(Palette.gray).frame(width: 50, alignment: .leading)
                        Text(t.name).font(.geist(15)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L.money.f(t.amt)).font(.geist(15, .medium)).lineLimit(1).fixedSize()
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Hairline(opacity: 0.1) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.top, 4).padding(.bottom, 6)
    }

    private func deleteStep(_ L: Ledger, _ id: String) -> some View {
        let use = L.usage(of: id)
        let used = use.entries + use.bills > 0
        return VStack(alignment: .leading, spacing: 0) {
            Text("Delete category").font(.geist(13)).foregroundStyle(Palette.gray)
            Text("Delete \(name.isEmpty ? L.categoryName(id) : name)?").font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
            Text(usageText(entries: use.entries, bills: use.bills)).font(.geist(14.5)).padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)
            if used {
                // "Leave uncategorised" first so it's always in view; every chip shows at once.
                FlowLayout(spacing: 6) {
                    CreamChip(label: "Leave uncategorised", on: moveTo == "none") { moveTo = "none"; error = "" }
                    ForEach(L.rows.filter { $0.id != id }) { r in
                        CreamChip(label: r.name, on: moveTo == r.id) { moveTo = r.id; error = "" }
                    }
                }
                .padding(.top, 14)
                Text("Uncategorised entries stay in Activity but stop counting toward any budget.")
                    .font(.geist(12.5)).foregroundStyle(Palette.gray).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            sheetError(error).padding(.top, 10)
            HStack(spacing: 8) {
                BlockButton(title: "Keep it", fill: Palette.black, outline: true, height: 54) { deleting = false; moveTo = ""; error = "" }
                BlockButton(title: "Delete", fill: Palette.bad, height: 54) {
                    if used && moveTo.isEmpty { error = "Choose where its entries should go."; return }
                    store.deleteCategory(id, moveTo: moveTo.isEmpty || moveTo == "none" ? nil : moveTo)
                    dismiss()
                }
            }
            .padding(.top, 6)
        }
    }

    private func usageText(entries: Int, bills: Int) -> String {
        let n = entries + bills
        if n == 0 { return "Nothing uses this category yet, so it can go straight away." }
        var parts: [String] = []
        if entries > 0 { parts.append("\(entries) " + (entries == 1 ? "entry" : "entries")) }
        if bills > 0 { parts.append("\(bills) " + (bills == 1 ? "bill" : "bills")) }
        let verb = n == 1 ? "uses" : "use"
        let them = n == 1 ? "it" : "they"
        return "\(parts.joined(separator: " and ")) \(verb) this category. Where should \(them) go?"
    }

    private func groupChip(_ label: String, _ value: String) -> some View {
        let on = group == value
        return Button { group = value; error = "" } label: {
            Text(label).font(.geist(13.5, .medium)).frame(maxWidth: .infinity).frame(height: 44)
                .foregroundStyle(on ? Palette.white : Palette.black)
                .background(on ? Palette.black : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black.opacity(on ? 1 : 0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func load(_ L: Ledger) {
        guard !loaded else { return }
        loaded = true
        if let id = cat {
            set(L.household.budgets[id] ?? 0)
            let row = L.rows.first { $0.id == id }
            name = row?.name ?? ""
            group = (row?.group ?? .needs) == .wants ? "wants" : "needs"
        } else {
            set(0)
        }
    }

    private func save(_ L: Ledger) {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !isPocketMoney {
            if n.isEmpty { error = "Give it a name."; return }
            if L.rows.contains(where: { $0.id != cat && $0.name.lowercased() == n.lowercased() }) {
                error = "You already have a category with that name."; return
            }
        }
        if let id = cat {
            if !isPocketMoney, let row = L.rows.first(where: { $0.id == id }), row.name != n || row.group.rawValue != group {
                store.updateCategory(id, name: n, group: group)
            }
            store.setBudget(id, limit)
            if !moveFrom.isEmpty, let typed = parseAmount(moveText), typed > 0 {
                // Never more than the other category's limit (as the Mac).
                let mv = min(typed, L.household.budgets[moveFrom] ?? 0)
                if mv > 0 { store.moveBudget(from: moveFrom, to: id, amount: mv) }
            }
        } else {
            store.addCategory(name: n, group: group, limit: limit)
        }
        dismiss()
    }

    private func set(_ v: Double) {
        limit = max(0, v)
        text = Money(currency: "").num(limit).replacingOccurrences(of: ",", with: "")
    }

    private func stepButton(_ s: String, _ label: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.geist(28)).frame(width: 58, height: 58)
                .background(Palette.black, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                .foregroundStyle(Palette.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: Pay

struct PayForm: View {
    var who: Who
    @Environment(HouseholdStore.self) private var store
    @State private var amt = ""
    @State private var day = 1

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: "Income coming in", title: "\(L?.name(who) ?? "")’s pay", canSave: parseAmount(amt) != nil) {
            store.setIncome(who, amt: parseAmount(amt) ?? 0, day: day)
        } content: {
            FormLabel("Monthly take-home pay (\(L?.money.currency ?? ""))")
            CreamField(placeholder: "0", text: $amt, keyboard: .decimalPad)
            DayStepper(label: "Payday (day of the month)", day: $day).padding(.top, 16)
            Text("Pay feeds “Left to assign” on the Budget tab. Log the actual salary as income when it lands.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 12)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let inc = store.household?.incomes.first(where: { $0.who == who }) {
                amt = inc.amt > 0 ? fmt(inc.amt) : ""; day = inc.day
            }
        }
    }
}

// MARK: Account

@MainActor
struct AccountForm: View {
    var editing: Account?
    /// The type a new account starts as.
    var preset: AccountType? = nil
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var type: AccountType = .current
    @State private var who: Who = .joint
    @State private var bank = ""
    @State private var last4 = ""
    @State private var balance = ""
    @State private var limit = ""
    @State private var apy = ""
    @State private var cardApr = ""
    @State private var cost = ""
    @State private var statementDay = ""
    @State private var dueDay = ""
    @State private var minPct = ""
    @State private var minFloor = ""

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: editing == nil ? "New account" : "Edit account", title: name.isEmpty ? "Account" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && parseAmount(balance.isEmpty ? "0" : balance) != nil,
                       onSave: save, onDelete: editing == nil ? nil : { store.deleteAccount(editing!.id) },
                       deleteMessage: "Entries that used this account stay, but won’t count towards any balance.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Joint current account", text: $name)
            FormLabel("Type").padding(.top, 16)
            FlowLayout(spacing: 6) {
                ForEach(AccountType.allCases) { t in CreamChip(label: t.label, on: type == t) { type = t } }
            }
            FormLabel("Whose").padding(.top, 16)
            HStack(spacing: 6) {
                ForEach([Who.joint, .a, .b]) { w in CreamChip(label: L?.name(w) ?? w.rawValue, on: who == w) { who = w } }
            }
            FormLabel(type == .card ? "Amount owed now (\(L?.money.currency ?? ""))" : "Current balance (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $balance, keyboard: .decimalPad)
            if type == .card {
                FormLabel("Credit limit").padding(.top, 16)
                CreamField(placeholder: "Optional", text: $limit, keyboard: .decimalPad)
                FormLabel("Interest rate (APR %)").padding(.top, 16)
                CreamField(placeholder: "36 if left empty", text: $cardApr, keyboard: .decimalPad)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Statement day")
                        CreamField(placeholder: "Day 1–31", text: $statementDay, keyboard: .numberPad)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Due day")
                        CreamField(placeholder: "Day 1–31", text: $dueDay, keyboard: .numberPad)
                    }
                }
                .padding(.top, 16)
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Minimum %")
                        CreamField(placeholder: "5", text: $minPct, keyboard: .decimalPad)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        FormLabel("Minimum at least")
                        CreamField(placeholder: "100", text: $minFloor, keyboard: .decimalPad)
                    }
                }
                .padding(.top, 16)
                Text("The minimum payment is that % of what’s owed, but never less than the amount on the right.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if type == .invest {
                FormLabel("Amount you put in (optional)").padding(.top, 16)
                CreamField(placeholder: "Optional", text: $cost, keyboard: .decimalPad)
                Text("Net worth shows the gain: what it’s worth now minus what you put in.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
            }
            if type == .save || type == .invest {
                FormLabel("Interest a year (%)").padding(.top, 16)
                CreamField(placeholder: "Optional", text: $apy, keyboard: .decimalPad)
            }
            FormLabel("Bank").padding(.top, 16)
            CreamField(placeholder: "Optional", text: $bank)
            FormLabel("Last 4 digits").padding(.top, 16)
            CreamField(placeholder: "Optional", text: $last4, keyboard: .numberPad)
        }
        .presentationDetents([.large])
        .onAppear(perform: load)
    }

    private func load() {
        if editing == nil, let preset { type = preset }
        guard let a = editing, let L = store.ledger() else { return }
        name = a.name; type = a.type; who = a.who; bank = a.bank ?? ""; last4 = a.last4 ?? ""
        let b = L.balance(a)
        balance = fmt(a.type == .card ? -b : b)
        limit = a.limit.map(fmt) ?? ""; apy = a.apy.map(fmt) ?? ""; cardApr = a.apr.map(fmt) ?? ""; cost = a.cost.map(fmt) ?? ""
        statementDay = a.statementDay.map { String($0) } ?? ""; dueDay = a.dueDay.map { String($0) } ?? ""
        minPct = a.minPct.map(fmt) ?? ""; minFloor = a.minFloor.map(fmt) ?? ""
    }

    /// A day of the month typed in, or nil.
    private func day(_ s: String) -> Int? {
        guard let n = Int(s.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return Swift.min(31, n)
    }

    private func save() {
        var entered = parseAmount(balance) ?? 0
        if type == .card { entered = -abs(entered) }
        // Keep the entries' effect and set the opening so today's balance is what was typed.
        var opening = entered
        if let a = editing, let L = store.ledger() { opening = a.opening + (entered - L.balance(a)) }
        store.save(Account(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), type: type, who: who,
                           bank: bank.isEmpty ? nil : bank, last4: last4.isEmpty ? nil : String(last4.suffix(4)),
                           opening: opening, limit: type == .card ? parseAmount(limit) : nil,
                           apy: (type == .save || type == .invest) ? parseAmount(apy) : nil,
                           apr: type == .card ? parseAmount(cardApr) : nil,
                           cost: type == .invest ? parseAmount(cost).flatMap { $0 > 0 ? $0 : nil } : nil,
                           createdAt: editing?.createdAt,
                           statementDay: type == .card ? day(statementDay) : nil,
                           dueDay: type == .card ? day(dueDay) : nil,
                           minPct: type == .card ? parseAmount(minPct).flatMap { $0 >= 0 ? $0 : nil } : nil,
                           minFloor: type == .card ? parseAmount(minFloor).flatMap { $0 >= 0 ? $0 : nil } : nil))
    }
}

// MARK: Bill

@MainActor
struct BillForm: View {
    var editing: Bill?
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router
    @State private var name = ""
    @State private var amt = ""
    @State private var day = 1
    @State private var cat = ""
    @State private var sub = false

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: editing == nil ? "New bill" : "Edit bill", title: name.isEmpty ? "Bill" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(amt) ?? 0) > 0,
                       onSave: save, onDelete: editing == nil ? nil : { store.deleteBill(editing!.id) },
                       deleteMessage: "Payments already logged stay in Activity.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Rent", text: $name)
            FormLabel("Amount each month (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $amt, keyboard: .decimalPad)
            DayStepper(label: "Day of the month it’s due", day: $day).padding(.top, 12)
            FormLabel("Category").padding(.top, 12)
            FlowLayout(spacing: 6) {
                ForEach(L?.rows ?? []) { r in CreamChip(label: r.name, on: cat == r.id) { cat = r.id } }
            }
            Toggle(isOn: $sub) { Text("Subscription").font(.geist(15)) }
                .tint(Palette.black).padding(.top, 16)
            if let id = editing?.debtId, let loan = store.debts.first(where: { $0.id == id }) {
                Text("Shows the installment of \(loan.name). Paying it here pays the loan; change the amount or day from the loan, on Debt.")
                    .font(.geist(13.5)).foregroundStyle(Palette.gray).padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)
                Button { router.form = nil; router.drill(.loan(id)) } label: {
                    Text("Open the loan →").font(.geist(14, .medium)).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let b = editing {
                name = b.name; amt = fmt(b.amt); day = b.day; cat = b.cat; sub = b.sub
            } else if cat.isEmpty {
                // Utilities, or the first category left if it was deleted.
                cat = L?.catOr("utilities") ?? "utilities"
            }
        }
    }

    private func save() {
        store.save(Bill(id: editing?.id ?? "", day: day, name: name.trimmingCharacters(in: .whitespaces),
                        amt: parseAmount(amt) ?? 0, cat: cat, sub: sub, paid: editing?.paid ?? [:], debtId: editing?.debtId))
    }
}

// MARK: Pot (bottom sheet from the design)

@MainActor
struct PotSheet: View {
    var editing: Goal?
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var target = ""
    @State private var monthly = ""
    @State private var acct = ""
    @State private var roundUps = false
    @State private var error = ""
    @State private var deleting = false
    @State private var loaded = false

    var body: some View {
        if let L = store.ledger() {
            FitSheet {
                if deleting, let g = editing {
                    deleteStep(L, g)
                } else {
                    form(L)
                }
            }
            .onAppear { load(L) }
        }
    }

    private func form(_ L: Ledger) -> some View {
        let savings = L.accounts.filter { $0.type == .save }
        return VStack(alignment: .leading, spacing: 0) {
            Text(editing == nil ? "New savings pot" : "Edit pot").font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
            sheetLabel("Name")
            SheetField(placeholder: "e.g. New car", text: $name)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    sheetLabel("Target (\(L.money.currency))")
                    SheetField(placeholder: "0", text: $target, keyboard: .decimalPad)
                }
                VStack(alignment: .leading, spacing: 0) {
                    sheetLabel("Auto-save each payday").lineLimit(1).minimumScaleFactor(0.8)
                    SheetField(placeholder: "0", text: $monthly, keyboard: .decimalPad)
                }
            }
            sheetLabel("Kept in")
            if savings.isEmpty {
                Text("No savings account yet. Add one under More → Accounts so the pot has a home.")
                    .font(.geist(13.5)).foregroundStyle(Palette.gray).fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(savings) { a in CreamChip(label: a.name, on: acct == a.id) { acct = a.id; error = "" } }
                }
            }
            Toggle(isOn: $roundUps) { Text("Round-ups go to this pot").font(.geist(15)) }
                .tint(Palette.black).padding(.top, 14)
            sheetError(error).padding(.top, 10)
            BlockButton(title: "Save", height: 54) { save(L) }.padding(.top, 6)
            if editing != nil {
                Button { deleting = true; error = "" } label: {
                    Text("Delete pot").font(.geist(14, .medium)).foregroundStyle(Palette.overText)
                        .frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func deleteStep(_ L: Ledger, _ g: Goal) -> some View {
        let saved = L.saved(g)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Delete pot").font(.geist(13)).foregroundStyle(Palette.gray)
            Text("Delete \(g.name)?").font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
            Text(saved > 0
                 ? "\(L.money.f(saved)) is set aside in this pot. The money stays in \(L.accountName(g.acct)); it just stops being earmarked."
                 : "Nothing is saved in this pot yet, so it can go straight away.")
                .font(.geist(14.5)).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BlockButton(title: "Keep it", fill: Palette.black, outline: true, height: 54) { deleting = false }
                BlockButton(title: "Delete", fill: Palette.bad, height: 54) {
                    store.deleteGoal(g.id)
                    if L.household.roundUpPot == g.id { store.setRoundUpPot(nil) }
                    dismiss()
                }
            }
            .padding(.top, 20)
        }
    }

    private func load(_ L: Ledger) {
        guard !loaded else { return }
        loaded = true
        if let g = editing {
            name = g.name; target = fmt(g.target); monthly = g.monthly > 0 ? fmt(g.monthly) : ""; acct = g.acct
            roundUps = L.household.roundUpPot == g.id
        } else {
            acct = L.accounts.first { $0.type == .save }?.id ?? ""
        }
    }

    private func save(_ L: Ledger) {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { error = "Give it a name"; return }
        guard let t = parseAmount(target), t > 0 else { error = "Add a target amount"; return }
        guard !acct.isEmpty else { error = "Add a savings account first"; return }
        let m = max(0, parseAmount(monthly) ?? 0)
        // Auto-save is on for a new pot with a payday amount; 0 turns it off.
        let auto: Bool = m > 0 ? (editing.map { ($0.auto ?? false) || $0.monthly == 0 } ?? true) : false
        // New pots start at 0; an edited pot keeps what's in it.
        let g = Goal(id: editing?.id ?? "", name: n, target: t, startSaved: editing?.startSaved ?? 0, monthly: m,
                     acct: acct, due: editing?.due, auto: auto, createdAt: editing?.createdAt)
        let id = store.save(g)
        if roundUps {
            if L.household.roundUpPot != id { store.setRoundUpPot(id) }
        } else if L.household.roundUpPot == id {
            store.setRoundUpPot(nil)
        }
        dismiss()
    }
}

// MARK: Planned purchase

@MainActor
struct PlannedForm: View {
    var editing: Planned?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var cost = ""
    @State private var a = false
    @State private var b = false

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: editing == nil ? "Planned purchase" : "Edit planned purchase", title: name.isEmpty ? "Purchase" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(cost) ?? 0) > 0,
                       onSave: save, onDelete: editing.map { p in { store.deletePlanned(p.id) } },
                       deleteMessage: "It comes off the plan.") {
            FormLabel("What is it?")
            CreamField(placeholder: "e.g. New sofa", text: $name)
            FormLabel("Expected cost (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $cost, keyboard: .decimalPad)
            FormLabel("Who’s in?").padding(.top, 16)
            Toggle(isOn: $a) { Text(L?.household.nameA ?? "A").font(.geist(15)) }.tint(Palette.black)
            Toggle(isOn: $b) { Text(L?.household.nameB ?? "B").font(.geist(15)) }.tint(Palette.black).padding(.top, 4)
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let p = editing { name = p.name; cost = fmt(p.cost); a = p.A; b = p.B }
            else { a = store.me == .a; b = store.me == .b }
        }
    }

    private func save() {
        store.save(Planned(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), cost: parseAmount(cost) ?? 0,
                           A: a, B: b, createdAt: editing?.createdAt))
    }
}

// MARK: Trip or event

@MainActor
struct TripForm: View {
    var editing: Trip?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var when = ""
    @State private var budget = ""
    @State private var spent = ""

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: editing == nil ? "Trip or event" : "Edit trip or event", title: name.isEmpty ? "Trip" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(budget) ?? 0) > 0,
                       onSave: save, onDelete: editing.map { t in { store.deleteTrip(t.id) } },
                       deleteMessage: "It comes off the plan.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Eid break getaway", text: $name)
            FormLabel("When").padding(.top, 16)
            CreamField(placeholder: "e.g. Mar 2027", text: $when)
            FormLabel("Total budget (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $budget, keyboard: .decimalPad)
            FormLabel("Spent so far").padding(.top, 16)
            CreamField(placeholder: "0", text: $spent, keyboard: .decimalPad)
        }
        .presentationDetents([.large])
        .onAppear {
            guard let t = editing else { return }
            name = t.name; when = t.when; budget = fmt(t.budget); spent = t.spent > 0 ? fmt(t.spent) : ""
        }
    }

    private func save() {
        store.save(Trip(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), when: when.trimmingCharacters(in: .whitespaces),
                        budget: parseAmount(budget) ?? 0, spent: parseAmount(spent) ?? 0, createdAt: editing?.createdAt))
    }
}

// MARK: Asset (Net worth)

/// A home, car, gold …: name, kind and what it's worth today (the Mac's asset panel).
@MainActor
struct AssetForm: View {
    var editing: Asset?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var kind = "property"
    @State private var value = ""

    var body: some View {
        let cur = store.household?.currency ?? ""
        FormSheetFrame(kicker: editing == nil ? "New asset" : "Edit asset", title: name.isEmpty ? "Asset" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && parseAmount(value) != nil,
                       onSave: save, onDelete: editing.map { a in { store.deleteAsset(a.id) } },
                       deleteMessage: "It comes off your net worth.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Our flat", text: $name)
            FormLabel("Kind").padding(.top, 16)
            FlowLayout(spacing: 6) {
                ForEach(Asset.kinds, id: \.id) { k in CreamChip(label: k.label, on: kind == k.id) { kind = k.id } }
            }
            FormLabel("What it’s worth today (\(cur))").padding(.top, 16)
            CreamField(placeholder: "0", text: $value, keyboard: .decimalPad)
            Text("Valued by hand; entries never move it. Update it now and then.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
        }
        .presentationDetents([.large])
        .onAppear {
            guard let a = editing else { return }
            name = a.name; kind = a.kind; value = fmt(a.value)
        }
    }

    private func save() {
        store.save(Asset(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                         value: parseAmount(value) ?? 0, createdAt: editing?.createdAt))
    }
}

// MARK: Spending on a trip (Plan ahead → Log spend)

/// Logs spending on a trip or event: a Travel expense today, added to what the trip has spent.
@MainActor
struct TripSpendSheet: View {
    var trip: Trip
    @Environment(HouseholdStore.self) private var store
    @State private var amt = ""
    @State private var acct = ""

    var body: some View {
        let L = store.ledger()
        let accounts = (L?.accounts ?? []).filter { $0.type != .invest }
        FormSheetFrame(kicker: "Log spend", title: trip.name, saveTitle: "Log spend",
                       canSave: (parseAmount(amt) ?? 0) > 0, onSave: save) {
            FormLabel("Amount (\(L?.money.currency ?? ""))")
            CreamField(placeholder: "0", text: $amt, keyboard: .decimalPad)
            FlowLayout(spacing: 6) {
                ForEach([100.0, 250, 500, 1000], id: \.self) { v in
                    CreamChip(label: "+" + Money(currency: "").num(v), on: false) {
                        amt = fmt((parseAmount(amt) ?? 0) + v)
                    }
                }
            }
            .padding(.top, 10)
            if !accounts.isEmpty {
                FormLabel("Paid from").padding(.top, 16)
                FlowLayout(spacing: 6) {
                    ForEach(accounts) { a in CreamChip(label: a.name, on: acct == a.id) { acct = a.id } }
                }
            }
            if let L {
                Text("\(L.money.f(trip.spent)) of \(L.money.f(trip.budget)) spent so far. It’s logged as a \(L.categoryName(L.catOr("travel"))) expense today.")
                    .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { if acct.isEmpty { acct = L?.mainAccountId ?? "" } }
    }

    private func save() {
        store.spendOnTrip(trip, amount: parseAmount(amt) ?? 0, account: acct)
    }
}
