import SwiftUI

// A plain EnvironmentKey rather than `@Entry`, which needs the Xcode 16 SDK.
private struct ScreenTrailingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

/// True inside the right-hand (detail) pane of the wide layout.
private struct IsDetailPaneKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isDetailPane: Bool {
        get { self[IsDetailPaneKey.self] }
        set { self[IsDetailPaneKey.self] = newValue }
    }

    /// On wide screens the detail pane runs under the trailing safe area (the camera
    /// strip in landscape) so its colours reach the edge; text is pushed in by this much.
    var screenTrailingInset: CGFloat {
        get { self[ScreenTrailingInsetKey.self] }
        set { self[ScreenTrailingInsetKey.self] = newValue }
    }
}

/// Black header, stepped edge, then a coloured sheet running to the bottom.
struct Screen<Header: View, Content: View>: View {
    var color: Color
    var mirrored = false
    var contentPadding: CGFloat = 20
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @Environment(\.screenTrailingInset) private var trailingInset

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, trailingInset)
                BlobEdge(fill: color, mirrored: mirrored)
                VStack(alignment: .leading, spacing: 0) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, contentPadding)
                    .padding(.trailing, trailingInset)
                    // The system tab bar insets scroll content itself; this is just breathing room.
                    .padding(.bottom, 40)
                    .frame(minHeight: 520, alignment: .top)
                    .background(color)
                    .foregroundStyle(Palette.black)
            }
        }
        .scrollIndicators(.hidden)
        // Black above, the sheet colour below, so overscroll never shows a seam.
        // Runs under the safe areas so short screens don't end in a black band.
        .background(VStack(spacing: 0) { Palette.black; color }.ignoresSafeArea())
        .foregroundStyle(Palette.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// “AED 12,345” with the oversized figure.
struct BigAmount: View {
    var currency: String
    var value: String
    var size: CGFloat = 60
    var color: Color = Palette.white
    var currencyColor: Color = Palette.mute

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(currency).font(.geist(22, .medium)).foregroundStyle(currencyColor)
            Text(value).font(.geist(size, .medium)).tracking(em: -0.045, size: size).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Back arrow + centred title used on pushed screens. Without a back arrow
/// (sheets) it's just the title, aligned with the content below instead of centred
/// between two empty slots. Unfolded iPhone Duo: no pane has its own arrow (the one
/// Back sits by the tab rail), so every pane shows its title centred. iPad: each pane
/// keeps its own arrow, which goes back within that pane.
@MainActor
struct NavRow: View {
    var title: String
    var showBack = true
    /// Wide iPad: what Back does instead of popping the pane (e.g. closing the bills calendar).
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDetailPane) private var isDetailPane
    @Environment(Router.self) private var router

    var body: some View {
        if router.isWide && !Router.isPad {
            Text(title).font(.geist(19, .medium)).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 56)
                .padding(.top, 8)
        } else if showBack {
            HStack {
                Button {
                    if let onBack { onBack() }
                    else if router.isWide { router.paneBack(detail: isDetailPane, dismiss) }
                    else { router.back(dismiss) }
                } label: {
                    Text("←").font(.geist(24)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Text(title).font(.geist(19, .medium)).frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        } else {
            Text(title).font(.geist(19, .medium))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 20)
                .padding(.top, 18)
        }
    }
}

/// Thin progress line with a rounded fill.
struct ProgressLine: View {
    var ratio: Double
    var fill: Color = Palette.lavender
    var track: Color = Palette.black
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: g.size.width * Money.pct(ratio))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: ratio)
        .accessibilityHidden(true)
    }
}

struct SectionTitle: View {
    var title: String
    var action: (label: String, run: () -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.geist(22, .medium)).tracking(em: -0.01, size: 22)
            Spacer()
            if let action {
                Button(action.label, action: action.run).font(.geist(14, .medium)).frame(minHeight: 44)
            }
        }
    }
}

struct Hairline: View {
    var opacity: Double = 0.14
    var body: some View { Rectangle().fill(Palette.black.opacity(opacity)).frame(height: 1) }
}

