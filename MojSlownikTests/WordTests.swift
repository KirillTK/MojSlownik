import XCTest
import SwiftData
@testable import MojSlownik

final class WordTests: XCTestCase {
    func testNewWordStoresBothLanguagesInLowercaseWithoutLosingDiacritics() {
        let word = Word(russian: "СПАСИБО ЁЖ", polish: "DZIĘKUJĘ ŁÓDŹ", sourceLanguage: .polish)
        XCTAssertEqual(word.russian, "спасибо ёж")
        XCTAssertEqual(word.polish, "dziękuję łódź")
        XCTAssertEqual(word.sourceLanguageCode, "pl")
    }

    func testNewWordAutomaticallyCategorizesPair() {
        let word = Word(russian: "ВОДА", polish: "WODA", sourceLanguage: .russian)
        XCTAssertEqual(word.category, .food)
    }

    func testManualCategoryOverridesAutomaticCategory() {
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish, category: .travel)
        XCTAssertEqual(word.category, .travel)
        word.category = .home
        XCTAssertEqual(word.categoryRawValue, WordCategory.home.rawValue)
    }

    func testUnknownStoredCategoryRemainsReadableAsOther() {
        let word = Word(russian: "слово", polish: "słowo", sourceLanguage: .polish)
        word.categoryRawValue = "future-category"
        XCTAssertEqual(word.category, .other)
    }

    func testDuplicatePairMatchesEitherInputDirectionIgnoringCaseAndWhitespace() {
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        XCTAssertTrue(word.matches(source: " WODA\n", translation: " ВОДА ", language: .polish))
        XCTAssertTrue(word.matches(source: " ВОДА ", translation: "WODA", language: .russian))
        XCTAssertFalse(word.matches(source: "woda", translation: "кофе", language: .polish))
        XCTAssertFalse(word.matches(source: "kawa", translation: "вода", language: .polish))
    }

    func testDuplicatePairMatchesCanonicalUnicodeButPreservesMeaningfulDiacritics() {
        let word = Word(russian: "спасибо", polish: "dziękuję", sourceLanguage: .polish)
        XCTAssertTrue(word.matches(source: "DZIĘKUJĘ".decomposedStringWithCanonicalMapping,
                                   translation: "СПАСИБО", language: .polish))
        XCTAssertFalse(word.matches(source: "dziekuje", translation: "спасибо", language: .polish))
    }

    @MainActor
    func testSavedWordRoundTripPreservesLowercaseCategoryAndPracticeProgress() throws {
        let container = try ModelContainer(for: Word.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let word = Word(russian: "ВОДА", polish: "WODA", sourceLanguage: .polish,
                        createdAt: createdAt, category: .travel)
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        word.dueDate = createdAt.addingTimeInterval(14 * 86_400)
        context.insert(word)
        try context.save()

        let readingContext = ModelContext(container)
        let saved = try XCTUnwrap(readingContext.fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(saved.russian, "вода")
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.category, .travel)
        XCTAssertEqual(saved.repetitions, 7)
        XCTAssertEqual(saved.intervalDays, 14)
        XCTAssertEqual(saved.easeFactor, 2.8)
        XCTAssertEqual(saved.createdAt, createdAt)
        XCTAssertEqual(saved.dueDate, word.dueDate)
    }
}
