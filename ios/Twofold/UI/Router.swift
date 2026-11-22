import SwiftUI
import Observation

/// The app's tabs. (Not called `Tab`, which is SwiftUI's tab type.)
/// Declared in tab-bar order.
enum AppTab: String, CaseIterable {
    case home = "Home", budget = "Budget"
    /// Not a real destination: picking it opens the add-entry keypad.
    case add = "Add"
    case savings = "Savings", more = "More"

    var symbol: String {
        switch self {
        case .home: return "house"
        case .budget: return "chart.pie"
        case .savings: return "banknote"
        case .more: return "ellipsis"
        case .add: return "plus"
        }
    }
}

enum Route: Hashable {
    case activity(account: String?)
    case bills, accounts, worth, debt, reports, plan, us, settings
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
    var tab: AppTab = .home
    /// Each tab has its own navigation stack.
    var paths: [AppTab: [Route]] = [:]
    /// The stack of the selected tab.
    var path: [Route] {
        get { paths[tab] ?? [] }
        set { paths[tab] = newValue }
    }
    /// Unfolded / wide screens show detail screens in a right-hand pane.
    var isWide = false
    var detail: Route = .reports
    /// Screens pushed inside the right-hand pane, on top of `detail`.
    var detailPath: [Route] = []
    var entry: EntryDraft?
    var form: FormSheet?
    /// Bills: the day picked on the calendar (the list shows only that day's bills).
    var billDay: Int?
    /// Wide screens: Bills was opened from the left pane, so the left pane shows the
    /// calendar on its own and the right pane the hero and list.
    var billsSplit = false

    func select(_ t: AppTab) { tab = t; paths = [:]; billsSplit = false; billDay = nil }

    /// Opens a top-level detail screen: the right-hand pane on wide screens.
    func open(_ r: Route) {
        if r == .bills { billDay = nil }
        billsSplit = isWide && r == .bills
        if isWide { detail = r; detailPath = [] } else { path.append(r) }
    }

    /// Leaves the wide-screen bills calendar: the left pane goes back to its tab.
    func closeBillsSplit() { billsSplit = false }

    /// Goes one level deeper from a detail screen (e.g. an account's activity
    /// from Accounts), so the pane keeps a way back.
    func drill(_ r: Route) {
        if isWide { detailPath.append(r) } else { path.append(r) }
    }

    func back(_ dismiss: DismissAction) {
        if !path.isEmpty { path.removeLast() }
        else if !detailPath.isEmpty { detailPath.removeLast() }
        else { dismiss() }
    }

    func add(_ store: HouseholdStore, _ L: Ledger, configure: (inout EntryDraft) -> Void = { _ in }) {
        var d = EntryDraft(who: store.me, acct: L.mainAccountId ?? "")
        d.cat = L.catOr("groceries")
        configure(&d)
        entry = d
    }

    func edit(_ t: Tx) { entry = EntryDraft(editing: t) }
}