/// Black date block used for bills.
struct DateTile: View {
    var day: Int
    var month: String
    var body: some View {
        VStack(spacing: 0) {
            Text("\(day)").font(.geist(16, .semibold))
            Text(month).font(.geist(10))
        }
        .frame(width: 44, height: 44)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .foregroundStyle(Palette.white)
    }
}

struct InitialTile: View {
    var name: String
    var background: Color
    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).first ?? "?").uppercased())
            .font(.geist(17, .semibold))
            .frame(width: 44, height: 44)
            .background(background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct TxRow: View {
    var tx: Tx
    var ledger: Ledger
    var tile: Color
    var subColor: Color
    var line: Double = 0.14

    var body: some View {
        HStack(spacing: 12) {
            InitialTile(name: tx.name, background: tile)
            VStack(alignment: .leading, spacing: 1) {
                Text(tx.name).font(.geist(16, .medium)).lineLimit(1)
                Text(sub).font(.geist(13)).foregroundStyle(subColor).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(amount).font(.geist(15, .medium)).lineLimit(1).fixedSize()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline(opacity: line) }
        .contentShape(Rectangle())
    }

    private var sub: String {
        tx.type == .transfer
            ? ledger.accountName(tx.acct) + " → " + ledger.accountName(tx.to)
            : ledger.categoryName(tx.cat) + " · " + ledger.name(tx.who)
    }
    private var amount: String {
        (tx.type == .income ? "+" : tx.type == .transfer ? "" : "−") + ledger.money.f(tx.amt)
    }
}

/// An entry row: tap to edit; touch and hold for Edit and Delete (with Undo).
/// `sheet` is the colour behind the row, so the touch-and-hold preview matches.
@MainActor
struct EntryButton: View {
    var tx: Tx
    var ledger: Ledger
    var tile: Color
    var subColor: Color
    var sheet: Color
    var line: Double = 0.14
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.edit(tx) } label: {
            TxRow(tx: tx, ledger: ledger, tile: tile, subColor: subColor, line: line)
                .background(sheet)
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Button { router.edit(tx) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { router.delete(tx, store) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

/// Round chip used for filters and pickers on black.
struct Chip: View {
    var label: String
    var on: Bool
    var selected: Color = Palette.white
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.geist(13.5, .medium)).lineLimit(1)
                .padding(.horizontal, 14).frame(height: 44)
                .foregroundStyle(on ? Palette.black : Palette.white)
                .background(on ? selected : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? selected : Palette.white.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Filled, rounded-square button.
struct BlockButton: View {
    var title: String
    var fill: Color = Palette.black
    var text: Color = Palette.white
    var outline = false
    var height: CGFloat = 52
    var radius: CGFloat = 18
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.geist(15, .medium)).frame(maxWidth: .infinity).frame(height: height)
                .foregroundStyle(outline ? fill : text)
                .background(outline ? .clear : fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(outline ? fill : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EmptyNote: View {
    var text: String
    var color: Color = Palette.gray
    var body: some View {
        Text(text).font(.geist(14)).foregroundStyle(color).padding(.vertical, 6)
    }
}

/// Unfolded (wide): docks a screen's main action at the bottom of the right pane, in
/// thumb reach, instead of at the end of the list. Folded: nothing (the screen keeps
/// its own button in the content).
@MainActor
private struct WideDockedAction: ViewModifier {
    var title: String
    var sheet: Color
    var action: () -> Void
    @Environment(Router.self) private var router
    @Environment(\.screenTrailingInset) private var trailingInset

    @ViewBuilder
    func body(content: Content) -> some View {
        if router.isWide {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                BlockButton(title: title, height: 54, action: action)
                    .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 14)
                    .padding(.trailing, trailingInset)
                    .background(LinearGradient(colors: [sheet.opacity(0), sheet, sheet], startPoint: .top, endPoint: .bottom))
            }
        } else {
            content
        }
    }
}

extension View {
    /// See `WideDockedAction`.
    @MainActor
    func wideDockedAction(_ title: String, sheet: Color, action: @escaping () -> Void) -> some View {
        modifier(WideDockedAction(title: title, sheet: sheet, action: action))
    }
}

/// Lets the swipe-back gesture work although the navigation bar is hidden.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}
