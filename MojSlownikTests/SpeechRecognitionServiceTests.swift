import XCTest
@testable import MojSlownik

@MainActor
final class SpeechRecognitionServiceTests: XCTestCase {
    func testDeniedPermissionNeverStartsCapture() async {
        let backend = FakeSpeechBackend()
        backend.allowed = false
        let service = SpeechRecognitionService(backend: backend)
        service.start { _ in XCTFail("Denied permission committed text") }
        await backend.waitForPermission()
        await settle()
        XCTAssertEqual(service.state, .idle)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertTrue(backend.locales.isEmpty)
        XCTAssertEqual(backend.cancelCount, 1)
    }

    func testPendingPermissionCancelRestartAndStaleCallbacks() async {
        let backend = FakeSpeechBackend()
        backend.holdPermission = true
        let service = SpeechRecognitionService(backend: backend)
        var values: [String] = []
        service.start { values.append($0) }
        await backend.waitForPermission()
        service.cancel()
        service.start { values.append($0) }
        await backend.waitForPermission(count: 2)
        backend.permissions.removeFirst().resume(returning: true)
        await settle()
        XCTAssertTrue(backend.locales.isEmpty)
        backend.permissions.removeFirst().resume(returning: true)
        await settle()
        XCTAssertEqual(backend.locales, ["pl-PL"])
        let oldResult = backend.results[0]
        service.cancel()
        backend.holdPermission = false
        service.start { values.append($0) }
        await backend.waitForPermission(count: 3)
        await settle()
        oldResult("stale", true)
        XCTAssertEqual(service.state, .listening)
        XCTAssertTrue(service.draft.isEmpty)
        backend.results[1]("żółw", true)
        XCTAssertEqual(values, ["żółw"])
    }

    func testPartialIsDraftAndFinalCommitsOnceIncludingIdenticalTextAcrossSessions() async {
        let backend = FakeSpeechBackend()
        let service = SpeechRecognitionService(backend: backend)
        var values: [String] = []
        service.start { values.append($0) }
        await backend.waitForPermission()
        await settle()
        XCTAssertEqual(backend.locales, ["pl-PL"])
        backend.results[0]("dzię", false)
        XCTAssertEqual(service.draft, "dzię")
        XCTAssertTrue(values.isEmpty)
        backend.results[0](" dziękuję ", true)
        backend.results[0]("duplicate", true)
        backend.failures[0]("late error")
        XCTAssertEqual(values, ["dziękuję"])
        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(backend.cancelCount, 1)
        service.cancel()
        XCTAssertEqual(backend.cancelCount, 1)
        service.start { values.append($0) }
        await backend.waitForPermission(count: 2)
        await settle()
        backend.results[1]("dziękuję", true)
        XCTAssertEqual(values, ["dziękuję", "dziękuję"])
    }

    func testStopWaitsForFinalThenCommitsOnce() async {
        let backend = FakeSpeechBackend()
        let service = SpeechRecognitionService(backend: backend)
        var values: [String] = []
        service.start { values.append($0) }
        await backend.waitForPermission()
        await settle()
        backend.results[0]("żół", false)
        service.finish()
        service.finish()
        XCTAssertEqual(service.state, .finishing)
        XCTAssertEqual(backend.finishCount, 1)
        XCTAssertTrue(values.isEmpty)
        backend.results[0]("żółw", true)
        XCTAssertEqual(values, ["żółw"])
        XCTAssertEqual(service.state, .idle)
    }

    func testStopTimeoutCommitsLatestPartial() async {
        let backend = FakeSpeechBackend()
        let service = SpeechRecognitionService(backend: backend, finishTimeout: .milliseconds(1))
        let committed = expectation(description: "Timeout committed partial")
        service.start { text in
            XCTAssertEqual(text, "woda")
            committed.fulfill()
        }
        await backend.waitForPermission()
        await settle()
        backend.results[0]("woda", false)
        service.finish()
        await fulfillment(of: [committed], timeout: 1)
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(backend.cancelCount, 1)
    }

