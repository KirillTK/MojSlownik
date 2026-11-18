import Foundation
import Supabase

/// Lazily creates the app's single SupabaseClient, first used by auth (SupabaseAuthBackend) and
/// log upload (SupabaseLogUploader). Words are not synced: local SwiftData stays the source of
/// truth (offline-first). Constructing the provider performs no I/O.
@MainActor
final class SupabaseClientProvider {
    let configuration: SupabaseConfiguration
    private var cachedClient: SupabaseClient?

    init(configuration: SupabaseConfiguration = .production) {
        self.configuration = configuration
    }

    var isClientCreated: Bool { cachedClient != nil }

    var client: SupabaseClient {
        if let cachedClient { return cachedClient }
        let client = SupabaseClient(supabaseURL: configuration.url,
                                    supabaseKey: configuration.publishableKey,
                                    options: Self.clientOptions(for: configuration))
        cachedClient = client
        return client
    }

    /// SDK defaults otherwise: PKCE flow, Keychain session storage, automatic token refresh.
    /// No SDK logger in any build: SDK logs can carry access/refresh tokens and session data.
    /// `emitLocalSessionAsInitialSession` avoids the SDK's initial-session runtime issue.
    static func clientOptions(for configuration: SupabaseConfiguration) -> SupabaseClientOptions {
        SupabaseClientOptions(auth: .init(redirectToURL: configuration.authRedirectURL,
                                          emitLocalSessionAsInitialSession: true),
                              global: .init(logger: nil))
    }
}
