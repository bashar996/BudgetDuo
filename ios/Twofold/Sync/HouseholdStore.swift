import Foundation
import Observation
import FirebaseFirestore

/// Live copy of one household. Firestore keeps a local cache, so everything
/// works offline and syncs to the other phone when the connection is back.
@MainActor
@Observable
final class HouseholdStore {
    let uid: String
    let householdId: String

    private(set) var household: Household?
    private(set) var tx: [Tx] = []
    private(set) var accounts: [Account] = []
    private(set) var bills: [Bill] = []
    private(set) var goals: [Goal] = []
    private(set) var debts: [Debt] = []
    private(set) var planned: [Planned] = []
    private(set) var trips: [Trip] = []
    /// Homes, cars, gold … (a missing collection is just empty).
    private(set) var assets: [Asset] = []
    /// True while something saved on this phone hasn't reached the server yet.
    private(set) var syncing = false
    private(set) var missing = false
    var error: String?

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var pending: [String: Bool] = [:]
    /// Loan schedules are replayed only when the loans, the entries or the day change.
    @ObservationIgnored private var loanCache: (day: String, debts: [Debt], tx: [Tx], states: [String: LoanState])?
    /// Today ("yyyy-MM-dd"), moved on by `dayTick()`, so screens (which read it through
    /// `ledger()`) and plan billing move on at midnight.
    private(set) var today = DateKit.iso(Date())
    /// Collections that have had a snapshot from the server this session. Plans are billed
    /// only once the entries, loans and accounts are all in (a half-loaded cache could make a
    /// closed plan look open).
    @ObservationIgnored private var synced: Set<String> = []
    /// Card plans with a billing write in flight: plan id → the billedThrough it writes, and when.
    @ObservationIgnored private var billing: [String: (to: Int, at: Date)] = [:]
    @ObservationIgnored private var billQueued = false

    init(uid: String, householdId: String) {
        self.uid = uid
        self.householdId = householdId
        listen()
    }

    deinit { listeners.forEach { $0.remove() } }

    private var root: DocumentReference { db.collection("households").document(householdId) }
    private func col(_ name: String) -> CollectionReference { root.collection(name) }

