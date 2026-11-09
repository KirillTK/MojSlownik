import XCTest
import SwiftData
@testable import MojSlownik

final class FolderPersistenceTests: XCTestCase {
    @MainActor
    func testFolderCatalogAndVocabularySurviveClosingAndReopeningDiskStore() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictionary.store")
        let id = try autoreleasepool { try createSavedLibrary(at: url) }

        try autoreleasepool {
            let container = try makeContainer(at: url)
            let library = FolderLibraryStore()
            try library.load(context: container.mainContext)
            XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
            let words = try container.mainContext.fetch(FetchDescriptor<Word>())
            XCTAssertEqual(words.count, 2)
            let member = try XCTUnwrap(words.first { $0.polish == "woda" })
            XCTAssertEqual(member.russian, "вода")
            XCTAssertEqual(member.folderIDs, [id])
            XCTAssertEqual(member.repetitions, 7)
            XCTAssertEqual(member.intervalDays, 14)
            XCTAssertEqual(member.easeFactor, 2.8)
            XCTAssertEqual(member.dueDate, Date(timeIntervalSince1970: 1_700_000_000))
            let other = try XCTUnwrap(words.first { $0.polish == "kawa" })
            XCTAssertTrue(other.folderIDs.isEmpty)
        }
    }

    @MainActor
    func testFolderNameUniquenessIsEnforcedAfterDiskStoreReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictionary.store")
        let id = try autoreleasepool { try createSavedLibrary(at: url) }

        try autoreleasepool {
            let container = try makeContainer(at: url)
            let library = FolderLibraryStore()
            try library.load(context: container.mainContext)
            XCTAssertThrowsError(try library.create(name: " УРОК\n 1 ", context: container.mainContext))
            XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<WordFolder>()).count, 1)
        }
    }

    @MainActor
    private func createSavedLibrary(at url: URL) throws -> UUID {
        let container = try makeContainer(at: url)
        let context = container.mainContext
        let library = FolderLibraryStore()
        let id = try library.create(name: "Урок 1", context: context)
        XCTAssertEqual(library.options, [.init(id: id, name: "Урок 1")])
        let word = Word(russian: "ВОДА", polish: "WODA", sourceLanguage: .polish)
        word.folderIDs = [id]
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        word.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(word)
        context.insert(Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish))
        try context.save()
        return id
    }

    @MainActor
    private func makeContainer(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: Word.self, WordFolder.self,
                           configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
    }
}
