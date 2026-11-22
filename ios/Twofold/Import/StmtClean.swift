import Foundation

/// Bank descriptions → merchant names: "POS PURCHASE CARD 4XXXXXXXXXXX1234 CARREFOUR MOE DUBAI AE"
/// → "Carrefour Moe". Port of desktop/src/import/clean.ts. The raw text is kept in the entry's note.
enum StmtClean {
    private static let lead = RX(#"^(?:POS|PURCHASE|PUR|DEBIT CARD|CREDIT CARD|CARD|VISA|MASTERCARD|MASTER CARD|APPLE PAY|GOOGLE PAY|ECOM|E-COM|ONLINE|TXN|TRANSACTION|CONTACTLESS|NFC)\b[\s:\-#.]*"#)
    private static let places = ["RAS AL KHAIMAH", "UMM AL QUWAIN", "ABU DHABI", "AL AIN", "DUBAI", "SHARJAH", "AJMAN", "FUJAIRAH", "RAK", "DXB", "AUH", "UAE", "ARE", "AE",
                                 "US", "USA", "GB", "GBR", "UK", "SA", "SAU", "IN", "IND", "IE", "IRL", "NL", "NLD", "LU", "LUX", "SG", "SGP", "QA", "OM", "KW", "BH"]
    private static let trail = RX(#"(?:[\s,\-]+(?:"# + places.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) }.joined(separator: "|") + #"))+[\s,.\-]*$"#)
    private static let small: Set<String> = ["and", "of", "the", "for", "at", "by", "in", "on", "to", "de"]

    private static let mask1 = RX(#"\b\d{0,6}[X*•]{4,}[\d X*•-]*\d{0,4}\b"#)
    private static let mask2 = RX(#"[*•]{2,}\d{2,4}\b"#)
    private static let mask3 = RX(#"\b(?:[X*]{4}[\s-]?){2,}\d{4}\b"#)
    private static let refs = RX(#"\b(?:REF(?:ERENCE)?|REF NO|RRN|ARN|AUTH(?:CODE)?|APPROVAL CODE|TXN ID|TRN|SEQ|ID)\b\.?\s*(?:NO\.?|NUMBER|#)?\s*[:#\-]?\s*[A-Z0-9\-/]*\d[A-Z0-9\-/]*"#)
    private static let dates = RX(#"\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b"#)
    private static let times = RX(#"\b\d{1,2}:\d{2}(?::\d{2})?\b"#)
    private static let money = RX(#"\b(?:AED|USD|EUR|GBP|SAR)\s?\d[\d,]*(?:\.\d+)?\b"#)
    private static let longDigits = RX(#"\d{5,}"#)
    private static let ws = RX(#"\s+"#)
    private static let oddSpace = RX("[\u{00A0}\t]")
    private static let nonAZ = RX("[^A-Z]")
    private static let payPrefix = RX("^(SQ|TST|PP|PAYPAL)$")
    private static let trailJunk = RX(#"[\s,.\-#:/]+$"#)
    private static let leadJunk = RX(#"^[\s,.\-#:/]+"#)
    private static let vowel = RX("[aeiou]")
    private static let letter = RX("[a-z]")
    private static let domain = RX(#"\.(com|ae|net|org|io)\b"#)
    private static let tailWord = RX(#"\s+\S*$"#)

    private static func title(_ s: String) -> String {
        s.lowercased().components(separatedBy: " ").enumerated().map { (pair) -> String in
            let i = pair.offset, w = pair.element
            if w.isEmpty { return w }
            if i > 0 && small.contains(w) { return w }
            // Short words with no vowels are usually initials: KFC, H&M, TFL.
            if w.u16Count <= 3 && !vowel.test(w) && letter.test(w) { return w.uppercased() }
            if domain.test(w) { return w }
            var out = ""
            var prev: Character? = nil
            for ch in w {
                let starts = prev == nil || "-'(&/".contains(prev!)
                out.append(starts && ch >= "a" && ch <= "z" ? Character(ch.uppercased()) : ch)
                prev = ch
            }
            return out
        }.joined(separator: " ")
    }

    static func name(_ raw: String) -> String {
        var s = " " + oddSpace.replace(raw.uppercased(), " ") + " "
        // Card masks: 4XXXXXXXXXXX1234, 4111********1234, ****1234, XXXX1234, xxxx-xxxx-xxxx-1234
        s = mask1.replace(s, " ")
        s = mask2.replace(s, " ")
        s = mask3.replace(s, " ")
        // Reference codes.
        s = refs.replace(s, " ")
        // Dates, times and amounts that some banks repeat in the description.
        s = times.replace(dates.replace(s, " "), " ")
        s = money.replace(s, " ")
        s = longDigits.replace(s, " ")
        s = ws.replace(s, " ").jsTrim
        for _ in 0..<4 {
            let n = lead.replace(s, "")
            if n == s { break }
            s = n.jsTrim
        }
        // "TALABAT*ORDER 123" → "TALABAT"; "SQ *BLUE BOTTLE" keeps "BLUE BOTTLE".
        if s.contains("*") {
            let parts = s.components(separatedBy: "*").map { $0.jsTrim }
            let a = parts.first ?? ""
            s = nonAZ.replace(a, "").u16Count >= 3 ? a : parts.filter { !$0.isEmpty && !payPrefix.test($0) }.joined(separator: " ")
        }
        for _ in 0..<4 {
            let n = leadJunk.replace(trailJunk.replace(trail.replace(s, ""), ""), "")
            if n == s { break }
            s = n
        }
        s = ws.replace(s, " ").jsTrim
        if s.isEmpty { s = ws.replace(raw, " ").jsTrim }
        var out = title(s)
        if out.count > 40 {
            let cut = String(out.prefix(40))
            let shorter = tailWord.replace(cut, "")
            out = shorter.isEmpty ? cut : shorter
        }
        return out
    }

    private static let nonWord = RX("[^a-z0-9\u{0600}-\u{06FF}&]+")
    private static let allDigits = RX(#"^\d+$"#)

    /// Lower-case words for comparing names.
    static func tokens(_ s: String) -> [String] {
        nonWord.replace(s.lowercased(), " ").components(separatedBy: " ")
            .filter { $0.u16Count > 1 && !allDigits.test($0) }
    }

    /// Word overlap between two names, 0…1 (shared words ÷ the shorter name's words).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Set(tokens(a)), y = Set(tokens(b))
        if x.isEmpty || y.isEmpty { return 0 }
        return Double(x.intersection(y).count) / Double(min(x.count, y.count))
    }
}

/// Category suggestions: what you used before for the same merchant, then keyword rules.
/// Port of desktop/src/import/categorise.ts (identical keyword lists).
enum StmtCategory {
    static let rules: [(String, [String])] = [
        ("groceries", ["carrefour", "lulu", "spinneys", "waitrose", "choithrams", "union coop", "unioncoop", "coop", "géant", "geant", "viva", "west zone", "al maya", "nesto", "grandiose", "kibsons", "instashop", "el grocer", "elgrocer", "supermarket", "hypermarket", "grocery", "bakery", "fruit"]),
        ("transport", ["adnoc", "enoc", "eppco", "emarat", "petrol", "fuel", "salik", "darb", "rta", "nol", "parking", "mawaqif", "careem ride", "careem car", "uber", "taxi", "valtrans", "hala"]),
        ("utilities", ["dewa", "addc", "aadc", "sewa", "fewa", "etihad water", "empower", "tabreed", "etisalat", "e&", "du", "du.ae", "virgin mobile", "internet", "broadband", "chiller", "district cooling", "gas"]),
        ("dining", ["talabat", "deliveroo", "careem food", "noon food", "zomato", "restaurant", "cafe", "café", "coffee", "starbucks", "costa", "tim hortons", "mcdonald", "kfc", "burger", "pizza", "shawarma", "karak", "bistro", "grill", "kitchen", "eatery", "dining"]),
        ("subs", ["netflix", "spotify", "apple.com/bill", "apple.com", "itunes", "youtube", "google *", "google one", "osn", "shahid", "anghami", "disney", "amazon prime", "prime video", "icloud", "chatgpt", "openai", "microsoft", "adobe", "playstation", "xbox", "starzplay"]),
        ("shopping", ["noon", "amazon", "namshi", "ikea", "home centre", "home box", "centrepoint", "max fashion", "h&m", "zara", "sharaf dg", "jumbo", "virgin megastore", "ace hardware", "dragon mart", "mall", "store", "shop", "trading"]),
        ("health", ["pharmacy", "aster", "life pharmacy", "boots", "bin sina", "binsina", "clinic", "hospital", "medical", "dental", "mediclinic", "nmc", "health", "optic", "gym", "fitness"]),
        ("kids", ["nursery", "school", "kids", "toys", "hamleys", "mothercare", "babyshop", "early learning"]),
        ("insurance", ["insurance", "takaful", "axa", "oman insurance", "sukoon", "orient insurance", "gig", "daman"]),
        ("travel", ["emirates", "flydubai", "air arabia", "etihad airways", "booking.com", "airbnb", "agoda", "expedia", "hotel", "airline", "travel", "visa fee", "ica", "gdrfa"]),
        ("fun", ["vox", "reel cinemas", "novo", "cinema", "theatre", "theme park", "img worlds", "ferrari world", "global village", "bowling", "ticket"]),
        ("gifts", ["charity", "donation", "red crescent", "dubai cares", "gift", "flowers"]),
        ("housing", ["rent", "ejari", "landlord", "real estate", "properties", "maintenance", "service charge", "building"]),
        ("debt", ["loan", "installment", "instalment", "emi", "finance repayment"]),
    ]

    private static let shortWord = RX("^[a-z&]+$")

    /// Short keywords ("du", "rta", "emi", "rent") must be whole words; longer ones match anywhere.
    private static let compiled: [(String, [RX])] = rules.map { (rule) -> (String, [RX]) in
        let res: [RX] = rule.1.map { (k: String) -> RX in
            let t = k.jsTrim
            let esc = NSRegularExpression.escapedPattern(for: t)
            return t.u16Count <= 4 && shortWord.test(t)
                ? RX("(^|[^a-z0-9])" + esc + "($|[^a-z0-9])")
                : RX(NSRegularExpression.escapedPattern(for: k))
        }
        return (rule.0, res)
    }

    /// Bank names that would otherwise read as travel ("Emirates NBD") or similar.
    private static let noise = RX(#"\b(emirates nbd|emirates islamic|enbd|mashreq|adcb|fab|first abu dhabi|rakbank|dubai islamic|cbd|hsbc|citi(bank)?)\b"#)
    private static let ws = RX(#"\s+"#)

    static func rule(_ raw: String, has: (String) -> Bool) -> String? {
        let s = " " + ws.replace(noise.replace(raw.lowercased(), " "), " ") + " "
        for (cat, res) in compiled where has(cat) {
            if res.contains(where: { $0.test(s) }) { return cat }
        }
        return nil
    }

    /// First two words of a name, the key history is matched on.
    static func historyKey(_ name: String) -> String { StmtClean.tokens(name).prefix(2).joined(separator: " ") }

    /// Most-used category per merchant key, from existing expenses (ties: the one seen first).
    static func historyIndex(_ tx: [Tx], has: (String) -> Bool) -> [String: String] {
        var counts: [String: [(cat: String, n: Int)]] = [:]
        for t in tx where t.type == .expense && has(t.cat) {
            let k = historyKey(t.name)
            if k.isEmpty { continue }
            var list = counts[k] ?? []
            if let i = list.firstIndex(where: { $0.cat == t.cat }) { list[i].n += 1 } else { list.append((cat: t.cat, n: 1)) }
            counts[k] = list
        }
        var out: [String: String] = [:]
        for (k, list) in counts {
            var best = "", n = 0
            for e in list where e.n > n { n = e.n; best = e.cat }
            out[k] = best
        }
        return out
    }

    /// "history" or "rule" says where the suggestion came from.
    static func suggest(raw: String, name: String, history: [String: String], has: (String) -> Bool) -> (cat: String, how: String)? {
        if let h = history[historyKey(name)] { return (h, "history") }
        if let r = rule(raw, has: has) { return (r, "rule") }
        return nil
    }
}
