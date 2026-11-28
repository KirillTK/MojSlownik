import XCTest
@testable import MojSlownik

@MainActor
final class QuickActionTests: XCTestCase {
    func testShortcutTypeRoundTrips() {
        for action in QuickAction.allCases {
            XCTAssertEqual(QuickAction(shortcutType: action.shortcutType), action)
        }
    }

    func testUnknownShortcutTypesAreRejected() {
        XCTAssertNil(QuickAction(shortcutType: "scan-text"))
        XCTAssertNil(QuickAction(shortcutType: "MojSlownik.quickAction.unknown"))
        XCTAssertNil(QuickAction(shortcutType: "other.app.quickAction.scan-text"))
    }

    func testShortcutItemUsesTheActionTypeAndLocalizedTitle() {
        let item = QuickAction.scanText.shortcutItem
        XCTAssertEqual(item.type, QuickAction.scanText.shortcutType)
        XCTAssertEqual(item.localizedTitle, String(localized: "Scan text"))
        XCTAssertFalse(item.localizedTitle.isEmpty)
    }

    func testScanRequestOpensTheScannerOnceFromTheSelectedTab() {
        let store = QuickActionStore()
        XCTAssertTrue(store.handle(shortcutType: QuickAction.scanText.shortcutType))
        XCTAssertEqual(store.pending, .scanText)

        XCTAssertTrue(store.takeScanRequest(dictionaryIsSelected: true, isPresenting: false))
        XCTAssertNil(store.pending)
        XCTAssertFalse(store.takeScanRequest(dictionaryIsSelected: true, isPresenting: false))
    }

    func testScanRequestWaitsUntilTheDictionaryTabIsSelected() {
        let store = QuickActionStore()
        store.handle(shortcutType: QuickAction.scanText.shortcutType)

        XCTAssertFalse(store.takeScanRequest(dictionaryIsSelected: false, isPresenting: false))
        XCTAssertEqual(store.pending, .scanText, "kept for the tab switch")
        XCTAssertTrue(store.takeScanRequest(dictionaryIsSelected: true, isPresenting: false))
    }

    func testScanRequestIsDroppedWhileSomethingIsPresented() {
        let store = QuickActionStore()
        store.handle(shortcutType: QuickAction.scanText.shortcutType)

        XCTAssertFalse(store.takeScanRequest(dictionaryIsSelected: true, isPresenting: true))
        XCTAssertNil(store.pending, "an open sheet is not interrupted and the action does not fire later")
    }

    func testStoreIgnoresUnknownShortcutTypes() {
        let store = QuickActionStore()
        XCTAssertFalse(store.handle(shortcutType: "MojSlownik.quickAction.unknown"))
        XCTAssertNil(store.pending)
        XCTAssertFalse(store.takeScanRequest(dictionaryIsSelected: true, isPresenting: false))
    }
}
