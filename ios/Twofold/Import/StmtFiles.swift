import Foundation
import PDFKit

/// What a statement file holds once read: a table (CSV, Excel) or lines of text (PDF).
enum StmtLoaded {
    case table([[String]])
    case pdf([String])
}

enum StmtFileError: Error {
    /// The PDF is locked: ask for its password (`wrong` after a bad one).
    case needPassword(wrong: Bool)
    case message(String)

    var text: String {
        switch self {
        case .needPassword(let wrong): return wrong ? "That password didn’t open the PDF." : "This PDF needs its password."
        case .message(let m): return m
        }
    }
}

/// A picked file → a table or PDF lines (desktop/src/import/read.ts).
enum StmtFile {
    static let maxBytes = 40 * 1024 * 1024

    static func load(_ data: Data, name: String, password: String?) throws -> StmtLoaded {
        if data.count > maxBytes { throw StmtFileError.message("That file is too big for a statement (over 40 MB).") }
        let head = [UInt8](data.prefix(8))
        let ext = (name as NSString).pathExtension.lowercased()
        func starts(_ bytes: [UInt8]) -> Bool { head.count >= bytes.count && Array(head.prefix(bytes.count)) == bytes }
        if ext == "pdf" || starts([0x25, 0x50, 0x44, 0x46]) {
            return .pdf(try StmtPDF.lines(data, password: password))
        }
        if starts([0xD0, 0xCF, 0x11, 0xE0]) {
            throw StmtFileError.message("This is an older Excel file (.xls) or a password-protected one. Open it in Excel or Numbers, save it as .xlsx or CSV and try again.")
        }
        if starts([0x50, 0x4B]) || ext == "xlsx" || ext == "xlsm" {
            do {
                let table = try XLSXReader.read(data)
                if table.isEmpty { throw StmtFileError.message("This spreadsheet looks empty.") }
                return .table(table)
            } catch let e as StmtFileError {
                throw e
            } catch {
                throw StmtFileError.message("This spreadsheet couldn’t be read. Save it as CSV and try again.")
            }
        }
        let text = StmtCSV.decode(data)
        // Some banks send an HTML table named .xls.
        if text.range(of: "<table", options: .caseInsensitive) != nil {
            let table = StmtCSV.htmlTable(text)
            if !table.isEmpty { return .table(table) }
        }
        if ext == "xls" { throw StmtFileError.message("Save it as .xlsx or CSV and try again.") }
        let table = StmtCSV.parse(text)
        if table.isEmpty { throw StmtFileError.message("This file has no rows to read.") }
        return .table(table)
    }
}

// MARK: CSV

/// CSV / TSV text → rows of cells: quotes, doubled quotes, newlines inside quotes, a
/// byte-order mark, and the delimiter (, ; tab |) picked from the first lines (csv.ts).
enum StmtCSV {
    static func detectDelimiter(_ text: String) -> Character {
        let lines = text.components(separatedBy: .newlines).filter { !$0.jsTrim.isEmpty }.prefix(40)
        var best: Character = ",", bestScore = -1
        for d in [",", ";", "\t", "|"] as [Character] {
            let counts: [Int] = lines.map { l in
                var n = 0, q = false
                for c in l { if c == "\"" { q.toggle() } else if c == d && !q { n += 1 } }
                return n
            }
            let rows = counts.filter { $0 > 0 }
            if rows.isEmpty { continue }
            var freq: [Int: Int] = [:]
            rows.forEach { freq[$0, default: 0] += 1 }
            let score = (freq.values.max() ?? 0) * 10 + rows.count
            if score > bestScore { bestScore = score; best = d }
        }
        return best
    }

