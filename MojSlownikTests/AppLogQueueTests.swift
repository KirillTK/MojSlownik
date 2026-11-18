import XCTest
@testable import MojSlownik

@MainActor
private final class UploaderSpy: AppLogUploading {
    private(set) var batches: [[AppLogRow]] = []
    private(set) var attempts = 0
    var alwaysFailTransiently = false
    var transientFailuresLeft = 0
    /// Rows with this event are rejected permanently by the "server".
    var rejectedEvent: LogEvent?
    var onUpload: (() -> Void)?

    struct Transient: Error {}

    func upload(_ rows: [AppLogRow]) async throws {
        attempts += 1
        onUpload?()
        if alwaysFailTransiently { throw Transient() }
        if transientFailuresLeft > 0 {
            transientFailuresLeft -= 1
            throw Transient()
        }
        if let rejectedEvent, rows.contains(where: { $0.event == rejectedEvent }) {
            throw AppLogRejectedError()
        }
        batches.append(rows)
    }

    var uploadedEvents: [LogEvent] { batches.flatMap { $0 }.map(\.event) }
}

/// Succeeds, but the first upload waits until released (a slow request in flight).
@MainActor
private final class GatedUploader: AppLogUploading {
    private(set) var batches: [[AppLogRow]] = []
    private(set) var started = false
    private var gate: CheckedContinuation<Void, Never>?
    private var isGated = true

