import Foundation

/// Who an entry belongs to: partner A (the person who created the household),
/// partner B (the person who joined) or both of you.
enum Who: String, Codable, CaseIterable, Identifiable {
    case a = "A", b = "B", joint = "J"
    var id: String { rawValue }
}

enum TxType: String, Codable, CaseIterable, Identifiable {
    case expense = "exp", income = "inc", transfer = "xfer"
    var id: String { rawValue }
}

enum PotDirection: String, Codable { case into = "in", out = "out" }

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case current, cash, card, save, invest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .current: return "Current account"
        case .cash: return "Cash"
        case .card: return "Credit card"
        case .save: return "Savings"
        case .invest: return "Investment"
        }
    }
}

struct Income: Codable, Equatable {
    var who: Who
    var amt: Double
    var day: Int
}

/// The shared household document: `households/{code}`.
/// Its document ID doubles as the invite code your partner types in.
struct Household: Codable, Equatable {
    var nameA: String
    var nameB: String
    var currency: String
    var members: [String]
    /// uid → "A" / "B"
    var memberWho: [String: String]
    /// category id → monthly limit
    var budgets: [String: Double]
    var incomes: [Income]
    /// "yyyy-MM:index" → done
    var checks: [String: Bool]
    /// "yyyy-MM" → round-ups already moved
    var roundSwept: [String: Double]
    var roundUpPot: String?
    /// Categories you added yourselves (Needs or Wants).
    var custom: [CustomCategory]?
    /// Debt payoff order: "avalanche" (highest interest) or "snowball" (smallest balance).
    var strat: String?
    /// Extra paid towards debt each month, on top of the minimums.
    var extra: Double?
    /// Renamed or regrouped built-in categories: built-in id → new name and group.
    var catOv: [String: CategoryOverride]?
    /// Built-in categories the household removed.
    var catDel: [String]?

    static func new(uid: String, nameA: String, nameB: String, currency: String) -> Household {
        Household(nameA: nameA, nameB: nameB, currency: currency, members: [uid], memberWho: [uid: Who.a.rawValue],
                  budgets: [:], incomes: [Income(who: .a, amt: 0, day: 1), Income(who: .b, amt: 0, day: 1)],
                  checks: [:], roundSwept: [:], roundUpPot: nil, custom: [], strat: "avalanche", extra: 0)
    }
}

/// `households/{code}/tx/{id}`
struct Tx: Codable, Identifiable, Equatable {
    var id: String
    /// "yyyy-MM-dd"
    var date: String
    var name: String
    /// A category id, or "income" / "transfer"
    var cat: String
    var amt: Double
    var who: Who
    var type: TxType
    var note: String?
    var billId: String?
    var acct: String
    var to: String?
    var pot: String?
    var potDir: PotDirection?
    var createdAt: Date?

    var month: String { String(date.prefix(7)) }
}

/// `households/{code}/accounts/{id}`.
/// The live balance is never stored: it is `opening` plus every entry that
/// touches the account, so two phones editing at once can never disagree.
struct Account: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var type: AccountType
    var who: Who
    var bank: String?
    var last4: String?
    var opening: Double
    var limit: Double?
    var apy: Double?
    /// Card interest rate (APR %); used by the debt plan.
    var apr: Double?
    /// Investments only: the amount put in. Gain = balance − cost.
    var cost: Double?
    var createdAt: Date?
}

/// `households/{code}/bills/{id}`
struct Bill: Codable, Identifiable, Equatable {
    var id: String
    var day: Int
    var name: String
    var amt: Double
    var cat: String
    var sub: Bool
    /// "yyyy-MM" → paid
    var paid: [String: Bool]
}

/// A savings pot (`households/{code}/goals/{id}`). Like accounts, what's saved is
/// `startSaved` plus every deposit and withdrawal tagged with the pot.
struct Goal: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var target: Double
    var startSaved: Double
    var monthly: Double
    var acct: String
    var due: String?
    /// Auto-save each payday is switched on (shown on the Mac).
    var auto: Bool?
    var createdAt: Date?
}

struct CustomCategory: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    /// "needs" or "wants"
    var g: String
}

/// A new name and group for a built-in category (`household.catOv`).
struct CategoryOverride: Codable, Equatable {
    var name: String
    /// "needs" or "wants"
    var g: String
}

/// Something owned outside an account, valued by hand: `households/{code}/assets/{id}`.
/// Edited in the Mac app; the phone only shows them.
struct Asset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// "property", "vehicle", "gold", "business" or "other"
    var kind: String
    var value: Double
    var createdAt: Date?

    var kindLabel: String {
        switch kind {
        case "property": return "Property"
        case "vehicle": return "Vehicle"
        case "gold": return "Gold & jewellery"
        case "business": return "Business"
        default: return "Other"
        }
    }
}

/// A loan: `households/{code}/debts/{id}`
struct Debt: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var balance: Double
    var apr: Double
    var min: Double
    var createdAt: Date?
}

/// Something you're saving up for, with each partner's vote:
/// `households/{code}/planned/{id}`
struct Planned: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var cost: Double
    var A: Bool
    var B: Bool
    var createdAt: Date?
}

/// A trip or event with its own budget: `households/{code}/events/{id}`
struct Trip: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var when: String
    var budget: Double
    var spent: Double
    var createdAt: Date?
}
