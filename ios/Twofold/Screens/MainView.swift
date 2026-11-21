import SwiftUI

@MainActor
struct MainView: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            Group {
                if wide {
                    // Unfolded / wide: budget and tabs on the left, detail on the right.
                    HStack(spacing: 0) {
                        primary.frame(width: geo.size.width / 2)
                        NavigationStack { RouteView(route: router.detail, showBack: false) }
                            .frame(width: geo.size.width / 2)
                            .overlay(alignment: .leading) {
                                LinearGradient(colors: [.white.opacity(0.07), .black.opacity(0.3)], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 2).ignoresSafeArea()
                            }
                    }
                } else {
                    primary
                }
            }
            .onAppear { router.isWide = wide }
            .onChange(of: wide) { _, w in router.isWide = w; if w { router.path = [] } }
        }
        .background(Palette.black.ignoresSafeArea())
        .fullScreenCover(item: $router.entry) { AddEntryView(draft: $0) }
        .sheet(item: $router.form) { f in FormHost(form: f) }
        .overlay(alignment: .top) { ErrorToast() }
    }

    private var primary: some View {
        @Bindable var router = router
        return ZStack(alignment: .bottom) {
            NavigationStack(path: $router.path) {
                Group {
                    switch router.tab {
                    case .home: HomeView()
                    case .budget: BudgetView()
                    case .savings: SavingsView()
                    case .more: MoreView()
                    }
                }
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
            TabBar()
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

/// Floating black tab bar with the lavender + in the middle.
@MainActor
struct TabBar: View {
    @Environment(HouseholdStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            item(.home); item(.budget)
            Button {
                if let L = store.ledger() { router.add(store, L) }
            } label: {
                Text("+").font(.geist(30)).frame(width: 52, height: 52)
                    .background(Palette.lavender, in: Circle()).foregroundStyle(Palette.black)
            }
            .buttonStyle(.plain)
            .frame(width: 64)
            .accessibilityLabel("Add entry")
            item(.savings); item(.more)
        }
        .padding(.horizontal, 6)
        .frame(height: 64)
        .background(Palette.tabBar, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 12)
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    private func item(_ t: Tab) -> some View {
        let on = router.tab == t && router.path.isEmpty
        return Button { router.select(t) } label: {
            Text(t.rawValue).font(.geist(13.5, .medium)).frame(maxWidth: .infinity).frame(height: 52)
                .foregroundStyle(on ? Palette.lavender : Palette.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
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
