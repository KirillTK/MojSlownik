import XCTest
@testable import MojSlownik

@MainActor
final class AppLogTests: XCTestCase {
    // MARK: Privacy by construction

    func testNameAcceptsIdentifiers() {
        for value in ["ru", "pl", "manual", "vocabulary.words.50", "NSURLErrorDomain", "MojSlownik.FolderStore.FolderError", "to_pl", "a-b"] {
            XCTAssertEqual(LogValue.name(value).storage, .name(value), value)
        }
    }

    func testNameRejectsAnythingThatCouldBeUserText() {
        let unsafe = ["кот", "dziękuję", "two words", "user@example.com", "https://x.example/?q=kot",
                      "", String(repeating: "a", count: LogValue.maxNameLength + 1), "a/b", "line\nbreak",
                      "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig=", "kot!"]
        for value in unsafe {
            XCTAssertEqual(LogValue.name(value).storage, .name(LogValue.invalidName), value)
        }
    }

    func testDecodingSanitizesStoredNames() throws {
        let decoded = try JSONDecoder().decode([String: LogValue].self, from: Data(#"{"a":"кот","b":3,"c":true}"#.utf8))
        XCTAssertEqual(decoded["a"], .name(LogValue.invalidName))
        XCTAssertEqual(decoded["b"], .int(3))
        XCTAssertEqual(decoded["c"], .bool(true))
    }

    func testValuesEncodeAsJSONScalars() throws {
        let data = try JSONEncoder().encode(["n": LogValue.name("ru"), "i": .int(7), "b": .bool(false)])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["n"] as? String, "ru")
        XCTAssertEqual(object["i"] as? Int, 7)
        XCTAssertEqual(object["b"] as? Bool, false)
    }

    func testErrorLogsOnlyDomainAndCode() {
        let spy = AppLogSpy()
        spy.log(.storageFailed, error: UserTextError(text: "кот"), [.operation: .name("word.add")])
        let entry = spy.entries[0]
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(Set(entry.properties.keys), [.operation, .errorDomain, .errorCode])
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("кот") || $0.contains("Failed") })

        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                              userInfo: [NSLocalizedDescriptionKey: "secret kot"])
        spy.log(.translationFailed, error: nsError)
        XCTAssertEqual(spy.entries[1].properties[.errorDomain], .name(NSURLErrorDomain))
        XCTAssertEqual(spy.entries[1].properties[.errorCode], .int(NSURLErrorNotConnectedToInternet))
    }

    /// Review finding: a cancelled URLSession load (-999) is a cancellation, not a failure.
    func testCancellationIsNotLogged() {
        let spy = AppLogSpy()
        spy.log(.translationFailed, error: CancellationError())
        spy.log(.translationFailed, error: URLError(.cancelled))
        spy.log(.translationFailed, error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        XCTAssertTrue(spy.entries.isEmpty)
        spy.log(.translationFailed, error: URLError(.timedOut))
        XCTAssertEqual(spy.events, [.translationFailed])
    }

    func testLoggedHelperLogsFailureAndRethrows() {
        let spy = AppLogSpy()
        XCTAssertEqual(try spy.logged("op.ok") { 7 }, 7)
        XCTAssertTrue(spy.entries.isEmpty)
        XCTAssertThrowsError(try spy.logged("op.fail") { throw UserTextError(text: "кот") })
        XCTAssertEqual(spy.events, [.storageFailed])
        XCTAssertEqual(spy.entries[0].properties[.operation], .name("op.fail"))
    }

    // MARK: Server contract

    func testEveryEventMatchesServerCheck() {
        for event in LogEvent.allCases {
            XCTAssertNotNil(event.rawValue.range(of: LogEvent.serverPattern, options: .regularExpression), event.rawValue)
        }
    }

    func testKeysAreSnakeCaseIdentifiers() {
        for key in LogKey.allCases {
            XCTAssertNotNil(key.rawValue.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression), key.rawValue)
        }
    }

    /// The unit-test host app must not log to disk or Supabase (see AppResources.unitTestHost).
    func testUnitTestHostUsesNoopLogger() {
        XCTAssertTrue(AppResources.isUnitTestHost)
        XCTAssertTrue(AppLog.shared is NoopAppLogger)
    }

    func testSyncEventsAndKeysMatchTheServerContract() {
        let events: [LogEvent] = [.syncCompleted, .syncFailed, .syncRowsSkipped, .syncLinked, .syncAccountMismatch]
        XCTAssertEqual(events.map(\.rawValue),
                       ["sync.completed", "sync.failed", "sync.rows_skipped", "sync.linked", "sync.account_mismatch"])
        for event in events {
            XCTAssertNotNil(event.rawValue.range(of: LogEvent.serverPattern, options: .regularExpression))
        }
        XCTAssertEqual([LogKey.trigger, .pulled, .pushed, .skipped, .reason, .relink].map(\.rawValue),
                       ["trigger", "pulled", "pushed", "skipped", "reason", "relink"])
    }
}
