import XCTest
import Observation
import SwiftData
@testable import MojSlownik

final class FolderLibraryStoreTests: XCTestCase {
    @MainActor
    func testCreatingFolderPublishesOptionsToOtherConsumerWithoutReload() throws {
        let context = try makeContext()
        let library = FolderLibraryStore()
        let dictionaryConsumer = library
        let trainingConsumer = library
        let changed = expectation(description: "Other screen observes the shared catalog")
        withObservationTracking {
            _ = trainingConsumer.options
        } onChange: {
            changed.fulfill()
        }

        let id = try dictionaryConsumer.create(name: " Урок 1 ", context: context)

        XCTAssertTrue(dictionaryConsumer === trainingConsumer)
        XCTAssertEqual(trainingConsumer.options, [.init(id: id, name: "Урок 1")])
        wait(for: [changed], timeout: 1)
    }

    @MainActor
    func testNewStoreRestoresPreviouslyCreatedFoldersAfterReload() throws {
        let context = try makeContext()
        let library = FolderLibraryStore()
        let id = try library.create(name: "Урок 1", context: context)
        let relaunched = FolderLibraryStore()
        try relaunched.load(context: ModelContext(context.container))
        XCTAssertEqual(relaunched.options, [.init(id: id, name: "Урок 1")])
    }

    @MainActor
    func testDuplicateCreationDoesNotChangeSharedOptions() throws {
        let context = try makeContext()
        let library = FolderLibraryStore()
        let id = try library.create(name: "Урок 1", context: context)
        XCTAssertThrowsError(try library.create(name: "  УРОК\n 1 ", context: context))
        XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
    }

    @MainActor
    func testDeletionUpdatesAllConsumersAndPreservesWordAndProgress() throws {
        let context = try makeContext()
        let library = FolderLibraryStore()
        let anotherConsumer = library
        let id = try library.create(name: "Урок 1", context: context)
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.folderIDs = [id]
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        word.dueDate = dueDate
        context.insert(word)
        try context.save()

        try library.delete(id: id, context: context)

        XCTAssertTrue(anotherConsumer.options.isEmpty)
        let readingContext = ModelContext(context.container)
        let saved = try XCTUnwrap(readingContext.fetch(FetchDescriptor<Word>()).first)
        XCTAssertTrue(saved.folderIDs.isEmpty)
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.repetitions, 7)
        XCTAssertEqual(saved.intervalDays, 14)
        XCTAssertEqual(saved.easeFactor, 2.8)
        XCTAssertEqual(saved.dueDate, dueDate)
        XCTAssertTrue(try readingContext.fetch(FetchDescriptor<WordFolder>()).isEmpty)
    }

    @MainActor
    func testReloadUpdatesCatalogWhenPersistedFoldersChange() throws {
        let context = try makeContext()
        let library = FolderLibraryStore()
        _ = try library.create(name: "Урок 1", context: context)
        let folder = try XCTUnwrap(context.fetch(FetchDescriptor<WordFolder>()).first)
        context.delete(folder)
        try context.save()
        try library.load(context: context)
        XCTAssertTrue(library.options.isEmpty)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(for: Word.self, WordFolder.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
}
