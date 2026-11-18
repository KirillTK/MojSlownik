import XCTest
@testable import MojSlownik

/// Scriptable backend for failure and cancellation paths.
@MainActor
private final class ScriptedAuthBackend: AuthBackend {
    struct Cancelled: Error {}
    struct Failed: LocalizedError { var errorDescription: String? { "server said: user@example.com" } }

    var signInError: Error?
    var signOutError: Error?
    private(set) var signInCalls: [AuthProvider] = []
    private(set) var signOutCalls = 0
    var signInGate: CheckedContinuation<Void, Never>?
    var onSignOut: (() -> Void)?
    var holdSignIn = false
    private var continuation: AsyncStream<AuthAccount?>.Continuation?
    private let initial: AuthAccount?

    init(initial: AuthAccount? = nil) { self.initial = initial }

    func accountUpdates() -> AsyncStream<AuthAccount?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(initial)
        }
    }

    func signIn(with provider: AuthProvider) async throws {
        signInCalls.append(provider)
        if holdSignIn { await withCheckedContinuation { signInGate = $0 } }
        if let signInError { throw signInError }
        continuation?.yield(AuthAccount(userID: UUID(), email: "a@b.c", provider: provider))
    }

    func signOut() async throws {
        signOutCalls += 1
        onSignOut?()
        if let signOutError { throw signOutError }
        continuation?.yield(nil)
    }

    func isCancellation(_ error: Error) -> Bool { error is Cancelled }

    func emit(_ account: AuthAccount?) { continuation?.yield(account) }
}

/// A logger whose uploads hang until released.
@MainActor
private final class GatedFlushLogger: AppLogging {
    private(set) var flushesStarted = 0
    private(set) var flushesFinished = 0
    private(set) var flushesCancelled = 0
    private var gates: [UUID: CheckedContinuation<Void, Never>] = [:]

    func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue]) {}

    /// Hangs until released, or until cancelled (like AppLogQueue.flush).
    func flush() async {
        flushesStarted += 1
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { gates[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.resume(id) }
        }
        if Task.isCancelled { flushesCancelled += 1 } else { flushesFinished += 1 }
    }

    private func resume(_ id: UUID) {
        gates.removeValue(forKey: id)?.resume()
    }

    func release() {
        gates.values.forEach { $0.resume() }
        gates.removeAll()
    }
}

@MainActor
final class AuthStoreTests: XCTestCase {
    private let account = AuthAccount(userID: UUID(), email: "me@example.com", provider: .apple)

    /// Polls until `condition` holds (fails after `timeout`). A fixed number of `Task.yield()`s
    /// was not enough for the session stream on a loaded CI runner (flaked on CI).
    private func waitUntil(_ what: String, timeout: Duration = .seconds(5),
                           file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return XCTFail("timed out waiting for \(what)", file: file, line: line)
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Only a fresh sign-in closes the account sheet; a restored session or refresh does not.
    func testCompletesSignInOnlyFromSignedOut() {
        let signedIn = AuthStore.State.signedIn(account)
        XCTAssertTrue(signedIn.completesSignIn(from: .signedOut))
        XCTAssertFalse(signedIn.completesSignIn(from: .unknown), "session restored at launch")
        XCTAssertFalse(signedIn.completesSignIn(from: signedIn), "token refresh")
        XCTAssertFalse(AuthStore.State.signedOut.completesSignIn(from: signedIn))
        XCTAssertFalse(AuthStore.State.signedOut.completesSignIn(from: .unknown))
    }

    func testStartsUnknownThenFollowsSession() async {
        let store = AuthStore(backend: StaticAuthBackend())
        XCTAssertEqual(store.state, .unknown)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        XCTAssertEqual(store.state, .signedOut)

        let signedIn = AuthStore(backend: StaticAuthBackend(account: account))
        signedIn.start()
        await waitUntil("session") { signedIn.state != .unknown }
        XCTAssertEqual(signedIn.state, .signedIn(account))
        XCTAssertTrue(signedIn.isSignedIn)
    }

    func testStartIsIdempotent() async {
        let backend = ScriptedAuthBackend()
        let store = AuthStore(backend: backend)
        store.start()
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .google)
        await waitUntil("signed in") { store.isSignedIn }
        XCTAssertEqual(store.account?.provider, .google)
    }

