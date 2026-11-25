import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class SwiftDataSyncStoreTests: XCTestCase {
    private typealias Kit = SyncTestKit
    private let t0 = SyncTestKit.t0
    private var container: ModelContainer!
    private var store: SwiftDataSyncStore!

    override func setUpWithError() throws {
        container = try Kit.makeContainer()
        store = SwiftDataSyncStore(container: container, now: { self.t0 })
        // The pl ← ru workspace every legacy-shaped test row belongs to (dirty: never synced).
        try Kit.insertWorkspace(container)
    }

    // MARK: prepareLink

    func testPrepareLinkGivesSentinelToCleanSyncedRowsAndNilToTheRest() throws {
        let synced = t0.addingTimeInterval(-600)
        let clean = try Kit.insertWord(container, polish: "clean", syncedAt: synced)
        let cleanTombstone = try Kit.insertWord(container, polish: "gone", syncedAt: synced, deletedAt: synced)
        let neverSynced = try Kit.insertWord(container, polish: "new")
        let edited = try Kit.insertWord(container, polish: "edited", syncedAt: synced)
        try Kit.edit(container, edited, at: t0) { $0.repetitions = 7 }
        let sentinel = try Kit.insertWord(container, polish: "sentinel")
        try Kit.edit(container, sentinel, at: t0) { $0.serverUpdatedAt = .distantPast }
        let cleanFolder = try Kit.insertFolder(container, name: "A", syncedAt: synced)
        let newFolder = try Kit.insertFolder(container, name: "B")

        try store.prepareLink()

        XCTAssertEqual(try Kit.word(container, clean)?.serverUpdatedAt, .distantPast)
        XCTAssertEqual(try Kit.word(container, cleanTombstone)?.serverUpdatedAt, .distantPast)
        XCTAssertNil(try Kit.word(container, neverSynced)?.serverUpdatedAt)
        XCTAssertNil(try Kit.word(container, edited)?.serverUpdatedAt, "a real local change keeps last-write-wins")
        XCTAssertEqual(try Kit.word(container, sentinel)?.serverUpdatedAt, .distantPast, "an existing sentinel stays")
        let folders = try Kit.folders(container)
        XCTAssertEqual(folders.first { $0.id == cleanFolder }?.serverUpdatedAt, .distantPast)
        XCTAssertNil(folders.first { $0.id == newFolder }?.serverUpdatedAt)
        // Linking never touches content or modification times.
        XCTAssertEqual(try Kit.word(container, clean)?.updatedAt, synced)
        XCTAssertEqual(try Kit.words(container).count, 5)
    }

    // MARK: markPushed

    func testMarkPushedSetsBothFieldsOnlyWhenSnapshotMatches() throws {
        let matching = try Kit.insertWord(container, polish: "a")
        let edited = try Kit.insertWord(container, polish: "b")
        let snapshots = [matching: try XCTUnwrap(Kit.word(container, matching)).lastModifiedAt,
                         edited: try XCTUnwrap(Kit.word(container, edited)).lastModifiedAt]
        try Kit.edit(container, edited, at: t0) { $0.repetitions = 3 }
        let server = t0.addingTimeInterval(5)

        try store.markPushed([RemoteAck(id: matching, updatedAt: server), RemoteAck(id: edited, updatedAt: server),
                              RemoteAck(id: UUID(), updatedAt: server)],
                             snapshots: snapshots, kind: .words)

        let a = try XCTUnwrap(Kit.word(container, matching))
        XCTAssertEqual(a.updatedAt, server)
        XCTAssertEqual(a.serverUpdatedAt, server)
        XCTAssertFalse(a.isSyncDirty)
        let b = try XCTUnwrap(Kit.word(container, edited))
        XCTAssertEqual(b.updatedAt, t0, "an edit made during the request is kept")
        XCTAssertNil(b.serverUpdatedAt)
        XCTAssertTrue(b.isSyncDirty)
    }

    func testMarkPushedForFolders() throws {
        let id = try Kit.insertFolder(container)
        let snapshot = try XCTUnwrap(Kit.folders(container).first).lastModifiedAt
        let server = t0.addingTimeInterval(5)
        try store.markPushed([RemoteAck(id: id, updatedAt: server)], snapshots: [id: snapshot], kind: .folders)
        let folder = try XCTUnwrap(Kit.folders(container).first)
        XCTAssertEqual(folder.serverUpdatedAt, server)
        XCTAssertEqual(folder.updatedAt, server)
    }

    // MARK: apply

    func testApplyWordsInsertUpdateSoftDeleteAndAcknowledge() throws {
        let synced = t0.addingTimeInterval(-600)
        let updated = try Kit.insertWord(container, polish: "u", syncedAt: synced)
        let deleted = try Kit.insertWord(container, polish: "d", syncedAt: synced)
        let alreadyDeleted = try Kit.insertWord(container, polish: "x", syncedAt: synced, deletedAt: synced)
        try Kit.edit(container, alreadyDeleted, at: synced) { $0.serverUpdatedAt = .distantPast }
        let newer = t0.addingTimeInterval(-60)
        let insertedID = UUID()

        let result = try store.applyWords([
            try Kit.validated(Kit.remoteWord(id: updated, term: "u2", translation: "ю", category: "food", updatedAt: newer)),
            try Kit.validated(Kit.remoteWord(id: deleted, term: "d", updatedAt: newer, deletedAt: newer)),
            try Kit.validated(Kit.remoteWord(id: alreadyDeleted, term: "x", updatedAt: newer, deletedAt: newer)),
            try Kit.validated(Kit.remoteWord(id: insertedID, term: "NEW", translation: "Новый", updatedAt: newer)),
        ])

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.softDeleted, 1)
        XCTAssertEqual(result.adopted, 0)
        XCTAssertTrue(result.changedAnything)
        XCTAssertEqual(try Kit.words(container).count, 4, "the row count never decreases")
        let u = try XCTUnwrap(Kit.word(container, updated))
        XCTAssertEqual(u.polish, "u2")
        XCTAssertEqual(u.russian, "ю")
        XCTAssertEqual(u.category, .food)
        XCTAssertEqual(u.serverUpdatedAt, newer)
        XCTAssertEqual(u.updatedAt, newer)
        XCTAssertFalse(u.isSyncDirty)
        let d = try XCTUnwrap(Kit.word(container, deleted))
        XCTAssertEqual(d.deletedAt, newer)
        XCTAssertFalse(d.isSyncDirty)
        let ack = try XCTUnwrap(Kit.word(container, alreadyDeleted))
        XCTAssertEqual(ack.deletedAt, synced, "acknowledge keeps the local tombstone time")
        XCTAssertEqual(ack.serverUpdatedAt, newer)
        XCTAssertFalse(ack.isSyncDirty)
        let inserted = try XCTUnwrap(Kit.word(container, insertedID))
        XCTAssertEqual(inserted.polish, "new", "the Word.init lowercase invariant holds")
        XCTAssertEqual(inserted.russian, "новый")
        XCTAssertFalse(inserted.isSyncDirty)
        XCTAssertTrue(inserted.isActive)
    }

    func testPulledLongScheduleIsClampedAndTheRowStaysClean() throws {
        let synced = t0.addingTimeInterval(-600)
        let existing = try Kit.insertWord(container, polish: "e", syncedAt: synced)
        let newer = t0.addingTimeInterval(-60)
        let insertedID = UUID()
        let far = t0.addingTimeInterval(400 * 86_400)

        _ = try store.applyWords([
            try Kit.validated(Kit.remoteWord(id: existing, term: "e", updatedAt: newer, intervalDays: 400, dueDate: far)),
            try Kit.validated(Kit.remoteWord(id: insertedID, term: "n", updatedAt: newer, intervalDays: 400, dueDate: far)),
        ])

        for id in [existing, insertedID] {
            let word = try XCTUnwrap(Kit.word(container, id))
            XCTAssertLessThanOrEqual(word.intervalDays, SRSEngine.maxLibraryIntervalDays)
            XCTAssertLessThanOrEqual(word.dueDate, t0.addingTimeInterval(33 * 86_400))
            XCTAssertFalse(word.isSyncDirty, "the clamp must not make the pulled row dirty")
            XCTAssertEqual(word.serverUpdatedAt, newer)
        }
    }

    func testLapseCountRoundTripsThroughApplyAndPending() throws {
        let id = UUID()
        _ = try store.applyWords([try Kit.validated(Kit.remoteWord(id: id, updatedAt: t0.addingTimeInterval(-60),
                                                                   lapseCount: 7))])
        XCTAssertEqual(try Kit.word(container, id)?.lapseCount, 7)
        try Kit.edit(container, id, at: t0) { $0.repetitions = 2 }
        let row = try XCTUnwrap(store.pendingWords(ownerID: Kit.owner, now: t0, excluding: []).rows.first)
        XCTAssertEqual(row.payload.lapseCount, 7)
        // A server row without the column reads as 0.
        let legacy = UUID()
        _ = try store.applyWords([try Kit.validated(Kit.remoteWord(id: legacy, updatedAt: t0.addingTimeInterval(-50)))])
        XCTAssertEqual(try Kit.word(container, legacy)?.lapseCount, 0)
    }

    func testApplyWordsRestoresALocalTombstone() throws {
        let synced = t0.addingTimeInterval(-600)
        let id = try Kit.insertWord(container, syncedAt: synced, deletedAt: synced)
        let result = try store.applyWords([try Kit.validated(Kit.remoteWord(id: id, updatedAt: t0))])
        XCTAssertEqual(result.updated, 1)
        XCTAssertTrue(try XCTUnwrap(Kit.word(container, id)).isActive)
    }

    func testApplyFoldersInsertUpdateAndSoftDelete() throws {
        let synced = t0.addingTimeInterval(-600)
        let renamed = try Kit.insertFolder(container, name: "Old", syncedAt: synced)
        let removed = try Kit.insertFolder(container, name: "Gone", syncedAt: synced)
        let word = try Kit.insertWord(container, folders: [removed], syncedAt: synced)
        let insertedID = UUID()
        let newer = t0.addingTimeInterval(-60)

        let result = try store.applyFolders([
            try Kit.validated(Kit.remoteFolder(id: renamed, name: "New", updatedAt: newer)),
            try Kit.validated(Kit.remoteFolder(id: removed, name: "Gone", updatedAt: newer, deletedAt: newer)),
            try Kit.validated(Kit.remoteFolder(id: insertedID, name: "Cloud", updatedAt: newer)),
        ])

        XCTAssertEqual([result.inserted, result.updated, result.softDeleted], [1, 1, 1])
        XCTAssertTrue(result.foldersChanged)
        let folders = try Kit.folders(container)
        XCTAssertEqual(folders.count, 3)
        XCTAssertEqual(folders.first { $0.id == renamed }?.name, "New")
        XCTAssertNotNil(folders.first { $0.id == removed }?.deletedAt)
        XCTAssertEqual(folders.first { $0.id == insertedID }?.serverUpdatedAt, newer)
        let member = try XCTUnwrap(Kit.word(container, word))
        XCTAssertTrue(try Kit.folderIDs(container, of: word).isEmpty,
                      "a pulled folder tombstone tombstones the membership, like FolderStore.delete")
        XCTAssertTrue(member.isActive, "removing a folder never deletes words")
        XCTAssertFalse(member.isSyncDirty, "the word row itself is untouched")
        let membership = try XCTUnwrap(Kit.memberships(container).first)
        XCTAssertNotNil(membership.deletedAt)
        XCTAssertTrue(membership.isSyncDirty, "the membership change is pushed")
        XCTAssertEqual(Set(try store.knownIDs().folders.keys), Set([renamed, removed, insertedID]),
                       "tombstones are known")
    }

    func testEchoChangesNothing() throws {
        let synced = t0.addingTimeInterval(-600)
        let id = try Kit.insertWord(container, polish: "kept", syncedAt: synced)
        let result = try store.applyWords([try Kit.validated(Kit.remoteWord(id: id, term: "other", updatedAt: synced))])
        XCTAssertFalse(result.changedAnything)
        XCTAssertEqual(try Kit.word(container, id)?.polish, "kept")
    }

    /// Shape guard instead of a wall-clock bound: the adoption index is built once per call and
    /// every unsynced local word is adopted without inserts.
    func testAdoptionBuildsItsIndexOncePerCallForThousandsOfWords() throws {
        let count = 2_000
        var remote: [ValidatedRemoteWord] = []
        let context = ModelContext(container)
        for index in 0..<count {
            context.insert(Word(russian: "р\(index)", polish: "p\(index)", side: .term,
                                createdAt: t0.addingTimeInterval(-7_200)))
            remote.append(try Kit.validated(Kit.remoteWord(term: "P\(index)", translation: "Р\(index)",
                                                           updatedAt: t0.addingTimeInterval(-60))))
        }
        try context.save()

        let before = SwiftDataSyncStore.adoptionIndexBuilds
        let result = try store.applyWords(remote)

        XCTAssertEqual(SwiftDataSyncStore.adoptionIndexBuilds - before, 1)
        XCTAssertEqual(result.adopted, count)
        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(try Kit.words(container).count, count)
        XCTAssertEqual(Set(try Kit.words(container).compactMap(\.uuid)), Set(remote.map(\.id)))
    }

    func testAdoptedFolderIsAdoptedOnlyOnce() throws {
        try Kit.insertFolder(container, name: "Урок")
        let first = try Kit.validated(Kit.remoteFolder(name: "урок", updatedAt: t0.addingTimeInterval(-60)))
        let second = try Kit.validated(Kit.remoteFolder(name: "Урок ", updatedAt: t0.addingTimeInterval(-50)))
        let result = try store.applyFolders([first, second])
        XCTAssertEqual(result.adopted, 1)
        XCTAssertEqual(result.inserted, 1, "the second remote row is a genuine duplicate name")
        XCTAssertEqual(try Kit.folders(container).count, 2)
    }

    // MARK: pending rows

    func testPendingWordsMapsWireFormatAndSkipsHeldAndCleanRows() throws {
        let dirty = try Kit.insertWord(container, russian: " Кот ", polish: " Kot\n", source: .term,
                                       category: .nature)
        let held = try Kit.insertWord(container, polish: "held")
        _ = try Kit.insertWord(container, polish: "clean", syncedAt: t0.addingTimeInterval(-60))
        let batch = try store.pendingWords(ownerID: Kit.owner, now: t0, excluding: [held])

        XCTAssertEqual(batch.rows.count, 1)
        XCTAssertTrue(batch.invalid.isEmpty)
        let row = try XCTUnwrap(batch.rows.first)
        XCTAssertEqual(row.id, dirty)
        XCTAssertEqual(row.snapshot, try XCTUnwrap(Kit.word(container, dirty)).lastModifiedAt)
        XCTAssertEqual(row.payload.term, "kot")
        XCTAssertEqual(row.payload.translation, "кот")
        XCTAssertEqual(row.payload.workspaceID, WorkspaceID.legacy)
        XCTAssertEqual(row.payload.enteredSide, "term")
        XCTAssertEqual(row.payload.category, "nature")
        XCTAssertEqual(row.payload.userID, Kit.owner)
        XCTAssertNil(row.payload.deletedAt)
    }

    func testPendingWordsFallsBackToTermForAnUnknownSideCode() throws {
        let id = try Kit.insertWord(container)
        try Kit.edit(container, id, at: t0) { $0.sourceLanguageCode = "xx" }
        let row = try XCTUnwrap(store.pendingWords(ownerID: Kit.owner, now: t0, excluding: []).rows.first)
        XCTAssertEqual(row.payload.enteredSide, "term")
    }

    func testPendingWordsBackfillsMissingIdentity() throws {
        let context = ModelContext(container)
        let legacy = Word(russian: "в", polish: "w", side: .term, createdAt: t0.addingTimeInterval(-60))
        legacy.uuid = nil
        context.insert(legacy)
        try context.save()
        let batch = try store.pendingWords(ownerID: Kit.owner, now: t0, excluding: [])
        XCTAssertEqual(batch.rows.count, 1)
        XCTAssertNotNil(try Kit.words(container).first?.uuid)
    }

    func testPendingRowsIncludeTombstonesAndCountInvalidRows() throws {
        let tombstone = try Kit.insertWord(container, polish: "tomb", deletedAt: t0.addingTimeInterval(-60))
        try Kit.insertWord(container, polish: String(repeating: "a", count: 501))
        let folder = try Kit.insertFolder(container, name: "   ")
        let words = try store.pendingWords(ownerID: Kit.owner, now: t0, excluding: [])
        XCTAssertEqual(words.rows.map(\.id), [tombstone])
        XCTAssertNotNil(words.rows.first?.payload.deletedAt)
        XCTAssertEqual(words.invalid, ["invalid_text": 1])
        let folders = try store.pendingFolders(ownerID: Kit.owner, now: t0, excluding: [])
        XCTAssertTrue(folders.rows.isEmpty)
        XCTAssertEqual(folders.invalid, ["invalid_text": 1])
        XCTAssertNotNil(try Kit.folders(container).first { $0.id == folder })
    }

    // MARK: workspaces, memberships, scoped adoption (v2)

    func testPrepareLinkCoversWorkspacesAndMemberships() throws {
        let synced = t0.addingTimeInterval(-600)
        let cleanWorkspace = try Kit.insertWorkspace(container, term: "de", translation: "ru", syncedAt: synced)
        let word = try Kit.insertWord(container, syncedAt: synced)
        let folder = try Kit.insertFolder(container, syncedAt: synced)
        let cleanMembership = try Kit.insertMembership(container, wordID: word, folderID: folder, syncedAt: synced)
        let newMembership = try Kit.insertMembership(container, wordID: word, folderID: UUID())

        try store.prepareLink()

        let workspaces = try Kit.workspaces(container)
        XCTAssertEqual(workspaces.first { $0.id == cleanWorkspace }?.serverUpdatedAt, .distantPast)
        XCTAssertNil(workspaces.first { $0.id == WorkspaceID.legacy }?.serverUpdatedAt, "a never-synced row stays nil")
        let memberships = try Kit.memberships(container)
        XCTAssertEqual(memberships.first { $0.id == cleanMembership }?.serverUpdatedAt, .distantPast)
        XCTAssertNil(memberships.first { $0.id == newMembership }?.serverUpdatedAt)
    }

    func testApplyWorkspacesInsertsUpdatesAndMaterializesTombstones() throws {
        let synced = t0.addingTimeInterval(-600)
        let newer = t0.addingTimeInterval(-60)
        let existing = try Kit.insertWorkspace(container, term: "uk", translation: "ru", syncedAt: synced)

        let result = try store.applyWorkspaces([
            try Kit.validated(Kit.remoteWorkspace(term: "de", translation: "ru", sortOrder: 4, updatedAt: newer)),
            try Kit.validated(Kit.remoteWorkspace(term: "uk", translation: "ru", sortOrder: 2, updatedAt: newer)),
            try Kit.validated(Kit.remoteWorkspace(term: "fr", translation: "ru", updatedAt: newer, deletedAt: newer)),
        ])

        XCTAssertEqual([result.inserted, result.updated], [2, 1])
        let rows = try Kit.workspaces(container)
        let de = try XCTUnwrap(rows.first { $0.id == WorkspaceID.make(term: "de", translation: "ru") })
        XCTAssertEqual(de.sortOrder, 4)
        XCTAssertEqual(de.serverUpdatedAt, newer)
        XCTAssertFalse(de.isSyncDirty)
        XCTAssertEqual(rows.first { $0.id == existing }?.sortOrder, 2)
        let fr = try XCTUnwrap(rows.first { $0.id == WorkspaceID.make(term: "fr", translation: "ru") })
        XCTAssertEqual(fr.deletedAt, newer, "a remote workspace tombstone is stored")
        XCTAssertFalse(fr.isSyncDirty, "and stays clean (never pushed)")
        XCTAssertEqual(rows.count, 4)
    }

    func testApplyWorkspaceTombstoneHidesAnActiveCleanWorkspace() throws {
        let synced = t0.addingTimeInterval(-600)
        let id = try Kit.insertWorkspace(container, term: "de", translation: "ru", syncedAt: synced)
        let result = try store.applyWorkspaces([
            try Kit.validated(Kit.remoteWorkspace(term: "de", translation: "ru", updatedAt: t0, deletedAt: t0))])
        XCTAssertEqual(result.softDeleted, 1)
        XCTAssertEqual(try Kit.workspaces(container).first { $0.id == id }?.deletedAt, t0)
    }

    func testApplyWordsKeepsGermanCaseAndTakesWorkspaceAndSide() throws {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        try Kit.insertWorkspace(container, term: "de", translation: "ru", syncedAt: t0.addingTimeInterval(-600))
        let known = KnownRemoteIDs(workspaceIDs: [de])
        let id = UUID()
        let result = try store.applyWords([try Kit.validated(
            Kit.remoteWord(id: id, term: "Haus", translation: "Дом", workspace: de, entered: "term",
                           updatedAt: t0.addingTimeInterval(-60)), known: known)])
        XCTAssertEqual(result.inserted, 1)
        let word = try XCTUnwrap(Kit.word(container, id))
        XCTAssertEqual(word.term, "Haus", "German keeps its case")
        XCTAssertEqual(word.translation, "дом", "the Russian side is lowercased")
        XCTAssertEqual(word.workspaceID, de)
        XCTAssertEqual(word.sourceLanguageCode, "de", "entered_side term = the term language code")
        XCTAssertFalse(word.isSyncDirty)
    }

    func testWordAdoptionIsScopedToTheWorkspace() throws {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        let known = KnownRemoteIDs(workspaceIDs: [de, WorkspaceID.legacy])
        let local = try Kit.insertWord(container, russian: "кот", polish: "kot")
        let remoteID = UUID()
        // Same texts but another workspace: inserted, not adopted.
        var result = try store.applyWords([try Kit.validated(
            Kit.remoteWord(id: remoteID, term: "kot", translation: "кот", workspace: de,
                           updatedAt: t0.addingTimeInterval(-60)), known: known)])
        XCTAssertEqual([result.adopted, result.inserted], [0, 1])
        XCTAssertEqual(try Kit.words(container).count, 2)
        // Same workspace: adopted, and the memberships follow the new id.
        let folder = try Kit.insertFolder(container)
        try Kit.insertMembership(container, wordID: local, folderID: folder)
        let adoptedRemote = UUID()
        result = try store.applyWords([try Kit.validated(
            Kit.remoteWord(id: adoptedRemote, term: "kot", translation: "кот",
                           updatedAt: t0.addingTimeInterval(-50)), known: known)])
        XCTAssertEqual(result.adopted, 1)
        XCTAssertEqual(try Kit.words(container).count, 2)
        let memberships = try Kit.memberships(container)
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships[0].wordID, adoptedRemote)
        XCTAssertEqual(memberships[0].id, MembershipID.make(wordID: adoptedRemote, folderID: folder))
        XCTAssertNil(memberships[0].serverUpdatedAt)
        XCTAssertTrue(memberships[0].isSyncDirty, "the re-keyed membership is pushed")
    }

    func testFolderAdoptionIsScopedAndRekeysMemberships() throws {
        let de = WorkspaceID.make(term: "de", translation: "ru")
        let known = KnownRemoteIDs(workspaceIDs: [de, WorkspaceID.legacy])
        let localFolder = try Kit.insertFolder(container, name: "Урок")
        let word = try Kit.insertWord(container)
        try Kit.insertMembership(container, wordID: word, folderID: localFolder)
        let otherWorkspaceFolder = UUID()
        var result = try store.applyFolders([try Kit.validated(
            Kit.remoteFolder(id: otherWorkspaceFolder, name: "урок", workspace: de,
                             updatedAt: t0.addingTimeInterval(-60)), known: known)])
        XCTAssertEqual([result.adopted, result.inserted], [0, 1], "another workspace never adopts")
        let remoteID = UUID()
        result = try store.applyFolders([try Kit.validated(
            Kit.remoteFolder(id: remoteID, name: "УРОК", updatedAt: t0.addingTimeInterval(-50)), known: known)])
        XCTAssertEqual(result.adopted, 1)
        let membership = try XCTUnwrap(Kit.memberships(container).first)
        XCTAssertEqual(membership.folderID, remoteID)
        XCTAssertEqual(membership.id, MembershipID.make(wordID: word, folderID: remoteID))
        XCTAssertTrue(membership.isSyncDirty)
    }

    func testApplyMembershipsInsertUpdateAndTombstone() throws {
        let synced = t0.addingTimeInterval(-600)
        let newer = t0.addingTimeInterval(-60)
        let word = try Kit.insertWord(container, syncedAt: synced)
        let folderA = try Kit.insertFolder(container, name: "A", syncedAt: synced)
        let folderB = try Kit.insertFolder(container, name: "B", syncedAt: synced)
        let folderC = try Kit.insertFolder(container, name: "C", syncedAt: synced)
        try Kit.insertMembership(container, wordID: word, folderID: folderB, syncedAt: synced)
        try Kit.insertMembership(container, wordID: word, folderID: folderC, syncedAt: synced)
        var known = try store.knownIDs()
        known.workspaceIDs.insert(WorkspaceID.legacy)

        let result = try store.applyMemberships([
            try Kit.validated(Kit.remoteMembership(wordID: word, folderID: folderA, updatedAt: newer), known: known),
            try Kit.validated(Kit.remoteMembership(wordID: word, folderID: folderB, updatedAt: newer,
                                                   deletedAt: newer), known: known),
            // Echo of the synced version: nothing changes.
            try Kit.validated(Kit.remoteMembership(wordID: word, folderID: folderC, updatedAt: synced),
                              known: known),
        ])

        XCTAssertEqual([result.inserted, result.softDeleted], [1, 1])
        XCTAssertEqual(try Kit.folderIDs(container, of: word), [folderA, folderC])
        let memberships = try Kit.memberships(container)
        XCTAssertEqual(memberships.count, 3, "the tombstone row stays")
        XCTAssertTrue(memberships.allSatisfy { !$0.isSyncDirty })
    }

    func testMembershipTombstoneWithoutLocalRowIsNotMaterialized() throws {
        let word = try Kit.insertWord(container, syncedAt: t0.addingTimeInterval(-600))
        let folder = try Kit.insertFolder(container, syncedAt: t0.addingTimeInterval(-600))
        var known = try store.knownIDs()
        known.workspaceIDs.insert(WorkspaceID.legacy)
        _ = try store.applyMemberships([try Kit.validated(
            Kit.remoteMembership(wordID: word, folderID: folder, updatedAt: t0, deletedAt: t0), known: known)])
        XCTAssertTrue(try Kit.memberships(container).isEmpty)
    }

    func testPulledWordTombstoneTombstonesItsMemberships() throws {
        let synced = t0.addingTimeInterval(-600)
        let word = try Kit.insertWord(container, syncedAt: synced)
        let folder = try Kit.insertFolder(container, syncedAt: synced)
        try Kit.insertMembership(container, wordID: word, folderID: folder, syncedAt: synced)
        _ = try store.applyWords([try Kit.validated(Kit.remoteWord(id: word, updatedAt: t0, deletedAt: t0))])
        XCTAssertNotNil(try Kit.word(container, word)?.deletedAt, "the word is soft-deleted, never removed")
        let membership = try XCTUnwrap(Kit.memberships(container).first)
        XCTAssertNotNil(membership.deletedAt)
        XCTAssertTrue(membership.isSyncDirty)
    }

    func testPendingWorkspacesAndMemberships() throws {
        let synced = t0.addingTimeInterval(-600)
        let word = try Kit.insertWord(container, syncedAt: synced)
        let folder = try Kit.insertFolder(container, syncedAt: synced)
        let heldWord = try Kit.insertWord(container, polish: "held", syncedAt: synced)
        let unsyncedWord = try Kit.insertWord(container, polish: "new")
        try Kit.insertMembership(container, wordID: word, folderID: folder)
        try Kit.insertMembership(container, wordID: heldWord, folderID: folder)
        try Kit.insertMembership(container, wordID: unsyncedWord, folderID: folder)

        let workspaces = try store.pendingWorkspaces(ownerID: Kit.owner, now: t0, excluding: [])
        XCTAssertEqual(workspaces.rows.map(\.id), [WorkspaceID.legacy])
        XCTAssertEqual(workspaces.rows.first?.payload.termLanguage, "pl")

        let batch = try store.pendingMemberships(ownerID: Kit.owner, now: t0, excluding: [heldWord])
        // Skipped (kept dirty, not invalid): a held word, an unsynced word.
        XCTAssertEqual(Set(batch.rows.map(\.payload.wordID)), [word])
        XCTAssertTrue(batch.invalid.isEmpty)
        XCTAssertEqual(batch.rows.first?.payload.folderID, folder)
        XCTAssertEqual(batch.rows.first?.payload.workspaceID, WorkspaceID.legacy)
        // A session-rejected folder blocks its memberships too.
        let rejected = try store.pendingMemberships(ownerID: Kit.owner, now: t0, excluding: [], rejected: [folder])
        XCTAssertTrue(rejected.rows.isEmpty)
    }

    func testMarkPushedForWorkspacesAndMemberships() throws {
        let word = try Kit.insertWord(container)
        let folder = try Kit.insertFolder(container)
        let membershipID = try Kit.insertMembership(container, wordID: word, folderID: folder)
        let membership = try XCTUnwrap(Kit.memberships(container).first)
        let workspace = try XCTUnwrap(Kit.workspaces(container).first)
        let server = t0.addingTimeInterval(5)
        try store.markPushed([RemoteAck(id: membershipID, updatedAt: server)],
                             snapshots: [membershipID: membership.lastModifiedAt], kind: .memberships)
        try store.markPushed([RemoteAck(id: workspace.id, updatedAt: server)],
                             snapshots: [workspace.id: workspace.lastModifiedAt], kind: .workspaces)
        XCTAssertEqual(try Kit.memberships(container).first?.serverUpdatedAt, server)
        XCTAssertEqual(try Kit.workspaces(container).first?.serverUpdatedAt, server)
        // An edit during the request keeps the row dirty.
        try store.markPushed([RemoteAck(id: membershipID, updatedAt: server.addingTimeInterval(1))],
                             snapshots: [membershipID: t0.addingTimeInterval(-99_999)], kind: .memberships)
        XCTAssertEqual(try Kit.memberships(container).first?.serverUpdatedAt, server)
    }

    func testWordPayloadHasExactlyTheV2Keys() throws {
        try Kit.insertWord(container)
        let row = try XCTUnwrap(store.pendingWords(ownerID: Kit.owner, now: t0, excluding: []).rows.first)
        let data = try JSONEncoder().encode(row.payload)
        let keys = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
        XCTAssertTrue(keys.isSuperset(of: ["workspace_id", "entered_side", "term", "translation"]))
        XCTAssertTrue(keys.isDisjoint(with: ["term_language", "translation_language", "entered_language",
                                             "folder_ids"]))
    }

    // MARK: save failure

    func testFailedSaveLeavesNoPartialChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictionary.store")
        let id = UUID()
        try autoreleasepool {
            let seed = try ModelContainer(for: AppSchema.schema,
                                          configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(seed)
            let word = Word(russian: "в", polish: "w", side: .term, createdAt: t0.addingTimeInterval(-600))
            word.uuid = id
            word.updatedAt = word.createdAt
            word.serverUpdatedAt = word.createdAt
            context.insert(word)
            try context.save()
        }
        let readOnly = try ModelContainer(for: AppSchema.schema,
                                          configurations: ModelConfiguration(url: url, allowsSave: false,
                                                                             cloudKitDatabase: .none))
        let failing = SwiftDataSyncStore(container: readOnly, now: { self.t0 })

        XCTAssertThrowsError(try failing.applyWords([
            try Kit.validated(Kit.remoteWord(id: id, term: "changed", updatedAt: t0.addingTimeInterval(-60))),
            try Kit.validated(Kit.remoteWord(term: "added", updatedAt: t0.addingTimeInterval(-60))),
        ]))
        XCTAssertThrowsError(try failing.prepareLink())

        let words = try Kit.words(readOnly)
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.polish, "w")
        XCTAssertEqual(words.first?.serverUpdatedAt, words.first?.createdAt, "prepareLink was rolled back")
    }
}
