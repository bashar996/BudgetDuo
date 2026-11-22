import Foundation

enum CatGroup: String { case needs, wants, personal }

struct Category: Identifiable, Equatable {
    let id: String
    let name: String
    let group: CatGroup
    /// Pocket-money categories belong to one partner.
    var owner: Who? = nil
    var custom = false
    /// Day-to-day spending that coach tips watch (same flags as the Mac's catalog).
    var variable = false
}

enum Catalog {
    static let categories: [Category] = [
        Category(id: "housing", name: "Housing", group: .needs),
        Category(id: "groceries", name: "Groceries", group: .needs, variable: true),
        Category(id: "utilities", name: "Utilities", group: .needs),
        Category(id: "transport", name: "Transport", group: .needs, variable: true),
        Category(id: "insurance", name: "Insurance", group: .needs),
        Category(id: "health", name: "Health", group: .needs, variable: true),
        Category(id: "kids", name: "Kids & family", group: .needs, variable: true),
        Category(id: "debt", name: "Debt payments", group: .needs),
        Category(id: "dining", name: "Dining out", group: .wants, variable: true),
        Category(id: "fun", name: "Entertainment", group: .wants, variable: true),
        Category(id: "shopping", name: "Shopping", group: .wants, variable: true),
        Category(id: "subs", name: "Subscriptions", group: .wants),
        Category(id: "travel", name: "Travel & events", group: .wants, variable: true),
        Category(id: "gifts", name: "Gifts & giving", group: .wants, variable: true),
        Category(id: "allowA", name: "", group: .personal, owner: .a, variable: true),
        Category(id: "allowB", name: "", group: .personal, owner: .b, variable: true),
    ]

    /// Built-in categories followed by the ones you added.
    static func all(custom: [CustomCategory]?) -> [Category] {
        categories + (custom ?? []).map { Category(id: $0.id, name: $0.name, group: CatGroup(rawValue: $0.g) ?? .wants, custom: true, variable: true) }
    }

    /// The household's categories: built-ins minus the ones it removed (`catDel`)
    /// with renames and group moves (`catOv`) applied, then its own (`custom`).
    /// Pocket money can't be renamed, moved or removed.
    static func effective(_ h: Household) -> [Category] {
        let gone = Set(h.catDel ?? [])
        let ov = h.catOv ?? [:]
        let builtIns: [Category] = categories.compactMap { (c: Category) -> Category? in
            if c.group == .personal { return c }
            if gone.contains(c.id) { return nil }
            guard let o = ov[c.id] else { return c }
            let g: CatGroup = o.g == "wants" ? .wants : o.g == "needs" ? .needs : c.group
            return Category(id: c.id, name: o.name, group: g, variable: c.variable)
        }
        let own: [Category] = (h.custom ?? []).filter { !gone.contains($0.id) }.map {
            Category(id: $0.id, name: $0.name, group: $0.g == "needs" ? .needs : .wants, custom: true, variable: true)
        }
        return builtIns + own
    }

    static func isPocketMoney(_ id: String) -> Bool { id == "allowA" || id == "allowB" }

    static let groups: [(CatGroup, String)] = [(.needs, "Needs"), (.wants, "Wants"), (.personal, "Pocket money")]

    static let moneyDateChecks = [
        "Look at the categories that ran over",
        "Confirm next month’s bills",
        "Top up the savings goals",
        "Agree on planned purchases",
        "Pick one thing to celebrate",
    ]

    static let currencies = ["AED", "د.إ", "SAR", "$", "€", "£"]
}
