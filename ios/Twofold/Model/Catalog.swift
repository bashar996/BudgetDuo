import Foundation

enum CatGroup: String { case needs, wants, personal }

struct Category: Identifiable, Equatable {
    let id: String
    let name: String
    let group: CatGroup
    /// Pocket-money categories belong to one partner.
    var owner: Who? = nil
    var custom = false
}

enum Catalog {
    static let categories: [Category] = [
        Category(id: "housing", name: "Housing", group: .needs),
        Category(id: "groceries", name: "Groceries", group: .needs),
        Category(id: "utilities", name: "Utilities", group: .needs),
        Category(id: "transport", name: "Transport", group: .needs),
        Category(id: "insurance", name: "Insurance", group: .needs),
        Category(id: "health", name: "Health", group: .needs),
        Category(id: "kids", name: "Kids & family", group: .needs),
        Category(id: "debt", name: "Debt payments", group: .needs),
        Category(id: "dining", name: "Dining out", group: .wants),
        Category(id: "fun", name: "Entertainment", group: .wants),
        Category(id: "shopping", name: "Shopping", group: .wants),
        Category(id: "subs", name: "Subscriptions", group: .wants),
        Category(id: "travel", name: "Travel & events", group: .wants),
        Category(id: "gifts", name: "Gifts & giving", group: .wants),
        Category(id: "allowA", name: "", group: .personal, owner: .a),
        Category(id: "allowB", name: "", group: .personal, owner: .b),
    ]

    /// Built-in categories followed by the ones you added.
    static func all(custom: [CustomCategory]?) -> [Category] {
        categories + (custom ?? []).map { Category(id: $0.id, name: $0.name, group: CatGroup(rawValue: $0.g) ?? .wants, custom: true) }
    }

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
