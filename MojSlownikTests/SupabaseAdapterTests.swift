import AuthenticationServices
import Supabase
import XCTest
@testable import MojSlownik

/// Tests of Backend/ adapters over supabase-swift types. Like Backend/ itself, this is one of
/// the few places allowed to import Supabase (see AGENTS.md).
@MainActor
final class SupabaseAdapterTests: XCTestCase {
    private func user(provider: String = "google", email: String? = "me@example.com") -> User {
        User(id: UUID(uuidString: "00000000-0000-4000-8000-0000000000e2")!, appMetadata: ["provider": .string(provider)],
             userMetadata: [:], aud: "authenticated", email: email, createdAt: .now, updatedAt: .now)
    }

    private func session(expiresIn seconds: TimeInterval) -> Session {
        Session(accessToken: "a", tokenType: "bearer", expiresIn: seconds,
                expiresAt: Date().addingTimeInterval(seconds).timeIntervalSince1970, refreshToken: "r", user: user())
    }

    // MARK: Auth

    func testSDKProviderMapping() {
        XCTAssertEqual(SupabaseAuthBackend.sdkProvider(.apple), .apple)
        XCTAssertEqual(SupabaseAuthBackend.sdkProvider(.google), .google)
    }

    func testAccountMappingFromSDKUser() {
        XCTAssertEqual(SupabaseAuthBackend.account(from: user()),
                       AuthAccount(userID: user().id, email: "me@example.com", provider: .google))
        XCTAssertNil(SupabaseAuthBackend.account(from: user(provider: "github")).provider)
        XCTAssertNil(SupabaseAuthBackend.account(from: user(email: nil)).email)
    }

    /// Review finding: an expired stored session emitted at launch is not "signed in".
    func testExpiredInitialSessionCountsAsSignedOut() {
        XCTAssertNil(SupabaseAuthBackend.account(for: .initialSession, session: session(expiresIn: -60)))
        XCTAssertNotNil(SupabaseAuthBackend.account(for: .initialSession, session: session(expiresIn: 3_600)))
        XCTAssertNotNil(SupabaseAuthBackend.account(for: .tokenRefreshed, session: session(expiresIn: 3_600)))
        XCTAssertNotNil(SupabaseAuthBackend.account(for: .signedIn, session: session(expiresIn: 3_600)))
        XCTAssertNil(SupabaseAuthBackend.account(for: .signedOut, session: nil))
    }

    func testOnlyUserCancellationCountsAsCancellation() {
        let backend = SupabaseAuthBackend(provider: SupabaseClientProvider())
        XCTAssertTrue(backend.isCancellation(ASWebAuthenticationSessionError(.canceledLogin)))
        XCTAssertFalse(backend.isCancellation(ASWebAuthenticationSessionError(.presentationContextInvalid)))
        XCTAssertFalse(backend.isCancellation(URLError(.notConnectedToInternet)))
    }

    func testConstructingSupabaseBackendDoesNotCreateClient() {
        let provider = SupabaseClientProvider()
        _ = AuthStore(backend: SupabaseAuthBackend(provider: provider))
        _ = SupabaseLogUploader(provider: provider)
        XCTAssertFalse(provider.isClientCreated, "the client is created only when auth starts or logs upload")
    }

    // MARK: Log upload error classification (review finding)

