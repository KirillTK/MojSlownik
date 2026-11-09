import XCTest
@testable import MojSlownik

final class WordCategoryTests: XCTestCase {
    func testClassificationUsesEitherLanguageWithCaseAndWhitespaceNormalization() {
        XCTAssertEqual(WordCategory.detect(russian: " ХЛЕБ\n", polish: ""), .food)
        XCTAssertEqual(WordCategory.detect(russian: "", polish: " KSIĄŻKA "), .work)
        XCTAssertEqual(WordCategory.detect(russian: "", polish: "GŁOWA"), .health)
    }

    func testClassificationSupportsCanonicallyEquivalentPolishText() {
        XCTAssertEqual(WordCategory.detect(russian: "", polish: "GÓRA".decomposedStringWithCanonicalMapping), .nature)
    }

    func testUnknownAndEmptyWordsFallBackToOtherWithoutSubstringMatches() {
        XCTAssertEqual(WordCategory.detect(russian: "", polish: ""), .other)
        XCTAssertEqual(WordCategory.detect(russian: "неизвестное", polish: "unknown"), .other)
        XCTAssertEqual(WordCategory.detect(russian: "", polish: "domek"), .other)
        XCTAssertEqual(WordCategory.detect(russian: "водопад", polish: ""), .other)
    }
}
