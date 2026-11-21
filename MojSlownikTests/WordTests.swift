import XCTest
import SwiftData
@testable import MojSlownik

final class WordTests: XCTestCase {
    func testNewWordStoresBothLanguagesInLowercaseWithoutLosingDiacritics() {
        let word = Word(russian: "СПАСИБО ЁЖ", polish: "DZIĘKUJĘ ŁÓDŹ", side: .term)
        XCTAssertEqual(word.russian, "спасибо ёж")
        XCTAssertEqual(word.polish, "dziękuję łódź")
        XCTAssertEqual(word.sourceLanguageCode, "pl")
    }

    func testNewWordsHaveDistinctUUIDsAndUpdatedAtEqualsCreatedAt() {
        let created = Date(timeIntervalSince1970: 100)
        let first = Word(russian: "вода", polish: "woda", side: .term, createdAt: created)
        let second = Word(russian: "вода", polish: "woda", side: .term, createdAt: created)
        XCTAssertNotNil(first.uuid)
        XCTAssertNotEqual(first.uuid, second.uuid)
        XCTAssertEqual(first.updatedAt, created)
        XCTAssertNil(first.deletedAt)
        XCTAssertTrue(first.isActive)
        first.updatedAt = nil
        XCTAssertEqual(first.lastModifiedAt, created)
        let deleted = Date(timeIntervalSince1970: 200)
        first.markDeleted(now: deleted)
        XCTAssertFalse(first.isActive)
        XCTAssertEqual(first.updatedAt, deleted)
        XCTAssertEqual(first.deletedAt, deleted)
    }

    func testNewWordAutomaticallyCategorizesPair() {
        let word = Word(russian: "ВОДА", polish: "WODA", side: .translation)
        XCTAssertEqual(word.category, .food)
    }

    func testManualCategoryOverridesAutomaticCategory() {
        let word = Word(russian: "вода", polish: "woda", side: .term, category: .travel)
        XCTAssertEqual(word.category, .travel)
        word.category = .home
        XCTAssertEqual(word.categoryRawValue, WordCategory.home.rawValue)
    }

    func testUnknownStoredCategoryRemainsReadableAsOther() {
        let word = Word(russian: "слово", polish: "słowo", side: .term)
        word.categoryRawValue = "future-category"
        XCTAssertEqual(word.category, .other)
    }

    func testDuplicatePairMatchesEitherInputDirectionIgnoringCaseAndWhitespace() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        XCTAssertTrue(word.matches(WordEntry.legacy(source: " WODA\n", translation: " ВОДА ")))
        XCTAssertTrue(word.matches(WordEntry.legacy(source: " ВОДА ", translation: "WODA")))
        XCTAssertFalse(word.matches(WordEntry.legacy(source: "woda", translation: "кофе")))
        XCTAssertFalse(word.matches(WordEntry.legacy(source: "kawa", translation: "вода")))
    }

    func testDuplicatePairMatchesCanonicalUnicodeButPreservesMeaningfulDiacritics() {
        let word = Word(russian: "спасибо", polish: "dziękuję", side: .term)
        XCTAssertTrue(word.matches(WordEntry.legacy(source: "DZIĘKUJĘ".decomposedStringWithCanonicalMapping, translation: "СПАСИБО")))
        XCTAssertFalse(word.matches(WordEntry.legacy(source: "dziekuje", translation: "спасибо")))
    }

    @MainActor
    func testSavedWordRoundTripPreservesLowercaseCategoryAndPracticeProgress() throws {
        let container = try ModelContainer(for: Word.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let word = Word(russian: "ВОДА", polish: "WODA", side: .term,
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

    func testSyncPairKeyNormalizesCanonicalFormCaseAndWhitespace() {
        let composed = Word(russian: " КОТ ", polish: "Za\u{17C}\u{F3}\u{142}\u{107}", side: .term)
        let decomposed = Word(russian: "кот\n", polish: "zaz\u{307}o\u{301}\u{142}c\u{301}", side: .translation)
        XCTAssertEqual(composed.syncPairKey, decomposed.syncPairKey)
        XCTAssertNotEqual(composed.syncPairKey,
                          Word(russian: "кот", polish: "zazolc", side: .term).syncPairKey,
                          "diacritics are meaningful")
        XCTAssertEqual(Word.normalizedText("  ŁÓDŹ \n"), "łódź")
    }

    func testMatchesBehaviourIsUnchangedByNormalizationExtraction() {
        let word = Word(russian: "кот", polish: "kot", side: .translation)
        XCTAssertTrue(word.matches(WordEntry.legacy(source: " KOT ", translation: "Кот")))
        XCTAssertTrue(word.matches(WordEntry.legacy(source: "кот", translation: "kot")))
        XCTAssertFalse(word.matches(WordEntry.legacy(source: "kot", translation: "пёс")))
    }

    func testNewWordIsSyncDirtyUntilServerTimeEqualsItsModificationTime() {
        let word = Word(russian: "кот", polish: "kot", side: .translation)
        XCTAssertNil(word.serverUpdatedAt)
        XCTAssertTrue(word.isSyncDirty)
        word.serverUpdatedAt = word.lastModifiedAt
        XCTAssertFalse(word.isSyncDirty)
    }

    func testInitPerPairAndSideStoresEachSideInItsLanguageForm() {
        let german = LanguagePair(term: .german, translation: .russian)
        let typedTerm = Word(entry: WordEntry(term: " Das Haus ", translation: " ДОМ ", enteredSide: .term),
                             pair: german, workspaceID: WorkspaceID.make(term: "de", translation: "ru"))
        XCTAssertEqual(typedTerm.term, "Das Haus", "German keeps its case")
        XCTAssertEqual(typedTerm.translation, "дом")
        XCTAssertEqual(typedTerm.sourceLanguageCode, "de")
        XCTAssertEqual(typedTerm.workspaceID, WorkspaceID.make(term: "de", translation: "ru"))

        let typedTranslation = Word(entry: WordEntry(term: "Das Haus", translation: "дом", enteredSide: .translation),
                                    pair: german, workspaceID: nil)
        XCTAssertEqual(typedTranslation.sourceLanguageCode, "ru")
        XCTAssertNil(typedTranslation.workspaceID)
        XCTAssertEqual(typedTranslation.effectiveWorkspaceID, WorkspaceID.legacy)
    }

    func testNonGermanPairsLowercaseBothSides() {
        let enPl = LanguagePair(term: .english, translation: .polish)
        let word = Word(entry: WordEntry(term: "House", translation: "DOM", enteredSide: .translation),
                        pair: enPl, workspaceID: nil)
        XCTAssertEqual(word.term, "house")
        XCTAssertEqual(word.translation, "dom")
        XCTAssertEqual(word.sourceLanguageCode, "pl")
    }

    func testMatchesIgnoresCaseOfKeptCaseText() {
        let german = LanguagePair(term: .german, translation: .russian)
        let word = Word(entry: WordEntry(term: "Das Haus", translation: "дом", enteredSide: .term),
                        pair: german, workspaceID: nil)
        XCTAssertTrue(word.matches(WordEntry(term: "das haus", translation: "ДОМ", enteredSide: .term)))
        XCTAssertFalse(word.matches(WordEntry(term: "das auto", translation: "дом", enteredSide: .term)))
    }
}
