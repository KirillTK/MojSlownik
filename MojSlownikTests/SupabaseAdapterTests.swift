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

    /// An expired stored session emitted at launch is `.restoring`: neither signed in nor signed out.
    func testExpiredInitialSessionIsRestoring() {
        XCTAssertEqual(SupabaseAuthBackend.update(for: .initialSession, session: session(expiresIn: -60)), .restoring)
        guard case .account(let valid) = SupabaseAuthBackend.update(for: .initialSession,
                                                                    session: session(expiresIn: 3_600)) else {
            return XCTFail("a valid initial session is an account")
        }
        XCTAssertNotNil(valid)
        for event in [AuthChangeEvent.tokenRefreshed, .signedIn] {
            guard case .account(let account) = SupabaseAuthBackend.update(for: event, session: session(expiresIn: 3_600)) else {
                return XCTFail("a valid session is an account")
            }
            XCTAssertNotNil(account)
        }
        XCTAssertEqual(SupabaseAuthBackend.update(for: .initialSession, session: nil), .account(nil))
        XCTAssertEqual(SupabaseAuthBackend.update(for: .signedOut, session: nil), .account(nil))
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
            id: UUID(), userID: UUID(), workspaceID: WorkspaceID.legacy, term: "kot", translation: "кот",
            enteredSide: "translation", category: "other",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil, easeFactor: 2.5,
            intervalDays: 0, repetitions: 0, dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            lastReviewGrade: nil, knowledgeTier: nil, consecutiveSoftMisses: 0, lapseCount: 3)
        let object = try jsonObject(word)
        XCTAssertEqual(object["lapse_count"] as? Int, 3)
        XCTAssertEqual(Set(object.keys),
                       ["id", "user_id", "workspace_id", "term", "translation", "entered_side", "category",
                        "created_at", "deleted_at", "ease_factor", "interval_days", "repetitions", "due_date",
                        "last_review_grade", "knowledge_tier", "consecutive_soft_misses", "lapse_count",
                        "fsrs_state", "fsrs_stability", "fsrs_difficulty", "fsrs_learning_step",
                        "fsrs_last_review"])
        for legacy in ["term_language", "translation_language", "entered_language", "folder_ids"] {
            XCTAssertFalse(object.keys.contains(legacy), "\(legacy) no longer exists on the server")
        }
        XCTAssertFalse(object.keys.contains("updated_at"), "the server assigns updated_at")
        for key in ["deleted_at", "last_review_grade", "knowledge_tier", "fsrs_state", "fsrs_stability",
                    "fsrs_difficulty", "fsrs_last_review"] {
            XCTAssertTrue(object[key] is NSNull, "\(key) must be an explicit null")
        }
        // The select list names exactly the decoded columns.
        XCTAssertEqual(Set(RemoteWordUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(object.keys).union(["updated_at"]))
    }

    func testFolderUpsertEncodesEveryKeyWithExplicitNulls() throws {
        let folder = RemoteFolderUpsert(id: UUID(), userID: UUID(), workspaceID: WorkspaceID.legacy, name: "Еда", sortOrder: 2,
                                        createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil)
        let object = try jsonObject(folder)
        XCTAssertEqual(Set(object.keys), ["id", "user_id", "workspace_id", "name", "sort_order", "created_at", "deleted_at"])
        XCTAssertTrue(object["deleted_at"] is NSNull)
        XCTAssertEqual(Set(RemoteFolderUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(object.keys).union(["updated_at"]))
    }

    func testBatchWithTombstoneAndLiveRowKeepsTheSameKeys() throws {
        func row(deleted: Date?) -> RemoteFolderUpsert {
            RemoteFolderUpsert(id: UUID(), userID: UUID(), workspaceID: WorkspaceID.legacy, name: "x", sortOrder: 0,
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

    func testMembershipKeysetFilterIsExact() {
        let word = UUID(uuidString: "8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69")!
        let folder = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let cursor = SyncCursor(updatedAtMillis: 1_794_955_800_123, id: word, secondaryID: folder)
        XCTAssertEqual(
            SupabaseSyncRemote.membershipKeysetFilter(after: cursor),
            "updated_at.gt.\"2026-11-17T22:50:00.123Z\","
                + "and(updated_at.eq.\"2026-11-17T22:50:00.123Z\",word_id.gt.8c1d3a57-2e1b-4f0b-9b7a-1e2d3c4b5a69),"
                + "and(updated_at.eq.\"2026-11-17T22:50:00.123Z\",word_id.eq.8c1d3a57-2e1b-4f0b-9b7a-1e2d3c4b5a69,"
                + "folder_id.gt.11111111-2222-4333-8444-555555555555)")
    }

    func testV2TablesAndSelectColumns() throws {
        XCTAssertEqual(SupabaseSyncRemote.workspacesTable, "workspaces")
        XCTAssertEqual(SupabaseSyncRemote.membershipsTable, "word_folders")
        let membership = RemoteMembershipUpsert(userID: UUID(), workspaceID: WorkspaceID.legacy, wordID: UUID(),
                                                folderID: UUID(),
                                                createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil)
        let object = try jsonObject(membership)
        XCTAssertEqual(Set(object.keys), ["user_id", "workspace_id", "word_id", "folder_id", "created_at", "deleted_at"])
        XCTAssertTrue(object["deleted_at"] is NSNull)
        XCTAssertEqual(Set(RemoteMembershipUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(object.keys).union(["updated_at"]))
        let workspace = RemoteWorkspaceUpsert(id: WorkspaceID.legacy, userID: UUID(), termLanguage: "pl",
                                              translationLanguage: "ru", sortOrder: 0,
                                              createdAt: Date(timeIntervalSince1970: 1_800_000_000), deletedAt: nil)
        let workspaceObject = try jsonObject(workspace)
        XCTAssertEqual(Set(workspaceObject.keys), ["id", "user_id", "term_language", "translation_language",
                                                   "sort_order", "created_at", "deleted_at"])
        XCTAssertEqual(Set(RemoteWorkspaceUpsert.selectColumns.split(separator: ",").map(String.init)),
                       Set(workspaceObject.keys).union(["updated_at"]))
    }

    func testDecodesV2RowsWithPostgRESTsDecoder() throws {
        let owner = UUID().uuidString.lowercased()
        let workspaces = try RemoteRecordDecoder.workspaces(from: Data("""
            [{"id":"0db61f29-e285-5e06-84f5-d85acfa1b5cc","user_id":"\(owner)","term_language":"pl",
              "translation_language":"ru","sort_order":0,"created_at":"2026-11-17T22:49:18.123456+00:00",
              "updated_at":"2026-11-17T22:50:00+00:00","deleted_at":null}]
            """.utf8))
        XCTAssertEqual(workspaces.first?.termLanguage, "pl")
        XCTAssertNil(workspaces.first?.deletedAt)
        let memberships = try RemoteRecordDecoder.memberships(from: Data("""
            [{"user_id":"\(owner)","workspace_id":"0db61f29-e285-5e06-84f5-d85acfa1b5cc",
              "word_id":"8c1d3a57-2e1b-4f0b-9b7a-1e2d3c4b5a69","folder_id":"11111111-2222-4333-8444-555555555555",
              "created_at":"2026-11-17T22:49:18+00:00","updated_at":"2026-11-17T22:50:00.5+00:00",
              "deleted_at":"2026-11-17T23:00:00+00:00"}]
            """.utf8))
        XCTAssertEqual(memberships.first?.workspaceID, WorkspaceID.legacy)
        XCTAssertNotNil(memberships.first?.deletedAt)
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
