import SwiftUI
import FirebaseCore

@main
struct TwofoldApp: App {
    @State private var session: Session

    init() {
        // Needs GoogleService-Info.plist in Twofold/Resources (see ios/README.md).
        FirebaseApp.configure()
        _session = State(initialValue: Session())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Palette.lavender)
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                Splash()
            case .signedOut:
                AuthView()
            case .needsHousehold(let uid):
                HouseholdSetupView(uid: uid)
            case .ready(let uid, let hid):
                HouseholdHost(uid: uid, householdId: hid).id(uid + hid)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
    }
}

struct Splash: View {
    var body: some View {
        ZStack {
            Palette.black.ignoresSafeArea()
            Text("Twofold").font(.geist(34, .medium)).tracking(em: -0.03, size: 34).foregroundStyle(Palette.lavender)
        }
    }
}

/// Owns the live store for the household this phone is signed in to.
@MainActor
struct HouseholdHost: View {
    @State private var store: HouseholdStore
    @State private var router = Router()

    init(uid: String, householdId: String) {
        _store = State(initialValue: HouseholdStore(uid: uid, householdId: householdId))
    }

    var body: some View {
        Group {
            if store.household != nil {
                MainView()
            } else if store.missing {
                MissingHousehold()
            } else {
                Splash()
            }
        }
        .environment(store)
        .environment(router)
    }
}

private struct MissingHousehold: View {
    @Environment(Session.self) private var session
    @Environment(HouseholdStore.self) private var store
    var body: some View {
        ZStack {
            Palette.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("We couldn’t open your shared budget.").font(.geist(20, .medium)).multilineTextAlignment(.center)
                if let e = store.error { Text(e).font(.geist(13)).foregroundStyle(Palette.mute).multilineTextAlignment(.center) }
                BlockButton(title: "Start or join another", fill: Palette.lavender, text: Palette.black) {
                    Task { await session.leaveHousehold(uid: store.uid) }
                }
                BlockButton(title: "Sign out", fill: Palette.white, outline: true) { session.signOut() }
            }
            .padding(24)
            .foregroundStyle(Palette.white)
        }
    }
}