    private func httpError(_ status: Int) -> HTTPError {
        HTTPError(data: Data(), response: HTTPURLResponse(url: URL(string: "https://x.supabase.co")!,
                                                          statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func testPermanentRejectionsAreClassifiedAsRejected() {
        for code in ["23514", "23503", "23502", "22P02", "22001"] {
            let error = SupabaseLogUploader.classify(PostgrestError(code: code, message: "x"))
            XCTAssertTrue(error is AppLogRejectedError, code)
        }
        XCTAssertTrue(SupabaseLogUploader.classify(httpError(413)) is AppLogRejectedError)
    }

    func testTransientErrorsAreRetried() {
        // 42501/PGRST3xx: the request went out without a valid session (review finding: racing
        // sign-out must not delete still-valid rows).
        // Review finding: schema/request mismatches (42xxx, PGRST1xx/2xx) would drop every row
        // until the server catches up; they are retried instead.
        for code in ["42501", "42703", "42P01", "42P10", "PGRST100", "PGRST102", "PGRST204", "PGRST205",
                     "PGRST301", "PGRST302", "PGRST000", "57014", "08006", "53300"] {
            XCTAssertFalse(SupabaseLogUploader.classify(PostgrestError(code: code, message: "x")) is AppLogRejectedError, code)
        }
        XCTAssertFalse(SupabaseLogUploader.classify(PostgrestError(message: "no code")) is AppLogRejectedError)
        // Review finding: gateway/WAF/paused-project responses are not about our rows.
        for status in [400, 401, 403, 404, 408, 409, 422, 429, 500, 503] {
            XCTAssertFalse(SupabaseLogUploader.classify(httpError(status)) is AppLogRejectedError, "\(status)")
        }
        XCTAssertFalse(SupabaseLogUploader.classify(URLError(.notConnectedToInternet)) is AppLogRejectedError)
    }

    // MARK: Sync remote

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try PostgrestClient.Configuration.jsonEncoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testWordUpsertEncodesEveryKeyWithExplicitNulls() throws {
        let word = RemoteWordUpsert(
            id: UUID(), userID: UUID(), term: "kot", termLanguage: "pl", translation: "кот",
            translationLanguage: "ru", enteredLanguage: "ru", category: "other", folderIDs: [],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil, easeFactor: 2.5,
            intervalDays: 0, repetitions: 0, dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            lastReviewGrade: nil, knowledgeTier: nil, consecutiveSoftMisses: 0)
        let object = try jsonObject(word)
        XCTAssertEqual(Set(object.keys),
                       ["id", "user_id", "term", "term_language", "translation", "translation_language",
                        "entered_language", "category", "folder_ids", "created_at", "deleted_at", "ease_factor",
                        "interval_days", "repetitions", "due_date", "last_review_grade", "knowledge_tier",
                        "consecutive_soft_misses"])
        XCTAssertFalse(object.keys.contains("updated_at"), "the server assigns updated_at")
        for key in ["deleted_at", "last_review_grade", "knowledge_tier"] {
            XCTAssertTrue(object[key] is NSNull, "\(key) must be an explicit null")
        }
        XCTAssertEqual(object["folder_ids"] as? [String], [])
        // The select list names exactly the decoded columns.
        XCTAssertEqual(Set(RemoteWordUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(object.keys).union(["updated_at"]))
    }

    func testFolderUpsertEncodesEveryKeyWithExplicitNulls() throws {
        let folder = RemoteFolderUpsert(id: UUID(), userID: UUID(), name: "Еда", sortOrder: 2,
                                        createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil)
        let object = try jsonObject(folder)
        XCTAssertEqual(Set(object.keys), ["id", "user_id", "name", "sort_order", "created_at", "deleted_at"])
        XCTAssertTrue(object["deleted_at"] is NSNull)
        XCTAssertEqual(Set(RemoteFolderUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(object.keys).union(["updated_at"]))
    }

    func testBatchWithTombstoneAndLiveRowKeepsTheSameKeys() throws {
        func row(deleted: Date?) -> RemoteFolderUpsert {
            RemoteFolderUpsert(id: UUID(), userID: UUID(), name: "x", sortOrder: 0,
                               createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: deleted)
        }
        let data = try PostgrestClient.Configuration.jsonEncoder.encode([row(deleted: nil), row(deleted: .now)])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(Set(rows[0].keys), Set(rows[1].keys))
    }

    func testKeysetFilterIsExact() {
        let id = UUID(uuidString: "8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69")!
        let cursor = SyncCursor(updatedAtMillis: 1_794_955_800_123, id: id)
        XCTAssertEqual(SupabaseSyncRemote.keysetFilter(after: cursor),
                       "updated_at.gt.\"2026-11-17T22:50:00.123Z\",and(updated_at.eq.\"2026-11-17T22:50:00.123Z\",id.gt.8c1d3a57-2e1b-4f0b-9b7a-1e2d3c4b5a69)")
    }

    func testCursorTimestampStringIsExact() throws {
        let id = UUID()
        XCTAssertEqual(SyncCursor(updatedAtMillis: 1_794_955_800_999, id: id).timestampString, "2026-11-17T22:50:00.999Z")
        XCTAssertEqual(SyncCursor(updatedAtMillis: 1_794_955_800_000, id: id).timestampString, "2026-11-17T22:50:00.000Z")
        XCTAssertEqual(SyncCursor(updatedAtMillis: 1_794_955_800_007, id: id).timestampString, "2026-11-17T22:50:00.007Z")
        // A server timestamp decoded by PostgREST's decoder round-trips to the same text.
        let json = #"[{"id":"8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69","updated_at":"2026-11-17T22:50:00.123+00:00"}]"#
        let acks = try PostgrestClient.Configuration.jsonDecoder.decode([RemoteAck].self, from: Data(json.utf8))
        XCTAssertEqual(SyncCursor(updatedAt: acks[0].updatedAt, id: acks[0].id).timestampString,
                       "2026-11-17T22:50:00.123Z")
        // The overlap moves back 60 s with the nil UUID.
        let overlapping = SyncCursor(updatedAtMillis: 1_794_955_800_123, id: id).overlapping()
        XCTAssertEqual(overlapping.updatedAtMillis, 1_794_955_740_123)
        XCTAssertEqual(overlapping.id.uuidString, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(overlapping.timestampString, "2026-11-17T22:49:00.123Z")
    }

    func testSyncClassifyMapsErrors() {
        for code in ["23514", "23503", "23502", "22P02", "22001"] {
            XCTAssertEqual(SupabaseSyncRemote.classify(PostgrestError(code: code, message: "x")) as? SyncRemoteError,
                           .rejected, code)
        }
        XCTAssertEqual(SupabaseSyncRemote.classify(httpError(413)) as? SyncRemoteError, .rejected)
        for code in ["42501", "PGRST301", "PGRST302"] {
            XCTAssertEqual(SupabaseSyncRemote.classify(PostgrestError(code: code, message: "x")) as? SyncRemoteError,
                           .unauthorized, code)
        }
        XCTAssertEqual(SupabaseSyncRemote.classify(httpError(401)) as? SyncRemoteError, .unauthorized)
        for code in ["42703", "PGRST204", "57014", "08006", "53300"] {
            XCTAssertNil(SupabaseSyncRemote.classify(PostgrestError(code: code, message: "x")) as? SyncRemoteError, code)
        }
        for status in [400, 403, 408, 429, 500, 503] {
            XCTAssertNil(SupabaseSyncRemote.classify(httpError(status)) as? SyncRemoteError, "\(status)")
        }
        XCTAssertNil(SupabaseSyncRemote.classify(URLError(.notConnectedToInternet)) as? SyncRemoteError)
    }

    func testConstructingSyncRemoteDoesNotCreateClient() {
        let provider = SupabaseClientProvider()
        _ = SupabaseSyncRemote(provider: provider)
        XCTAssertFalse(provider.isClientCreated)
    }
}
