import Foundation
import Observation

/// Account state for views. Signing in is optional: the dictionary works fully offline and
/// stays local; an account is used for diagnostics upload now and for sync later.
@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(AuthAccount)

        /// A sign-in just completed (signed out → signed in). Restoring a session at launch
        /// (unknown → signed in) and token refreshes do not count.
        func completesSignIn(from previous: State) -> Bool {
            guard case .signedOut = previous, case .signedIn = self else { return false }
            return true
        }
    }

    private(set) var state: State = .unknown
    /// The provider whose sign-in sheet is in progress, if any.
    private(set) var pendingProvider: AuthProvider?
    private(set) var isSigningOut = false
    /// Calm Russian message for the account screen; never contains server/error text.
    private(set) var errorMessage: String?

    @ObservationIgnored private let backend: any AuthBackend
    @ObservationIgnored private let logger: any AppLogging
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let signOutFlushTimeout: Duration
    /// Called when the account changes (sign-in, sign-out, restored session), never for a token
    /// refresh of the same account.
    @ObservationIgnored var onAccountChange: ((AuthAccount?) -> Void)?
    /// Runs while the session still exists, next to the log flush, within the same time bound.
    @ObservationIgnored var beforeSignOut: (@MainActor () async -> Void)?

    init(backend: any AuthBackend, logger: (any AppLogging)? = nil,
         signOutFlushTimeout: Duration = .seconds(3)) {
        self.backend = backend
        self.logger = logger ?? NoopAppLogger()
        self.signOutFlushTimeout = signOutFlushTimeout
    }

    var account: AuthAccount? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    var isSignedIn: Bool { account != nil }
    var isBusy: Bool { pendingProvider != nil || isSigningOut }

    /// Starts following the backend's session. Idempotent.
    func start() {
        guard observation == nil else { return }
        let updates = backend.accountUpdates()
        observation = Task { [weak self] in
            for await account in updates {
                guard let self else { return }
                let wasSignedIn = self.isSignedIn
                let newState = account.map(State.signedIn) ?? .signedOut
                // Token refreshes repeat the same account: no write, so no view invalidation.
                guard newState != self.state else { continue }
                self.errorMessage = nil
                self.state = newState
                self.onAccountChange?(account)
                if self.isSignedIn, !wasSignedIn {
                    // Never block session updates on the network.
                    Task { await self.logger.flush() }
                }
            }
        }
    }

    func signIn(with provider: AuthProvider) async {
        guard !isBusy else { return }
        errorMessage = nil
        pendingProvider = provider
        defer { pendingProvider = nil }
        do {
            try await backend.signIn(with: provider)
            logger.log(.authSignedIn, [.provider: .name(provider)])
        } catch where backend.isCancellation(error) {
            logger.log(.authSignInCancelled, [.provider: .name(provider)])
        } catch {
            errorMessage = "Не удалось войти. Попробуйте ещё раз."
            logger.log(.authFailed, error: error, [.provider: .name(provider), .operation: .name("sign_in")])
        }
    }

    func signOut() async {
        guard !isBusy else { return }
        errorMessage = nil
        isSigningOut = true
        defer { isSigningOut = false }
        // Logged while the account is still current, so it is attributed to it, and uploaded
        // while the session still exists. Sign-out waits at most `signOutFlushTimeout`; rows
        // that did not make it stay queued for this account.
        logger.log(.authSignedOut)
        await flushBounded()
        do {
            try await backend.signOut()
        } catch {
            // The SDK removes the local session before calling the server, so the user is
            // signed out here; only the server-side revocation failed. Nothing to retry.
            logger.log(.authFailed, error: error, [.operation: .name("sign_out")])
        }
    }

    /// Waits until the log flush and `beforeSignOut` (the final sync) both finish, or the
    /// timeout fires, then cancels what is left. The queue's flush stops on cancellation (rows
    /// stay queued for this account).
    private func flushBounded() async {
        let before = beforeSignOut
        await withTaskGroup(of: Bool.self) { group in
            var pending = 1
            group.addTask { @MainActor in
                await self.logger.flush()
                return true
            }
            if let before {
                pending += 1
                group.addTask { @MainActor in
                    await before()
                    return true
                }
            }
            group.addTask { [signOutFlushTimeout] in
                try? await Task.sleep(for: signOutFlushTimeout)
                return false
            }
            while pending > 0, let finishedWork = await group.next() {
                guard finishedWork else { break }
                pending -= 1
            }
            group.cancelAll()
        }
    }

    /// Clears a shown error (e.g. when the account sheet closes) so it never resurfaces later.
    func dismissError() {
        errorMessage = nil
    }
}
