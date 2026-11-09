import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class DailyStudyStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_225_600)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    func testEmptyAndUnreviewedWordsDoNotInventCompletion() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(2)
            _ = container
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(store.progress(for: [], now: now), .init(completed: 0, remaining: 0))
            XCTAssertEqual(store.progress(for: [], now: now).fraction, 0)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 2))
            words.forEach { $0.dueDate = now.addingTimeInterval(86_400) }
            XCTAssertEqual(store.progress(for: words, now: now).fraction, 0)
        }
    }

    func testSuccessfulReviewsAreUniqueAndSurviveStoreAndModelReload() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(2)
            let context = container.mainContext
            let wordID = words[0].persistentModelID
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: context, now: now)
            try store.record(wordID: wordID, grade: .good, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(store.progress(for: words, now: now).fraction, 0.5)

            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            let freshContext = ModelContext(container)
            let freshWords = try freshContext.fetch(FetchDescriptor<Word>())
            XCTAssertTrue(freshWords.contains { $0.persistentModelID == wordID })
            XCTAssertEqual(reloaded.progress(for: freshWords, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(freshWords.first { $0.persistentModelID == wordID }?.repetitions, 1)
        }
    }

    func testAgainRemainsPendingDuringDelayAndAcrossReloadUntilSuccessfulReview() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: container.mainContext, now: now)
            XCTAssertEqual(store.progress(for: words, now: now).fraction, 1)
            try store.review(.again, to: words[0], context: container.mainContext, now: now)
            XCTAssertGreaterThan(words[0].dueDate, now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.reviewWords(for: words, now: now).map(\.persistentModelID), words.map(\.persistentModelID))

            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(reloaded.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            try reloaded.review(.hard, to: words[0], context: container.mainContext, now: now)
            XCTAssertEqual(reloaded.progress(for: words, now: now), .init(completed: 1, remaining: 0))
            XCTAssertTrue(reloaded.reviewWords(for: words, now: now).isEmpty)
        }
    }

    func testCurrentlyDueWordOverridesAnEarlierSuccessfulRecord() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            _ = container
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.record(wordID: words[0].persistentModelID, grade: .good, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            words[0].dueDate = now.addingTimeInterval(60)
            XCTAssertEqual(store.progress(for: words, now: now).completed, 1)
            XCTAssertEqual(store.progress(for: words, now: now.addingTimeInterval(60)).remaining, 1)
            XCTAssertEqual(store.progress(for: words, now: now.addingTimeInterval(60)).completed, 0)
        }
    }

    func testFolderScopeDeletionAndNewDueWordsUseCurrentVocabulary() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(3)
            let folderID = UUID()
            words[0].folderIDs = [folderID]
            words[1].folderIDs = [folderID]
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: container.mainContext, now: now)
            try store.review(.good, to: words[2], context: container.mainContext, now: now)
            let scoped = FolderStore.words(words, in: folderID)
            XCTAssertEqual(store.progress(for: scoped, now: now), .init(completed: 1, remaining: 1))
            // Deleted words and moved memberships disappear from the supplied live scope.
            XCTAssertEqual(store.progress(for: [words[1]], now: now), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.progress(for: FolderStore.words(words, in: UUID()), now: now).total, 0)
            let added = Word(russian: "новое", polish: "nowe", sourceLanguage: .polish, createdAt: now)
            container.mainContext.insert(added)
            try container.mainContext.save()
            XCTAssertEqual(store.progress(for: words + [added], now: now), .init(completed: 2, remaining: 2))
        }
    }

    func testMidnightResetsCompletedAndPendingWithoutMutatingDuringProgressRead() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(2)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: container.mainContext, now: now)
            try store.review(.again, to: words[1], context: container.mainContext, now: now)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            words.forEach { $0.dueDate = tomorrow.addingTimeInterval(3_600) }
            XCTAssertEqual(store.progress(for: words, now: tomorrow), .init(completed: 0, remaining: 0))
            // A read at tomorrow did not erase today's stored activity.
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 1))
            store.refresh(now: tomorrow)
            XCTAssertEqual(store.progress(for: words, now: tomorrow).total, 0)
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: tomorrow)
            XCTAssertEqual(reloaded.progress(for: words, now: tomorrow).total, 0)
            try reloaded.record(wordID: words[1].persistentModelID, grade: .easy, now: tomorrow)
            XCTAssertEqual(reloaded.progress(for: words, now: tomorrow).completed, 1)
        }
    }

    func testDayBoundaryUsesTheInjectedLocalCalendar() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            _ = container
            let formatter = ISO8601DateFormatter()
            let before = formatter.date(from: "2026-11-09T22:30:00Z")!
            let after = formatter.date(from: "2026-11-09T23:30:00Z")!
            words[0].dueDate = after.addingTimeInterval(86_400)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: before)
            try store.record(wordID: words[0].persistentModelID, grade: .good, now: before)
            XCTAssertEqual(store.progress(for: words, now: after).completed, 0)
            var utc = calendar
            utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let utcStore = DailyStudyStore(defaults: defaults, calendar: utc, now: after)
            XCTAssertEqual(utcStore.progress(for: words, now: after).completed, 1)
        }
    }

    func testUnreadableActivityStartsSafelyWithoutChangingVocabulary() throws {
        try withDefaults { defaults in
            defaults.set(Data("invalid".utf8), forKey: "dailyStudyActivity.v1")
            let (container, words) = try makeWords(1)
            _ = container
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            XCTAssertEqual(words[0].repetitions, 0)
        }
    }

    func testPartialQuizPersistsSixSuccessfulWordsOutOfEighteenWithoutChangingSRS() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(18)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            for (index, word) in words.prefix(8).enumerated() {
                try store.recordQuizAnswer(wordID: word.persistentModelID, isCorrect: index < 6, now: now)
            }
            // No session-finish action is needed before recreating the store and model context.
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            let context = ModelContext(container)
            let freshWords = try context.fetch(FetchDescriptor<Word>())
            XCTAssertEqual(reloaded.progress(for: freshWords, now: now), .init(completed: 6, remaining: 12))
            XCTAssertEqual(reloaded.answerTotals(for: freshWords, now: now), .init(correct: 6, incorrect: 2))
            for word in freshWords {
                XCTAssertEqual(word.repetitions, 0)
                XCTAssertEqual(word.intervalDays, 0)
                XCTAssertEqual(word.easeFactor, 2.5)
                XCTAssertEqual(word.dueDate, now)
            }
        }
    }

    func testRepeatedQuizAnswersCountAttemptsButOnlyOneCompletedWord() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            _ = container
            var store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            let id = words[0].persistentModelID
            try store.recordQuizAnswer(wordID: id, isCorrect: true, now: now)
            store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.recordQuizAnswer(wordID: id, isCorrect: true, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 0))
            try store.recordQuizAnswer(wordID: id, isCorrect: false, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.recordQuizAnswer(wordID: id, isCorrect: true, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 0))
            XCTAssertEqual(store.answerTotals(for: words, now: now), .init(correct: 3, incorrect: 1))
            XCTAssertEqual(store.answerTotals(for: words, now: now).total, 4)
        }
    }

    func testLatestAnswersReopenAndCompleteWordsAcrossBothPracticeModes() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            let word = words[0]
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.recordQuizAnswer(wordID: word.persistentModelID, isCorrect: true, now: now)
            try store.review(.again, to: word, context: container.mainContext, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            try store.recordQuizAnswer(wordID: word.persistentModelID, isCorrect: true, now: now)
            XCTAssertTrue(store.reviewWords(for: words, now: now).isEmpty)
            try store.review(.good, to: word, context: container.mainContext, now: now)
            XCTAssertEqual(store.progress(for: words, now: now).completed, 1)
            try store.recordQuizAnswer(wordID: word.persistentModelID, isCorrect: false, now: now)
            XCTAssertGreaterThan(word.dueDate, now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.reviewWords(for: words, now: now).map(\.persistentModelID), [word.persistentModelID])
            XCTAssertEqual(store.answerTotals(for: words, now: now), .init(correct: 3, incorrect: 2))
        }
    }

    func testLegacyDailyActivityKeepsCompletionAndPendingWithoutInventingAnswerHistory() throws {
        struct LegacyActivity: Codable {
            let day: Date
            let completedIDs: Set<PersistentIdentifier>
            let pendingIDs: Set<PersistentIdentifier>
        }
        try withDefaults { defaults in
            let (container, words) = try makeWords(2)
            _ = container
            words.forEach { $0.dueDate = now.addingTimeInterval(3_600) }
            let old = LegacyActivity(day: now, completedIDs: [words[0].persistentModelID],
                                     pendingIDs: [words[1].persistentModelID])
            defaults.set(try JSONEncoder().encode(old), forKey: "dailyStudyActivity.v1")
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(store.answerTotals(for: words, now: now).total, 0)
            try store.recordQuizAnswer(wordID: words[1].persistentModelID, isCorrect: true, now: now)
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(reloaded.progress(for: words, now: now), .init(completed: 2, remaining: 0))
            XCTAssertEqual(reloaded.answerTotals(for: words, now: now), .init(correct: 1, incorrect: 0))
        }
    }

    func testQuizStatisticsFollowCurrentFolderAndDeletionScopeAndResetNextDay() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(3)
            _ = container
            let folderID = UUID()
            words[0].folderIDs = [folderID]
            words[1].folderIDs = [folderID]
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.recordQuizAnswer(wordID: words[0].persistentModelID, isCorrect: true, now: now)
            try store.recordQuizAnswer(wordID: words[1].persistentModelID, isCorrect: false, now: now)
            try store.recordQuizAnswer(wordID: words[2].persistentModelID, isCorrect: true, now: now)
            let scoped = FolderStore.words(words, in: folderID)
            XCTAssertEqual(store.answerTotals(for: scoped, now: now), .init(correct: 1, incorrect: 1))
            XCTAssertEqual(store.answerTotals(for: [words[1]], now: now), .init(correct: 0, incorrect: 1))
            XCTAssertEqual(store.answerTotals(for: [], now: now).total, 0)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            XCTAssertEqual(store.answerTotals(for: words, now: tomorrow).total, 0)
            XCTAssertEqual(store.progress(for: words, now: tomorrow), .init(completed: 0, remaining: 3))
            store.refresh(now: tomorrow)
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: tomorrow)
            XCTAssertEqual(reloaded.answerTotals(for: words, now: tomorrow).total, 0)
            try reloaded.recordQuizAnswer(wordID: words[0].persistentModelID, isCorrect: true, now: tomorrow)
            XCTAssertEqual(reloaded.answerTotals(for: words, now: tomorrow).total, 1)
        }
    }

    private func makeWords(_ count: Int) throws -> (ModelContainer, [Word]) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Word.self, WordFolder.self, configurations: configuration)
        let words = (0..<count).map { index in
            Word(russian: "слово \(index)", polish: "słowo \(index)", sourceLanguage: .polish, createdAt: now)
        }
        words.forEach { container.mainContext.insert($0) }
        try container.mainContext.save()
        return (container, words)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "DailyStudyStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
}