    func testSignInSuccessUpdatesStateLogsAndFlushes() async {
        let spy = AppLogSpy()
        let store = AuthStore(backend: StaticAuthBackend(), logger: spy)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .google)
        await waitUntil("signed in") { store.isSignedIn }
        XCTAssertEqual(store.account?.provider, .google)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(store.pendingProvider)
        XCTAssertEqual(spy.events, [.authSignedIn])
        XCTAssertEqual(spy.entries[0].properties[.provider], .name("google"))
        XCTAssertEqual(spy.flushCount, 1, "pending logs go out right after sign-in")
    }

    func testCancelledSignInIsQuiet() async {
        let backend = ScriptedAuthBackend()
        backend.signInError = ScriptedAuthBackend.Cancelled()
        let spy = AppLogSpy()
        let store = AuthStore(backend: backend, logger: spy)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .apple)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(spy.events, [.authSignInCancelled])
    }

    func testFailedSignInShowsCalmMessageAndLogsCodeOnly() async {
        let backend = ScriptedAuthBackend()
        backend.signInError = ScriptedAuthBackend.Failed()
        let spy = AppLogSpy()
        let store = AuthStore(backend: backend, logger: spy)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .google)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(store.errorMessage, "Не удалось войти. Попробуйте ещё раз.")
        XCTAssertEqual(spy.events, [.authFailed])
        XCTAssertEqual(spy.entries[0].level, .error)
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("@") || $0.contains("server") })
    }

    func testRetryClearsPreviousError() async {
        let backend = ScriptedAuthBackend()
        backend.signInError = ScriptedAuthBackend.Failed()
        let store = AuthStore(backend: backend)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .google)
        backend.signInError = nil
        await store.signIn(with: .google)
        await waitUntil("signed in") { store.isSignedIn }
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.isSignedIn)
    }

    func testSecondSignInWhileBusyIsIgnored() async {
        let backend = ScriptedAuthBackend()
        backend.holdSignIn = true
        let store = AuthStore(backend: backend)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        let first = Task { await store.signIn(with: .apple) }
        await waitUntil("sign-in pending") { store.pendingProvider != nil }
        XCTAssertEqual(store.pendingProvider, .apple)
        XCTAssertTrue(store.isBusy)
        await store.signIn(with: .google)
        await store.signOut()
        XCTAssertEqual(backend.signInCalls, [.apple])
        XCTAssertEqual(backend.signOutCalls, 0)
        backend.signInGate?.resume()
        await first.value
        XCTAssertNil(store.pendingProvider)
    }

    func testSignOutFlushesFirstThenSignsOut() async {
        let spy = AppLogSpy()
        let store = AuthStore(backend: StaticAuthBackend(account: account), logger: spy)
        store.start()
        await waitUntil("launch flush") { spy.flushCount >= 1 }
        XCTAssertEqual(spy.flushCount, 1, "an existing session at launch uploads pending logs")
        await store.signOut()
        await waitUntil("signed out") { store.state == .signedOut }
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(spy.flushCount, 2, "sign-out uploads while the session still exists")
        XCTAssertEqual(spy.events, [.authSignedOut])
    }

    /// Review finding: the SDK clears the local session before the server call, so a failed
    /// server logout is not shown to the user (they are signed out) and only logged.
    func testServerSignOutFailureIsLoggedNotShown() async {
        let backend = ScriptedAuthBackend(initial: account)
        backend.signOutError = ScriptedAuthBackend.Failed()
        let spy = AppLogSpy()
        let store = AuthStore(backend: backend, logger: spy)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signOut()
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSigningOut)
        XCTAssertEqual(spy.events, [.authSignedOut, .authFailed])
        XCTAssertEqual(spy.entries[1].properties[.operation], .name("sign_out"))
    }

    /// Review finding: an old error must not resurface after closing the sheet or a state change.
    func testErrorIsClearedOnDismissAndOnStateChange() async {
        let backend = ScriptedAuthBackend()
        backend.signInError = ScriptedAuthBackend.Failed()
        let store = AuthStore(backend: backend)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        await store.signIn(with: .google)
        XCTAssertNotNil(store.errorMessage)
        store.dismissError()
        XCTAssertNil(store.errorMessage)

        await store.signIn(with: .google)
        XCTAssertNotNil(store.errorMessage)
        backend.signInError = nil
        backend.emit(account)
        await waitUntil("signed in") { store.isSignedIn }
        XCTAssertTrue(store.isSignedIn)
        XCTAssertNil(store.errorMessage, "a session arriving later clears the stale failure")
    }

    /// Review finding: sign-out and session updates must not wait for a log upload.
    func testSignOutWaitsForAHangingUploadOnlyUntilTimeout() async {
        let logger = GatedFlushLogger()
        let store = AuthStore(backend: StaticAuthBackend(account: account), logger: logger,
                              signOutFlushTimeout: .milliseconds(50))
        store.start()
        await waitUntil("session") { store.state != .unknown }
        XCTAssertTrue(store.isSignedIn, "the session update was not blocked by the hanging flush")
        await store.signOut()
        await waitUntil("signed out") { store.state == .signedOut }
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertGreaterThanOrEqual(logger.flushesStarted, 2)
        XCTAssertEqual(logger.flushesFinished, 0, "uploads were still in flight")
        XCTAssertEqual(logger.flushesCancelled, 1, "sign-out cancelled its own flush after the timeout")
        logger.release()
    }

    /// Review finding: with the real queue, sign-in's uncancelled flush was still uploading, and
    /// sign-out's flush waited for it past the timeout (cancellation did not reach the wait).
    func testSignOutIsNotHeldByAnotherRunningFlush() async throws {
        let uploader = HangingUploader()
        let queue = AppLogQueue(fileURL: nil, persistDelay: .seconds(60))
        queue.uploader = uploader
        let backend = ScriptedAuthBackend(initial: account)
        let store = AuthStore(backend: backend, logger: queue, signOutFlushTimeout: .milliseconds(50))
        queue.currentAccountID = { [weak store] in store?.account?.userID }
        queue.log(.appLaunched)
        store.start()
        for _ in 0..<100 where uploader.uploads == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(uploader.uploads, 1, "sign-in started a flush that is now stuck")

        let started = ContinuousClock.now
        await store.signOut()
        XCTAssertLessThan(ContinuousClock.now - started, .seconds(2), "bounded by the 50 ms timeout")
        XCTAssertEqual(backend.signOutCalls, 1)
        XCTAssertEqual(uploader.uploads, 1, "sign-out did not start a second upload meanwhile")
        uploader.release()
    }

    /// Review finding: a quick upload finishes before the SDK removes the session, so the
    /// sign-out row goes out under the account instead of being stranded.
    func testSignOutUploadsBeforeRemovingSession() async {
        let backend = ScriptedAuthBackend(initial: account)
        let spy = AppLogSpy()
        let store = AuthStore(backend: backend, logger: spy)
        store.start()
        await waitUntil("launch flush") { spy.flushCount >= 1 }
        let flushesBefore = spy.flushCount
        var flushesAtSignOut = -1
        backend.onSignOut = { flushesAtSignOut = spy.flushCount }
        await store.signOut()
        XCTAssertEqual(flushesAtSignOut, flushesBefore + 1)
    }

    /// Review finding: the sign-out event is logged while the account is still current.
    func testSignOutEventIsLoggedBeforeBackendSignOut() async {
        let backend = ScriptedAuthBackend(initial: account)
        let spy = AppLogSpy()
        let store = AuthStore(backend: backend, logger: spy)
        store.start()
        await waitUntil("session") { store.state != .unknown }
        var eventsAtSignOut: [LogEvent] = []
        backend.onSignOut = { eventsAtSignOut = spy.events }
        await store.signOut()
        XCTAssertEqual(eventsAtSignOut, [.authSignedOut])
    }

    // MARK: UI-test configuration

    func testUITestAuthStateParsing() throws {
        XCTAssertEqual(try UITestLaunchConfiguration.parse(["UITEST_AUTH": "signedIn"])?.auth, .signedIn)
        XCTAssertEqual(try UITestLaunchConfiguration.parse(["UITEST_AUTH": "signedIn"])?.fixture, .empty)
        XCTAssertEqual(try UITestLaunchConfiguration.parse(["UITEST_FIXTURE": "empty"])?.auth, .signedOut)
        XCTAssertThrowsError(try UITestLaunchConfiguration.parse(["UITEST_AUTH": "admin"])) { error in
            XCTAssertEqual(error as? UITestLaunchConfiguration.ParseError, .unknownAuthState("admin"))
        }
    }

    func testUITestBackendsMatchStates() async {
        let failing = AuthStore(backend: UITestAuthState.failing.makeBackend())
        failing.start()
        await waitUntil("session") { failing.state != .unknown }
        await failing.signIn(with: .apple)
        XCTAssertNotNil(failing.errorMessage)

        let signedIn = AuthStore(backend: UITestAuthState.signedIn.makeBackend())
        signedIn.start()
        await waitUntil("session") { signedIn.state != .unknown }
        XCTAssertEqual(signedIn.account, StaticAuthBackend.testAccount)
    }
}
