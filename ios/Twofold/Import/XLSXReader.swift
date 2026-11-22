import Foundation
import Compression

// MARK: ZIP

/// Just enough of ZIP to open .xlsx files: the central directory, stored and deflated entries.
/// Deflate is inflated with Apple's Compression framework (`COMPRESSION_ZLIB` is raw DEFLATE).
struct ZipArchive {
    struct Entry {
        var name: String
        var method: Int
        var compressedSize: Int
        var size: Int
        var localOffset: Int
    }

    enum Failure: Error { case notZip, broken(String), unsupported(String) }

    private let bytes: [UInt8]
    let entries: [String: Entry]

    init(_ data: Data) throws {
        let b = [UInt8](data)
        bytes = b
        func u16(_ o: Int) -> Int {
            guard o >= 0, o + 2 <= b.count else { return 0 }
            let lo = Int(b[o]), hi = Int(b[o + 1])
            return lo | (hi << 8)
        }
        func u32(_ o: Int) -> Int {
            let lo = u16(o), hi = u16(o + 2)
            return o + 4 <= b.count ? lo | (hi << 16) : 0
        }
        guard b.count >= 22 else { throw Failure.notZip }
        // End of central directory: the last 0x06054b50 within the final 64 KB + 22 bytes.
        var eocd = -1
        var o = b.count - 22
        let stop = max(0, b.count - 22 - 65535)
        while o >= stop {
            if b[o] == 0x50 && b[o + 1] == 0x4B && b[o + 2] == 0x05 && b[o + 3] == 0x06 { eocd = o; break }
            o -= 1
        }
        guard eocd >= 0 else { throw Failure.notZip }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        var list: [String: Entry] = [:]
        for _ in 0..<count {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { throw Failure.broken("central directory") }
            let method = u16(p + 10)
            let csize = u32(p + 20), size = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + nameLen <= b.count else { throw Failure.broken("entry name") }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            list[name] = Entry(name: name, method: method, compressedSize: csize, size: size, localOffset: local)
            p += 46 + nameLen + extraLen + commentLen
        }
        entries = list
    }

    /// The uncompressed bytes of an entry, or nil when it isn't there.
    func data(_ name: String) throws -> Data? {
        guard let e = entries[name] else { return nil }
        let b = bytes
        func u16(_ o: Int) -> Int {
            guard o >= 0, o + 2 <= b.count else { return 0 }
            let lo = Int(b[o]), hi = Int(b[o + 1])
            return lo | (hi << 8)
        }
        let o = e.localOffset
        guard o + 30 <= b.count, b[o] == 0x50, b[o + 1] == 0x4B, b[o + 2] == 0x03, b[o + 3] == 0x04 else { throw Failure.broken(name) }
        let start = o + 30 + u16(o + 26) + u16(o + 28)
        guard e.size != 0xFFFF_FFFF, e.compressedSize != 0xFFFF_FFFF else { throw Failure.unsupported("ZIP64") }
        guard start + e.compressedSize <= b.count else { throw Failure.broken(name) }
        let raw = Data(b[start..<(start + e.compressedSize)])
        switch e.method {
        case 0: return raw
        case 8:
            guard let out = ZipArchive.inflate(raw, size: e.size) else { throw Failure.broken(name) }
            return out
        default:
            throw Failure.unsupported("compression \(e.method)")
        }
    }

