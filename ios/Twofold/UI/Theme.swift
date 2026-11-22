import SwiftUI
import Observation

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

/// Per-phone look (Settings → Look), kept in UserDefaults. Observable, so every view
/// that reads `Palette.lavender` in its body redraws when the accent changes.
@Observable
final class Look {
    static let shared = Look()
    /// The accents the Mac offers: lavender, blue, coral, sand.
    static let accents: [(hex: UInt32, name: String)] = [
        (0xb9b0ff, "Lavender"), (0xa9c4ff, "Blue"), (0xffb9a8, "Coral"), (0xd8d3c2, "Sand"),
    ]
    private static let key = "accent"

    private(set) var accent: UInt32

    init() {
        let saved = UInt32(truncatingIfNeeded: UserDefaults.standard.integer(forKey: Look.key))
        accent = Look.accents.contains { $0.hex == saved } ? saved : Look.accents[0].hex
    }

    func setAccent(_ hex: UInt32) {
        guard Look.accents.contains(where: { $0.hex == hex }) else { return }
        accent = hex
        UserDefaults.standard.set(Int(hex), forKey: Look.key)
    }
}

/// Black, lavender and cream only, as in the design reference.
enum Palette {
    static let black = Color(hex: 0x0b0b0c)
    /// The accent: lavender unless another one is picked in Settings → Look.
    static var lavender: Color { Color(hex: Look.shared.accent) }
    static let cream = Color(hex: 0xfbf9ef)
    static let white = Color.white
    /// Secondary text on black
    static let mute = Color(hex: 0xa9a7b8)
    /// Secondary text on lavender
    static let ink = Color(hex: 0x3a3566)
    /// Secondary text on cream
    static let gray = Color(hex: 0x6b6878)
    static let soft = Color(hex: 0xd9d7e4)
    static let amountPlaceholder = Color(hex: 0x6f66b8)
    static let tabBar = Color(hex: 0x17171b)
    static let field = Color(hex: 0x1d1d22)
    static let tile = Color(hex: 0xebe8da)
    static let overFill = Color(hex: 0xd0453a)
    static let overText = Color(hex: 0xb3352b)
    /// Overdue bills, Delete buttons, losses on cream
    static let bad = Color(hex: 0xc23b30)
    /// Negative figures on black (forecast dips)
    static let badOnBlack = Color(hex: 0xff8f85)
    /// Links and positive values on cream
    static let accentText = Color(hex: 0x4b40a8)
}

enum GeistWeight: String { case regular = "Geist-Regular", medium = "Geist-Medium", semibold = "Geist-SemiBold" }

extension Font {
    /// Geist at a design size. Text up to 22pt follows Dynamic Type; the big
    /// display figures stay fixed so they keep the layout.
    static func geist(_ size: CGFloat, _ weight: GeistWeight = .regular) -> Font {
        size > 22 ? .custom(weight.rawValue, fixedSize: size) : .custom(weight.rawValue, size: size, relativeTo: .body)
    }
}

extension View {
    /// CSS-style letter-spacing in em.
    func tracking(em: CGFloat, size: CGFloat) -> some View { tracking(em * size) }
}

/// The stepped “blob” edge that joins two colour blocks.
/// Drawn from the design's 402×78 SVG and stretched to the width.
struct BlobEdge: View {
    var fill: Color
    var hole: Color = Palette.black
    var mirrored = false
    var height: CGFloat = 66

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 402, sy = size.height / 78
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            var p = Path()
            p.move(to: pt(0, 78)); p.addLine(to: pt(0, 45))
            p.addQuadCurve(to: pt(11, 34), control: pt(0, 34)); p.addLine(to: pt(69, 34))
            p.addQuadCurve(to: pt(80, 45), control: pt(80, 34)); p.addLine(to: pt(80, 51))
            p.addQuadCurve(to: pt(91, 62), control: pt(80, 62)); p.addLine(to: pt(141, 62))
            p.addQuadCurve(to: pt(152, 51), control: pt(152, 62)); p.addLine(to: pt(152, 31))
            p.addQuadCurve(to: pt(163, 20), control: pt(152, 20)); p.addLine(to: pt(215, 20))
            p.addQuadCurve(to: pt(226, 31), control: pt(226, 20)); p.addLine(to: pt(226, 41))
            p.addQuadCurve(to: pt(237, 52), control: pt(226, 52)); p.addLine(to: pt(293, 52))
            p.addQuadCurve(to: pt(304, 41), control: pt(304, 52))
            p.addQuadCurve(to: pt(315, 30), control: pt(304, 30)); p.addLine(to: pt(391, 30))
            p.addQuadCurve(to: pt(402, 41), control: pt(402, 30)); p.addLine(to: pt(402, 78))
            p.closeSubpath()
            ctx.fill(p, with: .color(fill))
            let pill = CGRect(x: 326 * sx, y: 2 * sy, width: 60 * sx, height: 20 * sy)
            ctx.fill(Path(roundedRect: pill, cornerSize: CGSize(width: 10 * sx, height: 10 * sy)), with: .color(fill))
            let notch = CGRect(x: 22 * sx, y: 52 * sy, width: 44 * sx, height: 16 * sy)
            ctx.fill(Path(roundedRect: notch, cornerSize: CGSize(width: 8 * sx, height: 8 * sy)), with: .color(hole))
        }
        .frame(height: height)
        .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        .padding(.bottom, -1)
        .accessibilityHidden(true)
    }
}
