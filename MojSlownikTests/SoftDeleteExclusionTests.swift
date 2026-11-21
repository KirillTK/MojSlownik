import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class SoftDeleteExclusionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_225_600)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func tombstone(_ polish: String = "woda", russian: String = "вода") -> Word {
        let word = Word(russian: russian, polish: polish, sourceLanguage: .polish, createdAt: now,
                        category: .food)
        word.repetitions = 5
        word.markDeleted(now: now.addingTimeInterval(10))
        return word
    }

    func testFolderStoreWordsExcludesTombstones() {
        let folderID = UUID()
        let active = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish)
        active.folderIDs = [folderID]
        let deleted = tombstone()
        deleted.folderIDs = [folderID]
        XCTAssertEqual(FolderStore.words([active, deleted], in: nil).map(\.polish), ["kawa"])
        XCTAssertEqual(FolderStore.words([active, deleted], in: folderID).map(\.polish), ["kawa"])
    }

    func testAchievementMetricsIgnoreTombstones() {
        let deleted = tombstone()
        deleted.repetitions = 9
        let metrics = AchievementMetrics.vocabulary(words: [deleted], folderCount: 0)
        XCTAssertEqual(metrics[.wordCount], 0)
        XCTAssertEqual(metrics[.categoriesCovered], 0)
        XCTAssertEqual(metrics[.learnedWords], 0)
    }

    func testDailyStudyIgnoresDueTombstone() throws {
        let suite = "SoftDeleteExclusionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try makeContainer()
        let context = container.mainContext
        let active = Word(russian: "кофе", polish: "kawa", sourceLanguage: .polish, createdAt: now)
        let deleted = tombstone()
        context.insert(active)
        context.insert(deleted)
        try context.save()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
        try store.recordQuizAnswer(wordID: deleted.persistentModelID, isCorrect: false, now: now)

        XCTAssertEqual(store.progress(for: [active, deleted], now: now), .init(completed: 0, remaining: 1))
        XCTAssertEqual(store.reviewWords(for: [active, deleted], now: now).map(\.polish), ["kawa"])
        XCTAssertEqual(store.answerTotals(for: [active, deleted], now: now), .init(correct: 0, incorrect: 0))
    }

    func testFolderCatalogAndNameCheckIgnoreDeletedFolders() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок", container: container)
        try FolderStore.delete(id: folder.id, container: container)
        let context = ModelContext(container)
        XCTAssertTrue(try FolderStore.folders(in: context).isEmpty)
        XCTAssertThrowsError(try FolderStore.requireFolder(folder.id, in: context))
        XCTAssertNoThrow(try FolderStore.create(name: "урок", container: container))
        XCTAssertThrowsError(try FolderStore.rename(id: folder.id, name: "Другое", context: context))
    }

    func testChangeCategoryDoesNotModifyTombstone() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let deleted = tombstone()
        context.insert(deleted)
        try context.save()

        try ScanWordStore.changeCategory(.travel, source: "woda", translation: "вода", container: container)

        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(saved.category, .food)
        XCTAssertEqual(saved.updatedAt, now.addingTimeInterval(10))
    }

    func testFolderToggleOnTombstoneInsertsNewRowAndLeavesTombstoneUntouched() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок", container: container)
        let context = ModelContext(container)
        let deleted = tombstone()
        let deletedUUID = deleted.uuid
        context.insert(deleted)
        try context.save()

        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                               folderID: folder.id, container: container))

        let rows = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(rows.count, 2)
        let old = try XCTUnwrap(rows.first { !$0.isActive })
        let fresh = try XCTUnwrap(rows.first { $0.isActive })
        XCTAssertEqual(fresh.folderIDs, [folder.id])
        XCTAssertNotEqual(fresh.uuid, deletedUUID)
        XCTAssertEqual(old.uuid, deletedUUID)
        XCTAssertTrue(old.folderIDs.isEmpty)
        XCTAssertEqual(old.repetitions, 5)
        XCTAssertEqual(old.deletedAt, now.addingTimeInterval(10))
    }
}
