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
                } else {
                    stack
                }
            }
            .onAppear { router.isWide = wide }
            .onChange(of: wide) { _, w in
                router.isWide = w
                if w { router.paths = [:] } else { router.detailPath = [] }
            }
        }
        .background(Palette.black.ignoresSafeArea())
    }

    private var stack: some View {
        NavigationStack(path: Binding(get: { router.paths[tab] ?? [] }, set: { router.paths[tab] = $0 })) {
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
    }

    /// Only the selected tab hosts the detail pane, so there's one stack bound
    /// to `detailPath` at a time.
    @ViewBuilder private var detail: some View {
        @Bindable var router = router
        if router.tab == tab {
            NavigationStack(path: $router.detailPath) {
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
        case .bills: BillsView(showBack: showBack)
        case .reports: ReportsView(showBack: showBack)
        case .debt: DebtView(showBack: showBack)
        case .plan: PlanAheadView(showBack: showBack)
        case .us: UsTwoView(showBack: showBack)
        case .settings: SettingsView(showBack: showBack)
        case .activity(let acct): ActivityView(showBack: showBack, account: acct)
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
