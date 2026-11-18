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
}
