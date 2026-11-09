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
    func testDeleteTargetsExactRecordAndPreservesDuplicatesFoldersAndProgress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let firstFolder = WordFolder(name: "Урок 1")
        let secondFolder = WordFolder(name: "Урок 2")
        context.insert(firstFolder)
        context.insert(secondFolder)
        let target = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        let duplicate = Word(russian: "вода", polish: "woda", sourceLanguage: .russian, category: .food)
        let other = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish)
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        for word in [target, duplicate, other] {
            word.folderIDs = [firstFolder.id, secondFolder.id]
            word.repetitions = 7
            word.intervalDays = 14
            word.easeFactor = 2.8
            word.dueDate = dueDate
            context.insert(word)
        }
        try context.save()
        let targetID = target.persistentModelID
        let survivorIDs = Set([duplicate.persistentModelID, other.persistentModelID])

        try ScanWordStore.delete(wordID: targetID, container: container)

        let freshContext = ModelContext(container)
        let remaining = try freshContext.fetch(FetchDescriptor<Word>())
        XCTAssertEqual(Set(remaining.map(\.persistentModelID)), survivorIDs)
        XCTAssertFalse(remaining.contains { $0.persistentModelID == targetID })
        XCTAssertEqual(remaining.filter { $0.polish == "woda" }.count, 1)
        for word in remaining {
            XCTAssertEqual(word.folderIDs, [firstFolder.id, secondFolder.id])
            XCTAssertEqual(word.repetitions, 7)
            XCTAssertEqual(word.intervalDays, 14)
            XCTAssertEqual(word.easeFactor, 2.8)
            XCTAssertEqual(word.dueDate, dueDate)
        }
        XCTAssertEqual(remaining.first { $0.persistentModelID == duplicate.persistentModelID }?.category, .food)
        XCTAssertEqual(Set(try freshContext.fetch(FetchDescriptor<WordFolder>()).map(\.id)),
                       Set([firstFolder.id, secondFolder.id]))
    }

    @MainActor
    func testDeleteAndMissingRecordDoNotSaveOrRollBackUnrelatedPendingEdits() throws {
        let container = try makeContainer()
        let editingContext = ModelContext(container)
        editingContext.autosaveEnabled = false
        let target = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        let other = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish, category: .food)
        editingContext.insert(target)
        editingContext.insert(other)
        try editingContext.save()
        let targetID = target.persistentModelID
        other.category = .travel
        let unsaved = Word(russian: "дом", polish: "dom", sourceLanguage: .polish)
        editingContext.insert(unsaved)

        try ScanWordStore.delete(wordID: targetID, container: container)
        XCTAssertThrowsError(try ScanWordStore.delete(wordID: targetID, container: container)) { error in
            XCTAssertEqual(error.localizedDescription, "Слово больше не существует")
        }

        XCTAssertTrue(editingContext.hasChanges)
        XCTAssertEqual(other.category, .travel)
        XCTAssertEqual(unsaved.polish, "dom")
        let persisted = try words(in: container)
        XCTAssertEqual(persisted.count, 1)
        XCTAssertEqual(persisted.first?.polish, "kawa")
        XCTAssertEqual(persisted.first?.category, .food)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Word.self, WordFolder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func words(in container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }
}
