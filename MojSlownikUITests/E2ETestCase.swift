import XCTest

/// Shared base for fixture-based E2E tests. The app runs in DEBUG UI-test mode:
/// in-memory store seeded from a named fixture, stubbed translation, isolated defaults.
/// Typed text must be ASCII (Cyrillic typing is unreliable); Cyrillic sources come from prefill.
class E2ETestCase: XCTestCase {
    /// Mirrors the app-side `UITestFixture` (names are pinned by a unit test).
    enum Fixture: String {
        case empty, basicVocabulary, dueForReview, foldersOrdered, syncedVocabulary
    }

    /// Mirrors the app-side `UITestAuthState` (a network-free auth backend).
    enum AuthState: String {
        case signedOut, signedIn, failing
    }

    /// Mirrors the app-side `UITestSyncState` (a network-free sync server model).
    enum SyncState: String {
        case empty, remoteVocabulary, failsOnce, linkedToOtherAccount, syncedThenRemoteChanges
    }

    var app: XCUIApplication!

    /// Default wait for helpers. Shared CI runners are slow (the first launch on a cold
    /// simulator took over a minute and a screen missed a 10 s wait), so allow more.
    static let defaultTimeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    @discardableResult
    func launch(_ fixture: Fixture, prefill: String? = nil, auth: AuthState? = nil,
                sync: SyncState? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_FIXTURE"] = fixture.rawValue
        if let auth {
            app.launchEnvironment["UITEST_AUTH"] = auth.rawValue
        }
        if let sync {
            app.launchEnvironment["UITEST_SYNC"] = sync.rawValue
        }
        if let prefill {
            app.launchEnvironment["UITEST_PREFILL"] = prefill
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 60), "App did not reach the foreground")
        self.app = app
        return app
    }

    @MainActor
    func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    func waitFor(_ element: XCUIElement, _ format: String, timeout: TimeInterval = E2ETestCase.defaultTimeout,
                 _ message: @autoclosure () -> String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message(), file: file, line: line)
    }

    @MainActor
    func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = E2ETestCase.defaultTimeout,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Element \(element) did not appear", file: file, line: line)
        // Ask `isHittable` only once the element has a laid-out frame: on an element that
        // exists but is still mid-layout (a toolbar button right after launch), XCTest records
        // "Failed to determine hittability … Activation point invalid" as a test failure
        // instead of returning false (seen on CI).
        let hittable = NSPredicate { object, _ in
            guard let element = object as? XCUIElement, element.exists, !element.frame.isEmpty else {
                return false
            }
            return element.isHittable
        }
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Element \(element) is not hittable", file: file, line: line)
    }

    @MainActor
    func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = E2ETestCase.defaultTimeout,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Element \(element) did not appear", file: file, line: line)
        waitFor(element, "isEnabled == true", timeout: timeout, "Element \(element) is not enabled",
                file: file, line: line)
    }

    @MainActor
    func waitForLabel(_ element: XCUIElement, equals expected: String, timeout: TimeInterval = E2ETestCase.defaultTimeout,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Element \(element) did not appear", file: file, line: line)
        let matches = NSPredicate { object, _ in
            (object as? XCUIElement)?.label == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Label of \(element) is '\(element.label)', expected '\(expected)'",
                       file: file, line: line)
    }

    @MainActor
    func waitForValue(_ element: XCUIElement, equals expected: String, timeout: TimeInterval = E2ETestCase.defaultTimeout,
                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Element \(element) did not appear", file: file, line: line)
        let matches = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return (element.value as? String) == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: matches, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Value of \(element) is '\(element.value as? String ?? "nil")', expected '\(expected)'",
                       file: file, line: line)
    }

    @MainActor
    func openTab(_ title: String) {
        let tab = app.tabBars.buttons[title]
        waitForHittable(tab)
        tab.tap()
    }

    /// Taps the trailing edge so the caret sits at the end, deletes the old text, types the new one.
    @MainActor
    func replaceText(in field: XCUIElement, with text: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        waitForHittable(field, file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let current = (field.value as? String) ?? ""
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5)
        field.typeText(deletes)
        field.typeText(text)
        waitForValue(field, equals: text, file: file, line: line)
    }

    /// Achievement banners (4 s overlay) can cover top-area controls; several can queue.
    @MainActor
    func dismissAchievementBannerIfPresent() {
        let banners = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Достижение получено'"))
        for _ in 0..<5 {
            let deadline = Date().addingTimeInterval(1)
            var hittable: XCUIElement?
            repeat {
                hittable = banners.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
                if hittable != nil { break }
                Thread.sleep(forTimeInterval: 0.1)
            } while Date() < deadline
            guard let banner = hittable else { return }
            banner.tap()
            let gone = NSPredicate(format: "exists == false")
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: banner)], timeout: 2)
        }
    }
}
