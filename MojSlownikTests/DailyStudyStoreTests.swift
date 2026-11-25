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
            XCTAssertEqual(words[0].knowledgeTier, 2)
            try store.record(wordID: wordID, grade: .good, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(store.progress(for: words, now: now).fraction, 0.5)

            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            let freshContext = ModelContext(container)
            let freshWords = try freshContext.fetch(FetchDescriptor<Word>())
            XCTAssertTrue(freshWords.contains { $0.persistentModelID == wordID })
            XCTAssertEqual(reloaded.progress(for: freshWords, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(freshWords.first { $0.persistentModelID == wordID }?.repetitions, 1)
            XCTAssertEqual(freshWords.first { $0.persistentModelID == wordID }?.knowledgeTier, 2)
        }
    }

    func testPracticeAnswerPersistsConfidenceAndSoftMissesWithoutChangingSRS() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            let word = words[0]
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            word.knowledgeTier = 3
            let originalEase = word.easeFactor
            let originalInterval = word.intervalDays
            let originalRepetitions = word.repetitions
            let originalDueDate = word.dueDate

            try store.recordPracticeAnswer(word: word,
                                          answer: .typed(expected: "słowo", submitted: "słowx"),
                                          context: container.mainContext, mode: .flashcards, now: now)

            XCTAssertEqual(word.consecutiveSoftMisses, 1)
            XCTAssertEqual(word.knowledgeTier, 3)
            XCTAssertEqual(word.easeFactor, originalEase)
            XCTAssertEqual(word.intervalDays, originalInterval)
            XCTAssertEqual(word.repetitions, originalRepetitions)
            XCTAssertEqual(word.dueDate, originalDueDate)
            XCTAssertEqual(store.answerTotals(for: words, now: now), .init(correct: 0, incorrect: 1))

            let reloadedContext = ModelContext(container)
            let reloadedWord = try XCTUnwrap(reloadedContext.fetch(FetchDescriptor<Word>()).first)
            XCTAssertEqual(reloadedWord.consecutiveSoftMisses, 1)
            try store.recordPracticeAnswer(word: reloadedWord,
                                          answer: .typed(expected: "słowo", submitted: "słowx"),
                                          context: reloadedContext, mode: .flashcards, now: now)
            XCTAssertEqual(reloadedWord.consecutiveSoftMisses, 0)
            XCTAssertEqual(reloadedWord.knowledgeTier, 2)
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

    func testASuccessExemptsADueWordUntilTheNextDayAndPendingWins() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            _ = container
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            try store.record(wordID: words[0].persistentModelID, grade: .good, now: now)
            // Due again a minute later (FSRS may do that) but already answered correctly today.
            words[0].dueDate = now.addingTimeInterval(60)
            let later = now.addingTimeInterval(120)
            XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 1, remaining: 0))
            XCTAssertTrue(store.reviewWords(for: words, now: later).isEmpty)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            XCTAssertEqual(store.progress(for: words, now: tomorrow), .init(completed: 0, remaining: 1))
            // "Again" removes the completion and keeps the word pending.
            try store.record(wordID: words[0].persistentModelID, grade: .again, now: later)
            XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.reviewWords(for: words, now: later).count, 1)
        }
    }

    func testFolderScopeDeletionAndNewDueWordsUseCurrentVocabulary() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(3)
            let folderID = UUID()
            let index = MembershipIndex.linking([words[0], words[1]], to: folderID)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: container.mainContext, now: now)
            try store.review(.good, to: words[2], context: container.mainContext, now: now)
            let scoped = FolderStore.words(words, in: folderID, memberships: index)
            XCTAssertEqual(store.progress(for: scoped, now: now), .init(completed: 1, remaining: 1))
            // Deleted words and moved memberships disappear from the supplied live scope.
            XCTAssertEqual(store.progress(for: [words[1]], now: now), .init(completed: 0, remaining: 1))
            XCTAssertEqual(store.progress(for: FolderStore.words(words, in: UUID(), memberships: index), now: now).total, 0)
            let added = Word(russian: "новое", polish: "nowe", side: .term, createdAt: now)
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

    func testPartialQuizPersistsSixSuccessfulWordsOutOfEighteenAndSchedulesTheAnsweredDueWords() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(18)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            for (index, word) in words.prefix(8).enumerated() {
                try quiz(store, word, correct: index < 6, container: container)
            }
            // No session-finish action is needed before recreating the store and model context.
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            let context = ModelContext(container)
            let freshWords = try context.fetch(FetchDescriptor<Word>())
            XCTAssertEqual(reloaded.progress(for: freshWords, now: now), .init(completed: 6, remaining: 12))
            XCTAssertEqual(reloaded.answerTotals(for: freshWords, now: now), .init(correct: 6, incorrect: 2))
            let answered = Set(words.prefix(6).map(\.persistentModelID))
            let wrong = Set(words[6..<8].map(\.persistentModelID))
            for word in freshWords {
                if answered.contains(word.persistentModelID) {
                    XCTAssertEqual(word.repetitions, 1)
                    XCTAssertEqual(word.dueDate, now.addingTimeInterval(2 * 86_400), "FSRS Good on a new word")
                } else if wrong.contains(word.persistentModelID) {
                    XCTAssertEqual(word.repetitions, 0)
                    XCTAssertEqual(word.dueDate, now.addingTimeInterval(600))
                } else {
                    XCTAssertEqual(word.repetitions, 0)
                    XCTAssertEqual(word.intervalDays, 0)
                    XCTAssertEqual(word.easeFactor, 2.5)
                    XCTAssertEqual(word.dueDate, now)
                }
            }
        }
    }

    func testRepeatedQuizAnswersCountAttemptsButOnlyOneCompletedWord() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(1)
            var store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try quiz(store, words[0], correct: true, container: container)
            store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try quiz(store, words[0], correct: true, container: container)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 0))
            try quiz(store, words[0], correct: false, container: container)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try quiz(store, words[0], correct: true, container: container)
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
            try quiz(store, word, correct: true, container: container)
            try store.review(.again, to: word, context: container.mainContext, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 0, remaining: 1))
            try quiz(store, word, correct: true, container: container)
            XCTAssertTrue(store.reviewWords(for: words, now: now).isEmpty)
            try store.review(.good, to: word, context: container.mainContext, now: now)
            XCTAssertEqual(store.progress(for: words, now: now).completed, 1)
            try quiz(store, word, correct: false, container: container)
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
            words.forEach { $0.dueDate = now.addingTimeInterval(3_600) }
            let old = LegacyActivity(day: now, completedIDs: [words[0].persistentModelID],
                                     pendingIDs: [words[1].persistentModelID])
            defaults.set(try JSONEncoder().encode(old), forKey: "dailyStudyActivity.v1")
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(store.progress(for: words, now: now), .init(completed: 1, remaining: 1))
            XCTAssertEqual(store.answerTotals(for: words, now: now).total, 0)
            try quiz(store, words[1], correct: true, container: container, now: now)
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            XCTAssertEqual(reloaded.progress(for: words, now: now), .init(completed: 2, remaining: 0))
            XCTAssertEqual(reloaded.answerTotals(for: words, now: now), .init(correct: 1, incorrect: 0))
        }
    }

    func testQuizStatisticsFollowCurrentFolderAndDeletionScopeAndResetNextDay() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(3)
            let folderID = UUID()
            let index = MembershipIndex.linking([words[0], words[1]], to: folderID)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try quiz(store, words[0], correct: true, container: container, now: now)
            try quiz(store, words[1], correct: false, container: container, now: now)
            try quiz(store, words[2], correct: true, container: container, now: now)
            let scoped = FolderStore.words(words, in: folderID, memberships: index)
            XCTAssertEqual(store.answerTotals(for: scoped, now: now), .init(correct: 1, incorrect: 1))
            XCTAssertEqual(store.answerTotals(for: [words[1]], now: now), .init(correct: 0, incorrect: 1))
            XCTAssertEqual(store.answerTotals(for: [], now: now).total, 0)
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
            XCTAssertEqual(store.answerTotals(for: words, now: tomorrow).total, 0)
            // Only the wrong answer (10 minutes) is due tomorrow; the two correct ones are due in 2 days.
            XCTAssertEqual(store.progress(for: words, now: tomorrow), .init(completed: 0, remaining: 1))
            store.refresh(now: tomorrow)
            let reloaded = DailyStudyStore(defaults: defaults, calendar: calendar, now: tomorrow)
            XCTAssertEqual(reloaded.answerTotals(for: words, now: tomorrow).total, 0)
            try quiz(reloaded, words[0], correct: true, container: container, now: tomorrow)
            XCTAssertEqual(reloaded.answerTotals(for: words, now: tomorrow).total, 1)
        }
    }

    func testAppBootstrapReopensDictionaryBeforeRestoringSavedDailyIdentifiers() throws {
        try withDefaults { defaults in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("dictionary.store"),
                                                   cloudKitDatabase: .none)
            let folderID = try autoreleasepool {
                try seedStartupActivity(configuration: configuration, defaults: defaults)
            }

            try autoreleasepool {
                // Exercise the same bootstrap as the app, not a preconstructed test container.
                let resources = try AppResources(configuration: configuration, defaults: defaults,
                                                 calendar: calendar, now: now)
                XCTAssertEqual(Set(resources.container.schema.entities.map(\.name)), ["Word", "WordFolder", "Workspace", "FolderMembership", "ReviewLogEntry"])
                let context = resources.container.mainContext
                let words = try context.fetch(FetchDescriptor<Word>())
                let folders = try context.fetch(FetchDescriptor<WordFolder>())
                XCTAssertEqual(words.count, 2)
                XCTAssertEqual(folders.map(\.id), [folderID])
                XCTAssertEqual(folders.first?.name, "Урок 1")
                let completed = try XCTUnwrap(words.first { $0.polish == "woda" })
                XCTAssertEqual(completed.russian, "вода")
                XCTAssertEqual(try context.fetch(FetchDescriptor<FolderMembership>()).map(\.folderID), [folderID])
                XCTAssertEqual(completed.repetitions, 1)
                XCTAssertEqual(completed.intervalDays, 2)
                XCTAssertEqual(completed.easeFactor, 2.5, "ease is frozen")
                XCTAssertEqual(completed.dueDate, now.addingTimeInterval(2 * 86_400))
                let pending = try XCTUnwrap(words.first { $0.polish == "kawa" })
                XCTAssertEqual(pending.repetitions, 0)
                XCTAssertEqual(pending.dueDate, now.addingTimeInterval(600))
                XCTAssertEqual(resources.dailyStudy.progress(for: words, now: now), .init(completed: 1, remaining: 1))
                XCTAssertEqual(resources.dailyStudy.answerTotals(for: words, now: now), .init(correct: 1, incorrect: 1))
                XCTAssertEqual(resources.dailyStudy.reviewWords(for: words, now: now).map(\.polish), ["kawa"])
            }
        }
    }

    func testAppBootstrapRegistersBothModelsWithEmptyOrUnreadableDailyActivity() throws {
        try withDefaults { defaults in
            for activity in [nil, Data("invalid".utf8)] as [Data?] {
                defaults.set(activity, forKey: "dailyStudyActivity.v1")
                let resources = try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                                 defaults: defaults, calendar: calendar, now: now)
                XCTAssertEqual(Set(resources.container.schema.entities.map(\.name)), ["Word", "WordFolder", "Workspace", "FolderMembership", "ReviewLogEntry"])
                XCTAssertTrue(try resources.container.mainContext.fetch(FetchDescriptor<Word>()).isEmpty)
                XCTAssertTrue(try resources.container.mainContext.fetch(FetchDescriptor<WordFolder>()).isEmpty)
                XCTAssertEqual(resources.dailyStudy.progress(for: [], now: now).total, 0)
            }
        }
    }

    // MARK: Review log

    private func entries(_ container: ModelContainer) throws -> [ReviewLogEntry] {
        try container.mainContext.fetch(FetchDescriptor<ReviewLogEntry>())
            .sorted { $0.reviewedAt < $1.reviewedAt }
    }

    func testFlashcardGradeSavesOneCompleteLogEntryWithTheWord() throws {
        let (container, words) = try makeWords(1)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        let word = words[0]
        try store.review(.good, to: word, context: container.mainContext, now: now)

        let logged = try entries(container)
        XCTAssertEqual(logged.count, 1)
        let entry = try XCTUnwrap(logged.first)
        XCTAssertEqual(entry.wordID, word.uuid)
        XCTAssertEqual(entry.workspaceID, word.effectiveWorkspaceID)
        XCTAssertEqual(entry.reviewedAt, now)
        XCTAssertEqual(entry.ratingRawValue, "good")
        XCTAssertEqual(entry.modeRawValue, "flashcards")
        XCTAssertTrue(entry.affectsSchedule)
        XCTAssertEqual(entry.elapsedDays, 0)
        XCTAssertEqual(entry.intervalDaysBefore, 0)
        XCTAssertEqual(entry.intervalDaysAfter, word.intervalDays)
        XCTAssertEqual(entry.dueBefore, now)
        XCTAssertEqual(entry.dueAfter, word.dueDate)
        XCTAssertEqual(entry.stateBefore, 0)
        XCTAssertEqual(entry.stateAfter, word.fsrsStateRawValue)
        XCTAssertEqual(entry.stabilityBefore, 0)
        XCTAssertEqual(entry.stabilityAfter, word.fsrsStability)
        XCTAssertEqual(entry.difficultyAfter, word.fsrsDifficulty)
        XCTAssertNil(entry.lastReviewedAtBefore)
        XCTAssertNil(entry.uploadedAt)

        try store.review(.hard, to: word, context: container.mainContext, now: now.addingTimeInterval(3 * 86_400 + 60))
        let second = try entries(container)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(second[1].stateBefore, 2)
        XCTAssertEqual(second[1].elapsedDays, 3)
        XCTAssertEqual(second[1].lastReviewedAtBefore, now)
        XCTAssertEqual(second[1].intervalDaysBefore, 2)
    }

    func testDueQuizAndListeningAnswersLogOneEntryThatAffectsTheSchedule() throws {
        for mode in [PracticeMode.quiz, .listening] {
            let (container, words) = try makeWords(2)
            let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
            try store.recordPracticeAnswer(word: words[0], answer: .choice(isCorrect: true),
                                           context: container.mainContext, mode: mode, now: now)
            try store.recordPracticeAnswer(word: words[1], answer: .typed(expected: "słowo", submitted: "xyz"),
                                           context: container.mainContext, mode: mode, now: now)
            let logged = try entries(container)
            XCTAssertEqual(logged.count, 2, "\(mode)")
            XCTAssertTrue(logged.allSatisfy { $0.affectsSchedule && $0.modeRawValue == mode.rawValue })
            XCTAssertEqual(Set(logged.map(\.ratingRawValue)), ["good", "again"])
        }
    }

    func testNotDueAndSoftMissAnswersLogWithoutChangingTheWord() throws {
        let (container, words) = try makeWords(2)
        let notDue = words[0]
        notDue.repetitions = 3
        notDue.intervalDays = 10
        notDue.dueDate = now.addingTimeInterval(5 * 86_400)
        let before = SRSState(word: notDue)
        let soft = words[1]
        let softBefore = SRSState(word: soft)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        let context = container.mainContext
        try store.recordPracticeAnswer(word: notDue, answer: .choice(isCorrect: true), context: context,
                                       mode: .quiz, now: now)
        try store.recordPracticeAnswer(word: notDue, answer: .choice(isCorrect: false), context: context,
                                       mode: .listening, now: now)
        try store.recordPracticeAnswer(word: soft, answer: .typed(expected: "kotek", submitted: "kotex"),
                                       context: context, mode: .listening, now: now)

        XCTAssertEqual(SRSState(word: notDue), before)
        XCTAssertEqual(SRSState(word: soft), softBefore)
        let logged = try entries(container)
        XCTAssertEqual(logged.count, 3)
        XCTAssertTrue(logged.allSatisfy { !$0.affectsSchedule })
        XCTAssertEqual(logged.map(\.ratingRawValue).sorted(), ["again", "good", "hard"])
        for entry in logged {
            XCTAssertEqual(entry.intervalDaysBefore, entry.intervalDaysAfter)
            XCTAssertEqual(entry.dueBefore, entry.dueAfter)
            XCTAssertEqual(entry.stateBefore, entry.stateAfter)
            XCTAssertEqual(entry.stabilityBefore, entry.stabilityAfter)
            XCTAssertEqual(entry.difficultyBefore, entry.difficultyAfter)
        }
        XCTAssertEqual(Set(logged.map(\.modeRawValue)), ["quiz", "listening"])
    }

    func testAWordWithoutAUUIDGetsNoEntryButStillSaves() throws {
        let (container, words) = try makeWords(1)
        words[0].uuid = nil
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try store.review(.good, to: words[0], context: container.mainContext, now: now)
        XCTAssertTrue(try entries(container).isEmpty)
        XCTAssertEqual(words[0].repetitions, 1)
        try store.recordPracticeAnswer(word: words[0], answer: .choice(isCorrect: true),
                                       context: container.mainContext, mode: .quiz, now: now)
        XCTAssertTrue(try entries(container).isEmpty)
    }

    // MARK: Today's progress never goes backwards

    func testHardOnANewWordStaysCompletedEvenWhenFSRSMakesItDueAgainToday() throws {
        let (container, words) = try makeWords(1)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try store.review(.hard, to: words[0], context: container.mainContext, now: now)
        XCTAssertEqual(words[0].dueDate, now.addingTimeInterval(900), "FSRS learning step after Hard")

        let later = now.addingTimeInterval(16 * 60)
        XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 1, remaining: 0))
        XCTAssertTrue(store.reviewWords(for: words, now: later).isEmpty, "a new session does not offer it")

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(store.progress(for: words, now: tomorrow), .init(completed: 0, remaining: 1))
        XCTAssertEqual(store.reviewWords(for: words, now: tomorrow).count, 1)
    }

    func testACorrectQuizAnswerBehavesTheSameWay() throws {
        let (container, words) = try makeWords(1)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try quiz(store, words[0], correct: true, container: container)
        words[0].dueDate = now.addingTimeInterval(900)
        let later = now.addingTimeInterval(16 * 60)
        XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 1, remaining: 0))
        XCTAssertTrue(store.reviewWords(for: words, now: later).isEmpty)
    }

    func testAgainKeepsTheWordPendingAndTheNextWrongAnswerReturnsItAfterHard() throws {
        let (container, words) = try makeWords(1)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try store.review(.again, to: words[0], context: container.mainContext, now: now)
        let later = now.addingTimeInterval(16 * 60)
        XCTAssertEqual(store.reviewWords(for: words, now: now).count, 1)
        XCTAssertEqual(store.reviewWords(for: words, now: later).count, 1)
        XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 0, remaining: 1))

        try store.review(.hard, to: words[0], context: container.mainContext, now: later)
        XCTAssertEqual(store.progress(for: words, now: later), .init(completed: 1, remaining: 0))
        // A wrong quiz answer the same day makes it pending again.
        words[0].dueDate = later
        try quiz(store, words[0], correct: false, container: container, now: later.addingTimeInterval(60))
        let after = later.addingTimeInterval(120)
        XCTAssertEqual(store.progress(for: words, now: after), .init(completed: 0, remaining: 1))
        XCTAssertEqual(store.reviewWords(for: words, now: after).count, 1)
    }

    private func seedStartupActivity(configuration: ModelConfiguration, defaults: UserDefaults) throws -> UUID {
        let resources = try AppResources(configuration: configuration, defaults: defaults,
                                         calendar: calendar, now: now)
        let context = resources.container.mainContext
        let folder = WordFolder(name: "Урок 1")
        context.insert(folder)
        let completed = Word(russian: "ВОДА", polish: "WODA", side: .term, createdAt: now)
        let pending = Word(russian: "кофе", polish: "kawa", side: .term, createdAt: now)
        context.insert(completed)
        context.insert(pending)
        context.insert(FolderMembership(wordID: try XCTUnwrap(completed.uuid), folderID: folder.id,
                                        workspaceID: WorkspaceID.legacy))
        try context.save()
        try resources.dailyStudy.review(.good, to: completed, context: context, now: now)
        try resources.dailyStudy.review(.again, to: pending, context: context, now: now)
        return folder.id
    }

    func testReviewAndPracticeAnswerSetUpdatedAtUnconditionally() throws {
        try withDefaults { defaults in
            let (container, words) = try makeWords(2)
            let later = now.addingTimeInterval(3_600)
            let store = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
            try store.review(.good, to: words[0], context: container.mainContext, now: later)
            try store.recordPracticeAnswer(word: words[1], answer: .typed(expected: "słowo", submitted: "słowo"),
                                           context: container.mainContext, mode: .flashcards, now: later)
            let fresh = try ModelContext(container).fetch(FetchDescriptor<Word>())
            XCTAssertEqual(fresh.count, 2)
            XCTAssertTrue(fresh.allSatisfy { $0.updatedAt == later })
        }
    }

    /// Review finding: quiz completion is derived from the mode, so a caller cannot log
    /// mode=quiz without recording quiz completion (or the reverse).
    func testQuizCompletionFollowsPracticeMode() throws {
        let (container, words) = try makeWords(3)
        let repository = InMemoryDailyActivityRepository()
        let store = DailyStudyStore(repository: repository, now: now)
        for (word, mode) in zip(words, [PracticeMode.quiz, .listening, .flashcards]) {
            try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: true),
                                           context: container.mainContext, mode: mode, now: now)
        }
        XCTAssertEqual(repository.stored?.quizCompletedIDs, words.prefix(2).map(\.persistentModelID))
    }

    // MARK: Practice answers schedule due words

    func testChoiceAndTypedAnswersOnADueWordScheduleInBothPracticeModes() throws {
        for mode in [PracticeMode.quiz, .listening] {
            let (container, words) = try makeWords(5)
            let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
            let context = container.mainContext
            try store.recordPracticeAnswer(word: words[0], answer: .choice(isCorrect: true),
                                           context: context, mode: mode, now: now)
            try store.recordPracticeAnswer(word: words[1], answer: .typed(expected: "słowo", submitted: "słowo"),
                                           context: context, mode: mode, now: now)
            for word in words.prefix(2) {
                XCTAssertEqual(word.repetitions, 1, "\(mode)")
                XCTAssertEqual(word.dueDate, now.addingTimeInterval(2 * 86_400))
                XCTAssertEqual(word.lastReviewGradeRawValue, ReviewGrade.good.rawValue)
            }
            // Wrong answers: Again (+ a lapse when the word had been answered correctly before).
            words[2].repetitions = 2
            words[2].intervalDays = 3
            try store.recordPracticeAnswer(word: words[2], answer: .choice(isCorrect: false),
                                           context: context, mode: mode, now: now)
            try store.recordPracticeAnswer(word: words[3], answer: .typed(expected: "słowo", submitted: "xyz"),
                                           context: context, mode: mode, now: now)
            XCTAssertEqual(words[2].dueDate, now.addingTimeInterval(600))
            XCTAssertEqual(words[2].lapseCount, 1)
            XCTAssertEqual(words[2].repetitions, 0)
            XCTAssertEqual(words[3].dueDate, now.addingTimeInterval(600))
            XCTAssertEqual(words[3].lapseCount, 0, "a never-learned word is not forgotten")
            // A typed soft miss leaves the schedule alone.
            let before = SRSState(word: words[4])
            try store.recordPracticeAnswer(word: words[4], answer: .typed(expected: "słowo", submitted: "słowx"),
                                           context: context, mode: mode, now: now)
            XCTAssertEqual(SRSState(word: words[4]), before)
        }
    }

    func testAnswersOnANotDueWordLeaveTheScheduleAndLapsesAlone() throws {
        let (container, words) = try makeWords(1)
        let word = words[0]
        word.repetitions = 3
        word.intervalDays = 10
        word.dueDate = now.addingTimeInterval(5 * 86_400)
        let before = SRSState(word: word)
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: true),
                                       context: container.mainContext, mode: .quiz, now: now)
        XCTAssertEqual(SRSState(word: word), before)
        try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: false),
                                       context: container.mainContext, mode: .listening, now: now)
        XCTAssertEqual(SRSState(word: word), before)
        XCTAssertEqual(store.reviewWords(for: words, now: now).map(\.persistentModelID), [word.persistentModelID],
                       "a wrong answer still makes the word pending today")
    }

    func testListeningSoftMissLeavesTheScheduleAlone() throws {
        let (container, words) = try makeWords(1)
        let before = SRSState(word: words[0])
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), calendar: calendar, now: now)
        try store.recordPracticeAnswer(word: words[0], answer: .typed(expected: "kotek", submitted: "kotex"),
                                       context: container.mainContext, mode: .listening, now: now)
        XCTAssertEqual(SRSState(word: words[0]), before)
    }

    private func quiz(_ store: DailyStudyStore, _ word: Word, correct: Bool, container: ModelContainer,
                      now: Date? = nil) throws {
        try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: correct),
                                       context: container.mainContext, mode: .quiz, now: now ?? self.now)
    }

    private func makeWords(_ count: Int) throws -> (ModelContainer, [Word]) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSchema.schema, configurations: configuration)
        let words = (0..<count).map { index in
            Word(russian: "слово \(index)", polish: "słowo \(index)", side: .term, createdAt: now)
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

    func testChangeSignalFiresAfterSuccessfulReviewAndPracticeAnswerOnly() throws {
        let (container, words) = try makeWords(2)
        let signal = LocalChangeSignal()
        var fired = 0
        signal.handler = { fired += 1 }
        let repository = InMemoryDailyActivityRepository()
        let store = DailyStudyStore(repository: repository, calendar: calendar, now: now, changeSignal: signal)

        try store.review(.good, to: words[0], context: container.mainContext, now: now)
        XCTAssertEqual(fired, 1)
        try store.recordPracticeAnswer(word: words[1], answer: .choice(isCorrect: true),
                                       context: container.mainContext, mode: .quiz, now: now)
        XCTAssertEqual(fired, 2)

        repository.prepareError = RepositoryFakeError.forced
        XCTAssertThrowsError(try store.review(.easy, to: words[0], context: container.mainContext, now: now))
        XCTAssertThrowsError(try store.recordPracticeAnswer(word: words[1], answer: .choice(isCorrect: true),
                                                            context: container.mainContext, mode: .quiz, now: now))
        XCTAssertEqual(fired, 2, "failures never notify")
    }
}
