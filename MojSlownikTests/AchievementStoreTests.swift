import XCTest
@testable import MojSlownik

@MainActor
final class AchievementStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_225_600)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func def(_ id: String, _ metric: AchievementMetric, _ target: Int, points: Int = 1) -> AchievementDefinition {
        AchievementDefinition(id: id, category: .vocabulary, title: id, detail: id, symbol: "star",
                              points: points, criterion: .threshold(metric, target))
    }

    private var catalog: [AchievementDefinition] {
        [def("w1", .wordCount, 1, points: 5), def("w2", .wordCount, 2, points: 10),
         def("w3", .wordCount, 3, points: 20)]
    }

    private func makeStore(_ defaults: UserDefaults, duration: Duration = .seconds(60)) -> AchievementStore {
        AchievementStore(defaults: defaults, calendar: calendar, catalog: catalog, displayDuration: duration)
    }

    private func words(_ count: Int) -> AchievementMetrics { AchievementMetrics([.wordCount: count]) }

    func testFirstSyncIsSilentThenLaterUnlocksAreQueuedFIFO() {
        withDefaults { defaults in
            let store = makeStore(defaults)
            store.sync(vocabulary: words(1), now: now)
            XCTAssertEqual(store.unlocked["w1"], now)
            XCTAssertTrue(store.pendingAnnouncements.isEmpty)
            store.sync(vocabulary: words(3), now: now.addingTimeInterval(10))
            XCTAssertEqual(store.pendingAnnouncements.map(\.id), ["w2", "w3"])
            XCTAssertEqual(store.currentAnnouncement?.id, "w2")
            store.dismissAnnouncement()
            XCTAssertEqual(store.currentAnnouncement?.id, "w3")
            store.dismissAnnouncement()
            XCTAssertNil(store.currentAnnouncement)
        }
    }

    func testEmptyFirstSyncStillMarksInitialSync() {
        withDefaults { defaults in
            let store = makeStore(defaults)
            store.sync(vocabulary: words(0), now: now)
            store.sync(vocabulary: words(1), now: now)
            XCTAssertEqual(store.pendingAnnouncements.map(\.id), ["w1"])
        }
    }

    func testPersistenceAndPermanence() {
        withDefaults { defaults in
            let store = makeStore(defaults)
            store.sync(vocabulary: words(2), now: now)
            store.record(.answer(mode: .quiz, isCorrect: true), now: now)
            store.sync(vocabulary: words(0), now: now.addingTimeInterval(100))
            XCTAssertEqual(store.unlockedCount, 2)

            let reloaded = makeStore(defaults)
            XCTAssertEqual(reloaded.unlocked["w1"], now)
            XCTAssertEqual(reloaded.unlocked["w2"], now)
            XCTAssertEqual(reloaded.ledger.totalAnswers, 1)
            reloaded.sync(vocabulary: words(2), now: now.addingTimeInterval(200))
            XCTAssertTrue(reloaded.pendingAnnouncements.isEmpty)
            XCTAssertEqual(reloaded.unlocked["w1"], now)
        }
    }

    func testRecordedAnswersUnlockLedgerAchievements() {
        withDefaults { defaults in
            let store = AchievementStore(defaults: defaults, calendar: calendar,
                                         catalog: AchievementCatalog.all, displayDuration: .seconds(60))
            store.sync(vocabulary: words(0), now: now)
            for _ in 0..<100 { store.record(.answer(mode: .flashcards, isCorrect: true), now: now) }
            store.sync(vocabulary: words(0), now: now)
            XCTAssertNotNil(store.unlocked["practice.answers.100"])
            XCTAssertEqual(store.currentAnnouncement?.id, "practice.answers.100")
        }
    }

    func testTotalsIgnoreUnknownStoredIDs() {
        withDefaults { defaults in
            let store = makeStore(defaults)
            store.sync(vocabulary: words(1), now: now)
            let stored = #"{"unlocked":{"w1":0,"gone":0},"didInitialSync":true}"#
            defaults.set(Data(stored.utf8), forKey: "achievements.v1")
            let reloaded = makeStore(defaults)
            XCTAssertEqual(reloaded.unlockedCount, 1)
            XCTAssertEqual(reloaded.totalPoints, 5)
            XCTAssertEqual(reloaded.possiblePoints, 35)
        }
    }

    func testAutoAdvanceAfterDuration() async throws {
        let name = "AchievementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = makeStore(defaults, duration: .milliseconds(50))
        store.sync(vocabulary: words(0), now: now)
        store.sync(vocabulary: words(2), now: now)
        XCTAssertEqual(store.currentAnnouncement?.id, "w1")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(store.currentAnnouncement?.id, "w2")
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(store.currentAnnouncement)
    }

    func testInactiveSceneKeepsItemAndDoesNotReannounce() async throws {
        let name = "AchievementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = makeStore(defaults, duration: .milliseconds(50))
        store.sync(vocabulary: words(0), now: now)
        store.sync(vocabulary: words(1), now: now)
        XCTAssertEqual(store.announcedIDs.count, 1)
        store.setSceneActive(false)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(store.currentAnnouncement?.id, "w1")
        store.setSceneActive(true)
        XCTAssertEqual(store.announcedIDs.count, 1)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(store.currentAnnouncement)
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "AchievementStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }
}
