import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class SyncEngineTests: XCTestCase {
    private typealias Kit = SyncTestKit
    private let t0 = SyncTestKit.t0
    private let owner = SyncTestKit.owner

    private var container: ModelContainer!
    private var remote: InMemorySyncRemote!
    private var state: UserDefaultsSyncStateRepository!
    private var engine: SyncEngine!
    private var suite = ""
    /// The fake server's clock (what the trigger reads); the app clock is fixed at `t0`.
    private var serverNow = SyncTestKit.t0

    override func setUpWithError() throws {
        container = try Kit.makeContainer()
        remote = InMemorySyncRemote(currentUserID: owner, clock: { self.serverNow })
        suite = "SyncEngineTests.\(UUID().uuidString)"
        state = UserDefaultsSyncStateRepository(defaults: UserDefaults(suiteName: suite)!)
        engine = makeEngine(container: container, state: state)
        // The pl ← ru workspace every test row lives in: synced on this device and on the server.
        try Kit.insertWorkspace(container, syncedAt: workspaceStamp)
        remote.seed(workspaces: [Kit.remoteWorkspace(updatedAt: workspaceStamp)])
    }

    private let workspaceStamp = SyncTestKit.t0.addingTimeInterval(-9_000)

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func makeEngine(container: ModelContainer, state: UserDefaultsSyncStateRepository) -> SyncEngine {
        SyncEngine(remote: remote, local: SwiftDataSyncStore(container: container, now: { self.t0 }),
                   state: state, now: { self.t0 })
    }

    /// State as after a completed first link (no sentinel conversion).
    private func linked(_ account: UUID? = nil, cursorsFrom: SyncState = SyncState()) throws {
        var linked = cursorsFrom
        linked.linkedAccountID = account ?? owner
        linked.capabilityVersion = SyncEngine.capabilityVersion
        try state.save(linked)
    }

    private func sentTerms() -> [String] { remote.upsertedWordBatches.flatMap { $0 }.map(\.term) }

    // MARK: First link and push

    func testFirstLinkUploadsEveryRowWithTheV2WireMapping() async throws {
        let folder = try Kit.insertFolder(container, name: " Урок ")
        let word = try Kit.insertWord(container, russian: "кот ", polish: " kot", source: .translation,
                                      category: .nature, folders: [folder])
        let other = try Kit.insertWord(container, russian: "дом", polish: "dom", source: .term)

        try engine.link(to: owner)
        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.pushed, 4, "folder, two words and the membership (the workspace is on the server)")
        XCTAssertEqual(remote.callLog, ["fetchWorkspaces", "fetchFolders", "fetchWords", "fetchMemberships",
                                        "upsertFolders", "upsertWords", "upsertMemberships"],
                       "pull workspaces, folders, words, memberships; push in the same order")
        let row = try XCTUnwrap(remote.word(id: word, userID: owner))
        XCTAssertEqual(row.term, "kot")
        XCTAssertEqual(row.translation, "кот")
        XCTAssertEqual(row.workspaceID, WorkspaceID.legacy)
        XCTAssertEqual(row.enteredSide, "translation")
        XCTAssertEqual(row.category, "nature")
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual(try XCTUnwrap(remote.word(id: other, userID: owner)).enteredSide, "term")
        let serverFolder = try XCTUnwrap(remote.folder(id: folder, userID: owner))
        XCTAssertEqual(serverFolder.name, "Урок")
        XCTAssertEqual(serverFolder.workspaceID, WorkspaceID.legacy)
        let membership = try XCTUnwrap(remote.membership(wordID: word, folderID: folder, userID: owner))
        XCTAssertNil(membership.deletedAt)
        for local in try Kit.words(container) {
            XCTAssertFalse(local.isSyncDirty)
            XCTAssertEqual(local.serverUpdatedAt, remote.word(id: try XCTUnwrap(local.uuid), userID: owner)?.updatedAt)
        }
        XCTAssertFalse(try XCTUnwrap(Kit.folders(container).first).isSyncDirty)
        XCTAssertFalse(try XCTUnwrap(Kit.memberships(container).first).isSyncDirty)
        XCTAssertEqual(state.load().lastSyncedAt, t0)
    }

    func testTombstoneWhoseEarlierAckWasLostIsUploadedNextCycle() async throws {
        let id = try Kit.insertWord(container)
        try engine.link(to: owner)
        remote.nextErrorAfterStore = URLError(.timedOut)
        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner))
        XCTAssertNil(try XCTUnwrap(remote.word(id: id, userID: owner)).deletedAt, "the server stored the live row")
        XCTAssertTrue(try XCTUnwrap(Kit.word(container, id)).isSyncDirty, "the ack was lost")

        try Kit.edit(container, id, at: t0.addingTimeInterval(30)) { $0.deletedAt = t0.addingTimeInterval(30) }
        serverNow = t0.addingTimeInterval(60)
        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try XCTUnwrap(remote.word(id: id, userID: owner)).deletedAt)
        XCTAssertFalse(try XCTUnwrap(Kit.word(container, id)).isSyncDirty)
        XCTAssertNotNil(remote.upsertedWordBatches.last?.first?.deletedAt)
    }

    func testNeverSyncedTombstoneIsUploadedAndRemoteTombstonesCreateNothingLocally() async throws {
        let local = try Kit.insertWord(container, polish: "mine", deletedAt: t0.addingTimeInterval(-60))
        let remoteOnly = UUID()
        remote.seed(words: [Kit.remoteWord(id: remoteOnly, term: "theirs", updatedAt: t0.addingTimeInterval(-30),
                                           deletedAt: t0.addingTimeInterval(-30))])
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try XCTUnwrap(remote.word(id: local, userID: owner)).deletedAt)
        XCTAssertNil(try Kit.word(container, remoteOnly), "a remote tombstone is never materialized")
        XCTAssertEqual(try Kit.words(container).count, 1)
    }

    // MARK: Pull

    func testPullInsertsRemoteFoldersWordsAndMemberships() async throws {
        let folder = UUID()
        let word = UUID()
        remote.seed(words: [Kit.remoteWord(id: word, term: "most", translation: "мост",
                                           updatedAt: t0.addingTimeInterval(-60))],
                    folders: [Kit.remoteFolder(id: folder, name: "Из облака", updatedAt: t0.addingTimeInterval(-60))],
                    memberships: [Kit.remoteMembership(wordID: word, folderID: folder,
                                                       updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertTrue(report.foldersChanged)
        XCTAssertTrue(report.membershipsChanged)
        XCTAssertTrue(report.vocabularyChanged)
        XCTAssertEqual(try Kit.folders(container).map(\.name), ["Из облака"])
        let local = try XCTUnwrap(Kit.words(container).first)
        XCTAssertEqual(local.polish, "most")
        XCTAssertEqual(local.russian, "мост")
        XCTAssertEqual(try Kit.folderIDs(container, of: word), [folder])
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty, "pulled rows are clean")
        XCTAssertTrue(remote.upsertedMembershipBatches.isEmpty)
    }

    func testSecondCycleRequestsOverlappingCursorForTheOwnerAndChangesNothing() async throws {
        let folder = UUID()
        remote.seed(words: [Kit.remoteWord(term: "a", updatedAt: t0.addingTimeInterval(-60)),
                            Kit.remoteWord(term: "b", updatedAt: t0.addingTimeInterval(-50))],
                    folders: [Kit.remoteFolder(id: folder, updatedAt: t0.addingTimeInterval(-70))])
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        let saved = state.load()
        let wordsCursor = try XCTUnwrap(saved.wordsCursor)
        let foldersCursor = try XCTUnwrap(saved.foldersCursor)
        XCTAssertEqual(wordsCursor.updatedAtMillis, Int64(((t0.timeIntervalSince1970 - 50) * 1000).rounded()))
        XCTAssertEqual(remote.requestedCursors.count, 4, "workspaces, folders, words, memberships")
        XCTAssertNil(remote.requestedCursors[0])

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(remote.requestedCursors[5], foldersCursor.overlapping(by: 60_000))
        XCTAssertEqual(remote.requestedCursors[6], wordsCursor.overlapping(by: 60_000))
        XCTAssertEqual(Set(remote.requestedOwners), [owner])
        XCTAssertEqual(report.pulled, 0, "re-fetched rows are echoes")
        XCTAssertFalse(report.vocabularyChanged)
        XCTAssertEqual(try Kit.words(container).count, 2)
        XCTAssertEqual(state.load().wordsCursor, wordsCursor, "the cursor never moves back")
    }

    func testTwelveHundredRowsSharingOneTimestampAllArriveThroughKeysetPaging() async throws {
        let stamp = t0.addingTimeInterval(-600)
        remote.seed(words: (0..<1_200).map { Kit.remoteWord(term: "w\($0)", translation: "с\($0)", updatedAt: stamp) })
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.pulled, 1_201, "1 200 words plus the linked workspace taking the account's version")
        XCTAssertEqual(try Kit.words(container).count, 1_200)
        XCTAssertEqual(remote.callLog.filter { $0 == "fetchWords" }.count, 3, "500 + 500 + 200")
        XCTAssertEqual(remote.requestedCursors.compactMap { $0 }.count, 2, "pages 2 and 3 continue from the last row")
    }

    func testRemoteNewerAndLocalCleanUpdatesAndTombstoneSoftDeletes() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let updated = try Kit.insertWord(container, polish: "u", syncedAt: synced)
        let deleted = try Kit.insertWord(container, polish: "d", syncedAt: synced)
        try linked()
        remote.seed(words: [
            Kit.remoteWord(id: updated, term: "u", translation: "новый", updatedAt: t0.addingTimeInterval(-60), repetitions: 9),
            Kit.remoteWord(id: deleted, term: "d", updatedAt: t0.addingTimeInterval(-50), deletedAt: t0.addingTimeInterval(-50)),
        ])

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.pulled, 2)
        XCTAssertEqual(try Kit.words(container).count, 2, "the row count never decreases")
        let u = try XCTUnwrap(Kit.word(container, updated))
        XCTAssertEqual(u.russian, "новый")
        XCTAssertEqual(u.repetitions, 9)
        XCTAssertNotNil(try XCTUnwrap(Kit.word(container, deleted)).deletedAt)
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty)
    }

    /// The launch normalizer never dirties a row, so a newer remote edit to a normalized word wins
    /// instead of being overwritten by the local copy.
    func testNormalizedCleanWordStillTakesANewerRemoteEditAndPushesNothing() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let id = try Kit.insertWord(container, polish: "kot", syncedAt: synced)
        try Kit.edit(container, id, at: synced) {
            $0.intervalDays = 400
            $0.repetitions = 5
            $0.dueDate = t0.addingTimeInterval(400 * 86_400)
        }
        try linked()
        let changed = try ScheduleNormalizer.normalize(in: ModelContext(container), now: t0)
        XCTAssertEqual(changed, 1)
        remote.seed(words: [Kit.remoteWord(id: id, term: "kot-remote", updatedAt: t0.addingTimeInterval(-60),
                                           intervalDays: 400, dueDate: t0.addingTimeInterval(400 * 86_400))])

        _ = try await engine.run(ownerID: owner)

        let local = try XCTUnwrap(Kit.word(container, id))
        XCTAssertEqual(local.polish, "kot-remote")
        XCTAssertLessThanOrEqual(local.intervalDays, 30)
        XCTAssertFalse(local.isSyncDirty)
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty, "nothing is pushed for the normalized word")
    }

    func testLocalDirtyAndRemoteNewerKeepsLocalAndPushesIt() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let id = try Kit.insertWord(container, polish: "local", syncedAt: synced)
        try Kit.edit(container, id, at: t0.addingTimeInterval(-100)) { $0.polish = "local-edit" }
        try linked()
        remote.seed(words: [Kit.remoteWord(id: id, term: "remote", updatedAt: t0.addingTimeInterval(-60))])
        serverNow = t0

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.word(container, id)?.polish, "local-edit")
        XCTAssertEqual(remote.word(id: id, userID: owner)?.term, "local-edit", "the last device to sync wins")
        XCTAssertFalse(try XCTUnwrap(Kit.word(container, id)).isSyncDirty)
    }

    /// Delete wins in the only cycle mode (background and sign-out cycles are the same).
    func testRemoteTombstoneBeatsADirtyLocalEditAndIsNeverUndone() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let id = try Kit.insertWord(container, polish: "kot", syncedAt: synced)
        try Kit.edit(container, id, at: t0.addingTimeInterval(-100)) { $0.repetitions = 5 }
        try linked()
        let tombstone = t0.addingTimeInterval(-60)
        remote.seed(words: [Kit.remoteWord(id: id, term: "kot", updatedAt: tombstone, deletedAt: tombstone)])

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try XCTUnwrap(Kit.word(container, id)).deletedAt, "the local row is soft-deleted")
        XCTAssertEqual(try Kit.words(container).count, 1)
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty, "nothing is pushed over the tombstone")
        XCTAssertNotNil(remote.word(id: id, userID: owner)?.deletedAt)
    }

    func testReLinkSentinelLetsTheNewAccountWinForCleanRowsOnly() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let shared = try Kit.insertWord(container, polish: "shared", syncedAt: synced)
        let missing = try Kit.insertWord(container, polish: "missing", syncedAt: synced)
        let edited = try Kit.insertWord(container, polish: "edited", syncedAt: synced)
        try Kit.edit(container, edited, at: t0.addingTimeInterval(-100)) { $0.repetitions = 2 }
        let accountA = UUID()
        try linked(accountA)
        remote.seed(words: [
            Kit.remoteWord(id: shared, term: "shared", updatedAt: t0.addingTimeInterval(-60), repetitions: 8),
            Kit.remoteWord(id: edited, term: "edited", updatedAt: t0.addingTimeInterval(-60), repetitions: 5),
        ])

        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.word(container, shared)?.repetitions, 8, "the account's newer SRS wins")
        let pushed = Set(remote.upsertedWordBatches.flatMap { $0 }.map(\.id))
        XCTAssertEqual(pushed, [missing, edited], "nothing stale is pushed for `shared`")
        XCTAssertEqual(remote.word(id: shared, userID: owner)?.repetitions, 8)
        XCTAssertNotNil(remote.word(id: missing, userID: owner), "a row the account lacks is uploaded")
        XCTAssertEqual(remote.word(id: edited, userID: owner)?.repetitions, 2, "a local edit keeps last-write-wins")
        XCTAssertTrue(try Kit.words(container).allSatisfy { !$0.isSyncDirty })
    }

    // MARK: Push details

    func testEditDuringAPushKeepsTheRowDirtyAndPushesItNext() async throws {
        let id = try Kit.insertWord(container, polish: "before")
        try engine.link(to: owner)
        remote.beforeAck = { [unowned self] in
            remote.beforeAck = nil
            try? Kit.edit(container, id, at: t0.addingTimeInterval(10)) { $0.polish = "after" }
        }

        _ = try await engine.run(ownerID: owner)
        XCTAssertTrue(try XCTUnwrap(Kit.word(container, id)).isSyncDirty, "the ack is not applied over a newer edit")
        XCTAssertEqual(remote.word(id: id, userID: owner)?.term, "before")

        serverNow = t0.addingTimeInterval(60)
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.word(id: id, userID: owner)?.term, "after")
        XCTAssertFalse(try XCTUnwrap(Kit.word(container, id)).isSyncDirty)
        XCTAssertEqual(sentTerms(), ["before", "after"])
    }

    func testLegacyScheduleIsPushedClampedAndLocalRowIsUntouched() async throws {
        let id = try Kit.insertWord(container)
        try Kit.edit(container, id, at: t0.addingTimeInterval(-10)) {
            $0.easeFactor = 15
            $0.intervalDays = 100_000
            $0.dueDate = t0.addingTimeInterval(100_000 * 86_400)
            $0.knowledgeTier = 9
            $0.lastReviewGradeRawValue = "weird"
            $0.repetitions = 4
        }
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        let sent = try XCTUnwrap(remote.upsertedWordBatches.first?.first)
        XCTAssertEqual(sent.easeFactor, SRSEngine.maxEaseFactor)
        XCTAssertEqual(sent.intervalDays, SRSEngine.maxIntervalDays)
        XCTAssertLessThanOrEqual(sent.dueDate, t0.addingTimeInterval(SRSEngine.maxIntervalDays * 86_400))
        XCTAssertNil(sent.knowledgeTier)
        XCTAssertNil(sent.lastReviewGrade)
        XCTAssertEqual(sent.repetitions, 4)
        let local = try XCTUnwrap(Kit.word(container, id))
        XCTAssertEqual(local.easeFactor, 15)
        XCTAssertEqual(local.intervalDays, 100_000)
        XCTAssertEqual(local.knowledgeTier, 9)
    }

    func testOverlongWordIsNotPushedStaysDirtyAndIsCounted() async throws {
        let long = try Kit.insertWord(container, polish: String(repeating: "a", count: 600))
        let fine = try Kit.insertWord(container, polish: "ok")
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.skipped, ["invalid_text": 1])
        XCTAssertEqual(report.pushed, 1)
        XCTAssertNil(remote.word(id: long, userID: owner))
        XCTAssertTrue(try XCTUnwrap(Kit.word(container, long)).isSyncDirty)
        XCTAssertFalse(try XCTUnwrap(Kit.word(container, fine)).isSyncDirty)
    }

    func testMultiLineWordRoundTripsToAnotherDevice() async throws {
        let id = try Kit.insertWord(container, russian: "первая\nвторая", polish: "pierwsza\nsecond\tx")
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.word(id: id, userID: owner)?.term, "pierwsza\nsecond\tx")

        let second = try Kit.makeContainer()
        let secondState = UserDefaultsSyncStateRepository(defaults: UserDefaults(suiteName: suite)!, key: "sync.second")
        let secondEngine = makeEngine(container: second, state: secondState)
        try secondEngine.link(to: owner)
        _ = try await secondEngine.run(ownerID: owner)

        let pulled = try XCTUnwrap(Kit.word(second, id))
        XCTAssertEqual(pulled.polish, "pierwsza\nsecond\tx")
        XCTAssertEqual(pulled.russian, "первая\nвторая")
    }

    func testRemoteEnteredSideMapsToTheSourceLanguageCode() async throws {
        remote.seed(words: [Kit.remoteWord(term: "kot", translation: "кот", entered: "term",
                                           updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        let word = try XCTUnwrap(Kit.words(container).first)
        XCTAssertEqual(word.russian, "кот")
        XCTAssertEqual(word.polish, "kot")
        XCTAssertEqual(word.sourceLanguageCode, "pl", "entered_side term = the term language")
        XCTAssertEqual(word.workspaceID, WorkspaceID.legacy)
    }

    // MARK: Validation and untrusted rows

    func testContentInvalidRemoteRowsAreSkippedCountedAndTheCursorAdvances() async throws {
        let good = Kit.remoteWord(term: "good", updatedAt: t0.addingTimeInterval(-60))
        let blank = Kit.remoteWord(term: "   ", updatedAt: t0.addingTimeInterval(-50))
        let future = Kit.remoteWord(term: "fut", category: "future_cat", updatedAt: t0.addingTimeInterval(-40))
        remote.seed(words: [good, blank, future])
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.skipped, ["invalid_text": 1, "unsupported_category": 1])
        XCTAssertEqual(try Kit.words(container).map(\.polish), ["good"])
        let cursor = try XCTUnwrap(state.load().wordsCursor)
        XCTAssertEqual(cursor, SyncCursor(updatedAt: future.updatedAt, id: future.id), "advances past skipped rows")
        XCTAssertEqual(state.load().heldIDs, [blank.id, future.id])
    }

    func testForeignOwnerRowAbortsTheCycleWithoutApplyingOrAdvancing() async throws {
        let mine = Kit.remoteWord(term: "mine", updatedAt: t0.addingTimeInterval(-60))
        remote.seed(words: [mine])
        remote.wordFetchTransform = { rows in
            rows + [Kit.remoteWord(term: "foreign", updatedAt: self.t0.addingTimeInterval(-50), userID: UUID())]
        }
        try engine.link(to: owner)

        do {
            _ = try await engine.run(ownerID: owner)
            XCTFail("a foreign row must abort the cycle")
        } catch {
            XCTAssertEqual(error as? SyncEngineError, .untrustedResponse)
        }

        XCTAssertTrue(try Kit.words(container).isEmpty, "nothing of the page is applied")
        XCTAssertNil(state.load().wordsCursor)
        XCTAssertNil(state.load().lastSyncedAt)
    }

    func testHeldIDsAreNotPushedUntilALaterSupportedVersionIsApplied() async throws {
        let held = UUID()
        let sentinelHeld = UUID()
        try Kit.insertWord(container, polish: "held", id: held)
        try Kit.insertWord(container, polish: "held2", id: sentinelHeld)
        try Kit.edit(container, sentinelHeld, at: t0.addingTimeInterval(-100)) { $0.serverUpdatedAt = .distantPast }
        try Kit.insertWord(container, polish: "free")
        try linked()
        remote.seed(words: [
            Kit.remoteWord(id: held, term: "held", category: "future_cat", updatedAt: t0.addingTimeInterval(-60)),
            Kit.remoteWord(id: sentinelHeld, term: "held2", category: "future_cat", updatedAt: t0.addingTimeInterval(-60)),
        ])

        let report = try await engine.run(ownerID: owner)
        XCTAssertEqual(report.skipped["unsupported_category"], 2)
        XCTAssertEqual(state.load().heldIDs, [held, sentinelHeld])
        XCTAssertEqual(sentTerms(), ["free"], "held local rows are not pushed")

        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(sentTerms(), ["free"], "still held in the next cycle")

        // A newer client version this build understands arrives: applied, and the id is released.
        serverNow = t0.addingTimeInterval(120)
        remote.server.put(Kit.remoteWord(id: held, term: "held", category: "food", updatedAt: t0), at: serverNow)
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(state.load().heldIDs, [sentinelHeld])
        XCTAssertTrue(sentTerms().contains("held"), "the released row is pushed again")
    }

    // MARK: Failures

    func testSecondPageFailureKeepsPageOneAndResumesFromItsCursor() async throws {
        let rows = (0..<600).map {
            Kit.remoteWord(term: "w\($0)", translation: "с\($0)", updatedAt: t0.addingTimeInterval(-10_000 + Double($0)))
        }
        remote.seed(words: rows)
        try engine.link(to: owner)
        var fetches = 0
        remote.onCall = { [unowned self] name in
            guard name == "fetchWords" else { return }
            fetches += 1
            if fetches == 2 { remote.nextError = URLError(.notConnectedToInternet) }
        }

        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner))

        XCTAssertEqual(try Kit.words(container).count, 500, "page 1 is applied, page 2 is not")
        let page1Last = rows[499]
        let saved = try XCTUnwrap(state.load().wordsCursor)
        XCTAssertEqual(saved, SyncCursor(updatedAt: page1Last.updatedAt, id: page1Last.id))

        remote.onCall = nil
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.requestedCursors.compactMap { $0 }.last, saved.overlapping(by: 60_000),
                       "the next cycle resumes from the page-1 cursor")
        XCTAssertEqual(try Kit.words(container).count, 600)
    }

    func testSecondPushBatchFailureKeepsBatchOneSyncedAndBatchTwoDirty() async throws {
        for index in 0..<250 {
            try Kit.insertWord(container, polish: "w\(index)", createdAt: t0.addingTimeInterval(-10_000 + Double(index)))
        }
        try engine.link(to: owner)
        var upserts = 0
        remote.onCall = { [unowned self] name in
            guard name == "upsertWords" else { return }
            upserts += 1
            if upserts == 2 { remote.nextError = URLError(.networkConnectionLost) }
        }

        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner))

        let words = try Kit.words(container)
        XCTAssertEqual(words.filter { !$0.isSyncDirty }.count, SyncEngine.pushBatchSize)
        XCTAssertEqual(words.filter(\.isSyncDirty).count, 50)

        remote.onCall = nil
        serverNow = t0.addingTimeInterval(60)
        _ = try await engine.run(ownerID: owner)
        XCTAssertTrue(try Kit.words(container).allSatisfy { !$0.isSyncDirty })
        XCTAssertEqual(remote.server.words.count, 250)
    }

    func testRejectedBatchIsolatesOneBadRowAndItIsNotResentUntilEdited() async throws {
        let bad = try Kit.insertWord(container, polish: "bad")
        try Kit.insertWord(container, polish: "good1")
        try Kit.insertWord(container, polish: "good2")
        try engine.link(to: owner)
        remote.rejectWhere = { $0.term == "bad" }

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.pushed, 2)
        XCTAssertEqual(report.skipped, ["server_rejected": 1])
        XCTAssertEqual(engine.rejected.count, 1)
        XCTAssertNil(remote.word(id: bad, userID: owner))
        XCTAssertTrue(try XCTUnwrap(Kit.word(container, bad)).isSyncDirty)

        let calls = remote.callCount
        let again = try await engine.run(ownerID: owner)
        XCTAssertEqual(again.skipped, ["server_rejected": 1])
        XCTAssertEqual(remote.callCount - calls, 4, "only the four pulls: the rejected row is not re-sent")

        remote.rejectWhere = nil
        try Kit.edit(container, bad, at: t0.addingTimeInterval(5)) { $0.polish = "bad" }
        serverNow = t0.addingTimeInterval(30)
        _ = try await engine.run(ownerID: owner)
        XCTAssertNotNil(remote.word(id: bad, userID: owner), "an edited row is retried")
    }

    func testRunWithAnUnlinkedOwnerThrowsNotLinkedWithoutAnyRequest() async throws {
        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner)) { error in
            XCTAssertEqual(error as? SyncEngineError, .notLinked)
        }
        try linked(UUID())
        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner)) { error in
            XCTAssertEqual(error as? SyncEngineError, .notLinked)
        }
        XCTAssertEqual(remote.callCount, 0)
    }

    func testCapabilityBumpClearsCursorsAndHeldIDs() async throws {
        let cursor = SyncCursor(updatedAtMillis: 1_799_999_000_000, id: UUID())
        try state.save(SyncState(linkedAccountID: owner, capabilityVersion: 1, workspacesCursor: cursor,
                                 foldersCursor: cursor, wordsCursor: cursor, membershipsCursor: cursor,
                                 heldIDs: [UUID()]))

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(remote.requestedCursors.count, 4)
        XCTAssertTrue(remote.requestedCursors.allSatisfy { $0 == nil }, "all four cursors were cleared")
        XCTAssertEqual(state.load().capabilityVersion, SyncEngine.capabilityVersion)
        XCTAssertTrue(state.load().heldIDs.isEmpty)
    }

    func testLinkClearsCursorsAndHeldIDs() throws {
        let cursor = SyncCursor(updatedAtMillis: 1_799_999_000_000, id: UUID())
        try state.save(SyncState(linkedAccountID: UUID(), capabilityVersion: 1, foldersCursor: cursor,
                                 wordsCursor: cursor, lastSyncedAt: t0, heldIDs: [UUID()]))
        try engine.link(to: owner)
        XCTAssertEqual(state.load(), SyncState(linkedAccountID: owner, capabilityVersion: SyncEngine.capabilityVersion,
                                               linkedAt: t0))
    }

    // MARK: Stale cycles, pull callback, folder tombstones

    /// A cycle that outlives its link must not write stale cursors over a newer link.
    func testStaleCycleCannotOverwriteANewerLink() async throws {
        let other = UUID()
        remote.seed(words: [Kit.remoteWord(term: "a", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)
        var relinked = false
        remote.onCall = { [unowned self] name in
            guard name == "fetchWords", !relinked else { return }
            relinked = true
            try? engine.link(to: other)  // sign-out/sign-in as another account, mid-cycle
        }

        await XCTAssertThrowsErrorAsync(try await engine.run(ownerID: owner))

        let saved = state.load()
        XCTAssertEqual(saved.linkedAccountID, other, "the newer link survives")
        XCTAssertNil(saved.wordsCursor)
        XCTAssertNil(saved.foldersCursor)
        XCTAssertNil(saved.lastSyncedAt)
        XCTAssertEqual(saved.linkedAt, t0)
    }

    func testCycleCancelledAfterAFetchAppliesAndSavesNothing() async throws {
        remote.seed(words: [Kit.remoteWord(term: "a", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)
        remote.callDelay = .milliseconds(200)
        let run = Task { try await engine.run(ownerID: owner) }
        try await Task.sleep(for: .milliseconds(50))
        run.cancel()
        await XCTAssertThrowsErrorAsync(try await run.value)
        XCTAssertTrue(try Kit.words(container).isEmpty)
        XCTAssertNil(state.load().wordsCursor)
    }

    func testWillApplyPulledRowsFiresOncePerCycleBeforeRowsAreApplied() async throws {
        remote.seed(words: [Kit.remoteWord(term: "a", updatedAt: t0.addingTimeInterval(-60)),
                            Kit.remoteWord(term: "b", updatedAt: t0.addingTimeInterval(-50))],
                    folders: [Kit.remoteFolder(updatedAt: t0.addingTimeInterval(-70))])
        try engine.link(to: owner)
        var fired = 0
        var wordsWhenFired = -1
        engine.willApplyPulledRows = { [unowned self] in
            fired += 1
            wordsWhenFired = (try? Kit.words(container).count) ?? -1
        }
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(wordsWhenFired, 0, "armed before the first pulled page is saved")

        fired = 0
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 1, "per cycle; echoes are still rows")
    }

    func testNothingPulledDoesNotFireTheCallback() async throws {
        remote.server.workspaces = [:]  // the setUp workspace would be a pulled (echo) row
        try engine.link(to: owner)
        var fired = 0
        engine.willApplyPulledRows = { fired += 1 }
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 0)
    }

    /// Like a local FolderStore.delete: the folder's memberships are tombstoned (dirty, they push);
    /// no word row changes.
    func testPulledFolderTombstoneTombstonesMembershipsAndPushesThem() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let folder = try Kit.insertFolder(container, name: "Урок", syncedAt: synced)
        let other = try Kit.insertFolder(container, name: "Другая", syncedAt: synced)
        let member = try Kit.insertWord(container, polish: "kot", folders: [folder], syncedAt: synced)
        let outsider = try Kit.insertWord(container, polish: "dom", folders: [other], syncedAt: synced)
        try linked()
        remote.seed(words: [Kit.remoteWord(id: member, term: "kot", updatedAt: synced),
                            Kit.remoteWord(id: outsider, term: "dom", updatedAt: synced)],
                    folders: [Kit.remoteFolder(id: folder, name: "Урок", updatedAt: t0.addingTimeInterval(-60),
                                               deletedAt: t0.addingTimeInterval(-60)),
                              Kit.remoteFolder(id: other, name: "Другая", updatedAt: synced)],
                    memberships: [Kit.remoteMembership(wordID: member, folderID: folder, updatedAt: synced),
                                  Kit.remoteMembership(wordID: outsider, folderID: other, updatedAt: synced)])
        serverNow = t0

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try Kit.folders(container).first { $0.id == folder }?.deletedAt)
        XCTAssertTrue(try Kit.folderIDs(container, of: member).isEmpty, "active member lost the folder")
        XCTAssertNotNil(remote.membership(wordID: member, folderID: folder, userID: owner)?.deletedAt,
                        "and the change is pushed")
        XCTAssertEqual(try Kit.folderIDs(container, of: outsider), [other], "other words are untouched")
        XCTAssertEqual(try Kit.words(container).count, 2)
        XCTAssertTrue(try Kit.words(container).allSatisfy { $0.isActive && !$0.isSyncDirty }, "words are untouched")
        XCTAssertTrue(try Kit.memberships(container).allSatisfy { !$0.isSyncDirty })
    }

    // MARK: Sentinel edited after the link

    /// An untouched sentinel row: the account's version wins even if the account's row is older.
    func testUneditedSentinelRowTakesTheServerVersion() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let id = try Kit.insertWord(container, polish: "kot", syncedAt: synced)
        try linked(UUID())
        remote.seed(words: [Kit.remoteWord(id: id, term: "kot", updatedAt: t0.addingTimeInterval(-3_600), repetitions: 8)])
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.word(container, id)?.repetitions, 8)
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty, "the stale copy is not pushed")
    }

    /// Edited after the link and before the first successful pull (e.g. offline): the edit is
    /// pushed and survives, like any dirty local edit.
    func testSentinelRowEditedAfterTheLinkKeepsAndPushesTheEdit() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let id = try Kit.insertWord(container, polish: "kot", syncedAt: synced)
        try linked(UUID())
        remote.seed(words: [Kit.remoteWord(id: id, term: "kot", updatedAt: t0.addingTimeInterval(-60), repetitions: 8)])
        try engine.link(to: owner)
        XCTAssertEqual(state.load().linkedAt, t0)
        try Kit.edit(container, id, at: t0.addingTimeInterval(5)) { $0.repetitions = 2 }

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.word(container, id)?.repetitions, 2, "the offline edit survives the first pull")
        XCTAssertEqual(remote.word(id: id, userID: owner)?.repetitions, 2, "and is pushed")
        XCTAssertFalse(try XCTUnwrap(Kit.word(container, id)).isSyncDirty)
    }

    func testSentinelRowEditedAfterTheLinkStillLosesToARemoteTombstone() async throws {
        let id = try Kit.insertWord(container, polish: "kot", syncedAt: t0.addingTimeInterval(-3_000))
        try linked(UUID())
        remote.seed(words: [Kit.remoteWord(id: id, term: "kot", updatedAt: t0.addingTimeInterval(-60),
                                           deletedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)
        try Kit.edit(container, id, at: t0.addingTimeInterval(5)) { $0.repetitions = 2 }

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try Kit.word(container, id)?.deletedAt, "delete wins over a concurrent edit")
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty)
    }

    // MARK: Adoption

    func testPairAdoptionRekeysAnUnsyncedLocalWordInsteadOfDuplicating() async throws {
        let localFolder = try Kit.insertFolder(container, name: "Локальная")
        let local = try Kit.insertWord(container, russian: "кот", polish: "kot", folders: [localFolder])
        let remoteFolderID = UUID()
        let remoteID = UUID()
        remote.seed(words: [Kit.remoteWord(id: remoteID, term: "KOT ", translation: " Кот",
                                           updatedAt: t0.addingTimeInterval(-60), repetitions: 6)],
                    folders: [Kit.remoteFolder(id: remoteFolderID, name: "Облако", updatedAt: t0.addingTimeInterval(-60))],
                    memberships: [Kit.remoteMembership(wordID: remoteID, folderID: remoteFolderID,
                                                       updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        let words = try Kit.words(container)
        XCTAssertEqual(words.count, 1, "no duplicate")
        let adopted = try XCTUnwrap(words.first)
        XCTAssertEqual(adopted.uuid, remoteID)
        XCTAssertNotEqual(adopted.uuid, local)
        XCTAssertEqual(adopted.repetitions, 6, "the server progress is adopted")
        XCTAssertEqual(try Kit.folderIDs(container, of: remoteID), [remoteFolderID, localFolder],
                       "remote memberships plus the re-keyed local one")
        XCTAssertNotNil(remote.membership(wordID: remoteID, folderID: localFolder, userID: owner),
                        "the re-keyed membership is pushed")
        XCTAssertFalse(adopted.isSyncDirty)
        XCTAssertTrue(try Kit.memberships(container).allSatisfy { $0.wordID == remoteID })
    }

    func testPairAdoptionAlsoAppliesToSentinelRows() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let local = try Kit.insertWord(container, polish: "kot", syncedAt: synced)
        try linked(UUID())
        try engine.link(to: owner)
        XCTAssertEqual(try Kit.word(container, local)?.serverUpdatedAt, .distantPast)
        let remoteID = UUID()
        remote.seed(words: [Kit.remoteWord(id: remoteID, updatedAt: t0.addingTimeInterval(-60))])

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.words(container).map(\.uuid), [remoteID])
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty)
    }

    func testFolderAdoptionRewritesMemberships() async throws {
        let localFolder = try Kit.insertFolder(container, name: "Урок")
        let member = try Kit.insertWord(container, polish: "kot", folders: [localFolder])
        let remoteFolderID = UUID()
        remote.seed(folders: [Kit.remoteFolder(id: remoteFolderID, name: "урок", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        let folders = try Kit.folders(container)
        XCTAssertEqual(folders.map(\.id), [remoteFolderID], "one folder, with the server id")
        XCTAssertEqual(folders.first?.name, "урок")
        XCTAssertEqual(try Kit.folderIDs(container, of: member), [remoteFolderID])
        XCTAssertNotNil(remote.membership(wordID: member, folderID: remoteFolderID, userID: owner),
                        "the rewritten membership is pushed")
        XCTAssertNil(remote.membership(wordID: member, folderID: localFolder, userID: owner))
        XCTAssertTrue(try Kit.words(container).allSatisfy { !$0.isSyncDirty })
    }

    // MARK: Workspaces on the wire (v2)

    /// F1: a workspace deleted on another device still has words, a folder and memberships on the
    /// server. A newly linked device stores the tombstone and the rows (hidden), holds nothing, and
    /// re-adding the pair brings everything back and pushes the revival.
    func testDeletedRemoteWorkspaceIsMaterializedAndItsRowsAreStoredNotHeld() async throws {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        let word = UUID(), folder = UUID()
        let stamp = t0.addingTimeInterval(-60)
        remote.seed(workspaces: [Kit.remoteWorkspace(term: "de", translation: "ru", sortOrder: 1, updatedAt: stamp,
                                                     deletedAt: stamp)],
                    words: [Kit.remoteWord(id: word, term: "Haus", translation: "дом", workspace: de,
                                           entered: "term", updatedAt: stamp)],
                    folders: [Kit.remoteFolder(id: folder, name: "Lektion", workspace: de, updatedAt: stamp)],
                    memberships: [Kit.remoteMembership(wordID: word, folderID: folder, workspace: de,
                                                       updatedAt: stamp)])
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertTrue(report.skipped.isEmpty, "nothing skipped: \(report.skipped)")
        XCTAssertTrue(state.load().heldIDs.isEmpty)
        let workspaces = try Kit.workspaces(container)
        let tombstone = try XCTUnwrap(workspaces.first { $0.id == de })
        XCTAssertNotNil(tombstone.deletedAt)
        XCTAssertFalse(tombstone.isSyncDirty, "a materialized tombstone is clean and never pushed")
        XCTAssertEqual(try Kit.words(container).count, 1)
        XCTAssertEqual(try Kit.words(container).first?.term, "Haus", "German keeps its case")
        XCTAssertEqual(try Kit.folders(container).count, 1)
        XCTAssertEqual(try Kit.folderIDs(container, of: word), [folder])
        XCTAssertTrue(WorkspaceScope.words(try Kit.words(container), workspaceID: de).count == 1,
                      "the words exist but the workspace is hidden: the scope is by workspace id")

        // Re-adding the pair revives the tombstone (dirty) and the next cycle pushes the revival.
        let context = ModelContext(container)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", context: context, now: t0)
        XCTAssertNil(try Kit.workspaces(container).first { $0.id == de }?.deletedAt)
        serverNow = t0.addingTimeInterval(60)
        _ = try await engine.run(ownerID: owner)
        XCTAssertNil(remote.workspace(id: de, userID: owner)?.deletedAt, "the revival reached the server")
        XCTAssertFalse(try XCTUnwrap(Kit.workspaces(container).first { $0.id == de }).isSyncDirty)
    }

    /// F1: membership tombstones whose word or folder is unknown are skipped without holding, so
    /// held ids never accumulate; an active orphan is held by its MembershipID.
    func testOrphanMembershipTombstonesAreSkippedNotHeldAndActiveOrphansAreHeld() async throws {
        let stamp = t0.addingTimeInterval(-60)
        let activeWord = UUID(), activeFolder = UUID()
        remote.seed(memberships: [
            Kit.remoteMembership(wordID: UUID(), folderID: UUID(), updatedAt: stamp, deletedAt: stamp),
            Kit.remoteMembership(wordID: UUID(), folderID: UUID(), updatedAt: stamp, deletedAt: stamp),
            Kit.remoteMembership(wordID: activeWord, folderID: activeFolder, updatedAt: stamp),
        ])
        try engine.link(to: owner)

        var counts: [Int] = []
        for cycle in 0..<3 {
            serverNow = t0.addingTimeInterval(Double(cycle) * 60)
            let report = try await engine.run(ownerID: owner)
            counts.append(state.load().heldIDs.count)
            if cycle == 0 {
                XCTAssertEqual(report.skipped["orphan_tombstone"], 2)
                XCTAssertEqual(report.skipped["unknown_reference"], 1)
            }
        }
        XCTAssertEqual(counts, [1, 1, 1], "only the active orphan is held; tombstones never accumulate")
        XCTAssertEqual(state.load().heldIDs, [MembershipID.make(wordID: activeWord, folderID: activeFolder)])
        XCTAssertTrue(try Kit.memberships(container).isEmpty)
    }

    func testLocalWordDeleteTombstonesItsMembershipsAndTheyPush() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let folder = try Kit.insertFolder(container, syncedAt: synced)
        let word = try Kit.insertWord(container, folders: [folder], syncedAt: synced)
        remote.seed(words: [Kit.remoteWord(id: word, updatedAt: synced)],
                    folders: [Kit.remoteFolder(id: folder, updatedAt: synced)],
                    memberships: [Kit.remoteMembership(wordID: word, folderID: folder, updatedAt: synced)])
        try linked()
        let wordRow = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        try ScanWordStore.delete(wordID: wordRow.persistentModelID, container: container, now: t0)
        serverNow = t0.addingTimeInterval(10)

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(remote.word(id: word, userID: owner)?.deletedAt)
        XCTAssertNotNil(remote.membership(wordID: word, folderID: folder, userID: owner)?.deletedAt)
        XCTAssertEqual(try Kit.words(container).count, 1, "the word row stays (soft delete)")
    }

    func testOnWorkspacesPulledFiresOncePerCycleAfterTheWorkspacePull() async throws {
        try engine.link(to: owner)
        var fired = 0
        var logAtFire: [String] = []
        engine.onWorkspacesPulled = {
            fired += 1
            logAtFire = self.remote.callLog
        }
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 1)
        XCTAssertEqual(logAtFire, ["fetchWorkspaces"], "after the workspace pull, before folders")
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 2)
    }

    func testPersistKeepsAllFourCursorsWhenTheLinkIsUnchanged() async throws {
        let stamp = t0.addingTimeInterval(-60)
        let word = UUID(), folder = UUID()
        remote.seed(words: [Kit.remoteWord(id: word, updatedAt: stamp)],
                    folders: [Kit.remoteFolder(id: folder, updatedAt: stamp)],
                    memberships: [Kit.remoteMembership(wordID: word, folderID: folder, updatedAt: stamp)])
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        let saved = state.load()
        XCTAssertNotNil(saved.workspacesCursor)
        XCTAssertNotNil(saved.foldersCursor)
        XCTAssertNotNil(saved.wordsCursor)
        XCTAssertEqual(saved.membershipsCursor?.id, word)
        XCTAssertEqual(saved.membershipsCursor?.secondaryID, folder, "memberships keep (word_id, folder_id)")
        XCTAssertEqual(saved.capabilityVersion, 2)
        XCTAssertEqual(SyncEngine.capabilityVersion, 2)
        XCTAssertNotNil(saved.lastSyncedAt)
    }

    func testLaterComparesSecondaryIDWhenMillisAndIDAreEqual() {
        let id = UUID()
        let low = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let high = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let a = SyncCursor(updatedAtMillis: 10, id: id, secondaryID: low)
        let b = SyncCursor(updatedAtMillis: 10, id: id, secondaryID: high)
        XCTAssertEqual(SyncEngine.later(a, b), b)
        XCTAssertEqual(SyncEngine.later(b, a), b, "never moves backwards")
        XCTAssertEqual(SyncEngine.later(nil, a), a)
        XCTAssertEqual(SyncEngine.later(SyncCursor(updatedAtMillis: 10, id: id), a), a, "nil sorts before any")
        XCTAssertEqual(SyncEngine.later(a, SyncCursor(updatedAtMillis: 10, id: id)), a)
        XCTAssertEqual(SyncEngine.later(a, SyncCursor(updatedAtMillis: 11, id: low)).updatedAtMillis, 11)
    }

    /// F10: a membership whose word was rejected, is held or not yet synced is kept dirty and sent
    /// once the word is acknowledged.
    func testMembershipWaitsForItsRejectedWordThenIsSent() async throws {
        let folder = try Kit.insertFolder(container, syncedAt: t0.addingTimeInterval(-3_000))
        remote.seed(folders: [Kit.remoteFolder(id: folder, updatedAt: t0.addingTimeInterval(-3_000))])
        let bad = try Kit.insertWord(container, polish: "bad", folders: [folder])
        try linked()
        remote.rejectWhere = { $0.term == "bad" }

        let first = try await engine.run(ownerID: owner)

        XCTAssertEqual(first.skipped["server_rejected"], 1)
        XCTAssertTrue(remote.upsertedMembershipBatches.isEmpty, "no membership is sent for a rejected word")
        XCTAssertTrue(try XCTUnwrap(Kit.memberships(container).first).isSyncDirty, "it stays dirty")

        remote.rejectWhere = nil
        try Kit.edit(container, bad, at: t0.addingTimeInterval(5)) { $0.repetitions = 2 }
        serverNow = t0.addingTimeInterval(30)
        _ = try await engine.run(ownerID: owner)
        XCTAssertNotNil(remote.word(id: bad, userID: owner), "the edited word is retried and acked")
        XCTAssertNil(remote.membership(wordID: bad, folderID: folder, userID: owner),
                     "a session-rejected id still blocks its memberships in the cycle that acks it")
        // The rejected ids live for the session (like the rejected word versions): a relaunch clears them.
        serverNow = t0.addingTimeInterval(60)
        _ = try await makeEngine(container: container, state: state).run(ownerID: owner)

        XCTAssertNotNil(remote.membership(wordID: bad, folderID: folder, userID: owner), "sent once the word is acked")
        XCTAssertFalse(try XCTUnwrap(Kit.memberships(container).first).isSyncDirty)
    }

    func testHeldWordKeepsItsMembershipsLocal() async throws {
        let held = UUID()
        let folder = try Kit.insertFolder(container, syncedAt: t0.addingTimeInterval(-3_000))
        remote.seed(folders: [Kit.remoteFolder(id: folder, updatedAt: t0.addingTimeInterval(-3_000))])
        try Kit.insertWord(container, polish: "held", id: held, folders: [folder],
                           syncedAt: t0.addingTimeInterval(-3_000))
        try linked()
        remote.seed(words: [Kit.remoteWord(id: held, term: "held", category: "future_cat",
                                           updatedAt: t0.addingTimeInterval(-60))])

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(state.load().heldIDs, [held])
        XCTAssertTrue(remote.upsertedMembershipBatches.isEmpty)
    }

    /// A membership the server's foreign key rejects is isolated per row.
    func testMembershipForeignKeyRejectionIsIsolatedPerRow() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let folder = try Kit.insertFolder(container, syncedAt: synced)
        let onServer = try Kit.insertWord(container, polish: "here", syncedAt: synced)
        let missing = try Kit.insertWord(container, polish: "gone", syncedAt: synced)
        try Kit.insertMembership(container, wordID: onServer, folderID: folder)
        try Kit.insertMembership(container, wordID: missing, folderID: folder)
        remote.seed(words: [Kit.remoteWord(id: onServer, term: "here", updatedAt: synced)],
                    folders: [Kit.remoteFolder(id: folder, updatedAt: synced)])
        try linked()

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.skipped["server_rejected"], 1)
        XCTAssertNotNil(remote.membership(wordID: onServer, folderID: folder, userID: owner))
        XCTAssertNil(remote.membership(wordID: missing, folderID: folder, userID: owner))
        let rows = try Kit.memberships(container)
        XCTAssertFalse(try XCTUnwrap(rows.first { $0.wordID == onServer }).isSyncDirty)
        XCTAssertTrue(try XCTUnwrap(rows.first { $0.wordID == missing }).isSyncDirty)
    }

    /// F2: a German word validates and applies in phase 2 (not held), case kept.
    func testGermanWorkspaceAndWordApplyWithoutBeingHeld() async throws {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        let id = UUID()
        remote.seed(workspaces: [Kit.remoteWorkspace(term: "de", translation: "ru", sortOrder: 1,
                                                     updatedAt: t0.addingTimeInterval(-60))],
                    words: [Kit.remoteWord(id: id, term: "Das Haus", translation: "Дом", workspace: de,
                                           entered: "term", updatedAt: t0.addingTimeInterval(-50))])
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertTrue(report.skipped.isEmpty)
        XCTAssertTrue(state.load().heldIDs.isEmpty)
        let word = try XCTUnwrap(Kit.word(container, id))
        XCTAssertEqual(word.term, "Das Haus")
        XCTAssertEqual(word.translation, "дом")
        XCTAssertFalse(word.isSyncDirty, "never pushed back lowercased")
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty)
    }

    func testWorkspaceOrderingPushesWorkspaceBeforeItsFoldersAndWords() async throws {
        let ja = try Kit.insertWorkspace(container, term: "de", translation: "ru")
        let word = try Kit.insertWord(container, polish: "Haus", workspace: ja)
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        let order = remote.callLog.filter { $0.hasPrefix("upsert") }
        XCTAssertEqual(order, ["upsertWorkspaces", "upsertWords"])
        XCTAssertNotNil(remote.workspace(id: ja, userID: owner))
        XCTAssertEqual(remote.word(id: word, userID: owner)?.workspaceID, ja)
    }
}

/// `XCTAssertThrowsError` for async expressions.
@MainActor
func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T, file: StaticString = #filePath,
                                  line: UInt = #line, _ handler: (Error) -> Void = { _ in }) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        handler(error)
    }
}
