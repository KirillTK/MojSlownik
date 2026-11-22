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

    /// Persisted in SwiftData (`Word.categoryRawValue`): must never change, whatever the UI language.
    func testRawValuesArePersistedRussianAndNeverLocalized() {
        XCTAssertEqual(WordCategory.allCases.map(\.rawValue),
                       ["Еда и напитки", "Дом", "Путешествия", "Природа", "Люди", "Работа и учёба", "Здоровье", "Другое"])
        let word = Word(russian: "x", polish: "y", side: .term, category: .work)
        XCTAssertEqual(word.categoryRawValue, "Работа и учёба")
        XCTAssertEqual(word.category, .work)
    }

    func testTitlesAreEnglishInTheEnglishHostAndRussianInTheRussianBundle() {
        XCTAssertEqual(WordCategory.allCases.map(\.title),
                       ["Food & drinks", "Home", "Travel", "Nature", "People", "Work & study", "Health", "Other"])
        XCTAssertEqual(WordCategory.allCases.map { LocalizationTestSupport.ru($0.title) }, WordCategory.allCases.map(\.rawValue))
    }
}
