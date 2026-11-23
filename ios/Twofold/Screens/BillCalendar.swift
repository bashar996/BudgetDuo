import SwiftUI

/// The budget month's calendar on the Bills screen: one square per day from the period's
/// first day to its last (weekday-aligned; a budget month that doesn't start on the 1st runs
/// across two months, and the 1st of the next month carries its month's name), coloured by
/// its bills (still due, overdue, all paid), today in black, paydays outlined.
/// Tapping a day that has bills filters the bill list to it; tapping it again clears it.
@MainActor
struct BillCalendar: View {
    var L: Ledger
    var hint: String
    @Environment(Router.self) private var router

    private struct Cell: Identifiable {
        let id: Int
        /// 0 for the blanks before the first day.
        let day: Int
        /// "yyyy-MM-dd" ("" for blanks).
        let iso: String
        /// "Dec" on the first day of a month after the period's first day, else nil.
        let monthMark: String?
        let bills: Int
        let due: Bool
        let late: Bool
        let today: Bool
        let payday: Bool

        var fill: Color {
            today ? Palette.black : late ? Palette.bad : due ? Palette.lavender : bills > 0 ? Palette.tile : .clear
        }
        var text: Color { today || late ? Palette.white : Palette.black }
    }

    private var cells: [Cell] {
        let p = L.period
        let first = DateKit.cal.component(.weekday, from: DateKit.date(p.from)) - 1
        var out: [Cell] = (0..<max(0, first)).map {
            Cell(id: $0, day: 0, iso: "", monthMark: nil, bills: 0, due: false, late: false, today: false, payday: false)
        }
        let rows = L.billRows
        for (k, iso) in p.dates.enumerated() {
            let d = Int(iso.suffix(2)) ?? 1
            let month = String(iso.prefix(7))
            let dim = DateKit.daysIn(month)
            let bs = rows.filter { $0.due == iso }
            let due = bs.contains { !$0.isPaid }
            let payday = L.household.incomes.contains { $0.amt > 0 && min($0.day, dim) == d }
            let mark: String? = (k > 0 && d == 1) ? DateKit.monthName(month, short: true) : nil
            out.append(Cell(id: 100 + k, day: d, iso: iso, monthMark: mark, bills: bs.count, due: due,
                            late: due && iso < L.todayIso, today: iso == L.todayIso, payday: payday))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(DateKit.monthLabel(L.ym)).font(.geist(18, .medium)).tracking(em: -0.01, size: 18)
                        .accessibilityAddTraits(.isHeader)
                    if L.cycleStart > 1 {
                        Text(L.period.rangeLabel).font(.geist(12.5)).foregroundStyle(Palette.gray)
                    }
                }
                Spacer(minLength: 0)
                Text(hint).font(.geist(12.5)).foregroundStyle(Palette.gray).multilineTextAlignment(.trailing)
            }
            .padding(.bottom, 10)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, w in
                    Text(w).font(.geist(12)).foregroundStyle(Palette.gray).frame(maxWidth: .infinity).padding(.bottom, 2)
                        .accessibilityHidden(true)
                }
                ForEach(cells) { c in cell(c) }
            }
            legend.padding(.top, 12)
        }
        .padding(14)
        .background(Palette.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .foregroundStyle(Palette.black)
    }

    @ViewBuilder
    private func cell(_ c: Cell) -> some View {
        if c.day == 0 {
            Color.clear.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
        } else if c.bills > 0 {
            let selected = router.billDay == c.day
            Button { router.billDay = selected ? nil : c.day } label: { face(c, selected: selected) }
                .buttonStyle(.plain)
                .zIndex(selected ? 1 : 0)
                .accessibilityLabel(label(c))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHint(selected ? "Shows every bill again" : "Shows only this day’s bills")
        } else {
            face(c, selected: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label(c))
        }
    }

    private func face(_ c: Cell, selected: Bool) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 1) {
                    if let mark = c.monthMark {
                        Text(mark).font(.geist(9, .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Text("\(c.day)").font(.geist(14, .medium)).lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 2) {
                        ForEach(0..<min(c.bills, 5), id: \.self) { _ in Circle().frame(width: 4, height: 4) }
                    }
                    .frame(height: 4)
                }
                .foregroundStyle(c.text)
            }
            .background(c.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.black.opacity(c.payday ? 1 : 0), lineWidth: 1.5)
            }
            .overlay {
                // Selected: 2pt white ring, then 2pt black ring, outside the square.
                if selected {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.black, lineWidth: 2).padding(-4)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.white, lineWidth: 2).padding(-2)
                    }
                    .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
    }

    private func label(_ c: Cell) -> String {
        let month: String = DateKit.monthName(String(c.iso.prefix(7)), short: true)
        var parts = ["\(c.day) \(month)"]
        if c.today { parts.append("today") }
        if c.bills > 0 {
            parts.append("\(c.bills) bill" + (c.bills == 1 ? "" : "s"))
            parts.append(c.late ? "overdue" : c.due ? "due" : "paid")
        }
        if c.payday { parts.append("payday") }
        return parts.joined(separator: ", ")
    }

    private var legend: some View {
        FlowLayout(spacing: 10) {
            legendItem("Due", Palette.lavender)
            legendItem("Overdue", Palette.bad)
            legendItem("Paid", Palette.tile)
            legendItem("Today", Palette.black)
            legendItem("Payday", .clear, border: Palette.black)
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ text: String, _ fill: Color, border: Color? = nil) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(border ?? fill, lineWidth: 1.5))
                .frame(width: 11, height: 11)
            Text(text).font(.geist(12)).foregroundStyle(Palette.gray)
        }
    }
}

/// Unfolded, with Bills opened from the left pane: the calendar on its own on the
/// left; the "Still due" hero and the list (filtered by the picked day) on the right.
@MainActor
struct BillCalendarScreen: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        if let L = store.ledger() {
            // Only shown unfolded, where Back is the one by the tab rail: just the title here.
            Screen(color: Palette.cream, mirrored: true, contentPadding: 16) {
                NavRow(title: "Bills", onBack: { router.closeBillsSplit() })
            } content: {
                BillCalendar(L: L, hint: "That day’s bills show on the right")
            }
        }
    }
}
