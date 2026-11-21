import XCTest
import SwiftData
@testable import MojSlownik

/// Test-local mirror of the HEAD d593a09 private daily-activity types.
private struct LegacyDailyActivityV1: Codable, Equatable {
    struct Answer: Codable, Equatable {
        let wordID: PersistentIdentifier
        let isCorrect: Bool
    }
    var day: Date
    var completedIDs: [PersistentIdentifier] = []
    var pendingIDs: [PersistentIdentifier] = []
    var quizCompletedIDs: [PersistentIdentifier]?
    var answers: [Answer]?
}

@MainActor
final class ProgressRepositoryTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "ProgressRepositoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: Achievements

    private let golden = """
    {"unlocked":{"vocabulary.words.1":1000.5},"ledger":{"totalAnswers":12,"correctAnswers":9,"listeningCorrect":3,\
    "perfectQuizzes":1,"currentStreakDays":2,"longestStreakDays":4,"lastStudyDay":2000},"didInitialSync":true}
    """

    func testGoldenAchievementJSONLoadsIntoExpectedState() {
        withDefaults { defaults in
            defaults.set(Data(golden.utf8), forKey: "achievements.v1")
            let state = UserDefaultsAchievementStateRepository(defaults: defaults).load()
            XCTAssertEqual(state.unlocked, ["vocabulary.words.1": Date(timeIntervalSinceReferenceDate: 1000.5)])
            XCTAssertEqual(state.ledger.totalAnswers, 12)
            XCTAssertEqual(state.ledger.correctAnswers, 9)
            XCTAssertEqual(state.ledger.listeningCorrect, 3)
            XCTAssertEqual(state.ledger.perfectQuizzes, 1)
            XCTAssertEqual(state.ledger.currentStreakDays, 2)
            XCTAssertEqual(state.ledger.longestStreakDays, 4)
            XCTAssertEqual(state.ledger.lastStudyDay, Date(timeIntervalSinceReferenceDate: 2000))
            XCTAssertTrue(state.didInitialSync)
        }
    }

    func testAchievementSaveUsesSameKeyAndJSONShape() throws {
        try withDefaults { defaults in
            let repo = UserDefaultsAchievementStateRepository(defaults: defaults)
            var ledger = AchievementLedger()
            ledger.totalAnswers = 5
            ledger.lastStudyDay = Date(timeIntervalSinceReferenceDate: 2000)
            let state = AchievementState(unlocked: ["a": Date(timeIntervalSinceReferenceDate: 10)],
                                         ledger: ledger, didInitialSync: true)
            try repo.save(state)
            let data = try XCTUnwrap(defaults.data(forKey: "achievements.v1"))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(Set(json.keys), ["unlocked", "ledger", "didInitialSync"])
            XCTAssertEqual(json["didInitialSync"] as? Bool, true)
            XCTAssertEqual((json["unlocked"] as? [String: Double])?["a"], 10)
            let ledgerJSON = try XCTUnwrap(json["ledger"] as? [String: Any])
            XCTAssertEqual(ledgerJSON["totalAnswers"] as? Int, 5)
            XCTAssertEqual(ledgerJSON["lastStudyDay"] as? Double, 2000)
            XCTAssertEqual(repo.load(), state)
        }
    }

    func testPartialAndCorruptAchievementPayloads() {
        withDefaults { defaults in
            let repo = UserDefaultsAchievementStateRepository(defaults: defaults)
            defaults.set(Data(#"{"unlocked":{"x":1}}"#.utf8), forKey: "achievements.v1")
            XCTAssertFalse(repo.load().didInitialSync)
            XCTAssertEqual(repo.load().unlocked.count, 1)
            defaults.set(Data("garbage".utf8), forKey: "achievements.v1")
            XCTAssertEqual(repo.load(), AchievementState())
        }
    }

    // MARK: Daily activity

    private func makeIDs() throws -> (ModelContainer, [PersistentIdentifier]) {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let words = [Word(russian: "а", polish: "a", sourceLanguage: .polish),
                     Word(russian: "б", polish: "b", sourceLanguage: .polish)]
        words.forEach(container.mainContext.insert)
        try container.mainContext.save()
        return (container, words.map(\.persistentModelID))
    }

    func testDailyActivityIsCompatibleWithLegacyMirrorBothWays() throws {
        let (container, ids) = try makeIDs()
        _ = container
        try withDefaults { defaults in
            let repo = UserDefaultsDailyActivityRepository(defaults: defaults)
            let day = Date(timeIntervalSinceReferenceDate: 5000)
            let legacy = LegacyDailyActivityV1(day: day, completedIDs: [ids[0]], pendingIDs: [ids[1]],
                                               quizCompletedIDs: [ids[0]],
                                               answers: [.init(wordID: ids[0], isCorrect: true)])
            defaults.set(try JSONEncoder().encode(legacy), forKey: "dailyStudyActivity.v1")
            let loaded = try XCTUnwrap(repo.load())
            XCTAssertEqual(loaded, DailyActivity(day: day, completedIDs: [ids[0]], pendingIDs: [ids[1]],
                                                 quizCompletedIDs: [ids[0]],
                                                 answers: [.init(wordID: ids[0], isCorrect: true)]))

            let current = DailyActivity(day: day, completedIDs: [ids[1]], pendingIDs: [], quizCompletedIDs: nil,
                                        answers: [.init(wordID: ids[1], isCorrect: false)])
            try repo.prepareSave(current)()
            let data = try XCTUnwrap(defaults.data(forKey: "dailyStudyActivity.v1"))
            let mirrored = try JSONDecoder().decode(LegacyDailyActivityV1.self, from: data)
            XCTAssertEqual(mirrored.completedIDs, [ids[1]])
            XCTAssertEqual(mirrored.answers?.first?.isCorrect, false)
            XCTAssertEqual(repo.load(), current)
        }
    }

    func testPrepareSaveWritesOnlyWhenCommitRunsAndClearRemovesKey() throws {
        try withDefaults { defaults in
            let repo = UserDefaultsDailyActivityRepository(defaults: defaults)
            let commit = try repo.prepareSave(DailyActivity(day: .now))
            XCTAssertNil(defaults.data(forKey: "dailyStudyActivity.v1"))
            commit()
            XCTAssertNotNil(defaults.data(forKey: "dailyStudyActivity.v1"))
            XCTAssertNotNil(repo.load())
            repo.clear()
            XCTAssertNil(defaults.data(forKey: "dailyStudyActivity.v1"))
            defaults.set(Data("bad".utf8), forKey: "dailyStudyActivity.v1")
            XCTAssertNil(repo.load())
        }
    }

    // MARK: Stores over fakes

    func testAchievementStoreOverFakePersistsAndRestores() {
        let fake = InMemoryAchievementStateRepository()
        let store = AchievementStore(repository: fake)
        store.record(.answer(mode: .listening, isCorrect: true))
        XCTAssertEqual(fake.saveCount, 1)
        XCTAssertEqual(fake.state.ledger.totalAnswers, 1)
        let restored = AchievementStore(repository: fake)
        XCTAssertEqual(restored.ledger.totalAnswers, 1)
        XCTAssertEqual(restored.ledger.listeningCorrect, 1)
    }

    func testDailyStudyStoreOverFakeCommitsAndRestoresAndPrepareFailureIsAtomic() throws {
        let (container, _) = try makeIDs()
        let context = container.mainContext
        let words = try context.fetch(FetchDescriptor<Word>())
        let now = Date(timeIntervalSince1970: 1_794_225_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let fake = InMemoryDailyActivityRepository()
        let store = DailyStudyStore(repository: fake, calendar: calendar, now: now)

        try store.review(.good, to: words[0], context: context, now: now)
        XCTAssertEqual(fake.stored?.completedIDs, [words[0].persistentModelID])
        let restored = DailyStudyStore(repository: fake, calendar: calendar, now: now)
        XCTAssertEqual(restored.answerTotals(for: words, now: now), .init(correct: 1, incorrect: 0))

        fake.prepareError = RepositoryFakeError.forced
        let before = (words[1].repetitions, words[1].dueDate, words[1].updatedAt)
        XCTAssertThrowsError(try store.review(.good, to: words[1], context: context, now: now))
        XCTAssertEqual(words[1].repetitions, before.0)
        XCTAssertEqual(words[1].dueDate, before.1)
        XCTAssertEqual(words[1].updatedAt, before.2)
        XCTAssertEqual(fake.stored?.completedIDs, [words[0].persistentModelID])

        store.refresh(now: now.addingTimeInterval(86_400 * 2))
        XCTAssertEqual(fake.clearCount, 1)
    }
}
