import XCTest
@testable import MojSlownik

final class RemoteMergePolicyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var t1: Date { t0.addingTimeInterval(60) }
    private var t2: Date { t0.addingTimeInterval(120) }
    private let sentinel = Date.distantPast

    private func decide(local: LocalRecordState?, updatedAt: Date, deletedAt: Date? = nil) -> RemoteMergeDecision {
        RemoteMergePolicy.decide(local: local, remoteUpdatedAt: updatedAt, remoteDeletedAt: deletedAt)
    }

    private func state(_ serverUpdatedAt: Date?, dirty: Bool, deleted: Bool = false) -> LocalRecordState {
        LocalRecordState(serverUpdatedAt: serverUpdatedAt, isDirty: dirty, isDeleted: deleted)
    }

    // 1. No local row
    func testNewActiveRemoteRowIsInserted() {
        XCTAssertEqual(decide(local: nil, updatedAt: t1), .insert)
    }

    func testNewRemoteTombstoneIsNotMaterialized() {
        XCTAssertEqual(decide(local: nil, updatedAt: t1, deletedAt: t1), .keepLocal)
    }

    // 2. Re-link sentinel: the server wins, newer or older
    func testSentinelRowTakesTheServerVersionWhateverItsTime() {
        for remote in [t0, t2] {
            XCTAssertEqual(decide(local: state(sentinel, dirty: true), updatedAt: remote), .update)
            XCTAssertEqual(decide(local: state(sentinel, dirty: true, deleted: true), updatedAt: remote), .update,
                           "a remote active row restores a local tombstone")
            XCTAssertEqual(decide(local: state(sentinel, dirty: true), updatedAt: remote, deletedAt: remote),
                           .softDelete(at: remote))
            XCTAssertEqual(decide(local: state(sentinel, dirty: true, deleted: true), updatedAt: remote, deletedAt: remote),
                           .acknowledge)
        }
    }

    // 3. Echo or stale row
    func testEchoAndStaleRowsKeepLocal() {
        let local = state(t1, dirty: false)
        XCTAssertEqual(decide(local: local, updatedAt: t1), .keepLocal, "a tie with a real base keeps local")
        XCTAssertEqual(decide(local: local, updatedAt: t0), .keepLocal)
        XCTAssertEqual(decide(local: local, updatedAt: t0, deletedAt: t0), .keepLocal)
        XCTAssertEqual(decide(local: state(t1, dirty: true), updatedAt: t1, deletedAt: t1), .keepLocal,
                       "even a dirty row ignores a stale tombstone")
    }

    // 4. Local row not dirty
    func testCleanLocalRowFollowsNewerRemote() {
        XCTAssertEqual(decide(local: state(t0, dirty: false), updatedAt: t1), .update)
        XCTAssertEqual(decide(local: state(t0, dirty: false), updatedAt: t1, deletedAt: t1), .softDelete(at: t1))
        XCTAssertEqual(decide(local: state(t0, dirty: false, deleted: true), updatedAt: t1, deletedAt: t1), .acknowledge)
        XCTAssertEqual(decide(local: state(t0, dirty: false, deleted: true), updatedAt: t1), .update,
                       "a newer active remote row restores a local tombstone")
    }

    // 5. Local row dirty: a true concurrent change
    func testDirtyLocalRowKeepsLocalAgainstNewerActiveRemote() {
        XCTAssertEqual(decide(local: state(t0, dirty: true), updatedAt: t1), .keepLocal)
        XCTAssertEqual(decide(local: state(nil, dirty: true), updatedAt: t1), .keepLocal, "never synced")
    }

    func testRemoteTombstoneBeatsDirtyActiveLocalEdit() {
        XCTAssertEqual(decide(local: state(t0, dirty: true), updatedAt: t1, deletedAt: t1), .softDelete(at: t1))
        XCTAssertEqual(decide(local: state(nil, dirty: true), updatedAt: t1, deletedAt: t1), .softDelete(at: t1))
    }

    func testDirtyLocalTombstoneKeepsLocalAgainstRemoteTombstone() {
        XCTAssertEqual(decide(local: state(t0, dirty: true, deleted: true), updatedAt: t1, deletedAt: t1), .keepLocal)
        XCTAssertEqual(decide(local: state(t0, dirty: true, deleted: true), updatedAt: t1), .keepLocal,
                       "a dirty local delete is pushed, not undone by an older remote edit")
    }

    /// The decision type has no hard-delete case; this switch stops compiling if one is added.
    func testNoDecisionHardDeletes() {
        let all: [RemoteMergeDecision] = [.insert, .update, .softDelete(at: t0), .keepLocal, .acknowledge,
                                          .insertTombstone(at: t0)]
        for decision in all {
            switch decision {
            case .insert, .update, .softDelete, .keepLocal, .acknowledge, .insertTombstone: break
            }
        }
    }

    func testLocalStateComesFromWordAndFolder() {
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: t0)
        XCTAssertEqual(word.localRecordState, LocalRecordState(serverUpdatedAt: nil, isDirty: true, isDeleted: false))
        word.serverUpdatedAt = t0
        XCTAssertFalse(word.isSyncDirty)
        XCTAssertEqual(word.localRecordState, LocalRecordState(serverUpdatedAt: t0, isDirty: false, isDeleted: false))
        word.markDeleted(now: t1)
        XCTAssertTrue(word.isSyncDirty)
        XCTAssertEqual(word.localRecordState, LocalRecordState(serverUpdatedAt: t0, isDirty: true, isDeleted: true))
        word.serverUpdatedAt = .distantPast
        XCTAssertTrue(word.isSyncDirty, "the sentinel never equals a real modification time")

        let folder = WordFolder(name: "Еда")
        XCTAssertTrue(folder.isSyncDirty)
        folder.serverUpdatedAt = folder.lastModifiedAt
        XCTAssertFalse(folder.isSyncDirty)
        folder.markDeleted(now: t1)
        XCTAssertEqual(folder.localRecordState,
                       LocalRecordState(serverUpdatedAt: folder.serverUpdatedAt, isDirty: true, isDeleted: true))
    }

    /// Dirty state is equality, not ordering: a backwards device clock still marks a row dirty.
    func testDirtyIsEqualityNotOrdering() {
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: t1)
        word.serverUpdatedAt = t1
        word.updatedAt = t0
        XCTAssertTrue(word.isSyncDirty)
    }

    func testSentinelEditedSinceLinkIsAnOrdinaryDirtyEdit() {
        let edited = LocalRecordState(serverUpdatedAt: sentinel, isDirty: true, isDeleted: false, editedSinceLink: true)
        XCTAssertEqual(decide(local: edited, updatedAt: t1), .keepLocal, "the local edit is pushed")
        XCTAssertEqual(decide(local: edited, updatedAt: t1, deletedAt: t1), .softDelete(at: t1), "delete still wins")
        let untouched = LocalRecordState(serverUpdatedAt: sentinel, isDirty: true, isDeleted: false)
        XCTAssertEqual(decide(local: untouched, updatedAt: t0), .update, "an untouched sentinel row follows the server")
    }

    func testEditedSinceLinkComesFromTheRowsOwnModificationTime() {
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: t0)
        word.serverUpdatedAt = sentinel
        XCTAssertFalse(word.localRecordState(linkedAt: t1).editedSinceLink)
        XCTAssertFalse(word.localRecordState(linkedAt: nil).editedSinceLink)
        word.updatedAt = t2
        XCTAssertTrue(word.localRecordState(linkedAt: t1).editedSinceLink)
        XCTAssertFalse(word.localRecordState(linkedAt: t2).editedSinceLink, "equal to the link time is not an edit")
        word.serverUpdatedAt = t0
        XCTAssertFalse(word.localRecordState(linkedAt: t1).editedSinceLink, "only sentinel rows qualify")
        let folder = WordFolder(name: "x")
        folder.serverUpdatedAt = sentinel
        folder.updatedAt = t2
        XCTAssertTrue(folder.localRecordState(linkedAt: t1).editedSinceLink)
    }

    // MARK: Workspaces and memberships

    private func workspace(deletedAt: Date? = nil, updatedAt: Date) -> ValidatedRemoteWorkspace {
        ValidatedRemoteWorkspace(id: WorkspaceID.legacy, termLanguage: "pl", translationLanguage: "ru", sortOrder: 0,
                                 createdAt: t0, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private func membership(deletedAt: Date? = nil, updatedAt: Date) -> ValidatedRemoteMembership {
        ValidatedRemoteMembership(workspaceID: WorkspaceID.legacy, wordID: UUID(), folderID: UUID(),
                                  createdAt: t0, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private func wordRecord(deletedAt: Date?) -> ValidatedRemoteWord {
        ValidatedRemoteWord(id: UUID(), workspaceID: WorkspaceID.legacy, term: "kot", translation: "кот",
                            enteredSide: .term, category: .other, createdAt: t0, updatedAt: t1, deletedAt: deletedAt,
                            easeFactor: 2.5, intervalDays: 1, repetitions: 1, dueDate: t1, lastReviewGrade: nil,
                            knowledgeTier: nil, consecutiveSoftMisses: 0)
    }

    /// The documented workspace-only exception: a remote tombstone with no local row is stored.
    func testWorkspaceTombstoneWithoutLocalRowIsMaterialized() {
        XCTAssertEqual(RemoteMergePolicy.decide(local: nil, remote: workspace(deletedAt: t1, updatedAt: t1)),
                       .insertTombstone(at: t1))
        XCTAssertEqual(RemoteMergePolicy.decide(local: nil, remote: workspace(updatedAt: t1)), .insert)
    }

    func testOtherKindsStillNeverMaterializeTombstones() {
        XCTAssertEqual(RemoteMergePolicy.decide(local: nil, remote: wordRecord(deletedAt: t1)), .keepLocal)
        XCTAssertEqual(RemoteMergePolicy.decide(local: nil, remote: ValidatedRemoteFolder(
            id: UUID(), workspaceID: WorkspaceID.legacy, name: "x", sortOrder: 0, createdAt: t0, updatedAt: t1,
            deletedAt: t1)), .keepLocal)
        XCTAssertEqual(RemoteMergePolicy.decide(local: nil, remote: membership(deletedAt: t1, updatedAt: t1)),
                       .keepLocal)
    }

    func testMembershipAndWorkspaceFollowTheSameRules() {
        let clean = LocalRecordState(serverUpdatedAt: t0, isDirty: false, isDeleted: false)
        XCTAssertEqual(RemoteMergePolicy.decide(local: clean, remote: membership(updatedAt: t1)), .update)
        XCTAssertEqual(RemoteMergePolicy.decide(local: clean, remote: membership(deletedAt: t1, updatedAt: t1)),
                       .softDelete(at: t1))
        XCTAssertEqual(RemoteMergePolicy.decide(local: clean, remote: workspace(updatedAt: t0)), .keepLocal,
                       "an echo of the synced version changes nothing")
        let dirty = LocalRecordState(serverUpdatedAt: nil, isDirty: true, isDeleted: false)
        XCTAssertEqual(RemoteMergePolicy.decide(local: dirty, remote: membership(updatedAt: t1)), .keepLocal)
    }

    func testLocalStateComesFromWorkspaceAndMembership() {
        let workspace = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        XCTAssertEqual(workspace.localRecordState(linkedAt: nil),
                       LocalRecordState(serverUpdatedAt: nil, isDirty: true, isDeleted: false))
        workspace.serverUpdatedAt = workspace.lastModifiedAt
        XCTAssertFalse(workspace.localRecordState(linkedAt: nil).isDirty)
        let membership = FolderMembership(wordID: UUID(), folderID: UUID(), workspaceID: WorkspaceID.legacy,
                                          createdAt: t0)
        membership.markDeleted(now: t1)
        XCTAssertEqual(membership.localRecordState(linkedAt: nil),
                       LocalRecordState(serverUpdatedAt: nil, isDirty: true, isDeleted: true))
    }
}
