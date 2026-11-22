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
    /// Homes, cars, gold … (added in the Mac app; a missing collection is just empty).
    private(set) var assets: [Asset] = []
    /// True while something saved on this phone hasn't reached the server yet.
    private(set) var syncing = false
    private(set) var missing = false
    var error: String?

    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var pending: [String: Bool] = [:]

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
        return Ledger(household: household, tx: tx, accounts: accounts, bills: bills, goals: goals,
                      debts: debts, planned: planned, trips: trips, assets: assets, today: today)
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

    /// Deletes an entry; a bill payment also marks that bill unpaid again.
    func deleteEntry(_ t: Tx) {
        guard !t.id.isEmpty else { return }
        let batch = db.batch()
        batch.deleteDocument(col("tx").document(t.id))
        if let billId = t.billId, bills.contains(where: { $0.id == billId }) {
            batch.updateData(["paid.\(t.month)": false], forDocument: col("bills").document(billId))
        }
        batch.commit(completion: report)
    }

    /// Marks a bill paid (adding its expense) or unpaid (removing it). The entry's
    /// ID is fixed per bill and month, so paying on both phones can't double-count.
    func togglePaid(_ row: BillRow, ym: String, account: String?) {
        let b = row.bill
        let batch = db.batch()
        let txRef = col("tx").document("bill-\(b.id)-\(ym)")
        batch.updateData(["paid.\(ym)": !row.isPaid], forDocument: col("bills").document(b.id))
        if row.isPaid {
            batch.deleteDocument(txRef)
        } else {
            let day = min(b.day, DateKit.daysIn(ym))
            let t = Tx(id: txRef.documentID, date: "\(ym)-\(DateKit.pad(day))", name: b.name, cat: b.cat, amt: b.amt,
                       who: .joint, type: .expense, note: nil, billId: b.id, acct: account ?? "", to: nil, pot: nil,
                       potDir: nil, createdAt: Date())
            write { try batch.setData(from: t, forDocument: txRef) }
        }
        batch.commit(completion: report)
    }

    func setBudget(_ cat: String, _ limit: Double) {
        root.updateData(["budgets.\(cat)": max(0, limit)], completion: report)
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

    func save(_ d: Debt) { saveDoc(d, in: "debts", id: d.id) { $0.id = $1; if $0.createdAt == nil { $0.createdAt = Date() } } }
    func deleteDebt(_ id: String) { col("debts").document(id).delete(completion: report) }

    func save(_ p: Planned) { saveDoc(p, in: "planned", id: p.id) { $0.id = $1; if $0.createdAt == nil { $0.createdAt = Date() } } }
    func deletePlanned(_ id: String) { col("planned").document(id).delete(completion: report) }
    func vote(_ p: Planned, who: Who) {
        guard who != .joint else { return }
        col("planned").document(p.id).updateData([who.rawValue: !(who == .a ? p.A : p.B)], completion: report)
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
