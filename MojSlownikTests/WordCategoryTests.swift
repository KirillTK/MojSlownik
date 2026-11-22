import XCTest
@testable import MojSlownik

final class WordCategoryTests: XCTestCase {
    func testClassificationUsesEitherLanguageWithCaseAndWhitespaceNormalization() {
        XCTAssertEqual(WordCategory.detect(term: "", translation: " ХЛЕБ\n"), .food)
        XCTAssertEqual(WordCategory.detect(term: " KSIĄŻKA ", translation: ""), .work)
        XCTAssertEqual(WordCategory.detect(term: "GŁOWA", translation: ""), .health)
    }

    func testClassificationSupportsCanonicallyEquivalentPolishText() {
        XCTAssertEqual(WordCategory.detect(term: "GÓRA".decomposedStringWithCanonicalMapping, translation: ""), .nature)
    }

    func testUnknownAndEmptyWordsFallBackToOtherWithoutSubstringMatches() {
        XCTAssertEqual(WordCategory.detect(term: "", translation: ""), .other)
        XCTAssertEqual(WordCategory.detect(term: "unknown", translation: "неизвестное"), .other)
        XCTAssertEqual(WordCategory.detect(term: "domek", translation: ""), .other)
        XCTAssertEqual(WordCategory.detect(term: "", translation: "водопад"), .other)
    }

    func testRussianTranslationSideStillDetectsForOtherStudiedLanguages() {
        XCTAssertEqual(WordCategory.detect(term: "das Haus", translation: "дом"), .home)
        XCTAssertEqual(WordCategory.detect(term: "das Fahrrad", translation: "велосипед"), .other)
    }
}
