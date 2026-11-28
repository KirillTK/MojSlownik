import XCTest

/// Ways into the scanner: the labelled Dictionary button and the Home Screen quick action.
/// The camera itself is not available in the simulator; these only check that the scanner opens.
final class ScanAccessFlowTests: E2ETestCase {
    @MainActor
    func testScanButtonOpensScanner() throws {
        launch(.basicVocabulary)

        let scan = element("scanButton")
        waitForHittable(scan)
        XCTAssertEqual(scan.label, "Сканировать текст")
        scan.tap()

        XCTAssertTrue(element("closeScannerButton").waitForExistence(timeout: Self.defaultTimeout),
                      "Scanner did not open from the scan button")
    }

    @MainActor
    func testScanQuickActionOpensScannerOnLaunch() throws {
        launch(.basicVocabulary, quickAction: "scan-text")

        XCTAssertTrue(element("closeScannerButton").waitForExistence(timeout: Self.defaultTimeout),
                      "Scanner did not open from the Home Screen quick action")
    }
}
