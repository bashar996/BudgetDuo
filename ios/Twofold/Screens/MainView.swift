import SwiftUI

@MainActor
struct MainView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        // The system tab bar: at the bottom on most iPhones, and on the trailing
        // edge (next to the status bar and camera) on iPhone Duo.
        TabView(selection: Binding(
            get: { router.tab },
            set: { t in
                if t == .add {
                    // The Add tab is an action, not a place: open the keypad and stay put.
                    if let L = store.ledger() { router.add(store, L) }
                } else if t != router.tab {
                    router.select(t)
                } else {
                    // Tapping the current tab also leaves the wide-screen bills calendar.
                    router.closeBillsSplit()
                }
            }
        )) {
            // `.tabItem` rather than `Tab`, which needs iOS 18 (the app supports 17).
            ForEach(AppTab.allCases, id: \.self) { t in
                Group {
                    if t == .add { Palette.black.ignoresSafeArea() } else { TabRoot(tab: t) }
                }
                .tabItem { Label(t.rawValue, systemImage: t.symbol) }
                .tag(t)
            }
        }
        .background(Palette.black.ignoresSafeArea())
        .fullScreenCover(item: $router.entry) { AddEntryView(draft: $0) }
        .sheet(item: $router.form) { f in FormHost(form: f) }
        .overlay(alignment: .top) { ErrorToast() }
        .overlay(alignment: .bottom) { UndoToast() }
    }
}