    /// Raw DEFLATE → bytes of a known size.
    static func inflate(_ src: Data, size: Int) -> Data? {
        if size == 0 { return Data() }
        // A statement sheet is never this big; refuse rather than reserve huge memory.
        if src.isEmpty || size < 0 || size > 200_000_000 { return nil }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            src.withUnsafeBytes { (s: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let sp = s.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, size, sp, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
    }
}

// MARK: XLSX

/// .xlsx → rows of cells, like the Mac's SheetJS reader (xlsx.ts): shared strings, inline
/// strings, numbers, booleans, dates (date-formatted numbers → "yyyy-MM-dd"). The sheet with
/// the most rows is the statement (others are often a cover page).
enum XLSXReader {
    static func read(_ data: Data) throws -> [[String]] {
        let zip = try ZipArchive(data)
        let shared = try zip.data("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let dateStyles = try zip.data("xl/styles.xml").map(StylesParser.dateStyles) ?? []
        var sheets: [String] = []
        if let wb = try zip.data("xl/workbook.xml"), let rels = try zip.data("xl/_rels/workbook.xml.rels") {
            let targets = RelsParser.parse(rels)
            for rid in WorkbookParser.sheetIds(wb) {
                guard let t = targets[rid] else { continue }
                let path = t.hasPrefix("/") ? String(t.dropFirst()) : "xl/" + t
                if zip.entries[path] != nil { sheets.append(path) }
            }
        }
        if sheets.isEmpty {
            sheets = zip.entries.keys.filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        var best: [[String]] = []
        for s in sheets {
            guard let xml = try zip.data(s) else { continue }
            let rows = SheetParser.parse(xml, shared: shared, dateStyles: dateStyles)
            if rows.count > best.count { best = rows }
        }
        return best
    }

    /// Column letters of a cell reference ("BC12" → 54, zero-based), or nil.
    static func column(_ ref: String) -> Int? {
        var n = 0
        var any = false
        for ch in ref.uppercased().unicodeScalars {
            guard ch.value >= 65 && ch.value <= 90 else { break }
            n = n * 26 + Int(ch.value - 64)
            any = true
        }
        return any ? n - 1 : nil
    }

    /// A number as JavaScript's String(n) writes it: "1234.5", "100", "-38".
    static func numberText(_ s: String) -> String {
        guard let d = Double(s), d.isFinite else { return s }
        if d == d.rounded() && abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }
}

/// Element name without a namespace prefix ("x:row" → "row").
private func local(_ name: String) -> String {
    if let i = name.lastIndex(of: ":") { return String(name[name.index(after: i)...]) }
    return name
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var out: [String] = []
    private var cur = ""
    private var inSI = false, inT = false, phonetic = 0

    static func parse(_ data: Data) -> [String] {
        let d = SharedStringsParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch local(elementName) {
        case "si": inSI = true; cur = ""
        case "rPh": phonetic += 1
        case "t": inT = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "si": inSI = false; out.append(cur)
        case "rPh": phonetic = max(0, phonetic - 1)
        case "t": inT = false
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSI && inT && phonetic == 0 { cur += string }
    }
}

/// Which cell styles (indexes into cellXfs) show a date.
private final class StylesParser: NSObject, XMLParserDelegate {
    private var custom: [Int: String] = [:]
    private var xfFormats: [Int] = []
    private var inCellXfs = false

    static func dateStyles(_ data: Data) -> Set<Int> {
        let d = StylesParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        var out = Set<Int>()
        for (i, f) in d.xfFormats.enumerated() where isDateFormat(f, d.custom[f]) { out.insert(i) }
        return out
    }

    private static let quoted = RX(#""[^"]*""#)
    private static let bracket = RX(#"\[[^\]]*\]"#)
    private static let escaped = RX(#"\\.|_.|\*."#)
    private static let dateChars = RX("[dmy]", ci: true)

    static func isDateFormat(_ id: Int, _ code: String?) -> Bool {
        if (14...22).contains(id) || (27...36).contains(id) || (45...47).contains(id) || (50...58).contains(id) { return true }
        guard let code else { return false }
        let bare = escaped.replace(bracket.replace(quoted.replace(code, ""), ""), "")
        return dateChars.test(bare)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        switch local(elementName) {
        case "numFmt":
            if let id = a["numFmtId"].flatMap({ Int($0) }) { custom[id] = a["formatCode"] ?? "" }
        case "cellXfs": inCellXfs = true
        case "xf": if inCellXfs { xfFormats.append(a["numFmtId"].flatMap { Int($0) } ?? 0) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if local(elementName) == "cellXfs" { inCellXfs = false }
    }
}

/// Relationship id → target, from xl/_rels/workbook.xml.rels.
private final class RelsParser: NSObject, XMLParserDelegate {
    var out: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let d = RelsParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.out
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        if local(elementName) == "Relationship", let id = a["Id"], let t = a["Target"] { out[id] = t }
    }
}

/// The workbook's sheets in order (their relationship ids).
private final class WorkbookParser: NSObject, XMLParserDelegate {
    var ids: [String] = []

    static func sheetIds(_ data: Data) -> [String] {
        let d = WorkbookParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.ids
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        guard local(elementName) == "sheet" else { return }
        if let id = a["r:id"] ?? a.first(where: { local($0.key) == "id" && $0.key != "sheetId" })?.value { ids.append(id) }
    }
}

/// One worksheet → rows of cell text (at most 20,000 rows and 60 columns, empty rows dropped).
private final class SheetParser: NSObject, XMLParserDelegate {
    private let shared: [String]
    private let dateStyles: Set<Int>
    private var rows: [Int: [Int: String]] = [:]
    private var rowIndex = -1
    private var nextCol = 0
    private var cellCol = 0
    private var cellType = "n"
    private var cellStyle = 0
    private var value = ""
    private var inline = ""
    private var inV = false, inIs = false, inT = false

    private init(shared: [String], dateStyles: Set<Int>) {
        self.shared = shared
        self.dateStyles = dateStyles
    }

    static func parse(_ data: Data, shared: [String], dateStyles: Set<Int>) -> [[String]] {
        let d = SheetParser(shared: shared, dateStyles: dateStyles)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.rows.keys.sorted().compactMap { (r: Int) -> [String]? in
            guard let cells = d.rows[r], let maxCol = cells.keys.max() else { return nil }
            let row = (0...maxCol).map { cells[$0] ?? "" }
            return row.contains { !$0.isEmpty } ? row : nil
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        switch local(elementName) {
        case "row":
            rowIndex = a["r"].flatMap { Int($0) }.map { $0 - 1 } ?? rowIndex + 1
            nextCol = 0
        case "c":
            cellCol = a["r"].flatMap(XLSXReader.column) ?? nextCol
            nextCol = cellCol + 1
            cellType = a["t"] ?? "n"
            cellStyle = a["s"].flatMap { Int($0) } ?? 0
            value = ""
            inline = ""
        case "v": inV = true
        case "is": inIs = true
        case "t": inT = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "v": inV = false
        case "is": inIs = false
        case "t": inT = false
        case "c":
            guard rowIndex >= 0, rowIndex < 20000, cellCol < 60 else { return }
            let text = cellText()
            if !text.isEmpty { rows[rowIndex, default: [:]][cellCol] = text }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV { value += string } else if inIs && inT { inline += string }
    }

    private func cellText() -> String {
        switch cellType {
        case "s":
            guard let i = Int(value.jsTrim), i >= 0, i < shared.count else { return "" }
            return shared[i].jsTrim
        case "inlineStr": return inline.jsTrim
        case "str": return value.jsTrim
        case "b": return value.jsTrim == "1" ? "TRUE" : "FALSE"
        case "e": return ""
        case "d": return String(value.jsTrim.prefix(10))
        default:
            let v = value.jsTrim
            if v.isEmpty { return "" }
            if dateStyles.contains(cellStyle), let n = Double(v), let iso = StmtDates.fromSerial(n) { return iso }
            return XLSXReader.numberText(v)
        }
    }
}
