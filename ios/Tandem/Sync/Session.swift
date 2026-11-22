import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// Sign-in state and which shared household this phone belongs to.
@MainActor
@Observable
final class Session {
    enum Phase: Equatable {
        case loading
        case signedOut
        case needsHousehold(uid: String)
        case ready(uid: String, householdId: String)
    }

    private(set) var phase: Phase = .loading
    var busy = false
    var error: String?

    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var userListener: ListenerRegistration?
    @ObservationIgnored private let db = Firestore.firestore()

    init() {
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.userChanged(user)
        }
    }

    deinit {
        if let authHandle { Auth.auth().removeStateDidChangeListener(authHandle) }
        userListener?.remove()
    }

    private func userChanged(_ user: User?) {
        userListener?.remove()
        guard let user else { phase = .signedOut; return }
        let uid = user.uid
        userListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let hid = snap?.data()?["householdId"] as? String, !hid.isEmpty {
                self.phase = .ready(uid: uid, householdId: hid)
            } else if err != nil || (snap.map { !$0.metadata.isFromCache } ?? false) {
                // Only trust "no household" once the server has answered.
                self.phase = .needsHousehold(uid: uid)
            }
        }
    }

    // MARK: Account

    func signIn(email: String, password: String) async {
        await run { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    func signUp(email: String, password: String) async {
        await run { _ = try await Auth.auth().createUser(withEmail: email, password: password) }
    }

    func resetPassword(email: String) async {
        await run { try await Auth.auth().sendPasswordReset(withEmail: email) }
        if error == nil { error = "Check your inbox for a reset link." }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    // MARK: Household

    /// Starts a new shared budget. Its ID is the invite code your partner types in.
    func createHousehold(uid: String, myName: String, partnerName: String, currency: String) async {
        await run {
            let code = Session.makeCode()
            let hh = Household.new(uid: uid, nameA: myName, nameB: partnerName, currency: currency)
            let batch = self.db.batch()
            try batch.setData(from: hh, forDocument: self.db.collection("households").document(code))
            batch.setData(["householdId": code], forDocument: self.db.collection("users").document(uid))
            try await batch.commit()
        }
    }

    func joinHousehold(uid: String, code raw: String) async {
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count >= 6 else { error = "That code looks too short."; return }
        await run {
            do {
                try await self.db.collection("households").document(code).updateData([
                    "members": FieldValue.arrayUnion([uid]),
                    "memberWho.\(uid)": Who.b.rawValue,
                ])
            } catch {
                let ns = error as NSError
                let denied = ns.domain == FirestoreErrorDomain
                    && (ns.code == FirestoreErrorCode.permissionDenied.rawValue || ns.code == FirestoreErrorCode.notFound.rawValue)
                guard denied else { throw error }
                throw NSError(domain: "Twofold", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "No budget found for that code, or it already has two people."])
            }
            try await self.db.collection("users").document(uid).setData(["householdId": code])
        }
    }

    func leaveHousehold(uid: String) async {
        await run { try await self.db.collection("users").document(uid).setData(["householdId": ""]) }
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        do { try await work() } catch { self.error = error.localizedDescription }
        busy = false
    }

    /// 8 characters without look-alikes (no 0/O, 1/I/L).
    static func makeCode() -> String {
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }
}
