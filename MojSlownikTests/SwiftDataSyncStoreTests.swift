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
        XCTAssertEqual(member.folderIDs, [], "a pulled folder tombstone drops the membership, like FolderStore.delete")
        XCTAssertTrue(member.isActive, "removing a folder never deletes words")
        XCTAssertTrue(member.isSyncDirty, "the membership change is pushed")
        XCTAssertEqual(try store.knownFolderIDs(), Set([renamed, removed, insertedID]), "tombstones are known")
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
            context.insert(Word(russian: "р\(index)", polish: "p\(index)", sourceLanguage: .polish,
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
        let folder = try Kit.insertFolder(container)
        let dirty = try Kit.insertWord(container, russian: " Кот ", polish: " Kot\n", source: .polish,
                                       category: .nature, folders: [folder, folder])
        let held = try Kit.insertWord(container, polish: "held")
        _ = try Kit.insertWord(container, polish: "clean", syncedAt: t0.addingTimeInterval(-60))
        let batch = try store.pendingWords(ownerID: Kit.owner, now: t0, excluding: [held])

        XCTAssertEqual(batch.rows.count, 1)
        XCTAssertTrue(batch.invalid.isEmpty)
        let row = try XCTUnwrap(batch.rows.first)
        XCTAssertEqual(row.id, dirty)
        XCTAssertEqual(row.snapshot, try XCTUnwrap(Kit.word(container, dirty)).lastModifiedAt)
        XCTAssertEqual(row.payload.term, "kot")
        XCTAssertEqual(row.payload.termLanguage, "pl")
        XCTAssertEqual(row.payload.translation, "кот")
        XCTAssertEqual(row.payload.translationLanguage, "ru")
        XCTAssertEqual(row.payload.enteredLanguage, "pl")
        XCTAssertEqual(row.payload.category, "nature")
        XCTAssertEqual(row.payload.folderIDs, [folder])
        XCTAssertEqual(row.payload.userID, Kit.owner)
        XCTAssertNil(row.payload.deletedAt)
    }

    func testPendingWordsFallsBackToPolishForAnInvalidEnteredLanguage() throws {
        let id = try Kit.insertWord(container)
        try Kit.edit(container, id, at: t0) { $0.sourceLanguageCode = "xx" }
        let row = try XCTUnwrap(store.pendingWords(ownerID: Kit.owner, now: t0, excluding: []).rows.first)
        XCTAssertEqual(row.payload.enteredLanguage, "pl")
    }

    func testPendingWordsBackfillsMissingIdentity() throws {
        let context = ModelContext(container)
        let legacy = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0.addingTimeInterval(-60))
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

    // MARK: save failure

    func testFailedSaveLeavesNoPartialChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("dictionary.store")
        let id = UUID()
        try autoreleasepool {
            let seed = try ModelContainer(for: Word.self, WordFolder.self,
                                          configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(seed)
            let word = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0.addingTimeInterval(-600))
            word.uuid = id
            word.updatedAt = word.createdAt
            word.serverUpdatedAt = word.createdAt
            context.insert(word)
            try context.save()
        }
        let readOnly = try ModelContainer(for: Word.self, WordFolder.self,
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
