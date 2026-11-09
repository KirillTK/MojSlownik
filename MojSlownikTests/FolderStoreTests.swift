import XCTest
import SwiftData
@testable import MojSlownik

final class FolderStoreTests: XCTestCase {
    @MainActor
    func testCreateTrimsNameAndRejectsEmptyAndDuplicateNames() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "  Урок 1\n", container: container)
        XCTAssertEqual(folder.name, "Урок 1")
        XCTAssertThrowsError(try FolderStore.create(name: " \n ", container: container))
        XCTAssertThrowsError(try FolderStore.create(name: "УРОК 1", container: container))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 1)
    }

    @MainActor
    func testWordCanBelongToMultipleFoldersWithoutDuplicateMembership() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Сложные", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: second.id, included: true, container: container)
        var saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(Set(saved.folderIDs), Set([first.id, second.id]))
        XCTAssertEqual(saved.folderIDs.count, 2)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: false, container: container)
        saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(saved.folderIDs, [second.id])
        XCTAssertEqual(try words(in: container).count, 1)
    }

    @MainActor
    func testDeletingFolderPreservesVocabularyOtherMembershipAndSRS() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: second.id, included: true, container: container)
        try FolderStore.delete(id: first.id, container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(saved.folderIDs, [second.id])
        assertProgress(saved)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).map(\.id), [second.id])
    }

    @MainActor
    func testScanFolderToggleReusesExistingWordAndNeverDeletesProgress() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        _ = try insertWord(in: container)
        XCTAssertTrue(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .other,
                                               folderID: folder.id, container: container))
        var saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(saved.folderIDs, [folder.id])
        XCTAssertEqual(saved.category, .food)
        assertProgress(saved)
        XCTAssertFalse(try ScanWordStore.toggle(source: "вода", translation: "woda", category: .other,
                                                folderID: folder.id, container: container))
        saved = try XCTUnwrap(words(in: container).first)
        XCTAssertTrue(saved.folderIDs.isEmpty)
        assertProgress(saved)
        XCTAssertEqual(try words(in: container).count, 1)
    }

    @MainActor
    func testScanIntoTwoFoldersCreatesOnlyOnePair() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        XCTAssertTrue(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .food,
                                               folderID: first.id, container: container))
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                               folderID: second.id, container: container))
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(Set(saved.folderIDs), Set([first.id, second.id]))
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.russian, "вода")
    }

    @MainActor
    func testMissingFolderDoesNotInsertOrDeleteVocabulary() throws {
        let container = try makeContainer()
        let word = try insertWord(in: container)
        let missingID = UUID()
        XCTAssertThrowsError(try FolderStore.setMembership(wordID: word.persistentModelID, folderID: missingID,
                                                           included: true, container: container))
        XCTAssertThrowsError(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                                      folderID: missingID, container: container))
        XCTAssertThrowsError(try ScanWordStore.toggle(source: "kawa", translation: "кофе", category: .food,
                                                      folderID: missingID, container: container))
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertTrue(try XCTUnwrap(words(in: container).first).folderIDs.isEmpty)
    }

    @MainActor
    func testFolderFilteringIncludesOnlyMembersAndNilIncludesAll() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id, included: true, container: container)
        let context = ModelContext(container)
        context.insert(Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish))
        try context.save()
        let all = try words(in: container)
        XCTAssertEqual(FolderStore.words(all, in: nil).count, 2)
        XCTAssertEqual(FolderStore.words(all, in: folder.id).map(\.polish), ["woda"])
        XCTAssertTrue(FolderStore.words(all, in: UUID()).isEmpty)
    }

    @MainActor
    func testNoFolderRetainsGlobalToggleBehavior() throws {
        let container = try makeContainer()
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertTrue(try XCTUnwrap(words(in: container).first).folderIDs.isEmpty)
        XCTAssertFalse(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
    }

    @MainActor
    func testManualAddReusesExistingPairAndAddsFolderWithoutResettingProgress() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        _ = try insertWord(in: container)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", folderID: folder.id, container: container)
        try ScanWordStore.add(source: "вода", translation: "woda", folderID: folder.id, container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(saved.folderIDs, [folder.id])
        XCTAssertEqual(saved.category, .food)
        assertProgress(saved)
    }

    @MainActor
    func testManualAddOnlyChangesExistingCategoryWhenExplicitlySelected() throws {
        let container = try makeContainer()
        _ = try insertWord(in: container)
        try ScanWordStore.add(source: "woda", translation: "вода", category: .travel, container: container)
        try ScanWordStore.add(source: "woda", translation: "вода", container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(saved.category, .travel)
        assertProgress(saved)
    }

    @MainActor
    func testManualAddCreatesCategorizedPairAndRejectsMissingFolder() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try ScanWordStore.add(source: "woda", translation: "вода", folderID: UUID(), container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.russian, "вода")
        XCTAssertEqual(saved.category, .food)
        XCTAssertTrue(saved.folderIDs.isEmpty)
    }

    @MainActor
    func testCreationImmediatelyAppearsInObservedContextAndPersists() throws {
        let container = try makeContainer()
        let observedContext = ModelContext(container)
        observedContext.autosaveEnabled = false

        let folder = try FolderStore.create(name: "Урок 1", context: observedContext)

        XCTAssertTrue(folder.modelContext === observedContext)
        let visible = try observedContext.fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(visible.map(\.id), [folder.id])
        XCTAssertEqual(visible.first?.name, "Урок 1")
        let persisted = try ModelContext(container).fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(persisted.map(\.id), [folder.id])
    }

    @MainActor
    func testDuplicateNameFailureKeepsUnrelatedPendingWordInsertion() throws {
        let container = try makeContainer()
        let observedContext = ModelContext(container)
        observedContext.autosaveEnabled = false
        _ = try FolderStore.create(name: "Урок 1", context: observedContext)
        let pending = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish)
        observedContext.insert(pending)

        XCTAssertThrowsError(try FolderStore.create(name: " УРОК 1 ", context: observedContext))

        XCTAssertTrue(observedContext.hasChanges)
        XCTAssertTrue(pending.modelContext === observedContext)
        XCTAssertEqual(try observedContext.fetch(FetchDescriptor<Word>()).map(\.polish), ["kawa"])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Word>()).isEmpty)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 1)
    }

    @MainActor
    func testFolderNamesAreUniqueAcrossWhitespaceCaseAndCanonicalUnicode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = try FolderStore.create(name: "Урок 1", context: context)
        XCTAssertThrowsError(try FolderStore.create(name: "  УРОК\n\t  1  ", context: context))
        _ = try FolderStore.create(name: "GÓRA", context: context)
        XCTAssertThrowsError(try FolderStore.create(name: "góra".decomposedStringWithCanonicalMapping, context: context))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 2)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Word.self, WordFolder.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func insertWord(in container: ModelContainer) throws -> Word {
        let context = ModelContext(container)
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        word.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(word)
        try context.save()
        return word
    }

    @MainActor
    private func words(in container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }

    private func assertProgress(_ word: Word, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(word.repetitions, 7, file: file, line: line)
        XCTAssertEqual(word.intervalDays, 14, file: file, line: line)
        XCTAssertEqual(word.easeFactor, 2.8, file: file, line: line)
        XCTAssertEqual(word.dueDate, Date(timeIntervalSince1970: 1_700_000_000), file: file, line: line)
    }
}


extension FolderStoreTests {
    @MainActor
    func testManuallyAddedWordUsesNewlyCreatedFolderInsteadOfOriginalFolder() throws {
        let container = try ModelContainer(for: Word.self, WordFolder.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let original = try FolderStore.create(name: "Урок 1", context: context)
        let created = try FolderStore.create(name: "Урок 2", context: context)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", folderID: created.id, container: container)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(saved.folderIDs, [created.id])
        XCTAssertFalse(saved.folderIDs.contains(original.id))
    }
}
