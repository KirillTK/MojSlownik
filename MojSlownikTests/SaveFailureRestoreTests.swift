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

    func testReviewRestoresLapseCountWhenSaveFails() throws {
        let container = try readOnlyContainer()
        let word = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Word>()).first)
        word.repetitions = 3
        word.intervalDays = 8
        word.lapseCount = 2
        let before = SRSState(word: word)
        let suite = "SaveFailureRestoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DailyStudyStore(defaults: defaults, now: t0)

        XCTAssertThrowsError(try store.review(.again, to: word, context: container.mainContext,
                                              now: t0.addingTimeInterval(60)))

        XCTAssertEqual(SRSState(word: word), before)
        XCTAssertEqual(word.lapseCount, 2)
    }

    func testPracticeAnswerRestoresScheduleLapseAndTierWhenSaveFails() throws {
        let container = try readOnlyContainer()
        let word = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Word>()).first)
        word.repetitions = 3
        word.intervalDays = 8
        word.dueDate = t0
        word.lapseCount = 2
        word.knowledgeTier = 2
        let before = SRSState(word: word)
        let updatedAt = word.updatedAt
        let repository = InMemoryDailyActivityRepository()
        let store = DailyStudyStore(repository: repository, now: t0)

        XCTAssertThrowsError(try store.recordPracticeAnswer(
            word: word, answer: .choice(isCorrect: false), context: container.mainContext, mode: .quiz,
            now: t0.addingTimeInterval(60)))

        XCTAssertEqual(SRSState(word: word), before)
        XCTAssertEqual(word.knowledgeTier, 2)
        XCTAssertEqual(word.updatedAt, updatedAt)
        XCTAssertNil(repository.stored, "no activity is published when the save fails")
    }

    /// Nothing reached the store (a fresh context sees no entry) and nothing is left pending in the
    /// context, so no later successful save can persist a phantom entry. The failing context itself
    /// may still return the dropped object from a fetch on iOS 26, so it is not asserted.
    private func assertNoPendingLogEntry(in context: ModelContext, container: ModelContainer, line: UInt = #line) {
        XCTAssertTrue(((try? ModelContext(container).fetch(FetchDescriptor<ReviewLogEntry>())) ?? []).isEmpty,
                      "persisted", line: line)
        XCTAssertFalse(context.insertedModelsArray.contains { $0 is ReviewLogEntry }, "still pending", line: line)
    }

    func testFailedReviewSaveLeavesNoLogEntryAndRestoresTheFSRSFields() throws {
        let container = try readOnlyContainer()
        let context = container.mainContext
        let word = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first)
        word.fsrsStateRawValue = 2
        word.fsrsStability = 6
        word.fsrsDifficulty = 5
        word.fsrsLastReviewedAt = t0.addingTimeInterval(-86_400)
        word.repetitions = 2
        word.intervalDays = 6
        word.dueDate = t0
        let before = SRSState(word: word)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), now: t0)

        XCTAssertThrowsError(try store.review(.good, to: word, context: context, now: t0.addingTimeInterval(60)))
        XCTAssertEqual(SRSState(word: word), before, "every FSRS field is restored")
        assertNoPendingLogEntry(in: context, container: container)

        XCTAssertThrowsError(try store.recordPracticeAnswer(
            word: word, answer: .choice(isCorrect: false), context: context, mode: .quiz,
            now: t0.addingTimeInterval(60)))
        XCTAssertEqual(SRSState(word: word), before)
        assertNoPendingLogEntry(in: context, container: container)
        // A non-scheduling answer that fails to save leaves no entry either.
        word.dueDate = t0.addingTimeInterval(86_400)
        XCTAssertThrowsError(try store.recordPracticeAnswer(
            word: word, answer: .choice(isCorrect: true), context: context, mode: .quiz,
            now: t0.addingTimeInterval(60)))
        assertNoPendingLogEntry(in: context, container: container)
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