    func testEmptyStopTimeoutReportsNoSpeechWithoutCommit() async throws {
        let backend = FakeSpeechBackend()
        let service = SpeechRecognitionService(backend: backend, finishTimeout: .milliseconds(1))
        service.start { _ in XCTFail("Empty speech committed") }
        await backend.waitForPermission()
        await settle()
        service.finish()
        // Exercise the real finalization timer, without microphone or recognition hardware.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(service.state, .idle)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(backend.cancelCount, 1)
    }

    func testCancelDuringFinalizationInvalidatesTimeoutAndEmptyFinalDoesNotCommit() async throws {
        let backend = FakeSpeechBackend()
        let service = SpeechRecognitionService(backend: backend, finishTimeout: .milliseconds(1))
        service.start { _ in XCTFail("Cancelled capture committed") }
        await backend.waitForPermission()
        await settle()
        service.start { _ in XCTFail("Overlapping start replaced completion") }
        XCTAssertEqual(backend.locales.count, 1)
        backend.results[0]("woda", false)
        service.finish()
        service.cancel()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(service.state, .idle)
        XCTAssertNil(service.errorMessage)
        XCTAssertEqual(backend.cancelCount, 1)
        service.start { _ in XCTFail("Empty final committed") }
        await backend.waitForPermission(count: 2)
        await settle()
        backend.results[1]("   ", true)
        XCTAssertEqual(service.state, .idle)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(backend.cancelCount, 2)
    }

    func testSetupFailureCleansPartiallyStartedCapture() async {
        let backend = FakeSpeechBackend()
        backend.startError = NSError(domain: "test", code: 1)
        let service = SpeechRecognitionService(backend: backend)
        service.start { _ in XCTFail("Setup failure committed") }
        await backend.waitForPermission()
        await settle()
        XCTAssertEqual(service.state, .idle)
        XCTAssertNotNil(service.errorMessage)
        XCTAssertEqual(backend.cancelCount, 1)
    }

    func testFailureInterruptionAndBackgroundCancellationNeverCommitDraft() async {
        for terminal in 0..<3 {
            let backend = FakeSpeechBackend()
            let service = SpeechRecognitionService(backend: backend)
            service.start { _ in XCTFail("Failed or cancelled capture committed") }
            await backend.waitForPermission()
            await settle()
            backend.results[0]("woda", false)
            if terminal == 2 { service.cancel() }
            else { backend.failures[0](terminal == 0 ? "Ошибка распознавания" : "Запись прервана") }
            backend.results[0]("late result", true)
            XCTAssertEqual(service.state, .idle)
            XCTAssertEqual(backend.cancelCount, 1)
            XCTAssertEqual(service.errorMessage == nil, terminal == 2)
        }
    }

    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

@MainActor
private final class FakeSpeechBackend: SpeechRecognitionBackend {
    var allowed = true
    var holdPermission = false
    var permissions: [CheckedContinuation<Bool, Never>] = []
    var permissionCount = 0
    var locales: [String] = []
    var results: [@MainActor (String, Bool) -> Void] = []
    var failures: [@MainActor (String) -> Void] = []
    var startError: Error?
    var finishCount = 0
    var cancelCount = 0

    func requestPermission() async -> Bool {
        permissionCount += 1
        if holdPermission {
            return await withCheckedContinuation { permissions.append($0) }
        }
        return allowed
    }

    func waitForPermission(count: Int = 1) async {
        while permissionCount < count { await Task.yield() }
    }

    func start(locale: String, onResult: @escaping @MainActor (String, Bool) -> Void,
               onFailure: @escaping @MainActor (String) -> Void) throws {
        locales.append(locale)
        results.append(onResult)
        failures.append(onFailure)
        if let startError { throw startError }
    }

    func finishAudio() { finishCount += 1 }
    func cancel() { cancelCount += 1 }
}