/// One tab's content. Wide (unfolded): the tab on the left half and the detail
/// pane on the right half, split on the fold. Narrow: just the tab.
@MainActor
private struct TabRoot: View {
    var tab: AppTab
    @Environment(Router.self) private var router

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            Group {
                if wide {
                    // Spans the side safe areas so the divider sits on the fold;
                    // each pane pads its own content clear of the camera and tab bar.
                    let inset = geo.safeAreaInsets
                    let half = (geo.size.width + inset.leading + inset.trailing) / 2
                    HStack(spacing: 0) {
                        stack
                            .padding(.leading, inset.leading)
                            .frame(width: half)
                        detail
                            .environment(\.screenTrailingInset, inset.trailing)
                            .frame(width: half)
                            .overlay(alignment: .leading) {
                                LinearGradient(colors: [.white.opacity(0.07), .black.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 2).ignoresSafeArea()
                            }
                    }
                    .ignoresSafeArea(.container, edges: .horizontal)
                    // One Back for both panes, docked in the rail column on the right edge,
                    // low down where the thumb rests when the phone is unfolded.
                    .overlay {
                        if router.tab == tab {
                            // Runs under the trailing safe area so the button can sit in the
                            // rail's column; empty space lets touches through.
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RailBackButton()
                                    .frame(width: max(inset.trailing, 76))
                                    .padding(.bottom, 18)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .ignoresSafeArea(.container, edges: .horizontal)
                        }
                    }
                    .onAppear { router.railInset = inset.trailing }
                    .onChange(of: inset.trailing) { _, v in router.railInset = v }
                } else {
                    stack
                }
            }
            .onAppear { if router.isWide != wide { router.layoutChanged(wide: wide) } }
            .onChange(of: wide) { _, w in if router.isWide != w { router.layoutChanged(wide: w) } }
        }
        .background(Palette.black.ignoresSafeArea())
    }

    private var stack: some View {
        // Unfolded, Bills opened from this pane: the calendar covers the pane
        // (the tab stays underneath, so Back returns to where it was).
        let billsCalendar = router.isWide && router.billsSplit && router.tab == tab && router.detail == .bills
        return NavigationStack(path: Binding(get: { router.paths[tab] ?? [] }, set: { router.setPath(tab, $0) })) {
            Group {
                switch tab {
                case .home: HomeView()
                case .budget: BudgetView()
                case .savings: SavingsView()
                case .more: MoreView()
                case .add: EmptyView()
                }
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .accessibilityHidden(billsCalendar)
        .overlay {
            if billsCalendar { BillCalendarScreen() }
        }
    }

    /// Only the selected tab hosts the detail pane, so there's one stack bound
    /// to `detailPath` at a time.
    @ViewBuilder private var detail: some View {
        if router.tab == tab {
            NavigationStack(path: Binding(get: { router.detailPath }, set: { router.setDetailPath($0) })) {
                RouteView(route: router.detail, showBack: false)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        } else {
            Palette.black.ignoresSafeArea()
        }
    }
}

struct RouteView: View {
    var route: Route
    var showBack = true
    var body: some View {
        switch route {
        case .accounts: AccountsView(showBack: showBack)
        case .worth: NetWorthView(showBack: showBack)
        case .bills: BillsView(showBack: showBack)
        case .reports: ReportsView(showBack: showBack)
        case .debt: DebtView(showBack: showBack)
        case .plan: PlanAheadView(showBack: showBack)
        case .us: UsTwoView(showBack: showBack)
        case .settings: SettingsView(showBack: showBack)
        case .activity(let acct): ActivityView(showBack: showBack, account: acct)
        case .loan(let id): LoanDetailView(id: id, showBack: showBack)
        }
    }
}

private struct ErrorToast: View {
    @Environment(HouseholdStore.self) private var store
    var body: some View {
        if let e = store.error {
            Button { store.error = nil } label: {
                Text(e).font(.geist(13, .medium)).multilineTextAlignment(.leading)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(Palette.black)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .task(id: e) { try? await Task.sleep(for: .seconds(5)); store.error = nil }
        }
    }
}

/// "Deleted {name} · Undo" for about 5 seconds after an entry is deleted (Undo puts it
/// back with the same id), and "Imported {n} entries · Undo" for about 8 seconds after a
/// statement import (Undo deletes exactly those entries).
@MainActor
private struct UndoToast: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if let u = router.importUndo {
                toast("Imported \(u.count) \(u.count == 1 ? "entry" : "entries") ·", label: "Undo import", key: u.id.uuidString, seconds: 8) {
                    store.undoImport(u)
                    router.importUndo = nil
                } expire: {
                    if router.importUndo?.id == u.id { router.importUndo = nil }
                }
            } else if let t = router.undo {
                toast("Deleted \(t.name) ·", label: "Undo delete", key: t.id, seconds: 5) {
                    store.restore(t)
                    router.undo = nil
                } expire: {
                    if router.undo?.id == t.id { router.undo = nil }
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: (router.importUndo?.id.uuidString ?? "") + "|" + (router.undo?.id ?? ""))
    }

    private func toast(_ text: String, label: String, key: String, seconds: Double,
                       undo: @escaping () -> Void, expire: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.geist(14, .medium)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: undo) {
                Text("Undo").font(.geist(14, .semibold)).foregroundStyle(Palette.lavender)
                    .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
        .padding(.leading, 16).padding(.trailing, 4)
        .background(Palette.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.white.opacity(0.14), lineWidth: 1))
        .foregroundStyle(Palette.white)
        .padding(.horizontal, 14)
        // Clear of the tab bar; unfolded, in the right pane and clear of the rail and its Back.
        .frame(maxWidth: router.isWide ? CGFloat(440) : CGFloat.infinity)
        .padding(.trailing, router.isWide ? max(0, 76 - router.railInset) : 0)
        .frame(maxWidth: .infinity, alignment: router.isWide ? .trailing : .center)
        .padding(.bottom, router.isWide ? 18 : 58)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: key) {
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            expire()
        }
    }
}

/// Unfolded only: the one Back button, a 52pt dark circle in the tab rail's column.
/// Shown while there's something to go back to; undoes the latest step in either pane.
@MainActor
private struct RailBackButton: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if router.canGoBack {
                Button { withAnimation(.snappy(duration: 0.25)) { router.goBack() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.white)
                        .frame(width: 52, height: 52)
                        .background(Palette.tabBar, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.white.opacity(0.14), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .accessibilityLabel("Back")
                .accessibilityValue(Text(targetName))
                .accessibilityHint("Back to \(targetName)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: router.canGoBack)
    }

    private var targetName: String {
        switch router.backTarget {
        case .tab(let t): return t.rawValue
        case .route(let r):
            if case .loan(let id) = r, let d = store.debts.first(where: { $0.id == id }) { return d.name }
            return r.title
        case nil: return ""
        }
    }
}
