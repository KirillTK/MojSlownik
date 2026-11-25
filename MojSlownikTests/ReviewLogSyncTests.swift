import SwiftData
import XCTest
@testable import MojSlownik

/// FSRS block and review-log sync: the SwiftData side (apply, pending, markPushed, link, adoption)
/// and the engine cycle against the in-memory server.
@MainActor
final class ReviewLogSyncTests: XCTestCase {
    private typealias Kit = SyncTestKit
    private let t0 = SyncTestKit.t0
    private let owner = SyncTestKit.owner
    private let day: TimeInterval = 86_400

    private var container: ModelContainer!
    private var store: SwiftDataSyncStore!
    private var remote: InMemorySyncRemote!
    private var states: [UserDefaultsSyncStateRepository] = []
    private var suites: [String] = []
    private let workspaceStamp = SyncTestKit.t0.addingTimeInterval(-9_000)

    override func setUpWithError() throws {
        container = try Kit.makeContainer()
        store = SwiftDataSyncStore(container: container, now: { self.t0 })
        remote = InMemorySyncRemote(currentUserID: owner, clock: { self.t0 })
        try Kit.insertWorkspace(container, syncedAt: workspaceStamp)
        remote.seed(workspaces: [Kit.remoteWorkspace(updatedAt: workspaceStamp)])
    }

    override func tearDown() {
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
    }

    private func makeEngine(_ container: ModelContainer) -> SyncEngine {
        let suite = "ReviewLogSyncTests.\(UUID().uuidString)"
        suites.append(suite)
        let state = UserDefaultsSyncStateRepository(defaults: UserDefaults(suiteName: suite)!)
        states.append(state)
        return SyncEngine(remote: remote, local: SwiftDataSyncStore(container: container, now: { self.t0 }),
                          state: state, now: { self.t0 })
    }

    @discardableResult
    private func insertEntry(_ container: ModelContainer, wordID: UUID, at time: Date? = nil,
                             uploaded: Date? = nil) throws -> UUID {
        let reviewedAt = time ?? t0.addingTimeInterval(-3_600)
        let word = Word(russian: "кот", polish: "kot", side: .term, createdAt: t0)
        let transition = SRSEngine.transition(.good, from: SRSState(word: word), now: reviewedAt)
        let entry = ReviewLogEntry(wordID: wordID, workspaceID: WorkspaceID.legacy, mode: .flashcards,
                                   transition: transition, rating: .good, affectsSchedule: true,
                                   reviewedAt: reviewedAt)
        entry.uploadedAt = uploaded
        let context = ModelContext(container)
        context.insert(entry)
        try context.save()
        return entry.id
    }

    private func entries(_ container: ModelContainer) throws -> [ReviewLogEntry] {
        try ModelContext(container).fetch(FetchDescriptor<ReviewLogEntry>())
    }

    private let sampleMemory = FSRSMemory(state: 2, stability: 12.5, difficulty: 6.2, learningStep: 0,
                                          lastReviewedAt: SyncTestKit.t0.addingTimeInterval(-4 * 86_400))

    // MARK: Apply (pull)

    func testAPulledValidFSRSBlockIsStoredAndTheRowStaysClean() throws {
        let id = try Kit.insertWord(container, polish: "e", syncedAt: t0.addingTimeInterval(-600))
        let newer = t0.addingTimeInterval(-60)
        _ = try store.applyWords([try Kit.validated(Kit.remoteWord(id: id, term: "e", updatedAt: newer,
                                                                   fsrs: sampleMemory))])
        let word = try XCTUnwrap(Kit.word(container, id))
        XCTAssertEqual(SRSState(word: word).memory, sampleMemory)
        XCTAssertFalse(word.isSyncDirty)
        XCTAssertEqual(word.serverUpdatedAt, newer)
    }

    func testANullBlockIsDerivedFromTheScheduleAndStaysClean() throws {
        let existing = try Kit.insertWord(container, polish: "e", syncedAt: t0.addingTimeInterval(-600))
        let inserted = UUID()
        let newer = t0.addingTimeInterval(-60)
        let due = t0.addingTimeInterval(5 * day)
        _ = try store.applyWords([
            try Kit.validated(Kit.remoteWord(id: existing, term: "e", updatedAt: newer, intervalDays: 6, dueDate: due)),
            try Kit.validated(Kit.remoteWord(id: inserted, term: "n", updatedAt: newer, intervalDays: 6, dueDate: due)),
        ])
        for id in [existing, inserted] {
            let word = try XCTUnwrap(Kit.word(container, id))
            var schedule = SRSState(word: word)
            schedule.memory = nil
            XCTAssertEqual(SRSState(word: word).memory, FSRSMigration.derive(from: schedule, now: t0))
            XCTAssertEqual(word.fsrsStateRawValue, 2)
            XCTAssertEqual(word.fsrsStability, 6)
            XCTAssertFalse(word.isSyncDirty)
        }
    }

    // MARK: Push words