    func upload(_ rows: [AppLogRow]) async throws {
        started = true
        if isGated {
            isGated = false
            await withCheckedContinuation { gate = $0 }
        }
        batches.append(rows)
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

@MainActor
final class AppLogQueueTests: XCTestCase {
    private var directory: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let session = UUID(uuidString: "00000000-0000-4000-8000-0000000000aa")!
    private let userA = UUID()
    private let userB = UUID()
    private var writes = 0
    private var failingWrites = 0

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        writes = 0
        failingWrites = 0
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL { directory.appendingPathComponent("queue.json") }

    private func makeQueue(uploader: UploaderSpy? = nil, account: UUID? = nil,
                           persistDelay: Duration = .seconds(60)) -> AppLogQueue {
        let queue = AppLogQueue(fileURL: fileURL, sessionID: session, appVersion: "1.0 (1)",
                                osVersion: "18.2.0", now: { [now] in now }, persistDelay: persistDelay,
                                write: { [weak self] data, url in
                                    guard let self else { return }
                                    if failingWrites > 0 {
                                        failingWrites -= 1
                                        throw CocoaError(.fileWriteOutOfSpace)
                                    }
                                    writes += 1
                                    try data.write(to: url)
                                })
        queue.uploader = uploader
        queue.currentAccountID = { account }
        return queue
    }

    private func fill(_ queue: AppLogQueue, count: Int) {
        for index in 0..<count { queue.log(.practiceAnswered, [.count: .int(index)]) }
    }

    func testRowCarriesTypedFieldsOnly() throws {
        let queue = makeQueue()
        queue.log(.wordAdded, [.language: .name("ru"), .inFolder: .bool(true)])
        let row = try XCTUnwrap(queue.pending.first?.row)
        XCTAssertEqual(row.event, .wordAdded)
        XCTAssertEqual(row.level, .info)
        XCTAssertEqual(row.sessionID, session)
        XCTAssertEqual(row.occurredAt, now)
        XCTAssertEqual(row.properties, ["language": .name("ru"), "in_folder": .bool(true)])
        XCTAssertEqual(row.appVersion, "1.0 (1)")
        XCTAssertEqual(row.osVersion, "18.2.0")
    }

    // MARK: Persistence

    func testPendingRowsSurviveRelaunch() {
        let first = makeQueue()
        first.log(.appLaunched)
        first.log(.folderCreated)
        first.persistNow()
        XCTAssertEqual(makeQueue().pending.map(\.row.event), [.appLaunched, .folderCreated])
    }

    /// Review finding: logging must not rewrite the whole file on the main actor every call.
    func testBurstOfLogsIsCoalescedIntoOneDelayedWrite() async throws {
        let queue = makeQueue(persistDelay: .milliseconds(50))
        fill(queue, count: 15)
        XCTAssertEqual(writes, 0, "logging never writes synchronously")
        for _ in 0..<50 where writes == 0 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(makeQueue().pending.count, 15)
    }

    func testFlushPersistsEvenWithoutUploader() async {
        let queue = makeQueue()
        queue.log(.appLaunched)
        await queue.flush()
        XCTAssertEqual(writes, 1, "backgrounding calls flush, which must persist")
    }

    /// Review finding: a background flush during a running upload must still persist.
    func testFlushPersistsWhileAnotherFlushIsRunning() async throws {
        let queue = makeQueue(uploader: nil, account: nil)
        queue.log(.appLaunched)
        queue.currentAccountID = { [userA] in userA }
        let slow = HangingUploader()
        queue.uploader = slow
        let running = Task { await queue.flush() }
        for _ in 0..<50 where !slow.started { try await Task.sleep(for: .milliseconds(10)) }
        let writesBefore = writes
        queue.log(.folderCreated)
        let second = Task { await queue.flush() }
        for _ in 0..<50 where writes == writesBefore { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(writes, writesBefore + 1, "the waiting flush persisted before waiting")
        XCTAssertEqual(makeQueue().pending.map(\.row.event), [.appLaunched, .folderCreated])
        queue.uploader = nil  // the waiting flush then only persists instead of hanging again
        slow.release()
        await running.value
        await second.value
    }

    /// Review finding: a flush started during another one (backgrounding, sign-out) used to
    /// return at once, leaving rows logged meanwhile unsent; it now waits and drains them.
    func testFlushDuringRunningFlushWaitsAndUploadsNewRows() async throws {
        let uploader = GatedUploader()
        let queue = makeQueue(account: userA)
        queue.uploader = uploader
        queue.log(.appLaunched)
        let running = Task { await queue.flush() }
        for _ in 0..<50 where !uploader.started { try await Task.sleep(for: .milliseconds(10)) }
        queue.log(.authSignedOut)
        let second = Task { await queue.flush() }
        try await Task.sleep(for: .milliseconds(30))
        uploader.release()
        await second.value
        XCTAssertEqual(uploader.batches.map { $0.map(\.event) }, [[.appLaunched], [.authSignedOut]],
                       "the second flush returned only after uploading its rows")
        XCTAssertTrue(queue.pending.isEmpty)
        await running.value
    }

    /// Review finding: a cancelled caller waiting for someone else's flush returns at once.
    func testCancelledWaitForAnotherFlushReturnsImmediately() async throws {
        let slow = HangingUploader()
        let queue = makeQueue(account: userA)
        queue.uploader = slow
        queue.log(.appLaunched)
        let running = Task { await queue.flush() }
        for _ in 0..<50 where !slow.started { try await Task.sleep(for: .milliseconds(10)) }
        let waiting = Task { await queue.flush() }
        try await Task.sleep(for: .milliseconds(20))
        waiting.cancel()
        await waiting.value  // would hang until `release()` before the fix
        XCTAssertFalse(running.isCancelled)
        queue.uploader = nil
        slow.release()
        await running.value
    }

    func testCancellingFlushCancelsTheUpload() async throws {
        let slow = HangingUploader()
        let queue = makeQueue(account: userA)
        queue.uploader = slow
        queue.log(.appLaunched)
        let running = Task { await queue.flush() }
        for _ in 0..<50 where !slow.started { try await Task.sleep(for: .milliseconds(10)) }
        running.cancel()
        slow.release()
        await running.value
        XCTAssertEqual(queue.pending.map(\.row.event), [.appLaunched], "cancelled rows stay queued")
        let uploader = UploaderSpy()
        queue.uploader = uploader
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents, [.appLaunched], "a later flush is not blocked")
    }

    /// Review finding: unchanged queues must not be rewritten on every flush/background.
    func testPersistWritesOnlyWhenQueueChanged() async {
        let queue = makeQueue()
        queue.log(.appLaunched)
        queue.persistNow()
        queue.persistNow()
        await queue.flush()
        XCTAssertEqual(writes, 1)
        queue.log(.folderCreated)
        await queue.flush()
        XCTAssertEqual(writes, 2)
    }

    func testFailedWriteIsRetriedByNextPersist() {
        let queue = makeQueue()
        queue.log(.appLaunched)
        failingWrites = 1
        queue.persistNow()
        XCTAssertEqual(writes, 0)
        queue.persistNow()
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(makeQueue().pending.map(\.row.event), [.appLaunched])
    }

    /// Review finding: one unreadable row (e.g. an event a later version removed) used to drop
    /// the whole queue on launch.
    func testUnreadableEntryDropsOnlyItself() throws {
        let queue = makeQueue()
        queue.log(.appLaunched)
        queue.log(.folderCreated)
        queue.persistNow()
        var entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [[String: Any]])
        var row = try XCTUnwrap(entries[0]["row"] as? [String: Any])
        row["event"] = "removed.event"
        entries[0]["row"] = row
        entries.append(["garbage": true])
        try JSONSerialization.data(withJSONObject: entries).write(to: fileURL)
        XCTAssertEqual(makeQueue().pending.map(\.row.event), [.folderCreated])
    }

    /// Review finding: a persist task cancelled by flush still woke up and wrote at once,
    /// cancelling the newer debounced write.
    func testCancelledPersistDoesNotWriteEarly() async throws {
        let queue = makeQueue(persistDelay: .milliseconds(200))
        queue.log(.appLaunched)
        await queue.flush()
        XCTAssertEqual(writes, 1)
        queue.log(.folderCreated)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(writes, 1, "the cancelled task did not write; the new one is still debouncing")
        for _ in 0..<100 where writes == 1 { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(writes, 2)
    }

    func testCorruptFileStartsEmpty() throws {
        try Data("not json".utf8).write(to: fileURL)
        XCTAssertTrue(makeQueue().pending.isEmpty)
    }

    func testQueueIsCappedDroppingOldest() {
        let queue = makeQueue()
        fill(queue, count: AppLogQueue.maxStoredRows + 5)
        XCTAssertEqual(queue.pending.count, AppLogQueue.maxStoredRows)
        XCTAssertEqual(queue.pending.first?.row.properties["count"], .int(5))
    }

    // MARK: Upload

    func testDoesNotUploadWhileSignedOut() async {
        let uploader = UploaderSpy()
        let queue = makeQueue(uploader: uploader, account: nil)
        fill(queue, count: 3)
        await queue.flush()
        XCTAssertTrue(uploader.batches.isEmpty)
        XCTAssertEqual(queue.pending.count, 3)
    }

    func testUploadsInBatchesAndClearsDisk() async {
        let uploader = UploaderSpy()
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        fill(queue, count: AppLogQueue.batchSize + 10)
        account = userA
        await queue.flush()
        XCTAssertEqual(uploader.batches.map(\.count), [AppLogQueue.batchSize, 10])
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertTrue(makeQueue().pending.isEmpty, "the on-disk queue is cleared too")
    }

    func testTransientFailureKeepsRowsForRetry() async {
        let uploader = UploaderSpy()
        uploader.transientFailuresLeft = 1
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        fill(queue, count: 3)
        account = userA
        await queue.flush()
        XCTAssertEqual(queue.pending.count, 3)
        await queue.flush()
        XCTAssertTrue(queue.pending.isEmpty)
        XCTAssertEqual(uploader.batches.first?.count, 3)
    }

    /// Review finding: one row the server always rejects must not block the queue forever.
    func testRejectedRowIsDroppedAndTheRestStillUpload() async {
        let uploader = UploaderSpy()
        uploader.rejectedEvent = .folderDeleted
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        queue.log(.appLaunched)
        queue.log(.folderDeleted)
        queue.log(.folderCreated)
        account = userA
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents, [.appLaunched, .folderCreated])
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testTransientFailureWhileIsolatingKeepsUnsentRows() async {
        let uploader = UploaderSpy()
        uploader.rejectedEvent = .folderDeleted
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        queue.log(.folderDeleted)
        queue.log(.folderCreated)
        account = userA
        var calls = 0
        uploader.onUpload = { [weak uploader] in
            calls += 1
            // Call 1: batch rejected. Call 2: bad row rejected. Call 3: network drops.
            if calls == 3 { uploader?.transientFailuresLeft = 1 }
        }
        await queue.flush()
        XCTAssertTrue(uploader.batches.isEmpty)
        XCTAssertEqual(queue.pending.map(\.row.event), [.folderCreated], "only the rejected row is dropped")
    }

    func testRowsLoggedDuringUploadAreKept() async {
        let uploader = UploaderSpy()
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        fill(queue, count: 2)
        uploader.onUpload = { [weak queue, weak uploader] in
            queue?.log(.folderDeleted)
            uploader?.onUpload = nil
        }
        account = userA
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents.filter { $0 == .folderDeleted }.count, 1)
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testConcurrentFlushesUploadEachRowOnce() async {
        let uploader = UploaderSpy()
        var account: UUID?
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        fill(queue, count: 5)
        account = userA
        async let first: Void = queue.flush()
        async let second: Void = queue.flush()
        _ = await (first, second)
        XCTAssertEqual(uploader.batches.flatMap { $0 }.count, 5)
    }

    func testThresholdTriggersFlushOnlyWhenSignedIn() async throws {
        let signedOutUploader = UploaderSpy()
        let signedOut = makeQueue(uploader: signedOutUploader, account: nil)
        fill(signedOut, count: AppLogQueue.flushThreshold)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(signedOutUploader.batches.isEmpty)

        let uploader = UploaderSpy()
        let queue = makeQueue(uploader: uploader, account: userA)
        fill(queue, count: AppLogQueue.flushThreshold)
        for _ in 0..<50 where uploader.batches.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(uploader.batches.isEmpty)
    }

    /// Review finding: offline and signed in, logging must not start a request per event.
    /// Review finding: every log call in the same turn passed `flushTask == nil` and spawned
    /// its own automatic flush (here: one upload attempt each while offline).
    func testBurstOfLogsSpawnsOneAutomaticFlush() async throws {
        let uploader = UploaderSpy()
        uploader.alwaysFailTransiently = true
        let queue = makeQueue(uploader: uploader, account: userA)
        fill(queue, count: AppLogQueue.flushThreshold + 5)
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(uploader.attempts, 1)
    }

    /// Review finding: a cancelled flush (sign-out timeout) started the offline backoff.
    func testCancelledFlushDoesNotBackOffAutomaticFlushes() async throws {
        let slow = HangingUploader()
        let queue = makeQueue(account: userA)
        queue.uploader = slow
        queue.log(.appLaunched)
        let running = Task { await queue.flush() }
        for _ in 0..<50 where !slow.started { try await Task.sleep(for: .milliseconds(10)) }
        running.cancel()
        slow.release()
        await running.value
        let uploader = UploaderSpy()
        queue.uploader = uploader
        fill(queue, count: AppLogQueue.flushThreshold)
        for _ in 0..<50 where uploader.attempts == 0 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(uploader.attempts, 1, "automatic flushes were not paused by the cancellation")
    }

    func testOfflineAutoFlushIsThrottledAfterFailure() async throws {
        let uploader = UploaderSpy()
        uploader.alwaysFailTransiently = true
        let queue = makeQueue(uploader: uploader, account: userA)
        fill(queue, count: AppLogQueue.flushThreshold)
        for _ in 0..<50 where uploader.attempts == 0 { try await Task.sleep(for: .milliseconds(20)) }
        fill(queue, count: 30)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploader.attempts, 1, "one attempt, then back off for AppLogQueue.retryBackoff")
        XCTAssertEqual(queue.pending.count, AppLogQueue.flushThreshold + 30)
    }

    func testAutoFlushIgnoresRowsOfOtherAccounts() async throws {
        let uploader = UploaderSpy()
        let queue = makeQueue(uploader: nil, account: userB)
        fill(queue, count: 25)                       // B's rows, B signed out later
        queue.uploader = uploader
        queue.currentAccountID = { [userA] in userA }
        queue.log(.appLaunched)                      // A has 1 uploadable row: below threshold
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(uploader.attempts, 0, "B's 25 rows must not trigger flushes for A")
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents, [.appLaunched], "an explicit flush uploads only A's row")
        XCTAssertEqual(queue.pending.count, 25)
    }

