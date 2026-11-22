import Foundation

enum AuthProvider: String, CaseIterable, Sendable {
    case apple, google
}

struct AuthAccount: Equatable, Sendable {
    let userID: UUID
    let email: String?
    let provider: AuthProvider?
}

/// One step of the session stream.
enum AuthUpdate: Equatable, Sendable {
    /// The account (nil = signed out).
    case account(AuthAccount?)
    /// A stored session exists but is expired and being refreshed: the state stays unknown until
    /// the SDK emits the refreshed session (or the store's restore timeout fires).
    case restoring
}

/// Sign-in backend. The real one (Backend/SupabaseAuthBackend.swift) is a thin adapter over
/// supabase-swift's native auth API; the static one serves previews and UI tests.
@MainActor
protocol AuthBackend: AnyObject {
    /// The current account first, then every change (sign-in, sign-out, token refresh).
    func accountUpdates() -> AsyncStream<AuthUpdate>
    func signIn(with provider: AuthProvider) async throws
    func signOut() async throws
    /// True when the user closed the sign-in sheet; not an error worth showing.
    func isCancellation(_ error: Error) -> Bool
}

/// In-memory backend without network: previews and DEBUG UI tests.
@MainActor
final class StaticAuthBackend: AuthBackend {
    static let testAccount = AuthAccount(userID: UUID(uuidString: "00000000-0000-4000-8000-0000000000e1")!,
                                         email: "tester@example.com", provider: .google)

    struct SignInFailure: Error {}

    private var account: AuthAccount?
    private let failsSignIn: Bool
    private var continuations: [UUID: AsyncStream<AuthUpdate>.Continuation] = [:]

    init(account: AuthAccount? = nil, failsSignIn: Bool = false) {
        self.account = account
        self.failsSignIn = failsSignIn
    }

    func accountUpdates() -> AsyncStream<AuthUpdate> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(.account(account))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations[id] = nil }
            }
        }
    }

    func signIn(with provider: AuthProvider) async throws {
        if failsSignIn { throw SignInFailure() }
        publish(AuthAccount(userID: Self.testAccount.userID, email: Self.testAccount.email, provider: provider))
    }

    func signOut() async throws {
        publish(nil)
    }

    func isCancellation(_ error: Error) -> Bool { false }

    private func publish(_ account: AuthAccount?) {
        self.account = account
        for continuation in continuations.values { continuation.yield(.account(account)) }
    }
}