    func testPendingWordsEncodeTheFSRSBlockAndTheFrozenEase() throws {
        let reviewed = try Kit.insertWord(container, polish: "r")
        let plain = try Kit.insertWord(container, polish: "p")
        try Kit.edit(container, reviewed, at: t0) {
            $0.easeFactor = 1.7
            $0.fsrsStateRawValue = 2
            $0.fsrsStability = 12.5
            $0.fsrsDifficulty = 6.2
            $0.fsrsLearningStep = 0
            $0.fsrsLastReviewedAt = self.sampleMemory.lastReviewedAt
        }
        let batch = try store.pendingWords(ownerID: owner, now: t0, excluding: [])
        let byID = Dictionary(uniqueKeysWithValues: batch.rows.map { ($0.id, $0.payload) })
        let sent = try XCTUnwrap(byID[reviewed])
        XCTAssertEqual(sent.easeFactor, 1.7)
        XCTAssertEqual(sent.fsrsState, 2)
        XCTAssertEqual(sent.fsrsStability, 12.5)
        XCTAssertEqual(sent.fsrsDifficulty, 6.2)
        XCTAssertEqual(sent.fsrsLastReview, sampleMemory.lastReviewedAt)
        let derived = try XCTUnwrap(byID[plain])
        XCTAssertEqual(derived.fsrsState, 0, "a never-reviewed word sends the derived new state")
        XCTAssertEqual(derived.fsrsStability, 0)
    }

    // MARK: Pending logs, markPushed, link