    private func listen() {
        listeners.append(root.addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
            guard let self else { return }
            if let snap {
                if !snap.exists, !snap.metadata.isFromCache { self.missing = true }
                if let hh = try? snap.data(as: Household.self) { self.household = hh; self.missing = false }
                self.track("hh", snap.metadata.hasPendingWrites)
                // Card plans may be waiting for the household (billPlans needs it).
                if self.household != nil { self.queueBilling() }
            } else if let err {
                self.error = err.localizedDescription
                self.missing = true
            }
        })
        watch("tx", into: \.tx, sort: { $0.date == $1.date ? ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) : $0.date > $1.date })
        watch("accounts", into: \.accounts, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        watch("bills", into: \.bills, sort: { $0.day < $1.day })
        watch("goals", into: \.goals, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        watch("debts", into: \.debts, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        watch("planned", into: \.planned, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        watch("events", into: \.trips, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
        watch("assets", into: \.assets, sort: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })
    }

    private func watch<T: Decodable>(_ name: String, into path: ReferenceWritableKeyPath<HouseholdStore, [T]>, sort: @escaping (T, T) -> Bool) {
        listeners.append(col(name).addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
            guard let self else { return }
            if let err { self.error = err.localizedDescription; return }
            guard let snap else { return }
            self[keyPath: path] = snap.documents.compactMap { try? $0.data(as: T.self) }.sorted(by: sort)
            self.track(name, snap.metadata.hasPendingWrites)
            if !snap.metadata.isFromCache { self.synced.insert(name) }
            // Card plans bill themselves whenever their data changes (billPlans).
            if name == "tx" || name == "debts" || name == "accounts" { self.queueBilling() }
        })
    }

    private func track(_ key: String, _ isPending: Bool) {
        pending[key] = isPending
        syncing = pending.values.contains(true)
    }

    // MARK: Derived

    var me: Who { Who(rawValue: household?.memberWho[uid] ?? "A") ?? .a }
    var partnerJoined: Bool { (household?.members.count ?? 0) > 1 }

    func ledger(today: Date = Date()) -> Ledger? {
        guard let household else { return nil }
        // Read so that screens showing the ledger refresh when the day changes.
        _ = self.today
        let day = DateKit.iso(today)
        let states: [String: LoanState]
        if let c = loanCache, c.day == day, c.debts == debts, c.tx == tx {
            states = c.states
        } else {
            states = Ledger.computeLoanStates(debts, tx, today: day)
            loanCache = (day: day, debts: debts, tx: tx, states: states)
        }
        return Ledger(household: household, tx: tx, accounts: accounts, bills: bills, goals: goals,
                      debts: debts, planned: planned, trips: trips, assets: assets, today: today, loanStates: states)
    }

    // MARK: Writes
    // Firestore applies writes to the local cache immediately and retries them
    // in the background, so none of these wait for the network.

    private func write(_ body: () throws -> Void) {
        do { try body() } catch { self.error = error.localizedDescription }
    }

    nonisolated private func report(_ err: Error?) {
        if let err { Task { @MainActor in self.error = err.localizedDescription } }
    }

    func save(_ t: Tx) {
        var t = t
        let ref = t.id.isEmpty ? col("tx").document() : col("tx").document(t.id)
        t.id = ref.documentID
        if t.createdAt == nil { t.createdAt = Date() }
        write { try ref.setData(from: t, completion: report) }
    }

    /// The month a bill payment marked paid: the end of its fixed id ("bill-{billId}-{yyyy-MM}"),
    /// which is the calendar month the bill was due (with a budget month that doesn't start
    /// on the 1st, an imported payment can be dated in another month); else the entry's month.
    private func paidKey(_ t: Tx, billId: String) -> String {
        let prefix = "bill-\(billId)-"
        if t.id.hasPrefix(prefix) {
            let key = String(t.id.dropFirst(prefix.count))
            if key.count == 7 { return key }
        }
        return t.month
    }

    /// Deletes an entry; a bill payment also marks that bill unpaid again.
    func deleteEntry(_ t: Tx) {
        guard !t.id.isEmpty else { return }
        let batch = db.batch()
        batch.deleteDocument(col("tx").document(t.id))
        if let billId = t.billId, bills.contains(where: { $0.id == billId }) {
            batch.updateData(["paid.\(paidKey(t, billId: billId))": false], forDocument: col("bills").document(billId))
        }
        batch.commit(completion: report)
    }

    /// Puts a deleted entry back with the same id and fields (Undo). A bill payment
    /// also marks its bill paid again, as deleting it had unmarked it.
    func restore(_ t: Tx) {
        guard !t.id.isEmpty else { return }
        let batch = db.batch()
        let ref = col("tx").document(t.id)
        write { try batch.setData(from: t, forDocument: ref) }
        if let billId = t.billId, bills.contains(where: { $0.id == billId }) {
            batch.updateData(["paid.\(paidKey(t, billId: billId))": true], forDocument: col("bills").document(billId))
        }
        batch.commit(completion: report)
    }

    // MARK: Statement import

    /// Writes imported entries in batches of at most 450 writes (an entry and the bill it
    /// pays always share a batch). A bill match uses its fixed entry id and marks the bill
    /// paid for that month. Returns what Undo needs.
    @discardableResult
    func importEntries(_ entries: [ImportEntry]) -> ImportUndo {
        var ids: [String] = []
        var marked: [BillMonth] = []
        var batch = db.batch()
        var count = 0
        for e in entries {
            let paysBill = e.bill.map { b in bills.contains { $0.id == b.id } } ?? false
            if count + (paysBill ? 2 : 1) > 450 {
                batch.commit(completion: report)
                batch = db.batch()
                count = 0
            }
            var t = e.tx
            let ref = t.id.isEmpty ? col("tx").document() : col("tx").document(t.id)
            t.id = ref.documentID
            if t.createdAt == nil { t.createdAt = Date() }
            let current = batch
            write { try current.setData(from: t, forDocument: ref) }
            count += 1
            ids.append(t.id)
            if paysBill, let b = e.bill {
                batch.updateData(["paid.\(b.ym)": true], forDocument: col("bills").document(b.id))
                marked.append(b)
                count += 1
            }
        }
        if count > 0 { batch.commit(completion: report) }
        return ImportUndo(txIds: ids, bills: marked)
    }

    /// Undo for an import: deletes exactly those entries and marks unpaid the bills it marked paid.
    func undoImport(_ u: ImportUndo) {
        var batch = db.batch()
        var count = 0
        for id in u.txIds where !id.isEmpty {
            if count >= 450 { batch.commit(completion: report); batch = db.batch(); count = 0 }
            batch.deleteDocument(col("tx").document(id))
            count += 1
        }
        for b in u.bills where bills.contains(where: { $0.id == b.id }) {
            if count >= 450 { batch.commit(completion: report); batch = db.batch(); count = 0 }
            batch.updateData(["paid.\(b.ym)": false], forDocument: col("bills").document(b.id))
            count += 1
        }
        if count > 0 { batch.commit(completion: report) }
    }

    /// `id` if that account still exists.
    private func existingAccount(_ id: String?) -> String? {
        guard let id, accounts.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Marks a bill paid (adding its expense, dated the day it's due) or unpaid (removing
    /// it). The paid flag and the entry's fixed ID use the calendar month of the due date
    /// (`row.paidKey`), so paying on both phones can't double-count, whatever day the
    /// budget month starts. A loan's bill logs a loan payment (debtId, installment) from
    /// the loan's account.
    func togglePaid(_ row: BillRow, account: String?) {
        let b = row.bill
        let key = row.paidKey
        let batch = db.batch()
        let txRef = col("tx").document("bill-\(b.id)-\(key)")
        batch.updateData(["paid.\(key)": !row.isPaid], forDocument: col("bills").document(b.id))
        if row.isPaid {
            batch.deleteDocument(txRef)
        } else {
            let loan = b.debtId.flatMap { id in debts.first(where: { $0.id == id }) }
            let acct = existingAccount(loan?.acct) ?? account ?? ""
            let t = Tx(id: txRef.documentID, date: row.due, name: b.name, cat: b.cat, amt: b.amt,
                       who: .joint, type: .expense, note: nil, billId: b.id, acct: acct, to: nil, pot: nil,
                       potDir: nil, createdAt: Date(), debtId: b.debtId, debtPart: b.debtId == nil ? nil : "installment")
            write { try batch.setData(from: t, forDocument: txRef) }
        }
        batch.commit(completion: report)
    }

    func setBudget(_ cat: String, _ limit: Double) {
        root.updateData(["budgets.\(cat)": max(0, limit)], completion: report)
    }

    /// Moves part of one category's limit into another (as the Mac's `moveBudget`).
    func moveBudget(from: String, to: String, amount: Double) {
        guard amount > 0, from != to else { return }
        root.updateData(["budgets.\(from)": FieldValue.increment(-amount), "budgets.\(to)": FieldValue.increment(amount)], completion: report)
    }

    func setIncome(_ who: Who, amt: Double, day: Int) {
        guard var incomes = household?.incomes else { return }
        if let i = incomes.firstIndex(where: { $0.who == who }) {
            incomes[i] = Income(who: who, amt: amt, day: day)
        } else {
            incomes.append(Income(who: who, amt: amt, day: day))
        }
        let data = incomes.map { ["who": $0.who.rawValue, "amt": $0.amt, "day": $0.day] as [String: Any] }
        root.updateData(["incomes": data], completion: report)
    }

    func toggleCheck(_ key: String) {
        let on = household?.checks[key] ?? false
        root.updateData(["checks.\(key)": !on], completion: report)
    }

    func updateSettings(nameA: String, nameB: String, currency: String) {
        root.updateData(["nameA": nameA, "nameB": nameB, "currency": currency], completion: report)
    }

    /// Shared settings the Mac also writes: budgetStyle, rollover, cushion, coachTips,
    /// splitMode, splitRule, roundUps, sweep, cycleStart (an integer, 1–28).
    func updateHousehold(_ fields: [AnyHashable: Any]) {
        guard !fields.isEmpty else { return }
        root.updateData(fields, completion: report)
    }

    /// Records what was moved between you this month (settle-up), so later shared
    /// spending still shows. `amount` is what was owed (B owes A positive).
    func setSettled(ym: String, amount: Double) {
        root.updateData(["settled.\(ym)": FieldValue.increment(amount)], completion: report)
    }

    func setRoundUpPot(_ id: String?) {
        let value: Any
        if let id { value = id } else { value = FieldValue.delete() }
        root.updateData(["roundUpPot": value], completion: report)
    }

    func moveRoundUps(_ amount: Double, to pot: Goal, from account: String, ym: String, today: String) {
        guard amount > 0 else { return }
        let batch = db.batch()
        let ref = col("tx").document()
        let t = Tx(id: ref.documentID, date: today, name: "Round-ups · \(pot.name)", cat: "transfer", amt: amount, who: .joint,
                   type: .transfer, note: nil, billId: nil, acct: account, to: pot.acct, pot: pot.id, potDir: .into, createdAt: Date())
        write { try batch.setData(from: t, forDocument: ref) }
        batch.updateData(["roundSwept.\(ym)": FieldValue.increment(amount)], forDocument: root)
        batch.commit(completion: report)
    }

    func save(_ a: Account) {
        var a = a
        let ref = a.id.isEmpty ? col("accounts").document() : col("accounts").document(a.id)
        a.id = ref.documentID
        if a.createdAt == nil { a.createdAt = Date() }
        write { try ref.setData(from: a, completion: report) }
    }

    func deleteAccount(_ id: String) { col("accounts").document(id).delete(completion: report) }

    func save(_ b: Bill) {
        var b = b
        let ref = b.id.isEmpty ? col("bills").document() : col("bills").document(b.id)
        b.id = ref.documentID
        write { try ref.setData(from: b, completion: report) }
    }

    func deleteBill(_ id: String) { col("bills").document(id).delete(completion: report) }

    @discardableResult
    func save(_ g: Goal) -> String {
        var g = g
        let ref = g.id.isEmpty ? col("goals").document() : col("goals").document(g.id)
        g.id = ref.documentID
        if g.createdAt == nil { g.createdAt = Date() }
        write { try ref.setData(from: g, completion: report) }
        return ref.documentID
    }

    func deleteGoal(_ id: String) { col("goals").document(id).delete(completion: report) }

    /// Auto-save each payday on or off for one pot.
    func setGoalAuto(_ id: String, _ on: Bool) {
        col("goals").document(id).updateData(["auto": on], completion: report)
    }

    // MARK: Assets (home, car, gold …): valued by hand, never moved by entries

    func save(_ a: Asset) { saveDoc(a, in: "assets", id: a.id) { $0.id = $1; if $0.createdAt == nil { $0.createdAt = Date() } } }
    func deleteAsset(_ id: String) { col("assets").document(id).delete(completion: report) }

    // MARK: Categories
    // Your own categories live in `custom` and are rewritten directly; built-ins
    // are renamed / moved with `catOv` and removed with `catDel`. Pocket money is fixed.

    private func customData(_ list: [CustomCategory]) -> [[String: String]] {
        list.map { ["id": $0.id, "name": $0.name, "g": $0.g] }
    }

    private func writeCustom(_ list: [CustomCategory]) {
        root.updateData(["custom": customData(list)], completion: report)
    }

    private func isCustom(_ id: String) -> Bool { household?.custom?.contains { $0.id == id } ?? false }

    func addCategory(name: String, group: String, limit: Double) {
        let id = "c" + String(UUID().uuidString.prefix(8)).lowercased()
        writeCustom((household?.custom ?? []) + [CustomCategory(id: id, name: name, g: group)])
        if limit > 0 { setBudget(id, limit) }
    }

    /// Renames a category and/or moves it between Needs and Wants.
    func updateCategory(_ id: String, name: String, group: String) {
        guard !Catalog.isPocketMoney(id) else { return }
        if isCustom(id) {
            writeCustom((household?.custom ?? []).map { $0.id == id ? CustomCategory(id: id, name: name, g: group) : $0 })
        } else {
            root.updateData(["catOv.\(id)": ["name": name, "g": group]], completion: report)
        }
    }

    /// Removes a category and its limit. With a `target`, every entry and bill that
    /// used it moves there; without one they keep the old id and show as "Other"
    /// (outside every budget total). Batches stay under Firestore's 500-write limit.
    func deleteCategory(_ id: String, moveTo target: String?) {
        guard !Catalog.isPocketMoney(id) else { return }
        var fields: [AnyHashable: Any] = ["budgets.\(id)": FieldValue.delete()]
        if isCustom(id) {
            fields["custom"] = customData((household?.custom ?? []).filter { $0.id != id })
        } else {
            fields["catDel"] = FieldValue.arrayUnion([id])
            fields["catOv.\(id)"] = FieldValue.delete()
        }
        var refs: [DocumentReference] = []
        if let target, target != id {
            refs = tx.filter { $0.cat == id && !$0.id.isEmpty }.map { col("tx").document($0.id) }
                + bills.filter { $0.cat == id && !$0.id.isEmpty }.map { col("bills").document($0.id) }
        }
        var batch = db.batch()
        batch.updateData(fields, forDocument: root)
        var count = 1
        for ref in refs {
            if count >= 450 {
                batch.commit(completion: report)
                batch = db.batch()
                count = 0
            }
            batch.updateData(["cat": target ?? id], forDocument: ref)
            count += 1
        }
        batch.commit(completion: report)
    }

    // MARK: Debt plan

    func setStrategy(_ s: String) { root.updateData(["strat": s], completion: report) }
    func setExtra(_ v: Double) { root.updateData(["extra": max(0, v)], completion: report) }

    // MARK: Loans

    /// Saves a loan, also writing the legacy fields older builds and the debt plan
    /// read (apr = rate, min = installment, balance = amount borrowed for loans with
    /// a schedule). With `showInBills` the loan's bill is created or updated in the
    /// same batch; without, a linked bill is deleted.
    func saveLoan(_ loan: Debt, showInBills: Bool) {
        var d = loan
        let ref = d.id.isEmpty ? col("debts").document() : col("debts").document(d.id)
        d.id = ref.documentID
        if d.createdAt == nil { d.createdAt = Date() }
        d.apr = d.rate ?? d.apr
        let inst = Loans.installmentOf(d)
        d.min = inst
        if !Loans.isSimple(d) { d.balance = d.principal ?? d.balance }

        let batch = db.batch()
        let linked = d.billId.flatMap { id in bills.first(where: { $0.id == id }) }
        if showInBills {
            let billRef = linked.map { col("bills").document($0.id) } ?? col("bills").document()
            let day = d.firstDue.flatMap { Int($0.dropFirst(8).prefix(2)) } ?? 1
            let cat = ledger()?.catOr("debt") ?? "debt"
            let bill = Bill(id: billRef.documentID, day: max(1, min(31, day)), name: d.name, amt: (inst * 100).rounded() / 100,
                            cat: cat, sub: false, paid: linked?.paid ?? [:], debtId: d.id)
            d.billId = billRef.documentID
            write { try batch.setData(from: bill, forDocument: billRef) }
        } else {
            if let linked { batch.deleteDocument(col("bills").document(linked.id)) }
            d.billId = nil
        }
        write { try batch.setData(from: d, forDocument: ref) }
        batch.commit(completion: report)
    }

    /// Deletes a loan and its bill. Its payment entries stay in Activity.
    func deleteLoan(_ d: Debt) {
        let batch = db.batch()
        batch.deleteDocument(col("debts").document(d.id))
        for b in bills where b.id == d.billId || b.debtId == d.id {
            batch.deleteDocument(col("bills").document(b.id))
        }
        batch.commit(completion: report)
    }

    /// Logs a loan payment: an expense in the debt category from the loan's account
    /// (or the main one), dated today. `part` is "installment" or "extra".
    func payLoan(_ d: Debt, amount: Double, part: String) {
        guard let L = ledger() else { return }
        let amt = (amount * 100).rounded() / 100
        guard amt > 0 else { return }
        let t = Tx(id: "", date: DateKit.iso(Date()), name: d.name + (part == "extra" ? " · extra payment" : " · installment"),
                   cat: L.catOr("debt"), amt: amt, who: .joint, type: .expense, note: nil, billId: nil,
                   acct: existingAccount(d.acct) ?? L.mainAccountId ?? "", to: nil, pot: nil, potDir: nil, createdAt: nil,
                   debtId: d.id, debtPart: part)
        save(t)
    }

    /// Pays the next installment: through the loan's bill for the month it's due when
    /// that month isn't paid yet (so Bills stays in step), otherwise as a loan payment.
    func payInstallment(_ d: Debt) {
        guard let L = ledger() else { return }
        let st = L.loanState(d)
        if let bill = L.loanBill(d) {
            let ym = String((st.nextDue ?? L.todayIso).prefix(7))
            if !(bill.paid[ym] ?? false) {
                let due = ym + "-" + DateKit.pad(min(bill.day, DateKit.daysIn(ym)))
                togglePaid(BillRow(bill: bill, due: due, isPaid: false), account: L.mainAccountId)
                return
            }
        }
        payLoan(d, amount: st.installment, part: "installment")
    }

    // MARK: Card installment plans (Loans.swift, "Card installment plans"; the Mac's store.tsx)

    /// The category a plan's entries go in (Shopping when none is set, or the first one left).
    private func planCat(_ p: Debt, _ L: Ledger?) -> String {
        let c = (p.cat ?? "").isEmpty ? "shopping" : (p.cat ?? "shopping")
        return L?.catOr(c) ?? c
    }

    /// Saves a plan on a card. Writes the legacy fields like a loan, and keeps billedThrough at
    /// least at paidBefore. A new plan with a processing fee posts the fee on the card once.
    /// Editing never touches entries already posted; new amounts apply to what's still to be
    /// billed. Returns the plan's id.
    @discardableResult
    func savePlan(_ plan: Debt) -> String {
        var d = plan
        let planId = d.id
        let old: Debt? = planId.isEmpty ? nil : debts.first(where: { $0.id == planId })
        let ref = d.id.isEmpty ? col("debts").document() : col("debts").document(d.id)
        d.id = ref.documentID
        if d.createdAt == nil { d.createdAt = old?.createdAt ?? Date() }
        let paidBefore = d.paidBefore ?? 0
        d.kind = "cardplan"
        d.rate = d.rate ?? 0
        d.rateType = d.rateType ?? "flat"
        d.installment = nil
        d.paidBefore = paidBefore
        d.billedThrough = max(paidBefore, old?.billedThrough ?? old?.paidBefore ?? 0)
        d.apr = d.rate ?? 0
        d.min = Loans.installmentOf(d)
        d.balance = d.principal ?? 0

        let batch = db.batch()
        write { try batch.setData(from: d, forDocument: ref) }
        let fee = d.procFee ?? 0
        if old == nil, fee > 0, let acct = d.acct, !acct.isEmpty {
            let feeRef = col("tx").document(Loans.planEntryId(d.id, "fee"))
            let t = Tx(id: feeRef.documentID, date: Loans.planFeeDate(d, DateKit.iso(Date())), name: d.name + " · processing fee",
                       cat: planCat(d, ledger()), amt: (fee * 100).rounded() / 100, who: .joint, type: .expense, note: nil,
                       billId: nil, acct: acct, to: nil, pot: nil, potDir: nil, createdAt: Date(),
                       debtId: d.id, debtPart: "fee")
            write { try batch.setData(from: t, forDocument: feeRef) }
        }
        batch.commit(completion: report)
        return d.id
    }

    /// Closes a plan early: one expense on the card for the quote (what's left plus the fee).
    /// Returns it, or nil when there's nothing left to close.
    @discardableResult
    func closePlan(_ p: Debt) -> Tx? {
        guard let acct = p.acct, !acct.isEmpty else { return nil }
        let day = DateKit.iso(Date())
        let ps = Loans.planState(p, Ledger.payments(of: p.id, in: tx), today: day)
        let amt = (ps.settlement * 100).rounded() / 100
        if ps.done || !(amt > 0) { return nil }
        let t = Tx(id: Loans.planEntryId(p.id, "close"), date: day, name: p.name + " · closed early", cat: planCat(p, ledger()),
                   amt: amt, who: .joint, type: .expense, note: nil, billId: nil, acct: acct, to: nil, pot: nil, potDir: nil,
                   createdAt: Date(), debtId: p.id, debtPart: "extra")
        save(t)
        return t
    }

    /// Posts every plan installment that's due and not posted yet (`Loans.planChargesDue`), with
    /// fixed ids and billedThrough in the same batch, so it's safe on every device at once.
    /// Runs whenever the entries, loans or accounts change and when the day changes. A plan whose
    /// last write hasn't come back yet is skipped, so a slow sync can't post the same
    /// installments again and again. Returns how many entries it wrote.
    @discardableResult
    func billPlans(today day: String = DateKit.iso(Date())) -> Int {
        let need: [String] = ["tx", "debts", "accounts"]
        guard household != nil, need.allSatisfy({ synced.contains($0) }) else { return 0 }
        guard debts.contains(where: Loans.isPlan) else { return 0 }
        var batch = db.batch()
        var count = 0, wrote = 0
        var L: Ledger?
        for p in debts {
            guard Loans.isPlan(p), let acct = p.acct, accounts.contains(where: { $0.id == acct }) else { continue }
            if let wait = billing[p.id] {
                // Back in the data (or the write was given up on after a minute): bill again from there.
                if (p.billedThrough ?? 0) >= wait.to || Date().timeIntervalSince(wait.at) > 60 {
                    billing[p.id] = nil
                } else {
                    continue
                }
            }
            let due = Loans.planChargesDue(p, Ledger.payments(of: p.id, in: tx), today: day)
            guard let last = due.last else { continue }
            // Each plan's entries and its billedThrough share a batch (Firestore: 500 writes at most).
            if count > 0 && count + due.count + 1 > 450 {
                batch.commit(completion: report)
                batch = db.batch()
                count = 0
            }
            if L == nil { L = ledger() }
            let cat = planCat(p, L)
            let term = p.termMonths ?? 0
            for c in due {
                let ref = col("tx").document(Loans.planEntryId(p.id, c.n))
                // createdAt is the installment's date, the same on every device, so two writing at
                // once write the same document.
                let t = Tx(id: ref.documentID, date: c.date, name: "\(p.name) · \(c.n)/\(term)", cat: cat, amt: c.amt,
                           who: .joint, type: .expense, note: nil, billId: nil, acct: acct, to: nil, pot: nil, potDir: nil,
                           createdAt: DateKit.date(c.date), debtId: p.id, debtPart: "installment")
                let current = batch
                write { try current.setData(from: t, forDocument: ref) }
                count += 1
            }
            wrote += due.count
            batch.updateData(["billedThrough": last.n], forDocument: col("debts").document(p.id))
            count += 1
            billing[p.id] = (to: last.n, at: Date())
        }
        if count > 0 { batch.commit(completion: report) }
        return wrote
    }

    /// Bills plans once the current run of snapshot callbacks is done (several collections
    /// often change together).
    private func queueBilling() {
        guard !billQueued else { return }
        billQueued = true
        Task { [weak self] in
            guard let self else { return }
            self.billQueued = false
            self.billPlans()
        }
    }

    /// Called every minute while the app is open and when it comes to the front: moves `today`
    /// on at midnight and then posts any plan installment that came due.
    func dayTick(force: Bool = false) {
        let d = DateKit.iso(Date())
        let changed = d != today
        if changed { today = d }
        if changed || force { billPlans(today: d) }
    }

    func save(_ p: Planned) { saveDoc(p, in: "planned", id: p.id) { $0.id = $1; if $0.createdAt == nil { $0.createdAt = Date() } } }
    func deletePlanned(_ id: String) { col("planned").document(id).delete(completion: report) }
    func vote(_ p: Planned, who: Who) {
        guard who != .joint else { return }
        col("planned").document(p.id).updateData([who.rawValue: !(who == .a ? p.A : p.B)], completion: report)
    }

    /// Logs the purchase as a Shopping expense today and takes it off the plan.
    func buyPlanned(_ p: Planned, account: String) {
        guard let L = ledger() else { return }
        let batch = db.batch()
        let ref = col("tx").document()
        let t = Tx(id: ref.documentID, date: DateKit.iso(Date()), name: p.name, cat: L.catOr("shopping"), amt: p.cost, who: .joint,
                   type: .expense, note: nil, billId: nil, acct: account, to: nil, pot: nil, potDir: nil, createdAt: Date())
        write { try batch.setData(from: t, forDocument: ref) }
        batch.deleteDocument(col("planned").document(p.id))
        batch.commit(completion: report)
    }

    /// Logs spending on a trip as a Travel expense today and adds it to the trip.
    func spendOnTrip(_ trip: Trip, amount: Double, account: String) {
        guard let L = ledger(), amount > 0 else { return }
        let batch = db.batch()
        let ref = col("tx").document()
        let t = Tx(id: ref.documentID, date: DateKit.iso(Date()), name: trip.name, cat: L.catOr("travel"), amt: amount, who: .joint,
                   type: .expense, note: nil, billId: nil, acct: account, to: nil, pot: nil, potDir: nil, createdAt: Date())
        write { try batch.setData(from: t, forDocument: ref) }
        batch.updateData(["spent": FieldValue.increment(amount)], forDocument: col("events").document(trip.id))
        batch.commit(completion: report)
    }

    func save(_ t: Trip) { saveDoc(t, in: "events", id: t.id) { $0.id = $1; if $0.createdAt == nil { $0.createdAt = Date() } } }
    func deleteTrip(_ id: String) { col("events").document(id).delete(completion: report) }

    private func saveDoc<T: Encodable>(_ value: T, in name: String, id: String, stamp: (inout T, String) -> Void) {
        var v = value
        let ref = id.isEmpty ? col(name).document() : col(name).document(id)
        stamp(&v, ref.documentID)
        write { try ref.setData(from: v, completion: report) }
    }
}
