import SwiftUI
import Observation
import UIKit

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
    /// One loan's detail (schedule, payments), by loan id.
    case loan(String)

    /// The screen's title, as its NavRow shows it (a loan shows its own name).
    var title: String {
        switch self {
        case .activity: return "Activity"
        case .bills: return "Bills"
        case .accounts: return "Accounts"
        case .worth: return "Net worth"
        case .debt: return "Debt"
        case .reports: return "Reports"
        case .plan: return "Plan ahead"
        case .us: return "Us two"
        case .settings: return "Settings"
        case .loan: return "Loan"
        }
    }
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
    /// Loan payments keep their loan link when edited.
    var debtId: String?
    var debtPart: String?
    var error = ""

    init(who: Who, acct: String) {
        self.who = who
        self.acct = acct
    }

    init(editing t: Tx) {
        txId = t.id; type = t.type; name = t.name; cat = t.cat; who = t.who; acct = t.acct; to = t.to ?? ""
        date = DateKit.date(t.date); pot = t.pot; potDir = t.potDir; billId = t.billId; note = t.note
        debtId = t.debtId; debtPart = t.debtPart
        amt = EntryDraft.keypadAmount(t.amt)
    }

    /// An amount as the keypad types it: "1250" or "1250.50".
    static func keypadAmount(_ x: Double) -> String {
        let r = (x * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(format: "%.2f", r)
    }
}

enum FormSheet: Identifiable {
    case account(Account?), bill(Bill?), pot(Goal?), pay(Who), budget(String), settings
    case newCategory, debt(Debt?), planned(Planned?), trip(Trip?)
    /// The account form for a new credit card.
    case newCard
    /// The account form for a new investment (Net worth → + Add investment).
    case newInvestment
    /// A home, car, gold … on Net worth.
    case asset(Asset?)
    /// Log spending on a trip or event.
    case tripSpend(Trip)
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
        case .newCard: return "new-card"
        case .newInvestment: return "new-investment"
        case .asset(let a): return "asset-\(a?.id ?? "new")"
        case .tripSpend(let t): return "trip-spend-\(t.id)"
        }
    }
}

/// One step the unfolded (wide) layout can go back from, newest last.
enum NavStep: Equatable {
    /// A screen pushed in a tab's own stack (the left pane); `depth` is the stack size after the push.
    case push(tab: AppTab, depth: Int)
    /// The right pane switched to another screen (or the bills split opened); keeps
    /// what it showed before, so Back can put it back.
    case detail(from: Route, path: [Route], split: Bool, billDay: Int?)
    /// A screen pushed inside the right pane; `depth` is `detailPath.count` after the push.
    case drill(depth: Int)
}

/// Where Back goes on the wide layout (for its VoiceOver hint).
enum BackTarget: Equatable {
    case tab(AppTab)
    case route(Route)
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
    /// iPad: wide panes keep their own back arrows; the docked rail Back is for the Duo.
    static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    /// The single Back docked by the tab rail (unfolded iPhone Duo only).
    var dockedBack: Bool { isWide && !Router.isPad }
    /// Wide screens: width of the trailing column the system tab rail sits in (the
    /// Back button docks there; toasts keep clear of it).
    var railInset: CGFloat = 0
    var detail: Route = .reports
    /// Screens pushed inside the right-hand pane, on top of `detail`.
    var detailPath: [Route] = []
    var entry: EntryDraft?
    var form: FormSheet?
    /// The entry just deleted, while its Undo toast shows.
    var undo: Tx?
    /// The statement import just written, while its Undo toast shows.
    var importUndo: ImportUndo?
    /// Bills: the day picked on the calendar (the list shows only that day's bills).
    var billDay: Int?
    /// Wide screens: Bills was opened from the left pane, so the left pane shows the
    /// calendar on its own and the right pane the hero and list.
    var billsSplit = false
    /// Wide screens: one history across both panes, so a single Back (docked by the
    /// tab rail) undoes the latest step wherever it happened. Narrow screens don't use it.
    private(set) var history: [NavStep] = []

    func select(_ t: AppTab) { tab = t; paths = [:]; billsSplit = false; billDay = nil; history = [] }

    /// Opens a top-level detail screen: the right-hand pane on wide screens.
    func open(_ r: Route) {
        if isWide {
            let split = r == .bills
            let step = NavStep.detail(from: detail, path: detailPath, split: billsSplit, billDay: billDay)
            if r != detail || !detailPath.isEmpty || split != billsSplit || (r == .bills && billDay != nil) {
                history.append(step)
            }
            if r == .bills { billDay = nil }
            billsSplit = split
            detail = r
            detailPath = []
        } else {
            if r == .bills { billDay = nil }
            billsSplit = false
            path.append(r)
        }
    }

