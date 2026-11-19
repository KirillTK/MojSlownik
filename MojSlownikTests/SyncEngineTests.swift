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
    }

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

    func testFirstLinkUploadsEveryWordAndFolderWithTheWireMapping() async throws {
        let folder = try Kit.insertFolder(container, name: " Урок ")
        let word = try Kit.insertWord(container, russian: "кот ", polish: " kot", source: .russian,
                                      category: .nature, folders: [folder])
        let other = try Kit.insertWord(container, russian: "дом", polish: "dom", source: .polish)

        try engine.link(to: owner)
        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.pushed, 3)
        XCTAssertEqual(remote.callLog, ["fetchFolders", "fetchWords", "upsertFolders", "upsertWords"],
                       "pull folders, pull words, push folders, push words")
        let row = try XCTUnwrap(remote.word(id: word, userID: owner))
        XCTAssertEqual(row.term, "kot")
        XCTAssertEqual(row.termLanguage, "pl")
        XCTAssertEqual(row.translation, "кот")
        XCTAssertEqual(row.translationLanguage, "ru")
        XCTAssertEqual(row.enteredLanguage, "ru")
        XCTAssertEqual(row.category, "nature")
        XCTAssertEqual(row.folderIDs, [folder])
        XCTAssertNil(row.deletedAt)
        XCTAssertEqual(try XCTUnwrap(remote.word(id: other, userID: owner)).enteredLanguage, "pl")
        XCTAssertEqual(try XCTUnwrap(remote.folder(id: folder, userID: owner)).name, "Урок")
        for local in try Kit.words(container) {
            XCTAssertFalse(local.isSyncDirty)
            XCTAssertEqual(local.serverUpdatedAt, remote.word(id: try XCTUnwrap(local.uuid), userID: owner)?.updatedAt)
        }
        XCTAssertFalse(try XCTUnwrap(Kit.folders(container).first).isSyncDirty)
        XCTAssertEqual(state.load().lastSyncedAt, t0)
        XCTAssertFalse(report.vocabularyChanged)
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

    func testPullInsertsRemoteFoldersAndWords() async throws {
        let folder = UUID()
        let unknown = UUID()
        remote.seed(words: [Kit.remoteWord(term: "most", translation: "мост", folders: [folder, unknown],
                                           updatedAt: t0.addingTimeInterval(-60))],
                    folders: [Kit.remoteFolder(id: folder, name: "Из облака", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertTrue(report.foldersChanged)
        XCTAssertTrue(report.vocabularyChanged)
        XCTAssertEqual(report.pulled, 2)
        XCTAssertEqual(try Kit.folders(container).map(\.name), ["Из облака"])
        let word = try XCTUnwrap(Kit.words(container).first)
        XCTAssertEqual(word.polish, "most")
        XCTAssertEqual(word.russian, "мост")
        XCTAssertEqual(word.folderIDs, [folder, unknown], "ids of folders not on the device are kept (unknown ids)")
        XCTAssertTrue(remote.upsertedWordBatches.isEmpty, "pulled rows are clean")
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
        XCTAssertEqual(remote.requestedCursors.count, 2)
        XCTAssertNil(remote.requestedCursors[0])

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(remote.requestedCursors[2], foldersCursor.overlapping(by: 60_000))
        XCTAssertEqual(remote.requestedCursors[3], wordsCursor.overlapping(by: 60_000))
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

        XCTAssertEqual(report.pulled, 1_200)
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

    func testRemotePairInRussianTermOrderMapsToTheRightSides() async throws {
        remote.seed(words: [Kit.remoteWord(term: "кот", translation: "kot", termLanguage: "ru",
                                           translationLanguage: "pl", entered: "pl", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        let word = try XCTUnwrap(Kit.words(container).first)
        XCTAssertEqual(word.russian, "кот")
        XCTAssertEqual(word.polish, "kot")
        XCTAssertEqual(word.sourceLanguageCode, "pl")
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
        XCTAssertEqual(remote.requestedCursors.compactMap { $0 }.first, saved.overlapping(by: 60_000),
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
        XCTAssertEqual(remote.callCount - calls, 2, "only the two pulls: the rejected row is not re-sent")

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
        try state.save(SyncState(linkedAccountID: owner, capabilityVersion: 0, foldersCursor: cursor,
                                 wordsCursor: cursor, heldIDs: [UUID()]))

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(remote.requestedCursors.count, 2)
        XCTAssertNil(remote.requestedCursors[0])
        XCTAssertNil(remote.requestedCursors[1])
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
        try engine.link(to: owner)
        var fired = 0
        engine.willApplyPulledRows = { fired += 1 }
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(fired, 0)
    }

    /// Like a local FolderStore.delete: active words lose the membership and become dirty.
    func testPulledFolderTombstoneStripsMembershipFromActiveWordsAndPushesIt() async throws {
        let synced = t0.addingTimeInterval(-3_000)
        let folder = try Kit.insertFolder(container, name: "Урок", syncedAt: synced)
        let member = try Kit.insertWord(container, polish: "kot", folders: [folder], syncedAt: synced)
        let gone = try Kit.insertWord(container, polish: "old", folders: [folder], syncedAt: synced,
                                      deletedAt: synced)
        let other = UUID()
        let outsider = try Kit.insertWord(container, polish: "dom", folders: [other], syncedAt: synced)
        try linked()
        remote.seed(words: [Kit.remoteWord(id: member, term: "kot", folders: [folder], updatedAt: synced),
                            Kit.remoteWord(id: outsider, term: "dom", folders: [other], updatedAt: synced)],
                    folders: [Kit.remoteFolder(id: folder, name: "Урок", updatedAt: t0.addingTimeInterval(-60),
                                               deletedAt: t0.addingTimeInterval(-60))])
        serverNow = t0

        _ = try await engine.run(ownerID: owner)

        XCTAssertNotNil(try Kit.folders(container).first { $0.id == folder }?.deletedAt)
        XCTAssertEqual(try Kit.word(container, member)?.folderIDs, [], "active member lost the folder")
        XCTAssertEqual(remote.word(id: member, userID: owner)?.folderIDs, [], "and the change is pushed")
        XCTAssertEqual(try Kit.word(container, gone)?.folderIDs, [], "tombstones are stripped like FolderStore.delete")
        XCTAssertEqual(try Kit.word(container, gone)?.updatedAt, synced, "but keep their deletion-time updatedAt")
        XCTAssertEqual(try Kit.word(container, outsider)?.folderIDs, [other], "other words are untouched")
        XCTAssertEqual(try Kit.words(container).count, 3)
        XCTAssertTrue(try Kit.words(container).filter(\.isActive).allSatisfy { !$0.isSyncDirty })
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
        remote.seed(words: [Kit.remoteWord(id: remoteID, term: "KOT ", translation: " Кот", folders: [remoteFolderID],
                                           updatedAt: t0.addingTimeInterval(-60), repetitions: 6)],
                    folders: [Kit.remoteFolder(id: remoteFolderID, name: "Облако", updatedAt: t0.addingTimeInterval(-60))])
        try engine.link(to: owner)

        _ = try await engine.run(ownerID: owner)

        let words = try Kit.words(container)
        XCTAssertEqual(words.count, 1, "no duplicate")
        let adopted = try XCTUnwrap(words.first)
        XCTAssertEqual(adopted.uuid, remoteID)
        XCTAssertNotEqual(adopted.uuid, local)
        XCTAssertEqual(adopted.repetitions, 6, "the server progress is adopted")
        XCTAssertEqual(adopted.folderIDs, [remoteFolderID, localFolder], "remote first, then local memberships")
        XCTAssertEqual(remote.word(id: remoteID, userID: owner)?.folderIDs, [remoteFolderID, localFolder],
                       "the union is pushed")
        XCTAssertFalse(adopted.isSyncDirty)
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
        XCTAssertEqual(try Kit.word(container, member)?.folderIDs, [remoteFolderID])
        XCTAssertEqual(remote.word(id: member, userID: owner)?.folderIDs, [remoteFolderID],
                       "the rewritten membership is pushed")
        XCTAssertTrue(try Kit.words(container).allSatisfy { !$0.isSyncDirty })
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
