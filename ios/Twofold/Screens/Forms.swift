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
        case .pot(let g): PotForm(editing: g)
        case .pay(let w): PayForm(who: w)
        case .budget(let c): BudgetSheet(cat: c)
        case .settings: NavigationStack { SettingsView(showBack: false) }
        case .newCategory: NewCategoryForm()
        case .debt(let d): DebtForm(editing: d)
        case .planned(let p): PlannedForm(editing: p)
        case .trip(let t): TripForm(editing: t)
        }
    }
}

// MARK: Budget limit (bottom sheet from the design)

@MainActor
struct BudgetSheet: View {
    var cat: String
    @Environment(HouseholdStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error = ""
    @State private var confirmDelete = false
    @State private var limit: Double = 0
    @State private var text = ""
    @State private var loaded = false
    @FocusState private var typing: Bool

    var body: some View {
        if let L = store.ledger() {
            let avg = L.average(of: cat)
            let custom = L.isCustom(cat)
            VStack(alignment: .leading, spacing: 0) {
                Text("Monthly limit").font(.geist(13)).foregroundStyle(Palette.gray)
                if custom {
                    HStack(spacing: 8) {
                        CreamField(placeholder: "Name", text: $name)
                        Button("Delete") { confirmDelete = true }
                            .font(.geist(14, .medium)).foregroundStyle(Palette.overText).frame(minWidth: 64, minHeight: 44)
                    }
                    .padding(.top, 6)
                    if !error.isEmpty { Text(error).font(.geist(13, .semibold)).foregroundStyle(Palette.overText).padding(.top, 6) }
                } else {
                    Text(L.categoryName(cat)).font(.geist(24, .medium)).tracking(em: -0.01, size: 24)
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
                    }
                    Spacer()
                    stepButton("+", "More") { set(limit + 50) }
                }
                .padding(.top, 20).padding(.bottom, 14)
                Text("Spent \(L.money.f(L.spentByCat[cat] ?? 0)) so far this month").font(.geist(13.5)).foregroundStyle(Palette.gray)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    BlockButton(title: "3-month avg · \(L.money.num(avg))", fill: Palette.black, outline: true, height: 54) { set(avg) }
                    BlockButton(title: "Save", height: 54) {
                        if custom {
                            let n = name.trimmingCharacters(in: .whitespaces)
                            if n.isEmpty { error = "Give it a name"; return }
                            if L.rows.contains(where: { $0.id != cat && $0.name.lowercased() == n.lowercased() }) {
                                error = "You already have a category with that name."; return
                            }
                            if n != L.categoryName(cat) { store.renameCategory(cat, to: n) }
                        }
                        store.setBudget(cat, limit); dismiss()
                    }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 12)
            .foregroundStyle(Palette.black)
            .presentationDetents([.height(custom ? 440 : 380)])
            .confirmationDialog("Delete this category?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { store.deleteCategory(cat); dismiss() }
            } message: {
                Text("Its limit goes too. Entries keep their amounts and show as “Other”.")
            }
            .presentationBackground(Palette.cream)
            .presentationCornerRadius(30)
            .presentationDragIndicator(.visible)
            .onAppear { if !loaded { set(L.household.budgets[cat] ?? 0); name = L.categoryName(cat); loaded = true } }
        }
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
        guard let a = editing, let L = store.ledger() else { return }
        name = a.name; type = a.type; who = a.who; bank = a.bank ?? ""; last4 = a.last4 ?? ""
        let b = L.balance(a)
        balance = fmt(a.type == .card ? -b : b)
        limit = a.limit.map(fmt) ?? ""; apy = a.apy.map(fmt) ?? ""; cardApr = a.apr.map(fmt) ?? ""
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
                           apr: type == .card ? parseAmount(cardApr) : nil, createdAt: editing?.createdAt))
    }
}

// MARK: Bill

@MainActor
struct BillForm: View {
    var editing: Bill?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var amt = ""
    @State private var day = 1
    @State private var cat = "housing"
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
        }
        .presentationDetents([.large])
        .onAppear {
            guard let b = editing else { return }
            name = b.name; amt = fmt(b.amt); day = b.day; cat = b.cat; sub = b.sub
        }
    }

    private func save() {
        store.save(Bill(id: editing?.id ?? "", day: day, name: name.trimmingCharacters(in: .whitespaces),
                        amt: parseAmount(amt) ?? 0, cat: cat, sub: sub, paid: editing?.paid ?? [:]))
    }
}

// MARK: Pot

@MainActor
struct PotForm: View {
    var editing: Goal?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var target = ""
    @State private var saved = ""
    @State private var monthly = ""
    @State private var acct = ""
    @State private var roundUps = false