    /// Review finding: rows must be on disk before the upload starts (app may be killed).
    func testFlushPersistsBeforeUploading() async {
        let uploader = UploaderSpy()
        let queue = makeQueue(uploader: uploader, account: nil)
        queue.log(.appLaunched)
        var writesAtUpload = -1
        uploader.onUpload = { [weak self] in writesAtUpload = self?.writes ?? -1 }
        queue.currentAccountID = { [userA] in userA }
        await queue.flush()
        XCTAssertEqual(writesAtUpload, 1)
    }

    // MARK: Attribution (review finding)

    func testRowsOfAnotherAccountAreNeverUploadedUnderCurrentOne() async {
        let uploader = UploaderSpy()
        var account: UUID? = userA
        let queue = makeQueue(uploader: uploader)
        queue.currentAccountID = { account }
        queue.log(.authSignedOut)                                // A's row while A signs out
        account = nil
        queue.log(.authFailed, level: .error, properties: [:])   // device row while signed out
        account = userB
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents, [.authFailed], "B uploads device rows, not A's")
        XCTAssertEqual(queue.pending.map(\.accountID), [userA])

        account = userA
        await queue.flush()
        XCTAssertEqual(uploader.uploadedEvents, [.authFailed, .authSignedOut])
        XCTAssertTrue(queue.pending.isEmpty)
    }

    func testAccountTagSurvivesRelaunch() {
        let queue = makeQueue(account: userA)
        queue.log(.appLaunched)
        queue.persistNow()
        XCTAssertEqual(makeQueue().pending.first?.accountID, userA)
    }

    // MARK: Versions

    func testVersionsAreSanitizedToServerShape() {
        XCTAssertEqual(AppLogQueue.sanitizedVersion("1.0 (12)"), "1.0 (12)")
        XCTAssertEqual(AppLogQueue.sanitizedVersion("https://x/?q=кот"), "unknown")
        XCTAssertEqual(AppLogQueue.sanitizedVersion(""), "unknown")
        XCTAssertEqual(AppLogQueue.sanitizedVersion(String(repeating: "1", count: 33)), "unknown")
        XCTAssertNotEqual(AppLogQueue.sanitizedVersion(AppLogQueue.currentOSVersion), "unknown")
        XCTAssertNotEqual(AppLogQueue.sanitizedVersion(AppLogQueue.currentAppVersion), "unknown")
    }

    // MARK: Contract with public.app_logs

    /// The body PostgREST receives must have exactly the table's insertable columns and no
    /// user_id (the database default fills it from the session).
    func testRequestBodyMatchesAppLogsColumns() throws {
        let queue = makeQueue()
        queue.log(.wordAdded, [.source: .name("manual"), .language: .name("ru"), .count: .int(1)])
        let body = try SupabaseLogUploader.requestBody(queue.pending.map(\.row))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [[String: Any]])
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(Set(row.keys), ["occurred_at", "session_id", "level", "event", "properties",
                                       "app_version", "os_version"])
    }

    /// Golden body; supabase/tests/rls_app_logs.sql inserts this exact JSON into app_logs, so
    /// a change on either side breaks a test. (The SDK writes UTC without a zone suffix;
    /// Supabase sessions run in UTC.)
    static let goldenRequestBody = #"[{"app_version":"1.0 (1)","event":"word.added","level":"info","occurred_at":"2027-01-15T08:00:00.000","os_version":"18.2.0","properties":{"count":1,"language":"ru","source":"manual"},"session_id":"00000000-0000-4000-8000-0000000000AA"}]"#

    func testRequestBodyMatchesGoldenAcceptedByDatabase() throws {
        let queue = makeQueue()
        queue.log(.wordAdded, [.source: .name("manual"), .language: .name("ru"), .count: .int(1)])
        let body = try SupabaseLogUploader.requestBody(queue.pending.map(\.row))
        XCTAssertEqual(String(decoding: body, as: UTF8.self), Self.goldenRequestBody)
    }
}
