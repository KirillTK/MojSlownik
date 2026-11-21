import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class SyncStoreTests: XCTestCase {
    private typealias Kit = SyncTestKit
    private let t0 = SyncTestKit.t0
    private let owner = SyncTestKit.owner

    private var container: ModelContainer!
    private var remote: InMemorySyncRemote!
    private var state: UserDefaultsSyncStateRepository!
    private var folders: FolderLibraryStore!
    private var workspaces: WorkspaceStore!
    private var spy: AppLogSpy!
    private var suite = ""
    private var appNow = SyncTestKit.t0

    private var account: AuthAccount { AuthAccount(userID: owner, email: "secret.person@example.com", provider: .google) }

    override func setUpWithError() throws {
        container = try Kit.makeContainer()
        remote = InMemorySyncRemote(currentUserID: owner, clock: { self.t0 })
        suite = "SyncStoreTests.\(UUID().uuidString)"
        state = UserDefaultsSyncStateRepository(defaults: UserDefaults(suiteName: suite)!)
        folders = FolderLibraryStore.inLegacyWorkspace(repository: SwiftDataFolderRepository(container: container))
        workspaces = WorkspaceStore(repository: SwiftDataWorkspaceRepository(container: container),
                                    activeRepository: UserDefaultsActiveWorkspaceRepository(
                                        defaults: UserDefaults(suiteName: suite)!))
        // The pl ← ru workspace every legacy-shaped row belongs to (not on the server yet: it is pushed).
        try Kit.insertWorkspace(container)
        try workspaces.load()
        spy = AppLogSpy()
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func makeStore(engine: Bool = true, achievements: AchievementStore? = nil,
                           debounce: Duration = .milliseconds(20), foreground: TimeInterval = 30) -> SyncStore {
        let engine = engine ? SyncEngine(remote: remote, local: SwiftDataSyncStore(container: container, now: { self.t0 }),
                                         state: state, now: { self.t0 }) : nil
        return SyncStore(engine: engine, state: state, workspaces: workspaces, folders: folders, achievements: achievements, logger: spy,
                         debounce: debounce, foregroundInterval: foreground, now: { self.appNow })
    }

    private func waitUntil(_ what: String, timeout: Duration = .seconds(10), file: StaticString = #filePath,
                           line: UInt = #line, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("timed out waiting for \(what)", file: file, line: line) }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitForSynced(_ store: SyncStore, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil("synced", file: file, line: line) {
            if case .synced = store.status { return true }
            return false
        }
    }

    private func count(_ call: String) -> Int { remote.callLog.filter { $0 == call }.count }

    // MARK: Workspaces

    func testWorkspacesReloadAfterAPullAndPullFinishedIsExposed() async throws {
        remote.seed(workspaces: [Kit.remoteWorkspace(term: "de", translation: "ru", sortOrder: 1,
                                                     updatedAt: t0.addingTimeInterval(-60))])
        let store = makeStore()
        XCTAssertFalse(store.workspacePullFinished)
        XCTAssertEqual(workspaces.options.count, 1)

        store.accountDidChange(account)
        await waitForSynced(store)

        XCTAssertTrue(store.workspacePullFinished)
        XCTAssertEqual(workspaces.options.map(\.termCode), ["pl", "de"], "reloaded after the pull")

        store.accountDidChange(nil)
        XCTAssertFalse(store.workspacePullFinished, "reset when the account changes")
    }

    // MARK: Account changes

    func testNoAccountMeansSignedOutAndNoEngineMeansUnavailable() {
        let store = makeStore()
        XCTAssertEqual(store.status, .signedOut)
        store.accountDidChange(nil)
        XCTAssertEqual(store.status, .signedOut)
        XCTAssertFalse(store.canSyncNow)

        let none = makeStore(engine: false)
        XCTAssertEqual(none.status, .unavailable)
        none.accountDidChange(account)
        XCTAssertEqual(none.status, .unavailable)
    }

    func testFirstAccountLinksThenSyncs() async throws {
        try Kit.insertWord(container, polish: "kot")
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        XCTAssertEqual(state.load().linkedAccountID, owner)
        XCTAssertEqual(remote.server.words.count, 1)
        XCTAssertEqual(spy.events.filter { $0 == .syncLinked }.count, 1)
        XCTAssertEqual(spy.entries.first { $0.event == .syncLinked }?.properties[.relink], .bool(false))
    }

    func testSameAccountAfterRelaunchDoesNotRelink() async throws {
        try state.save(SyncState(linkedAccountID: owner, capabilityVersion: SyncEngine.capabilityVersion))
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        XCTAssertFalse(spy.events.contains(.syncLinked))
    }

    func testDifferentAccountPausesWithOneMismatchLogAndNoUploads() async throws {
        try Kit.insertWord(container)
        try state.save(SyncState(linkedAccountID: UUID(), capabilityVersion: SyncEngine.capabilityVersion))
        let store = makeStore()
        store.accountDidChange(account)
        XCTAssertEqual(store.status, .accountMismatch)
        store.syncNow()
        store.localDataChanged()
        store.sceneDidBecomeActive()
        await store.syncBeforeLeaving()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(remote.callCount, 0)
        XCTAssertEqual(spy.events.filter { $0 == .syncAccountMismatch }.count, 1)
        XCTAssertFalse(store.canSyncNow)
    }

    func testConfirmLinkUploadsAndOnlyWorksFromMismatch() async throws {
        try Kit.insertWord(container, polish: "kot")
        let store = makeStore()
        store.confirmLinkToCurrentAccount()
        XCTAssertEqual(store.status, .signedOut, "ignored outside the mismatch state")

        try state.save(SyncState(linkedAccountID: UUID(), capabilityVersion: SyncEngine.capabilityVersion))
        store.accountDidChange(account)
        XCTAssertEqual(store.status, .accountMismatch)
        store.confirmLinkToCurrentAccount()
        await waitForSynced(store)
        XCTAssertEqual(state.load().linkedAccountID, owner)
        XCTAssertEqual(remote.server.words.count, 1)
        XCTAssertEqual(spy.entries.last { $0.event == .syncLinked }?.properties[.relink], .bool(true))
    }

    // MARK: Triggers

    func testThreeChangesWithinTheDebounceRunOneCycle() async throws {
        let store = makeStore(debounce: .milliseconds(150))
        store.accountDidChange(account)
        await waitForSynced(store)
        let before = count("fetchWords")
        store.localDataChanged()
        store.localDataChanged()
        store.localDataChanged()
        await waitUntil("one debounced cycle") { self.count("fetchWords") == before + 1 }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(count("fetchWords"), before + 1)
    }

    func testTriggerDuringARunSchedulesExactlyOneFollowUp() async throws {
        let store = makeStore()
        var started = 0
        remote.onCall = { name in
            guard name == "fetchFolders" else { return }
            started += 1
            if started == 1 {
                store.syncNow()
                store.syncNow()
                store.syncNow()
            }
        }
        store.accountDidChange(account)
        await waitUntil("two cycles") { self.count("fetchFolders") >= 2 }
        await waitForSynced(store)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(count("fetchFolders"), 2, "the first cycle plus exactly one follow-up")
    }

    func testForegroundIsThrottled() async throws {
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        let before = count("fetchWords")
        store.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count("fetchWords"), before, "inside the 30 s window")

        appNow = appNow.addingTimeInterval(31)
        store.sceneDidBecomeActive()
        await waitUntil("foreground cycle") { self.count("fetchWords") == before + 1 }
    }

    func testSyncNowIgnoresTheThrottle() async throws {
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        let before = count("fetchWords")
        store.syncNow()
        await waitUntil("manual cycle") { self.count("fetchWords") == before + 1 }
    }

    func testSyncBeforeLeavingPullsBeforePushingAndWaitsForCompletion() async throws {
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        try Kit.insertWord(container, polish: "late")
        remote.seed(words: [Kit.remoteWord(term: "remote", updatedAt: t0.addingTimeInterval(-60))])
        let marker = remote.callLog.count

        await store.syncBeforeLeaving()

        XCTAssertEqual(Array(remote.callLog.dropFirst(marker)),
                       ["fetchWorkspaces", "fetchFolders", "fetchWords", "fetchMemberships", "upsertWords"],
                       "pull first, then push")
        XCTAssertEqual(remote.server.words.count, 2)
        XCTAssertEqual(try Kit.words(container).count, 2)
    }

    func testSignOutMidRunCancelsWithoutAFailureLog() async throws {
        let store = makeStore()
        remote.onCall = { name in
            if name == "fetchWorkspaces" { store.accountDidChange(nil) }
        }
        store.accountDidChange(account)
        await waitUntil("signed out") { store.status == .signedOut }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(store.status, .signedOut, "the cancelled cycle does not overwrite the status")
        XCTAssertFalse(spy.events.contains(.syncFailed))
    }

    // MARK: Failures, refresh, logs

    func testRepeatedIdenticalFailuresAreLoggedOnceAndRecoveryWorks() async throws {
        remote.failAll = URLError(.notConnectedToInternet)
        let store = makeStore()
        store.accountDidChange(account)
        await waitUntil("failed") { store.status == .failed }
        store.syncNow()
        await waitUntil("second failure") { self.count("fetchWorkspaces") == 2 }
        await waitUntil("failed again") { store.status == .failed }
        store.syncNow()
        await waitUntil("third attempt") { self.count("fetchWorkspaces") == 3 }
        await waitUntil("failed 3") { store.status == .failed }
        XCTAssertEqual(spy.events.filter { $0 == .syncFailed }.count, 1)
        XCTAssertEqual(spy.entries.first { $0.event == .syncFailed }?.properties[.errorDomain], .name(NSURLErrorDomain))

        remote.failAll = nil
        store.syncNow()
        await waitForSynced(store)
        XCTAssertTrue(store.canSyncNow)
    }

    func testFoldersAreReloadedOnlyWhenFoldersChange() async throws {
        let folder = UUID()
        remote.seed(folders: [Kit.remoteFolder(id: folder, name: "Облако", updatedAt: t0.addingTimeInterval(-60))])
        let store = makeStore()
        XCTAssertTrue(folders.options.isEmpty)
        store.accountDidChange(account)
        await waitForSynced(store)
        XCTAssertEqual(folders.options.map(\.name), ["Облако"], "options refreshed after a pull (Gap A)")
    }

    func testQuietUnlocksAreRequestedOnlyWhenVocabularyChanged() async throws {
        let achievements = AchievementStore(defaults: UserDefaults(suiteName: suite)!, catalog: [
            AchievementDefinition(id: "w1", category: .vocabulary, title: "w1", detail: "w1", symbol: "star",
                                  points: 1, criterion: .threshold(.wordCount, 1))])
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 0]), now: t0)
        let store = makeStore(achievements: achievements)
        store.accountDidChange(account)
        await waitForSynced(store)
        // Nothing was pulled: the next unlock is announced normally.
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 1]), now: t0.addingTimeInterval(1))
        XCTAssertEqual(achievements.pendingAnnouncements.map(\.id), ["w1"])
    }

    func testPulledVocabularySilencesTheNextUnlock() async throws {
        let achievements = AchievementStore(defaults: UserDefaults(suiteName: suite)!, catalog: [
            AchievementDefinition(id: "w1", category: .vocabulary, title: "w1", detail: "w1", symbol: "star",
                                  points: 1, criterion: .threshold(.wordCount, 1))])
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 0]), now: Date())
        remote.seed(words: [Kit.remoteWord(updatedAt: t0.addingTimeInterval(-60))])
        let store = makeStore(achievements: achievements)
        appNow = Date()
        store.accountDidChange(account)
        await waitForSynced(store)
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 1]), now: Date())
        XCTAssertNotNil(achievements.unlocked["w1"])
        XCTAssertTrue(achievements.pendingAnnouncements.isEmpty, "no banner for a pulled word")
    }

    func testOnCycleSucceededFiresAfterEachSuccess() async throws {
        let store = makeStore()
        var fired = 0
        store.onCycleSucceeded = { fired += 1 }
        store.accountDidChange(account)
        await waitForSynced(store)
        XCTAssertEqual(fired, 1)
    }

    func testStatusTextCoversEveryStatus() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(SyncStore.text(for: .idle), "Ещё не синхронизировано")
        XCTAssertEqual(SyncStore.text(for: .syncing), "Синхронизация…")
        XCTAssertEqual(SyncStore.text(for: .failed), "Не удалось синхронизировать. Повторим позже.")
        XCTAssertEqual(SyncStore.text(for: .accountMismatch),
                       "Словарь на этом iPhone связан с другим аккаунтом. Синхронизация выключена.")
        XCTAssertTrue(SyncStore.text(for: .synced(date)).hasPrefix("Синхронизировано: "))
        XCTAssertFalse(SyncStore.text(for: .unavailable).isEmpty)
        XCTAssertFalse(SyncStore.text(for: .signedOut).isEmpty)
    }

    func testSyncedDateIsShortAndRelative() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_794_955_800 + 3_600)  // 2026-11-17 23:50 UTC
        func text(_ date: Date) -> String { SyncStore.text(for: .synced(date), now: now, calendar: calendar) }
        XCTAssertEqual(text(now.addingTimeInterval(-600)), "Синхронизировано: сегодня, 23:40")
        XCTAssertEqual(text(now.addingTimeInterval(-86_400)), "Синхронизировано: вчера, 23:50")
        let older = text(now.addingTimeInterval(-5 * 86_400))
        XCTAssertEqual(older, "Синхронизировано: 12 нояб., 23:50")
        XCTAssertFalse(older.contains("2026"), "no year")
    }

    // MARK: Cancellation and quiet unlocks

    /// Sign-out/background expiry cancels syncBeforeLeaving while it waits for the running
    /// cycle: it returns promptly and never starts a fresh `.leaving` cycle (AC-9).
    func testCancelledSyncBeforeLeavingReturnsPromptlyAndStartsNoNewCycle() async throws {
        try state.save(SyncState(linkedAccountID: owner, capabilityVersion: SyncEngine.capabilityVersion))
        remote.callDelay = .seconds(30)
        let store = makeStore()
        store.accountDidChange(account)
        await waitUntil("cycle started") { self.remote.callLog.count == 1 }

        let leaving = Task { await store.syncBeforeLeaving() }
        try await Task.sleep(for: .milliseconds(50))
        let started = ContinuousClock.now
        leaving.cancel()
        await leaving.value

        XCTAssertLessThan(ContinuousClock.now - started, .seconds(5), "returned promptly")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(count("fetchWorkspaces"), 1, "no new cycle was started")
        XCTAssertNotEqual(store.status, .syncing)
    }

    /// The tracker re-syncs right after pulled words are saved, before the cycle ends: that
    /// unlock must be silent, and the silence must not outlive the cycle.
    func testPulledWordsAreSilentEvenWhenTheTrackerResyncsMidCycleAndSilenceEndsWithTheCycle() async throws {
        let achievements = AchievementStore(defaults: UserDefaults(suiteName: suite)!, catalog: [
            AchievementDefinition(id: "w1", category: .vocabulary, title: "w1", detail: "w1", symbol: "star",
                                  points: 1, criterion: .threshold(.wordCount, 1)),
            AchievementDefinition(id: "w2", category: .vocabulary, title: "w2", detail: "w2", symbol: "star",
                                  points: 1, criterion: .threshold(.wordCount, 2))])
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 0]), now: Date())
        remote.seed(words: [Kit.remoteWord(updatedAt: t0.addingTimeInterval(-60))])
        try Kit.insertWord(container, polish: "local")
        remote.onCall = { name in
            // After the pull was applied, while the push is still in flight.
            if name == "upsertWords" {
                achievements.sync(vocabulary: AchievementMetrics([.wordCount: 1]), now: Date())
            }
        }
        let store = makeStore(achievements: achievements)
        store.accountDidChange(account)
        await waitForSynced(store)

        XCTAssertNotNil(achievements.unlocked["w1"])
        XCTAssertTrue(achievements.pendingAnnouncements.isEmpty, "no banner for the pulled word")
        achievements.sync(vocabulary: AchievementMetrics([.wordCount: 2]), now: Date())
        XCTAssertEqual(achievements.pendingAnnouncements.map(\.id), ["w2"],
                       "a genuine unlock after the cycle is announced (no lingering window)")
    }

    /// AC-13: no word, folder name, email or id reaches a log.
    func testLogsNeverContainUserTextEmailOrIDs() async throws {
        let folderID = try Kit.insertFolder(container, name: "СекретнаяПапка")
        let wordID = try Kit.insertWord(container, russian: "секретноеслово", polish: "tajnesłowo", folders: [folderID])
        remote.seed(words: [Kit.remoteWord(term: "zdalnesłowo", translation: "удалённоеслово",
                                           category: "future_cat", updatedAt: t0.addingTimeInterval(-60))])
        let store = makeStore()
        store.accountDidChange(account)
        await waitForSynced(store)
        remote.failAll = URLError(.timedOut)
        store.syncNow()
        await waitUntil("failed") { store.status == .failed }
        remote.failAll = nil
        try state.save(SyncState(linkedAccountID: UUID(), capabilityVersion: 1))
        store.accountDidChange(account)

        XCTAssertFalse(spy.entries.isEmpty)
        let forbidden = ["секретноеслово", "tajnesłowo", "СекретнаяПапка", "zdalnesłowo", "удалённоеслово",
                         "secret.person@example.com", "example.com", wordID.uuidString, folderID.uuidString,
                         owner.uuidString]
        let encoded = spy.entries.map { entry in
            "\(entry.event.rawValue) " + entry.properties.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
        }.joined(separator: "\n")
        for text in forbidden {
            XCTAssertFalse(encoded.localizedCaseInsensitiveContains(text), "log contains \(text)")
        }
        let uuidPattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        XCTAssertNil(encoded.range(of: uuidPattern, options: .regularExpression), "log contains a uuid")
        XCTAssertTrue(spy.events.contains(.syncRowsSkipped))
        XCTAssertTrue(spy.events.contains(.syncAccountMismatch))
    }
}
