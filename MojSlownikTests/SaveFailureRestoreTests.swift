import XCTest
import SwiftData
@testable import MojSlownik

/// Forces real failing saves by reopening an on-disk store with `allowsSave: false`
/// (public ModelConfiguration option; no production hooks involved).
@MainActor
final class SaveFailureRestoreTests: XCTestCase {
    private var directory: URL!
    private let t0 = Date(timeIntervalSince1970: 1_794_225_600)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Seeds a store, then returns a container over it that rejects saves.
    private func readOnlyContainer() throws -> ModelContainer {
        let url = directory.appendingPathComponent("dictionary.store")
        try autoreleasepool {
            let container = try ModelContainer(for: AppSchema.schema,
                                               configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(Word(russian: "вода", polish: "woda", side: .term, createdAt: t0,
                                category: .food))
            context.insert(WordFolder(name: "Урок"))
            try context.save()
        }
        return try ModelContainer(for: AppSchema.schema,
                                  configurations: ModelConfiguration(url: url, allowsSave: false,
                                                                     cloudKitDatabase: .none))
    }

    func testReviewRestoresFieldsAndUpdatedAtWhenSaveFails() throws {
        let container = try readOnlyContainer()
        let context = container.mainContext
        let word = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first)
        let before = (word.repetitions, word.intervalDays, word.dueDate, word.updatedAt, word.knowledgeTier)
        let suite = "SaveFailureRestoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyStudyStore(defaults: defaults, now: t0)

        XCTAssertThrowsError(try store.review(.good, to: word, context: context, now: t0.addingTimeInterval(60)))

        XCTAssertEqual(word.repetitions, before.0)
        XCTAssertEqual(word.intervalDays, before.1)
        XCTAssertEqual(word.dueDate, before.2)
        XCTAssertEqual(word.updatedAt, before.3)
        XCTAssertEqual(word.knowledgeTier, before.4)
        XCTAssertNil(defaults.data(forKey: "dailyStudyActivity.v1"))
    }

    func testSetCategoryRestoresCategoryAndUpdatedAtWhenSaveFails() throws {
        let container = try readOnlyContainer()
        let word = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Word>()).first)
        let id = try XCTUnwrap(word.uuid)
        let repo = SwiftDataVocabularyRepository(container: container, now: { self.t0.addingTimeInterval(60) })

        XCTAssertThrowsError(try repo.setCategory(.travel, wordID: id))

        XCTAssertEqual(word.category, .food)
        XCTAssertEqual(word.updatedAt, t0)
    }

    func testRenameRestoresNameAndUpdatedAtWhenSaveFails() throws {
        let container = try readOnlyContainer()
        let folder = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<WordFolder>()).first)
        let originalUpdatedAt = folder.updatedAt
        let repo = SwiftDataFolderRepository(container: container, now: { self.t0.addingTimeInterval(60) })

        XCTAssertThrowsError(try repo.renameFolder(id: folder.id, name: "Другое"))

        XCTAssertEqual(folder.name, "Урок")
        XCTAssertEqual(folder.updatedAt, originalUpdatedAt)
    }
}
