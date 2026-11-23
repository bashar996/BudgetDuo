import SwiftUI

/// Text field styled for the black background.
struct DarkField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var caps: TextInputAutocapitalization? = nil

    var body: some View {
        Group {
            if secure { SecureField("", text: $text, prompt: prompt) } else { TextField("", text: $text, prompt: prompt) }
        }
        .font(.geist(16, .medium))
        .keyboardType(keyboard)
        .textContentType(content)
        .textInputAutocapitalization(caps ?? (keyboard == .emailAddress ? .never : .words))
        .autocorrectionDisabled(keyboard == .emailAddress)
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(Palette.white)
    }

    private var prompt: Text { Text(placeholder).foregroundColor(Palette.mute) }
}

private struct OnboardingFrame<Content: View>: View {
    var kicker: String
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(kicker).font(.geist(14)).foregroundStyle(Palette.mute)
                    Text(title).font(.geist(40, .medium)).tracking(em: -0.035, size: 40).lineSpacing(-4)
                }
                .padding(.horizontal, 20).padding(.top, 40)
                BlobEdge(fill: Palette.lavender)
                VStack(alignment: .leading, spacing: 12) { content }
                    .padding(20).padding(.bottom, 40)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.lavender)
                    .foregroundStyle(Palette.black)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(VStack(spacing: 0) { Palette.black; Palette.lavender }.ignoresSafeArea())
        .foregroundStyle(Palette.white)
    }
}

struct AuthView: View {
    @Environment(Session.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var creating = false

    var body: some View {
        OnboardingFrame(kicker: "Twofold", title: "One budget,\ntwo of you.") {
            HStack(spacing: 6) {
                modeButton("Sign in", on: !creating) { creating = false }
                modeButton("Create account", on: creating) { creating = true }
            }
            Text(creating ? "Each of you makes an account. One of you starts the budget, the other joins it with a code."
                          : "Welcome back.")
                .font(.geist(14)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            DarkField(placeholder: "Email", text: $email, keyboard: .emailAddress, content: .emailAddress)
            DarkField(placeholder: "Password" + (creating ? " (6+ characters)" : ""), text: $password, secure: true,
                      content: creating ? .newPassword : .password)
            if let e = session.error {
                Text(e).font(.geist(13, .semibold)).foregroundStyle(Palette.black).fixedSize(horizontal: false, vertical: true)
            }
            BlockButton(title: session.busy ? "One moment…" : creating ? "Create account" : "Sign in", height: 58, radius: 20) {
                Task {
                    let e = email.trimmingCharacters(in: .whitespaces)
                    if creating { await session.signUp(email: e, password: password) }
                    else { await session.signIn(email: e, password: password) }
                }
            }
            .disabled(session.busy || email.isEmpty || password.count < 6)
            .opacity(email.isEmpty || password.count < 6 ? 0.5 : 1)
            if !creating {
                Button("Forgot password?") { Task { await session.resetPassword(email: email) } }
                    .font(.geist(14, .medium)).frame(minHeight: 44).disabled(email.isEmpty)
            }
        }
    }

    private func modeButton(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.geist(14, .medium)).padding(.horizontal, 16).frame(height: 44)
                .foregroundStyle(on ? Palette.white : Palette.black)
                .background(on ? Palette.black : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}

struct HouseholdSetupView: View {
    let uid: String
    @Environment(Session.self) private var session
    @State private var joining = false
    @State private var me = ""
    @State private var partner = ""
    @State private var currency = "AED"
    @State private var code = ""

    var body: some View {
        OnboardingFrame(kicker: "Set up", title: joining ? "Join your\npartner." : "Start your\nshared budget.") {
            HStack(spacing: 6) {
                pick("Start new", on: !joining) { joining = false }
                pick("Join with a code", on: joining) { joining = true }
            }
            if joining {
                Text("Ask your partner for the 8-character code on their Home screen or in More → Settings.")
                    .font(.geist(14)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                DarkField(placeholder: "Invite code", text: $code, caps: .characters)
            } else {
                Text("It starts empty. You’ll add accounts, pay and limits next, and your partner joins with a code.")
                    .font(.geist(14)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                DarkField(placeholder: "Your name", text: $me, content: .givenName)
                DarkField(placeholder: "Your partner’s name", text: $partner)
                Text("Currency").font(.geist(13)).foregroundStyle(Palette.ink).padding(.top, 4)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Catalog.currencies, id: \.self) { c in pick(c, on: currency == c) { currency = c } }
                    }
                }
            }
            if let e = session.error {
                Text(e).font(.geist(13, .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            BlockButton(title: session.busy ? "One moment…" : joining ? "Join budget" : "Start budget", height: 58, radius: 20) {
                Task {
                    if joining { await session.joinHousehold(uid: uid, code: code) }
                    else {
                        await session.createHousehold(uid: uid, myName: me.trimmingCharacters(in: .whitespaces),
                                                      partnerName: partner.trimmingCharacters(in: .whitespaces), currency: currency)
                    }
                }
            }
            .disabled(session.busy || !ready)
            .opacity(ready ? 1 : 0.5)
            Button("Sign out") { session.signOut() }.font(.geist(14, .medium)).frame(minHeight: 44)
        }
    }

    private var ready: Bool {
        joining ? code.count >= 6 : !me.trimmingCharacters(in: .whitespaces).isEmpty && !partner.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func pick(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.geist(14, .medium)).padding(.horizontal, 16).frame(height: 44)
                .foregroundStyle(on ? Palette.white : Palette.black)
                .background(on ? Palette.black : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.black, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