    /// Leaves the wide-screen bills calendar: the left pane goes back to its tab.
    func closeBillsSplit() { billsSplit = false }

    /// Goes one level deeper from a detail screen (e.g. an account's activity
    /// from Accounts), so the pane keeps a way back.
    func drill(_ r: Route) {
        if isWide {
            detailPath.append(r)
            history.append(.drill(depth: detailPath.count))
        } else {
            path.append(r)
        }
    }

    /// The narrow layout's back arrow (and a deleted loan leaving its screen).
    /// Wide iPad: Back from a screen goes back within its own pane.
    func paneBack(detail: Bool, _ dismiss: DismissAction) {
        if detail {
            if !detailPath.isEmpty { setDetailPath(Array(detailPath.dropLast())) } else { dismiss() }
        } else {
            if !path.isEmpty { setPath(tab, Array(path.dropLast())) } else { dismiss() }
        }
    }

    func back(_ dismiss: DismissAction) {
        if isWide {
            if !detailPath.isEmpty { setDetailPath(Array(detailPath.dropLast())) }
            else if !path.isEmpty { setPath(tab, Array(path.dropLast())) }
            else { dismiss() }
            return
        }
        if !path.isEmpty { path.removeLast() }
        else if !detailPath.isEmpty { detailPath.removeLast() }
        else { dismiss() }
    }

    // MARK: Wide-layout history

    /// The wide layout's single Back is available.
    var canGoBack: Bool { isWide && !history.isEmpty }

    /// Where Back would go.
    var backTarget: BackTarget? {
        guard isWide, let step = history.last else { return nil }
        switch step {
        case .push(let t, let depth):
            let p = paths[t] ?? []
            return depth >= 2 && p.count >= depth - 1 ? .route(p[depth - 2]) : .tab(t)
        case .drill(let depth):
            return depth >= 2 && detailPath.count >= depth - 1 ? .route(detailPath[depth - 2]) : .route(detail)
        case .detail(let from, let p, _, _):
            return .route(p.last ?? from)
        }
    }

    /// Undoes the latest step: pops a stack, puts the previous right-pane screen back,
    /// or closes the bills split.
    func goBack() {
        guard let step = history.popLast() else { return }
        switch step {
        case .push(let t, let depth):
            let p = paths[t] ?? []
            if p.count >= depth { paths[t] = Array(p.prefix(depth - 1)) }
        case .drill(let depth):
            if detailPath.count >= depth { detailPath = Array(detailPath.prefix(depth - 1)) }
        case .detail(let from, let p, let split, let day):
            detail = from
            detailPath = p
            billsSplit = split
            billDay = day
        }
    }

    /// A tab stack changed from the NavigationStack itself (swipe back, or a push the
    /// router didn't make): keeps the history in step.
    func setPath(_ t: AppTab, _ new: [Route]) {
        let old = paths[t] ?? []
        paths[t] = new
        guard isWide else { return }
        if new.count < old.count {
            history.removeAll { step in
                if case .push(let st, let d) = step { return st == t && d > new.count }
                return false
            }
        } else if new.count > old.count {
            for d in (old.count + 1)...new.count { history.append(.push(tab: t, depth: d)) }
        }
    }

    /// The right pane's stack changed from the NavigationStack itself (swipe back):
    /// drops the pushes that are gone. Pushes made before the right pane last switched
    /// screens stay, as Back restores that screen's stack with them.
    func setDetailPath(_ new: [Route]) {
        let old = detailPath
        detailPath = new
        guard isWide else { return }
        if new.count < old.count {
            var i = history.count - 1
            while i >= 0 {
                if case .detail = history[i] { break }
                if case .drill(let d) = history[i], d > new.count { history.remove(at: i) }
                i -= 1
            }
        } else if new.count > old.count {
            for d in (old.count + 1)...new.count { history.append(.drill(depth: d)) }
        }
    }

    /// The layout switched between narrow and wide: each keeps its own way back.
    func layoutChanged(wide: Bool) {
        isWide = wide
        history = []
        if wide { paths = [:] } else { detailPath = [] }
    }

    func add(_ store: HouseholdStore, _ L: Ledger, configure: (inout EntryDraft) -> Void = { _ in }) {
        var d = EntryDraft(who: store.me, acct: L.mainAccountId ?? "")
        d.cat = L.catOr("groceries")
        configure(&d)
        entry = d
    }

    func edit(_ t: Tx) { entry = EntryDraft(editing: t) }

    /// Deletes an entry and offers Undo for a few seconds.
    func delete(_ t: Tx, _ store: HouseholdStore) {
        store.deleteEntry(t)
        importUndo = nil
        undo = t
    }

    /// After a statement import: offers Undo for those entries.
    func imported(_ u: ImportUndo) {
        undo = nil
        importUndo = u
    }
}