    func testPendingReviewLogsAreOrderedAndMarkPushedSetsUploadedAt() throws {
        let wordID = UUID()
        let late = try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-100))
        let early = try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-500))
        try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-300), uploaded: t0)

        let batch = try store.pendingReviewLogs(ownerID: owner, now: t0)
        XCTAssertEqual(batch.rows.map(\.id), [early, late])
        XCTAssertTrue(batch.invalid.isEmpty)
        XCTAssertEqual(batch.rows[0].payload.wordID, wordID)
        XCTAssertEqual(batch.rows[0].payload.rating, "good")

        let snapshots = Dictionary(uniqueKeysWithValues: batch.rows.map { ($0.id, $0.snapshot) })
        try store.markPushed([RemoteAck(id: early, updatedAt: t0)], snapshots: snapshots, kind: .reviewLogs)
        XCTAssertEqual(try store.pendingReviewLogs(ownerID: owner, now: t0).rows.map(\.id), [late])
        XCTAssertEqual(try entries(container).first { $0.id == early }?.uploadedAt, t0)
    }

    func testInvalidLogRowsAreCountedAndStayLocal() throws {
        let entry = try insertEntry(container, wordID: UUID(), at: t0.addingTimeInterval(10 * day))
        let batch = try store.pendingReviewLogs(ownerID: owner, now: t0)
        XCTAssertTrue(batch.rows.isEmpty)
        XCTAssertEqual(batch.invalid, ["invalid_date": 1])
        XCTAssertNil(try entries(container).first { $0.id == entry }?.uploadedAt)
    }

    func testPrepareLinkMakesEveryEntryPendingAgain() throws {
        let wordID = UUID()
        try insertEntry(container, wordID: wordID, uploaded: t0)
        try insertEntry(container, wordID: wordID)
        try store.prepareLink()
        XCTAssertTrue(try entries(container).allSatisfy { $0.uploadedAt == nil })
    }

    // MARK: Engine

    func testLogsArePushedLastInBatchesOfTwoHundredAndOnlyOnce() async throws {
        let wordID = try Kit.insertWord(container, polish: "kot")
        for index in 0..<450 {
            try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-Double(index + 1)))
        }
        let engine = makeEngine(container)
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(remote.callLog.last, "insertReviewLogs")
        XCTAssertEqual(remote.callLog.filter { $0 == "insertReviewLogs" }.count, 3)
        XCTAssertEqual(remote.insertedReviewLogBatches.map(\.count), [200, 200, 50])
        XCTAssertEqual(remote.server.reviewLogs.count, 450)
        XCTAssertGreaterThanOrEqual(report.pushed, 450)
        XCTAssertTrue(try entries(container).allSatisfy { $0.uploadedAt != nil })

        let calls = remote.callLog.count
        _ = try await engine.run(ownerID: owner)
        XCTAssertFalse(remote.callLog.dropFirst(calls).contains("insertReviewLogs"), "nothing is uploaded twice")
    }

    func testALostAckFollowedByARetryIsIdempotent() async throws {
        let wordID = try Kit.insertWord(container, polish: "kot")
        for index in 0..<5 { try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-Double(index + 1))) }
        let engine = makeEngine(container)
        try engine.link(to: owner)
        // Armed only for the log insert: earlier upserts of the cycle would consume it.
        remote.onCall = { [unowned self] name in
            if name == "insertReviewLogs" { self.remote.nextErrorAfterStore = URLError(.networkConnectionLost) }
        }

        do {
            _ = try await engine.run(ownerID: owner)
            XCTFail("the lost response is a transient error")
        } catch {}
        XCTAssertEqual(remote.server.reviewLogs.count, 5, "the server stored the rows")
        XCTAssertTrue(try entries(container).allSatisfy { $0.uploadedAt == nil })

        remote.onCall = nil
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.server.reviewLogs.count, 5, "the retry adds no duplicates")
        XCTAssertTrue(try entries(container).allSatisfy { $0.uploadedAt != nil })
    }

    func testARejectedRowIsIsolatedAndTheRestUploads() async throws {
        let wordID = try Kit.insertWord(container, polish: "kot")
        let bad = try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-10))
        for index in 0..<3 { try insertEntry(container, wordID: wordID, at: t0.addingTimeInterval(-Double(100 + index))) }
        remote.rejectReviewLogWhere = { $0.id == bad }
        let engine = makeEngine(container)
        try engine.link(to: owner)

        let report = try await engine.run(ownerID: owner)

        XCTAssertEqual(report.skipped["server_rejected"], 1)
        XCTAssertEqual(remote.server.reviewLogs.count, 3)
        XCTAssertEqual(try entries(container).filter { $0.uploadedAt == nil }.map(\.id), [bad])
    }

    func testARelinkUploadsEveryEntryAgain() async throws {
        let wordID = try Kit.insertWord(container, polish: "kot")
        try insertEntry(container, wordID: wordID)
        let engine = makeEngine(container)
        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.insertedReviewLogBatches.count, 1)

        try engine.link(to: owner)
        _ = try await engine.run(ownerID: owner)
        XCTAssertEqual(remote.insertedReviewLogBatches.count, 2)
        XCTAssertEqual(remote.server.reviewLogs.count, 1)
    }

    func testAdoptionRekeysOnlyEntriesThatAreNotUploadedYet() async throws {
        let local = try Kit.insertWord(container, russian: "кот", polish: "kot")
        let remoteID = UUID()
        remote.seed(words: [Kit.remoteWord(id: remoteID, term: "kot", translation: "кот",
                                           updatedAt: t0.addingTimeInterval(-60))])
        let engine = makeEngine(container)
        try engine.link(to: owner)
        let pending = try insertEntry(container, wordID: local, at: t0.addingTimeInterval(-50))
        let uploaded = try insertEntry(container, wordID: local, at: t0.addingTimeInterval(-90), uploaded: t0)

        _ = try await engine.run(ownerID: owner)

        XCTAssertEqual(try Kit.words(container).first?.uuid, remoteID)
        let stored = try entries(container)
        XCTAssertEqual(stored.first { $0.id == pending }?.wordID, remoteID, "pending entries follow the new id")
        XCTAssertEqual(stored.first { $0.id == uploaded }?.wordID, local, "uploaded entries are immutable")
        XCTAssertEqual(remote.server.reviewLogs.values.first { $0.id == pending }?.wordID, remoteID)
    }

    func testTwoDevicesPullTheSameMemoryAndDeriveTheSameForUnreviewedWords() async throws {
        let reviewed = try Kit.insertWord(container, polish: "r")
        let unreviewed = try Kit.insertWord(container, polish: "u")
        let engineA = makeEngine(container)
        try engineA.link(to: owner)
        _ = try await engineA.run(ownerID: owner)
        // Device A reviews one word and syncs the new FSRS columns.
        try Kit.edit(container, reviewed, at: t0.addingTimeInterval(10)) { word in
            SRSEngine.apply(.good, to: word, now: self.t0)
        }
        _ = try await engineA.run(ownerID: owner)
        // A server row nobody has reviewed since the FSRS migration: null block.
        let legacy = UUID()
        remote.seed(words: [Kit.remoteWord(id: legacy, term: "legacy", updatedAt: t0.addingTimeInterval(-30),
                                           intervalDays: 8, dueDate: t0.addingTimeInterval(3 * day))])

        let containerB = try Kit.makeContainer()
        let containerC = try Kit.makeContainer()
        for other in [containerB, containerC] {
            try Kit.insertWorkspace(other, syncedAt: workspaceStamp)
            let engine = makeEngine(other)
            try engine.link(to: owner)
            _ = try await engine.run(ownerID: owner)
        }

        let a = try XCTUnwrap(Kit.word(container, reviewed))
        let b = try XCTUnwrap(Kit.word(containerB, reviewed))
        XCTAssertEqual(SRSState(word: b).memory, SRSState(word: a).memory)
        XCTAssertEqual(b.fsrsStateRawValue, 2)
        XCTAssertEqual(try XCTUnwrap(Kit.word(containerB, unreviewed)).fsrsStateRawValue, 0)
        let legacyB = try XCTUnwrap(Kit.word(containerB, legacy))
        let legacyC = try XCTUnwrap(Kit.word(containerC, legacy))
        XCTAssertEqual(SRSState(word: legacyB).memory, SRSState(word: legacyC).memory)
        XCTAssertNotNil(SRSState(word: legacyB).memory)
        XCTAssertFalse(legacyB.isSyncDirty)
    }
}
