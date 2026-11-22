import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class ReAddAfterDeleteTests: XCTestCase {
    private let t1 = Date(timeIntervalSince1970: 1_794_225_600)
    private var t2: Date { t1.addingTimeInterval(3_600) }
    private var t3: Date { t1.addingTimeInterval(7_200) }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func rows(_ container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }

    func testReAddInsertsNewRowAndKeepsTombstoneIntact() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок", container: container)
        try ScanWordStore.add(source: "woda", translation: "вода", category: .food, container: container, now: t1)
        let first = try XCTUnwrap(rows(container).first)
        try ScanWordStore.delete(wordID: first.persistentModelID, container: container, now: t2)
        let snapshot = try XCTUnwrap(rows(container).first)
        let (oldUUID, oldCreated, oldUpdated, oldDeleted, oldCategory) =
            (snapshot.uuid, snapshot.createdAt, snapshot.updatedAt, snapshot.deletedAt, snapshot.category)

        try ScanWordStore.add(source: "вода", translation: "woda", category: .travel,
                              folderID: folder.id, container: container, now: t3)

        let all = try rows(container)
        XCTAssertEqual(all.count, 2)
        let old = try XCTUnwrap(all.first { !$0.isActive })
        let fresh = try XCTUnwrap(all.first { $0.isActive })
        XCTAssertEqual(old.uuid, oldUUID)
        XCTAssertEqual(old.createdAt, oldCreated)
        XCTAssertEqual(old.updatedAt, oldUpdated)
        XCTAssertEqual(old.deletedAt, oldDeleted)
        XCTAssertEqual(old.category, oldCategory)
        XCTAssertTrue(try memberFolders(old, container).isEmpty)
        XCTAssertNotEqual(fresh.uuid, oldUUID)
        XCTAssertEqual(fresh.createdAt, t3)
        XCTAssertEqual(fresh.updatedAt, t3)
        XCTAssertEqual(fresh.repetitions, 0)
        XCTAssertEqual(fresh.intervalDays, 0)
        XCTAssertEqual(fresh.category, .travel)
        XCTAssertEqual(try memberFolders(fresh, container), [folder.id])
        XCTAssertEqual(fresh.sourceLanguageCode, "ru")
    }

    func testToggleCyclesLeaveOneTombstonePerRemovalAndOneActiveRow() throws {
        let container = try makeContainer()
        for step in 0..<5 {
            let included = try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                                    container: container, now: t1.addingTimeInterval(Double(step)))
            XCTAssertEqual(included, step % 2 == 0)
        }
        let all = try rows(container)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.filter(\.isActive).count, 1)
        XCTAssertEqual(Set(all.compactMap(\.uuid)).count, 3)
    }

    func testDeleteTwiceAndReAddAffectsOnlyActiveRow() throws {
        let container = try makeContainer()
        for step in 0..<2 {
            try ScanWordStore.add(source: "woda", translation: "вода", container: container,
                                  now: t1.addingTimeInterval(Double(step * 10)))
            let active = try XCTUnwrap(rows(container).first { $0.isActive })
            try ScanWordStore.delete(wordID: active.persistentModelID, container: container,
                                     now: t1.addingTimeInterval(Double(step * 10 + 5)))
        }
        XCTAssertThrowsError(try ScanWordStore.delete(wordID: try XCTUnwrap(rows(container).first).persistentModelID,
                                                      container: container))
        try ScanWordStore.add(source: "woda", translation: "вода", category: .food, container: container, now: t3)
        let before = try rows(container).filter { !$0.isActive }.map { ($0.uuid, $0.category, $0.updatedAt) }

        try ScanWordStore.changeCategory(.home, source: "woda", translation: "вода", container: container, now: t3)

        let all = try rows(container)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.filter(\.isActive).map(\.category), [.home])
        let after = all.filter { !$0.isActive }.map { ($0.uuid, $0.category, $0.updatedAt) }
        XCTAssertEqual(before.count, after.count)
        for entry in before {
            XCTAssertTrue(after.contains { $0.0 == entry.0 && $0.1 == entry.1 && $0.2 == entry.2 })
        }
    }

    func testDailyActivityForReAddedWordStartsClean() throws {
        for isQuiz in [false, true] {
            let suite = "ReAddAfterDeleteTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
            let container = try makeContainer()
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: t1)

            try ScanWordStore.add(source: "woda", translation: "вода", container: container, now: t1)
            let context = ModelContext(container)
            let word = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first)
            if isQuiz {
                try store.recordPracticeAnswer(word: word, answer: .typed(expected: "woda", submitted: "xxxx"),
                                               context: context, mode: .quiz, now: t1)
            } else {
                try store.review(.again, to: word, context: context, now: t1)
            }
            XCTAssertEqual(store.answerTotals(for: [word], now: t1).total, 1)

            try ScanWordStore.delete(wordID: word.persistentModelID, container: container, now: t2)
            try ScanWordStore.add(source: "woda", translation: "вода", container: container, now: t3)

            let fresh = try ModelContext(container).fetch(FetchDescriptor<Word>())
            XCTAssertEqual(fresh.count, 2)
            let reAdded = try XCTUnwrap(fresh.first { $0.isActive })
            XCTAssertEqual(store.reviewWords(for: fresh, now: t3).map(\.persistentModelID), [reAdded.persistentModelID])
            XCTAssertEqual(store.progress(for: fresh, now: t3), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.answerTotals(for: fresh, now: t3), .init(correct: 0, incorrect: 0))
        }
    }
}
