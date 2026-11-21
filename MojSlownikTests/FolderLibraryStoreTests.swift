import XCTest
import Observation
import SwiftData
@testable import MojSlownik

final class FolderLibraryStoreTests: XCTestCase {
    @MainActor
    func testCreatingFolderPublishesOptionsToOtherConsumerWithoutReload() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        let dictionaryConsumer = library
        let trainingConsumer = library
        let changed = expectation(description: "Other screen observes the shared catalog")
        withObservationTracking {
            _ = trainingConsumer.options
        } onChange: {
            changed.fulfill()
        }

        let id = try dictionaryConsumer.create(name: " Урок 1 ")

        XCTAssertTrue(dictionaryConsumer === trainingConsumer)
        XCTAssertEqual(trainingConsumer.options, [.init(id: id, name: "Урок 1")])
        wait(for: [changed], timeout: 1)
    }

    @MainActor
    func testNewStoreRestoresPreviouslyCreatedFoldersAfterReload() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        let id = try library.create(name: "Урок 1")
        let persisted = try FolderStore.folders(in: ModelContext(container))
        XCTAssertEqual(persisted.map(\.id), [id])
        let relaunched = makeLibrary(container)
        try relaunched.load()
        XCTAssertEqual(relaunched.options, [.init(id: id, name: "Урок 1")])
    }

    @MainActor
    func testDuplicateCreationDoesNotChangeSharedOptions() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        let id = try library.create(name: "Урок 1")
        XCTAssertThrowsError(try library.create(name: "  УРОК\n 1 "))
        XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
    }

    @MainActor
    func testDeletionUpdatesAllConsumersAndPreservesWordAndProgress() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        let anotherConsumer = library
        let id = try library.create(name: "Урок 1")
        let context = ModelContext(container)
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.folderIDs = [id]
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        let dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        word.dueDate = dueDate
        context.insert(word)
        try context.save()

        try library.delete(id: id)

        XCTAssertTrue(anotherConsumer.options.isEmpty)
        let readingContext = ModelContext(container)
        let saved = try XCTUnwrap(readingContext.fetch(FetchDescriptor<Word>()).first)
        XCTAssertTrue(saved.folderIDs.isEmpty)
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.repetitions, 7)
        XCTAssertEqual(saved.intervalDays, 14)
        XCTAssertEqual(saved.easeFactor, 2.8)
        XCTAssertEqual(saved.dueDate, dueDate)
        XCTAssertTrue(try readingContext.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive).isEmpty)
    }

    @MainActor
    func testReloadUpdatesCatalogWhenPersistedFoldersChange() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        _ = try library.create(name: "Урок 1")
        let context = container.mainContext
        let folder = try XCTUnwrap(context.fetch(FetchDescriptor<WordFolder>()).first)
        context.delete(folder)
        try context.save()
        try library.load()
        XCTAssertTrue(library.options.isEmpty)
    }

    @MainActor
    func testRenameAndReorderPublishSharedCatalogAndPersistAfterReload() throws {
        let container = try makeContainer()
        let library = makeLibrary(container)
        let first = try library.create(name: "Урок 1")
        let second = try library.create(name: "Урок 2")

        try library.rename(id: first, name: "Первый урок")
        try library.reorder(ids: [second, first])

        XCTAssertEqual(library.options, [
            .init(id: second, name: "Урок 2"),
            .init(id: first, name: "Первый урок")
        ])
        let persisted = try FolderStore.folders(in: ModelContext(container))
        XCTAssertEqual(persisted.map(\.id), [second, first])
        XCTAssertEqual(persisted.map(\.name), ["Урок 2", "Первый урок"])
        let relaunched = makeLibrary(container)
        try relaunched.load()
        XCTAssertEqual(relaunched.options, library.options)
    }

    @MainActor
    func testStoreWorksOverInMemoryFakeRepository() throws {
        let fake = InMemoryFolderRepository()
        let library = FolderLibraryStore.inLegacyWorkspace(repository: fake)
        let id = try library.create(name: " Урок 1 ")
        XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
        fake.nextError = RepositoryFakeError.forced
        XCTAssertThrowsError(try library.rename(id: id, name: "Другое"))
        XCTAssertEqual(library.options.map(\.name), ["Урок 1"])
        try library.delete(id: id)
        XCTAssertTrue(library.options.isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func makeLibrary(_ container: ModelContainer) -> FolderLibraryStore {
        FolderLibraryStore.inLegacyWorkspace(repository: SwiftDataFolderRepository(container: container))
    }

    @MainActor
    func testChangeSignalFiresAfterSuccessfulWritesOnly() throws {
        let fake = InMemoryFolderRepository()
        let signal = LocalChangeSignal()
        var fired = 0
        signal.handler = { fired += 1 }
        let library = FolderLibraryStore.inLegacyWorkspace(repository: fake, changeSignal: signal)

        let first = try library.create(name: "Урок 1")
        let second = try library.create(name: "Урок 2")
        try library.rename(id: first, name: "Урок 3")
        try library.reorder(ids: [second, first])
        try library.delete(id: second)
        XCTAssertEqual(fired, 5)

        fake.nextError = RepositoryFakeError.forced
        XCTAssertThrowsError(try library.create(name: "Другое"))
        fake.nextError = RepositoryFakeError.forced
        XCTAssertThrowsError(try library.delete(id: first))
        XCTAssertEqual(fired, 5)
    }
}
