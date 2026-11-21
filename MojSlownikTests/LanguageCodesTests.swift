import XCTest
@testable import MojSlownik

final class LanguageCodesTests: XCTestCase {
    func testSupportedListIsPinned() {
        XCTAssertEqual(LanguageCodes.supported, ["pl", "ru", "uk", "en", "de", "fr", "es", "it", "cs", "pt"])
        XCTAssertEqual(Set(LanguageCodes.supported).count, 10)
        XCTAssertTrue(LanguageCodes.isSupported("de"))
        XCTAssertFalse(LanguageCodes.isSupported("ja"))
        XCTAssertFalse(LanguageCodes.isSupported("pt-BR"))
    }

    func testOnlyGermanKeepsCase() {
        XCTAssertEqual(LanguageCodes.supported.filter(LanguageCodes.preservesCase), ["de"])
        XCTAssertEqual(LanguageCodes.storedForm("Haus", language: "de"), "Haus")
        XCTAssertEqual(LanguageCodes.storedForm("Dom", language: "pl"), "dom")
        XCTAssertEqual(LanguageCodes.storedForm("Дом", language: "ru"), "дом")
    }
}
