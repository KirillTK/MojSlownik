import XCTest
import SwiftData
@testable import MojSlownik

final class ScanWordStoreTests: XCTestCase {
    @MainActor
    func testRepeatedTapAddsRemovesAndAddsAgainWithoutDuplicates() throws {
        let container = try makeContainer()
        XCTAssertTrue(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .food, container: container))
        let added = try words(in: container)
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.polish, "woda")
        XCTAssertEqual(added.first?.russian, "вода")
        XCTAssertEqual(added.first?.category, .food)

        XCTAssertFalse(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .travel, container: container))
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(try words(in: container).first?.category, .travel)
    }

    @MainActor
    func testRussianInputCanRemoveExistingPairAddedFromPolishDirection() throws {
        let container = try makeContainer()
        XCTAssertTrue(try ScanWordStore.toggle(source: "DZIĘKUJĘ", translation: "СПАСИБО", category: .other, container: container))
        XCTAssertFalse(try ScanWordStore.toggle(source: " СПАСИБО ", translation: "DZIĘKUJĘ".decomposedStringWithCanonicalMapping,
                                               category: .other, container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
        XCTAssertTrue(try ScanWordStore.toggle(source: "СПАСИБО", translation: "DZIĘKUJĘ", category: .other, container: container))
        let readded = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(readded.sourceLanguageCode, "ru")
        XCTAssertEqual(readded.russian, "спасибо")
        XCTAssertEqual(readded.polish, "dziękuję")
    }

    @MainActor
    func testDeletingExistingPairLeavesUnrelatedVocabularyAndProgressUntouched() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let target = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        let other = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish, category: .food)
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        other.repetitions = 7
        other.intervalDays = 14
        other.easeFactor = 2.8
        other.dueDate = dueDate
        context.insert(target)
        context.insert(other)
        try context.save()

        XCTAssertFalse(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        let remaining = try words(in: container)
        XCTAssertEqual(remaining.count, 1)
        let saved = try XCTUnwrap(remaining.first)
        XCTAssertEqual(saved.polish, "kawa")
        XCTAssertEqual(saved.russian, "кофе")
        XCTAssertEqual(saved.category, .food)
        XCTAssertEqual(saved.repetitions, 7)
        XCTAssertEqual(saved.intervalDays, 14)
        XCTAssertEqual(saved.easeFactor, 2.8)
        XCTAssertEqual(saved.dueDate, dueDate)
    }

    @MainActor
    func testRemovalDeletesAllMatchingLegacyDuplicatesButKeepsOtherPairs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(Word(russian: "вода", polish: "woda", sourceLanguage: .polish))
        context.insert(Word(russian: "ВОДА", polish: "WODA", sourceLanguage: .russian))
        context.insert(Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish))
        try context.save()

        XCTAssertFalse(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .food, container: container))
        let remaining = try words(in: container)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.polish, "kawa")
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertEqual(try words(in: container).filter { $0.polish == "woda" }.count, 1)
    }

    @MainActor
    func testCategoryCanBeChangedImmediatelyAfterAddAndReadd() throws {
        let container = try makeContainer()
        _ = try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container)
        try ScanWordStore.changeCategory(.travel, source: "WODA", translation: "ВОДА", container: container)
        XCTAssertEqual(try words(in: container).first?.category, .travel)
        _ = try ScanWordStore.toggle(source: "woda", translation: "вода", category: .travel, container: container)
        _ = try ScanWordStore.toggle(source: "woda", translation: "вода", category: .travel, container: container)
        try ScanWordStore.changeCategory(.home, source: "woda", translation: "вода", container: container)
        XCTAssertEqual(try words(in: container).first?.category, .home)
        XCTAssertEqual(try words(in: container).count, 1)
    }

    @MainActor
    func testToggleDoesNotSaveUnrelatedPendingEdits() throws {
        let container = try makeContainer()
        let editingContext = ModelContext(container)
        editingContext.autosaveEnabled = false
        let unsaved = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish)
        editingContext.insert(unsaved)
        _ = try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container)
        XCTAssertTrue(editingContext.hasChanges)
        XCTAssertEqual(unsaved.polish, "kawa")
        let persisted = try words(in: container)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.polish, "woda")
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Word.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func words(in container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }
}
