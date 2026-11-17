import Foundation

/// Supabase project endpoint and client key. Only publishable keys belong in the app:
/// secret (`sb_secret_…`) and service-role keys must never be added here.
struct SupabaseConfiguration: Equatable, Sendable {
    static let publishableKeyPrefix = "sb_publishable_"

    let url: URL
    let publishableKey: String

    enum ValidationError: Error, Equatable {
        case invalidURL
        case invalidKey
    }

    /// Requires an https URL with a host and a key in the `sb_publishable_…` format.
    init(urlString: String, publishableKey: String) throws {
        guard let url = URL(string: urlString),
              url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty else {
            throw ValidationError.invalidURL
        }
        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix(Self.publishableKeyPrefix),
              key.count > Self.publishableKeyPrefix.count else {
            throw ValidationError.invalidKey
        }
        self.url = url
        self.publishableKey = key
    }

    /// Project "bjwptrfbtcmxlhjaxiip". The publishable key is public by design (RLS protects data).
    static let production: SupabaseConfiguration = {
        do {
            return try SupabaseConfiguration(urlString: "https://bjwptrfbtcmxlhjaxiip.supabase.co",
                                             publishableKey: "sb_publishable_5gYMyVsuL5k5UHxIrWWiTA__Bf6BbMe")
        } catch {
            preconditionFailure("Invalid Supabase configuration: \(error)")
        }
    }()
}
