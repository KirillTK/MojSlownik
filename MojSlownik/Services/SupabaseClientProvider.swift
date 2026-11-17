import Foundation
import Supabase

/// Lazily creates the app's single SupabaseClient. Nothing calls it yet: local SwiftData stays the
/// source of truth (offline-first). Constructing the provider performs no I/O.
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
        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
        cachedClient = client
        return client
    }
}