    var body: some View {
        let L = store.ledger()
        let accts = (L?.accounts ?? []).filter { $0.type == .save }
        let choices = accts.isEmpty ? (L?.accounts ?? []) : accts
        FormSheetFrame(kicker: editing == nil ? "New pot" : "Edit pot", title: name.isEmpty ? "Pot" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(target) ?? 0) > 0 && !acct.isEmpty,
                       onSave: save, onDelete: editing == nil ? nil : { store.deleteGoal(editing!.id) },
                       deleteMessage: "The money stays in its account; only the pot goes.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Emergency fund", text: $name)
            FormLabel("Target (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $target, keyboard: .decimalPad)
            FormLabel("Already saved").padding(.top, 16)
            CreamField(placeholder: "0", text: $saved, keyboard: .decimalPad)
            FormLabel("Monthly contribution").padding(.top, 16)
            CreamField(placeholder: "0", text: $monthly, keyboard: .decimalPad)
            FormLabel("Lives in").padding(.top, 16)
            FlowLayout(spacing: 6) {
                ForEach(choices) { a in CreamChip(label: a.name, on: acct == a.id) { acct = a.id } }
            }
            if choices.isEmpty { Text("Add an account first.").font(.geist(13)).foregroundStyle(Palette.gray) }
            Toggle(isOn: $roundUps) { Text("Round-ups go to this pot").font(.geist(15)) }
                .tint(Palette.black).padding(.top, 16)
        }
        .presentationDetents([.large])
        .onAppear {
            if acct.isEmpty { acct = choices.first?.id ?? "" }
            if let g = editing, let L {
                name = g.name; target = fmt(g.target); saved = fmt(L.saved(g)); monthly = g.monthly > 0 ? fmt(g.monthly) : ""; acct = g.acct
                roundUps = L.household.roundUpPot == g.id
            }
        }
    }

    private func save() {
        let entered = parseAmount(saved) ?? 0
        var start = entered
        if let g = editing, let L = store.ledger() { start = g.startSaved + (entered - L.saved(g)) }
        let g = Goal(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), target: parseAmount(target) ?? 0,
                     startSaved: start, monthly: parseAmount(monthly) ?? 0, acct: acct, due: editing?.due, createdAt: editing?.createdAt)
        let id = store.save(g)
        if roundUps { store.setRoundUpPot(id) }
        else if store.household?.roundUpPot == id { store.setRoundUpPot(nil) }
    }
}

// MARK: New category

@MainActor
struct NewCategoryForm: View {
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var group = "needs"
    @State private var limit = ""

    var body: some View {
        let L = store.ledger()
        let n = name.trimmingCharacters(in: .whitespaces)
        let duplicate = L?.rows.contains { $0.name.lowercased() == n.lowercased() } ?? false
        FormSheetFrame(kicker: "Budget", title: "New category", canSave: !n.isEmpty && !duplicate,
                       onSave: { store.addCategory(name: n, group: group, limit: parseAmount(limit) ?? 0) }) {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Pets", text: $name)
            if duplicate {
                Text("You already have a category with that name.").font(.geist(13, .semibold)).foregroundStyle(Palette.overText).padding(.top, 6)
            }
            FormLabel("Group").padding(.top, 16)
            HStack(spacing: 6) {
                CreamChip(label: "Needs", on: group == "needs") { group = "needs" }
                CreamChip(label: "Wants", on: group == "wants") { group = "wants" }
            }
            FormLabel("Monthly limit (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $limit, keyboard: .decimalPad)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: Loan

@MainActor
struct DebtForm: View {
    var editing: Debt?
    @Environment(HouseholdStore.self) private var store
    @State private var name = ""
    @State private var balance = ""
    @State private var apr = ""
    @State private var min = ""

    var body: some View {
        let L = store.ledger()
        FormSheetFrame(kicker: editing == nil ? "New loan" : "Edit loan", title: name.isEmpty ? "Loan" : name,
                       canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty && (parseAmount(balance) ?? -1) >= 0,
                       onSave: save, onDelete: editing.map { d in { store.deleteDebt(d.id) } },
                       deleteMessage: "It comes off the payoff plan.") {
            FormLabel("Name")
            CreamField(placeholder: "e.g. Car loan", text: $name)
            FormLabel("Balance owed (\(L?.money.currency ?? ""))").padding(.top, 16)
            CreamField(placeholder: "0", text: $balance, keyboard: .decimalPad)
            FormLabel("Interest rate (APR %)").padding(.top, 16)
            CreamField(placeholder: "0", text: $apr, keyboard: .decimalPad)
            FormLabel("Minimum payment a month").padding(.top, 16)
            CreamField(placeholder: "0", text: $min, keyboard: .decimalPad)
            Text("Update the balance now and then; the plan works out the rest.")
                .font(.geist(13)).foregroundStyle(Palette.gray).padding(.top, 12)
        }
        .presentationDetents([.large])
        .onAppear {
            guard let d = editing else { return }
            name = d.name; balance = fmt(d.balance); apr = fmt(d.apr); min = fmt(d.min)
        }
    }

    private func save() {
        store.save(Debt(id: editing?.id ?? "", name: name.trimmingCharacters(in: .whitespaces), balance: parseAmount(balance) ?? 0,
                        apr: parseAmount(apr) ?? 0, min: parseAmount(min) ?? 0, createdAt: editing?.createdAt))
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
