import XCTest
@testable import MojSlownik

final class AppLocaleTests: XCTestCase {
    func testLanguageFollowsTheResolvedUILanguage() {
        // The scheme pins the unit-test host to English.
        XCTAssertEqual(AppLocale.current.language.languageCode?.identifier, "en")
    }

    func testRegionComesFromTheSystemLocale() {
        XCTAssertEqual(AppLocale.current.region, Locale.autoupdatingCurrent.region)
    }
}
