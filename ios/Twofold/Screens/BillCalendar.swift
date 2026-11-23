import SwiftUI

/// This month's calendar on the Bills screen: one square per day, coloured by
/// its bills (still due, overdue, all paid), today in black, paydays outlined.
/// Tapping a day that has bills filters the bill list to it; tapping it again clears it.
@MainActor
struct BillCalendar: View {
    var L: Ledger
    var hint: String
    @Environment(Router.self) private var router

    private struct Cell: Identifiable {
        let id: Int
        /// 0 for the blanks before the 1st.
        let day: Int
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
        let first = DateKit.cal.component(.weekday, from: DateKit.date(L.ym + "-01")) - 1
        var out: [Cell] = (0..<max(0, first)).map {
            Cell(id: 100 + $0, day: 0, bills: 0, due: false, late: false, today: false, payday: false)
        }
        let rows = L.billRows
        for d in 1...max(1, L.daysInMonth) {
            let bs = rows.filter { $0.dueDay == d }
            let due = bs.contains { !$0.isPaid }
            let payday = L.household.incomes.contains { $0.amt > 0 && min($0.day, L.daysInMonth) == d }
            out.append(Cell(id: 200 + d, day: d, bills: bs.count, due: due, late: due && d < L.todayDay,
                            today: d == L.todayDay, payday: payday))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(DateKit.monthLabel(L.ym)).font(.geist(18, .medium)).tracking(em: -0.01, size: 18)
                    .accessibilityAddTraits(.isHeader)
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
                VStack(spacing: 3) {
                    Text("\(c.day)").font(.geist(14, .medium))
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
        var parts = ["\(c.day) \(L.monthShort)"]
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