    static func parse(_ input: String, delimiter: Character? = nil) -> [[String]] {
        var text = input
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let d = delimiter ?? detectDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var q = false
        // Unicode scalars, so "\r\n" stays two characters as in JavaScript.
        let chars = Array(text.unicodeScalars)
        let dq: Unicode.Scalar = "\"", cr: Unicode.Scalar = "\r", lf: Unicode.Scalar = "\n"
        let ds = d.unicodeScalars.first ?? ","
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if q {
                if c == dq {
                    if i + 1 < chars.count && chars[i + 1] == dq { cell.unicodeScalars.append(dq); i += 1 } else { q = false }
                } else {
                    cell.unicodeScalars.append(c)
                }
            } else if c == dq && cell.jsTrim.isEmpty {
                q = true
                cell = ""
            } else if c == ds {
                row.append(cell.jsTrim); cell = ""
            } else if c == lf || c == cr {
                if c == cr && i + 1 < chars.count && chars[i + 1] == lf { i += 1 }
                row.append(cell.jsTrim); cell = ""
                rows.append(row); row = []
            } else {
                cell.unicodeScalars.append(c)
            }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell.jsTrim); rows.append(row) }
        return rows.filter { $0.contains { !$0.isEmpty } }
    }

    /// Text from a file's bytes: UTF-16 with a BOM, UTF-8, or Windows-1252 (older exports).
    static func decode(_ data: Data) -> String {
        let b = [UInt8](data.prefix(2))
        if b.count == 2 && b[0] == 0xFF && b[1] == 0xFE { return String(data: data, encoding: .utf16LittleEndian) ?? "" }
        if b.count == 2 && b[0] == 0xFE && b[1] == 0xFF { return String(data: data, encoding: .utf16BigEndian) ?? "" }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    private static let tr = RX(#"<tr\b[^>]*>([\s\S]*?)</tr>"#, ci: true)
    private static let td = RX(#"<t[dh]\b[^>]*>([\s\S]*?)</t[dh]>"#, ci: true)
    private static let br = RX(#"<br\s*/?>"#, ci: true)
    private static let tag = RX(#"<[^>]+>"#)
    private static let ws = RX(#"\s+"#)

    /// The rows of an HTML table (the ".xls" some banks send).
    static func htmlTable(_ html: String) -> [[String]] {
        tr.matches(html).prefix(20000).map { (row: RXMatch) -> [String] in
            td.matches(row[1] ?? "").prefix(60).map { (c: RXMatch) -> String in
                var s = tag.replace(br.replace(c[1] ?? "", " "), "")
                for (k, v) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
                    s = s.replacingOccurrences(of: k, with: v)
                }
                return ws.replace(s, " ").jsTrim
            }
        }
        .filter { $0.contains { !$0.isEmpty } }
    }
}

// MARK: PDF

/// PDF statements through PDFKit: page text → lines → statement rows (pdfText.ts).
enum StmtPDF {
    /// The text lines of every page (up to 200). Throws `needPassword` for a locked PDF.
    static func lines(_ data: Data, password: String?) throws -> [String] {
        guard let doc = PDFDocument(data: data) else {
            throw StmtFileError.message("This PDF couldn’t be read.")
        }
        if doc.isLocked {
            guard let password, !password.isEmpty else { throw StmtFileError.needPassword(wrong: false) }
            if !doc.unlock(withPassword: password) { throw StmtFileError.needPassword(wrong: true) }
        }
        var out: [String] = []
        for p in 0..<min(doc.pageCount, 200) {
            guard let text = doc.page(at: p)?.string else { continue }
            for l in text.components(separatedBy: .newlines) {
                let line = l.replacingOccurrences(of: "\u{00A0}", with: " ")
                if !line.jsTrim.isEmpty { out.append(line.jsTrim) }
            }
        }
        if out.isEmpty {
            throw StmtFileError.message("This PDF has no text to read — it may be a scanned image. Try the CSV or Excel download from your bank instead.")
        }
        return out
    }

    /// True when `password` opens the PDF (checked before closing the password sheet).
    static func opens(_ data: Data, password: String) -> Bool {
        guard let doc = PDFDocument(data: data) else { return false }
        return !doc.isLocked || doc.unlock(withPassword: password)
    }

    private static let contNoise = RX(#"\bpage\s+\d+|\bof\s+\d+\s*$|statement|balance|total|account\s+(no|number)|customer|iban|swift|continued|^\s*(date|description|debit|credit)\b"#, ci: true)
    private static let years = RX(#"\b20\d{2}\b"#)
    private static let gaps = RX(#"\s{2,}"#)

    /// Transaction rows from statement lines: lines that start with a date and hold at least
    /// one amount; following lines without a date or amount continue the description.
    static func rows(_ lines: [String], isCard: Bool) -> (rows: [StmtRawRow], order: DateOrder) {
        let lead = lines.map(StmtDates.leadingDates)
        let order = StmtDates.detectOrder(lead.flatMap { $0.dates.filter { StmtDates.numericParts($0) != nil } })
        // A year for dates printed without one ("12 Nov"): the latest full year in the text.
        let found = years.matches(lines.joined(separator: " ")).compactMap { Int($0[0] ?? "") }.filter { $0 >= 2000 && $0 <= 2100 }
        let year = found.max() ?? DateKit.cal.component(.year, from: Date())

        var rows: [StmtRawRow] = []
        var conts: [Int] = []
        var last: Int?
        var opening: Double?
        for (i, line) in lines.enumerated() {
            let (dates, rest) = lead[i]
            var date: String?
            if let d0 = dates.first {
                date = StmtDates.parse(d0, order, fallbackYear: year)
                if date == nil, dates.count > 1 { date = StmtDates.parse(dates[1], order, fallbackYear: year) }
            }
            let toks = StmtAmounts.tokens(date != nil ? rest : line)
            // Not `guard let date`: a guard can't rebind a local declared in the same scope.
            guard let rowDate = date else {
                if StmtDetect.noiseRow.test(line), let t = toks.last, opening == nil, rows.isEmpty { opening = StmtAmounts.signed(t.amount) }
                let trimmed = line.jsTrim
                if let li = last, toks.isEmpty, conts[li] < 2, !trimmed.isEmpty, !contNoise.test(line), trimmed.u16Count < 80 {
                    rows[li].desc += " " + trimmed
                    rows[li].raw += " " + trimmed
                    conts[li] += 1
                } else if !toks.isEmpty || contNoise.test(line) {
                    last = nil
                }
                continue
            }
            guard let first = toks.first, let lastTok = toks.last else { last = nil; continue }
            var desc = rest.u16(0, first.index).jsTrim
            if desc.isEmpty { desc = rest.u16(lastTok.end).jsTrim }
            desc = gaps.replace(desc, " ")
            if StmtDetect.noiseRow.test(desc) {
                if opening == nil && rows.isEmpty { opening = StmtAmounts.signed(lastTok.amount) }
                last = nil
                continue
            }
            let a = toks.map(\.amount)
            var money: StmtAmount
            var fixed: Int?
            var balance: Double?
            if a.count >= 3 {
                // Debit, Credit, Balance.
                let dv = abs(a[a.count - 3].value), cv = abs(a[a.count - 2].value)
                money = StmtAmount(value: abs(cv - dv), mark: nil)
                fixed = cv >= dv ? 1 : -1
                balance = StmtAmounts.signed(a[a.count - 1])
            } else if a.count == 2 {
                money = a[0]
                balance = StmtAmounts.signed(a[1])
            } else {
                money = a[0]
            }
            if money.value == 0 { last = nil; continue }
            rows.append(StmtRawRow(i: i, date: rowDate, desc: desc, money: money, fixed: fixed, balance: balance,
                                   raw: gaps.replace(line, "  ").jsTrim))
            conts.append(0)
            last = rows.count - 1
        }
        // The opening balance helps decide the first row's direction.
        if let opening, let firstRow = rows.first, firstRow.balance != nil {
            rows.insert(StmtRawRow(i: -1, date: firstRow.date, desc: "", money: StmtAmount(value: 0, mark: nil), fixed: nil,
                                   balance: opening, raw: ""), at: 0)
        }
        StmtDetect.prepare(&rows, isCard: isCard)
        return (rows.filter { $0.i >= 0 }, order)
    }
}
