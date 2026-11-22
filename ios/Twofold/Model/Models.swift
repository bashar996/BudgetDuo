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
    // Settings shared with the Mac (desktop/src/data/types.ts). Missing = the default.
    /// "Zero-based" (default), "Category limits" or "50/30/20".
    var budgetStyle: String?
    /// Unspent money rolls into next month (default off).
    var rollover: Bool?
    /// The cash cushion the forecast warns about (default 5,000).
    var cushion: Double?
    /// Coach tips on Home (default on).
    var coachTips: Bool?
    /// "One joint pot" (default) or "Split shared costs".
    var splitMode: String?
    /// "50/50" (default) or "By income".
    var splitRule: String?
    /// "yyyy-MM" → amount already settled between you (A owes B is negative).
    var settled: [String: Double]?
    /// Round-ups switched on (default off).
    var roundUps: Bool?
    /// Month-end sweep switched on (default off).
    var sweep: Bool?

    static let budgetStyles = ["Zero-based", "Category limits", "50/30/20"]
    static let splitModes = ["One joint pot", "Split shared costs"]
    static let splitRules = ["50/50", "By income"]

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
    /// A loan payment: the loan's id (`debts/{id}`).
    var debtId: String?
    /// "installment" or "extra" (missing = installment).
    var debtPart: String?
    /// Statement import: stable ID of the statement line ("imp_…", the same on the Mac),
    /// so a statement imported on either device isn't imported again.
    var importId: String?
    /// "import" for entries that came from a statement.
    var source: String?

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
    /// Cards: day of the month the statement is made.
    var statementDay: Int?
    /// Cards: day of the month the payment is due.
    var dueDay: Int?
    /// Cards: the minimum payment is this % of the balance (5 if missing) …
    var minPct: Double?
    /// … but at least this much (100 if missing).
    var minFloor: Double?
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
    /// Set when the bill shows a loan's installment (paying it logs a loan payment).
    var debtId: String?
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
struct Asset: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// "property", "vehicle", "gold", "business" or "other"
    var kind: String
    var value: Double
    var createdAt: Date?

    /// Same kinds and labels as the Mac (`ASSET_KINDS`).
    static let kinds: [(id: String, label: String)] = [
        ("property", "Property"), ("vehicle", "Vehicle"), ("gold", "Gold & jewellery"), ("business", "Business"), ("other", "Other"),
    ]

    var kindLabel: String { Asset.kinds.first { $0.id == kind }?.label ?? "Other" }
}

/// A rate change on a variable-rate loan: from that month on ("yyyy-MM"), the new annual %.
struct RateChange: Codable, Equatable, Hashable {
    var from: String
    var rate: Double
}

/// A loan: `households/{code}/debts/{id}`. Every field after `createdAt` is optional so
/// loans saved by older builds still load. The outstanding balance of a loan with a
/// schedule is worked out by `Loans.loanState` from its payments, never read from `balance`.
struct Debt: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Older, simple loans: the balance owed. Loans with a schedule keep the amount borrowed here.
    var balance: Double
    /// Kept equal to `rate` for older builds.
    var apr: Double
    /// Kept equal to the installment for older builds.
    var min: Double
    var createdAt: Date?
    /// "personal", "car", "mortgage", "student" or "other"
    var kind: String?
    var lender: String?
    /// Amount borrowed.
    var principal: Double?
    /// Annual rate in %.
    var rate: Double?
    /// "reducing" (missing) or "flat"
    var rateType: String?
    var termMonths: Int?
    /// Date of the first installment, "yyyy-MM-dd"; its day is the payment day.
    var firstDue: String?
    /// The bank's installment; missing = calculated.
    var installment: Double?
    /// Installments paid before the loan was added to Twofold.
    var paidBefore: Int?
    var rateChanges: [RateChange]?
    /// Early-settlement fee, % of the outstanding principal.
    var fee: Double?
    /// Account the installments come out of.
    var acct: String?
    /// Linked bill that shows the installment under Bills.
    var billId: String?

    var kindLabel: String {
        switch kind ?? "" {
        case "personal": return "Personal loan"
        case "car": return "Car loan"
        case "mortgage": return "Mortgage"
        case "student": return "Student loan"
        default: return "Loan"
        }
    }
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
