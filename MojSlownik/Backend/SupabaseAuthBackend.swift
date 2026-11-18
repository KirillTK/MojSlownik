import AuthenticationServices
import Foundation
import Supabase

/// Thin adapter over supabase-swift's native auth API; no custom token handling.
/// - `signInWithOAuth` runs the provider's web sign-in in ASWebAuthenticationSession with PKCE
///   (no app entitlement needed, so it works with a free Personal Team).
/// - The SDK stores the session in the Keychain and refreshes tokens itself.
/// - `authStateChanges` is the single source of the signed-in account.
@MainActor
final class SupabaseAuthBackend: AuthBackend {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider) {
        self.provider = provider
    }

    func accountUpdates() -> AsyncStream<AuthAccount?> {
        let changes = provider.client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await (event, session) in changes {
                    continuation.yield(Self.account(for: event, session: session))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signIn(with provider: AuthProvider) async throws {
        try await self.provider.client.auth.signInWithOAuth(provider: Self.sdkProvider(provider))
    }

    /// `.local`: signs out this device only (revokes this session), never the user's other devices.
    func signOut() async throws {
        try await provider.client.auth.signOut(scope: .local)
    }

    func isCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }

    nonisolated static func sdkProvider(_ provider: AuthProvider) -> Provider {
        switch provider {
        case .apple: .apple
        case .google: .google
        }
    }

    /// With `emitLocalSessionAsInitialSession` the stored session is emitted even when expired;
    /// the SDK requires checking `isExpired`. An expired one counts as signed out until the SDK
    /// emits `tokenRefreshed`/`signedIn` with a valid session.
    nonisolated static func account(for event: AuthChangeEvent, session: Session?) -> AuthAccount? {
        guard let session else { return nil }
        if event == .initialSession, session.isExpired { return nil }
        return account(from: session.user)
    }

    nonisolated static func account(from user: User) -> AuthAccount {
        AuthAccount(userID: user.id, email: user.email,
                    provider: user.appMetadata["provider"]?.stringValue.flatMap(AuthProvider.init(rawValue:)))
    }
}
