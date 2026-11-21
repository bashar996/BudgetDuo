import SwiftUI
import Observation

enum Tab: String, CaseIterable { case home = "Home", budget = "Budget", savings = "Savings", more = "More" }

enum Route: Hashable {
    case activity(account: String?)
    case bills, accounts, debt, reports, plan, us, settings
}

/// What's being typed in the add-entry screen.
struct EntryDraft: Identifiable, Equatable {
    var id = UUID()
    var txId = ""
    var type: TxType = .expense
    var amt = ""
    var name = ""
    var cat = "groceries"
    var who: Who = .joint
    var acct = ""
    var to = ""
    var date = Date()
    var pot: String?
    var potDir: PotDirection?
    var billId: String?
    var note: String?
    var error = ""

    init(who: Who, acct: String) {
        self.who = who
        self.acct = acct
    }

    init(editing t: Tx) {
        txId = t.id; type = t.type; name = t.name; cat = t.cat; who = t.who; acct = t.acct; to = t.to ?? ""
        date = DateKit.date(t.date); pot = t.pot; potDir = t.potDir; billId = t.billId; note = t.note
        amt = t.amt == t.amt.rounded() ? String(Int(t.amt)) : String(format: "%.2f", t.amt)
    }
}

enum FormSheet: Identifiable {
    case account(Account?), bill(Bill?), pot(Goal?), pay(Who), budget(String), settings
    case newCategory, debt(Debt?), planned(Planned?), trip(Trip?)
    var id: String {
        switch self {
        case .account(let a): return "account-\(a?.id ?? "new")"
        case .bill(let b): return "bill-\(b?.id ?? "new")"
        case .pot(let g): return "pot-\(g?.id ?? "new")"
        case .pay(let w): return "pay-\(w.rawValue)"
        case .budget(let c): return "budget-\(c)"
        case .settings: return "settings"
        case .newCategory: return "new-category"
        case .debt(let d): return "debt-\(d?.id ?? "new")"
        case .planned(let p): return "planned-\(p?.id ?? "new")"
        case .trip(let t): return "trip-\(t?.id ?? "new")"
        }
    }
}

@MainActor
@Observable
final class Router {
    var tab: Tab = .home
    var path: [Route] = []
    /// Unfolded / wide screens show detail screens in a right-hand pane.
    var isWide = false
    var detail: Route = .reports
    var entry: EntryDraft?
    var form: FormSheet?

    func select(_ t: Tab) { tab = t; path = [] }

    func open(_ r: Route) {
        if isWide { detail = r } else { path.append(r) }
    }

    func back(_ dismiss: DismissAction) {
        if !path.isEmpty { path.removeLast() } else { dismiss() }
    }

    func add(_ store: HouseholdStore, _ L: Ledger, configure: (inout EntryDraft) -> Void = { _ in }) {
        var d = EntryDraft(who: store.me, acct: L.mainAccountId ?? "")
        configure(&d)
        entry = d
    }

    func edit(_ t: Tx) { entry = EntryDraft(editing: t) }
}
