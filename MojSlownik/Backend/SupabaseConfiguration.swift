import Foundation

/// Supabase project endpoint and client key. Only publishable keys belong in the app:
/// secret (`sb_secret_…`) and service-role keys must never be added here.
struct SupabaseConfiguration: Equatable, Sendable {
    static let publishableKeyPrefix = "sb_publishable_"

    let url: URL
    let publishableKey: String
    /// OAuth callback captured by ASWebAuthenticationSession (PKCE). It must be listed in
    /// Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
    let authRedirectURL: URL

    enum ValidationError: Error, Equatable {
        case invalidURL
        case invalidKey
        case invalidRedirectURL
    }

    /// Requires an https URL with a host, a key in the `sb_publishable_…` format and a
    /// reverse-DNS custom-scheme redirect (never http/https, so it cannot be a web page).
    init(urlString: String, publishableKey: String, authRedirectURLString: String) throws {
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
        guard let redirect = URL(string: authRedirectURLString), let scheme = redirect.scheme?.lowercased(),
              scheme.contains("."), scheme != "http", scheme != "https",
              let redirectHost = redirect.host(percentEncoded: false), !redirectHost.isEmpty else {
            throw ValidationError.invalidRedirectURL
        }
        self.url = url
        self.publishableKey = key
        self.authRedirectURL = redirect
    }

    /// Project "bjwptrfbtcmxlhjaxiip". The publishable key is public by design (RLS protects data).
    static let production: SupabaseConfiguration = {
        do {
            return try SupabaseConfiguration(urlString: "https://bjwptrfbtcmxlhjaxiip.supabase.co",
                                             publishableKey: "sb_publishable_5gYMyVsuL5k5UHxIrWWiTA__Bf6BbMe",
                                             authRedirectURLString: "com.kirill.personal.mojslownik://auth-callback")
        } catch {
            preconditionFailure("Invalid Supabase configuration: \(error)")
        }
    }()
}
