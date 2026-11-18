import UIKit
import XCTest
@testable import MojSlownik

/// Review finding: the background task must end exactly once, on completion or on expiration.
@MainActor
final class BackgroundLogFlushTests: XCTestCase {
    private final class HangingLogger: AppLogging {
        private(set) var wasCancelled = false
        func log(_ event: LogEvent, level: LogLevel, properties: [LogKey: LogValue]) {}
        func flush() async {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            wasCancelled = true
        }
    }

    private let identifier = UIBackgroundTaskIdentifier(rawValue: 42)

    func testEndsTaskWhenFlushCompletes() async {
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = BackgroundLogFlush.start(logger: AppLogSpy(),
                                            begin: { [identifier] _, _ in identifier },
                                            end: { ended.append($0) })
        await task.value
        XCTAssertEqual(ended, [identifier])
    }

    func testExpirationCancelsFlushAndEndsTaskOnce() async {
        var ended: [UIBackgroundTaskIdentifier] = []
        var expire: (@MainActor () -> Void)?
        let logger = HangingLogger()
        let task = BackgroundLogFlush.start(logger: logger,
                                            begin: { [identifier] _, expiration in
                                                expire = expiration
                                                return identifier
                                            },
                                            end: { ended.append($0) })
        expire?()
        await task.value
        XCTAssertTrue(logger.wasCancelled)
        XCTAssertEqual(ended, [identifier], "ended once even though the flush also finished")
    }

    func testNoEndWhenBackgroundTimeIsUnavailable() async {
        var ended: [UIBackgroundTaskIdentifier] = []
        let task = BackgroundLogFlush.start(logger: AppLogSpy(), begin: { _, _ in .invalid },
                                            end: { ended.append($0) })
        await task.value
        XCTAssertTrue(ended.isEmpty)
    }
}
