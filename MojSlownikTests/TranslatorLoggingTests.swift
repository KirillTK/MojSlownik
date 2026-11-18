import XCTest
@testable import MojSlownik

/// Review finding: `translation.failed` is logged only when every web provider failed and the
/// request was not cancelled; the text itself never reaches the log.
@MainActor
final class TranslatorLoggingTests: XCTestCase {
    private var spy: AppLogSpy!
    private var previous: (any AppLogging)!

    override func setUp() {
        super.setUp()
        previous = AppLog.shared
        spy = AppLogSpy()
        AppLog.shared = spy
    }

    override func tearDown() {
        AppLog.shared = previous
        super.tearDown()
    }

    private struct ProviderDown: Error {}

    private func fallback(primary: @escaping () async throws -> String,
                          fallback: @escaping () async throws -> String) async throws -> String {
        try await Translator.webFallback(from: .russian, to: .polish, primary: primary, fallback: fallback)
    }

    func testPrimarySuccessLogsNothing() async throws {
        let result = try await fallback(primary: { "kot" }, fallback: { XCTFail("unused"); return "" })
        XCTAssertEqual(result, "kot")
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testFallbackSuccessLogsNothing() async throws {
        let result = try await fallback(primary: { throw ProviderDown() }, fallback: { "kot" })
        XCTAssertEqual(result, "kot")
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testBothProvidersFailingLogsLanguagesAndCodeOnly() async {
        do {
            _ = try await fallback(primary: { throw ProviderDown() },
                                   fallback: { throw UserTextError(text: "кот") })
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(spy.events, [.translationFailed])
        XCTAssertEqual(spy.entries[0].properties[.language], .name("ru"))
        // Review finding: the target language has its own key, not an ad-hoc "to_pl" operation.
        XCTAssertEqual(spy.entries[0].properties[.targetLanguage], .name("pl"))
        XCTAssertNil(spy.entries[0].properties[.operation])
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("кот") })
    }

    func testCancelledRequestsAreNotLogged() async {
        _ = try? await fallback(primary: { throw URLError(.cancelled) }, fallback: { throw URLError(.cancelled) })
        _ = try? await fallback(primary: { throw CancellationError() }, fallback: { "unused" })
        XCTAssertTrue(spy.entries.isEmpty)
    }
}
