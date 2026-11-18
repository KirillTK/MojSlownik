import Foundation
import Supabase

/// Inserts log rows into public.app_logs with the signed-in user's session (RLS: insert-only,
/// own rows). `user_id` is filled by the database default, so the client never sends it.
@MainActor
final class SupabaseLogUploader: AppLogUploading {
    static let table = "app_logs"

    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider) {
        self.provider = provider
    }

    /// The exact request body `insert` sends (PostgREST's encoder); used by contract tests.
    nonisolated static func requestBody(_ rows: [AppLogRow]) throws -> Data {
        try PostgrestClient.Configuration.jsonEncoder.encode(rows)
    }

    func upload(_ rows: [AppLogRow]) async throws {
        guard !rows.isEmpty else { return }
        do {
            try await provider.client.from(Self.table).insert(rows, returning: .minimal).execute()
        } catch {
            throw Self.classify(error)
        }
    }

    /// Maps permanent server rejections to `AppLogRejectedError` so the queue drops those rows
    /// instead of retrying forever. Auth problems stay transient: 42501/401/PGRST3xx also happen
    /// when the request went out without a session (e.g. racing sign-out), and the rows are
    /// still valid for the account. Rate limits, timeouts, 5xx and network errors stay transient.
    nonisolated static func classify(_ error: Error) -> Error {
        if let error = error as? PostgrestError, let code = error.code, isPermanent(code: code) {
            return AppLogRejectedError()
        }
        // Non-PostgREST responses (gateway, WAF, paused project) are not about our rows: retry.
        // Only "payload too large" is permanent; the queue then retries rows one by one.
        if let error = error as? HTTPError, error.response.statusCode == 413 {
            return AppLogRejectedError()
        }
        return error
    }

    /// Permanent only when the rows themselves are bad: SQLSTATE classes 22 (data) and 23
    /// (integrity: CHECK, FK, NOT NULL). Schema/request errors (42xxx, PGRST1xx/2xx) mean the
    /// server and this build disagree (migration not applied yet, cache reload): every row would
    /// be dropped, so they stay transient and the rows wait for a fix (capped queue).
    nonisolated static func isPermanent(code: String) -> Bool {
        code.hasPrefix("22") || code.hasPrefix("23")
    }
}
