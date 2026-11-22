import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class WorkspaceBackfillTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var container: ModelContainer!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        container = try ModelContainer(for: AppSchema.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: "WorkspaceBackfillTests.\(UUID().uuidString)")!
    }

    @discardableResult
    private func backfill(save: ((ModelContext) throws -> Void)? = nil) -> Bool {
        if let save { return WorkspaceBackfill.run(container: container, defaults: defaults, now: now, save: save) }
        return WorkspaceBackfill.run(container: container, defaults: defaults, now: now)
    }

    private func insertLegacyRows(updated: Date? = nil, synced: Date? = nil) throws {
        let context = ModelContext(container)
        for index in 0..<2 {
            let word = Word(russian: "в\(index)", polish: "w\(index)", side: .term,
                            createdAt: t0.addingTimeInterval(Double(index) * 10))
            word.updatedAt = updated
            word.serverUpdatedAt = synced
            word.repetitions = 5
            context.insert(word)
        }
        let folder = WordFolder(name: "Урок")
        folder.createdAt = t0.addingTimeInterval(-100)
        folder.updatedAt = updated
        folder.serverUpdatedAt = synced
        context.insert(folder)
        try context.save()
    }

    private func workspaces() throws -> [Workspace] {
        try ModelContext(container).fetch(FetchDescriptor<Workspace>())
    }

    func testExistingDataGetsLegacyWorkspaceAndAssignmentWithoutTouchingSyncFields() throws {
        let synced = t0.addingTimeInterval(500)
        try insertLegacyRows(updated: synced, synced: synced)

        XCTAssertTrue(backfill())

        let all = try workspaces()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, WorkspaceID.legacy)
        XCTAssertEqual([all[0].termLanguageCode, all[0].translationLanguageCode], ["pl", "ru"])
        XCTAssertEqual(all[0].sortOrder, 0)
        XCTAssertEqual(all[0].createdAt, t0.addingTimeInterval(-100), "earliest word/folder createdAt")
        XCTAssertEqual(all[0].updatedAt, all[0].createdAt)
        XCTAssertNil(all[0].serverUpdatedAt)
        let context = ModelContext(container)
        for word in try context.fetch(FetchDescriptor<Word>()) {
            XCTAssertEqual(word.workspaceID, WorkspaceID.legacy)
            XCTAssertEqual(word.updatedAt, synced)
            XCTAssertEqual(word.serverUpdatedAt, synced)
            XCTAssertFalse(word.isSyncDirty, "migrated rows stay clean")
            XCTAssertEqual(word.repetitions, 5)
        }
        let folder = try XCTUnwrap(context.fetch(FetchDescriptor<WordFolder>()).first)
        XCTAssertEqual(folder.workspaceID, WorkspaceID.legacy)
        XCTAssertEqual(folder.updatedAt, synced)
        XCTAssertEqual(folder.serverUpdatedAt, synced)
        XCTAssertTrue(defaults.bool(forKey: WorkspaceBackfill.markerKey))
    }

    func testSecondRunIsANoOp() throws {
        try insertLegacyRows()
        backfill()
        let before = try workspaces().map { [$0.id.uuidString, "\($0.createdAt.timeIntervalSince1970)"] }
        backfill()
        XCTAssertEqual(try workspaces().map { [$0.id.uuidString, "\($0.createdAt.timeIntervalSince1970)"] }, before)
        XCTAssertEqual(try workspaces().count, 1)
    }

    func testFreshInstallWithOnlySyncDefaultsCreatesNoWorkspaceAndWritesTheMarker() throws {
        defaults.set(Data("{}".utf8), forKey: "sync.v1")
        defaults.set(Data("{}".utf8), forKey: "achievements.v1")

        XCTAssertTrue(backfill())

        // A fresh install gets no workspace: the phase-4 gate shows the wizard (or waits for the pull).
        XCTAssertEqual(try workspaces().count, 0)
        XCTAssertTrue(defaults.bool(forKey: WorkspaceBackfill.markerKey))
    }

    func testMarkerPresentStillAssignsNilRowsWithoutInferringAnExistingInstall() throws {
        defaults.set(true, forKey: WorkspaceBackfill.markerKey)
        try insertLegacyRows()
        backfill()
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Word>()).allSatisfy { $0.workspaceID == WorkspaceID.legacy })
        XCTAssertEqual(try workspaces().count, 1, "rows without a workspace need the legacy one")
    }

    func testMarkerPresentAndNothingToAssignInsertsNoInferredWorkspace() throws {
        defaults.set(true, forKey: WorkspaceBackfill.markerKey)
        let context = ModelContext(container)
        let word = Word(russian: "в", polish: "w", side: .term, createdAt: t0)
        word.workspaceID = WorkspaceID.make(term: "de", translation: "ru")
        context.insert(word)
        let german = Workspace(termLanguageCode: "de", translationLanguageCode: "ru", createdAt: t0)
        context.insert(german)
        try context.save()
        backfill()
        XCTAssertEqual(try workspaces().map(\.termLanguageCode), ["de"], "an active workspace exists: nothing inferred")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Word>()).first?.workspaceID, german.id)
    }

    func testTombstonedLegacyWorkspaceStaysTombstoned() throws {
        try insertLegacyRows()
        let context = ModelContext(container)
        let tombstone = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        tombstone.markDeleted(now: t0.addingTimeInterval(9))
        context.insert(tombstone)
        let german = Workspace(termLanguageCode: "de", translationLanguageCode: "ru", sortOrder: 1, createdAt: t0)
        context.insert(german)
        try context.save()

        backfill()

        let all = try workspaces()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == WorkspaceID.legacy }?.deletedAt, t0.addingTimeInterval(9))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Word>())
            .allSatisfy { $0.workspaceID == WorkspaceID.legacy }, "rows are assigned but the workspace is not revived")
    }

    func testBackfillNeverRevivesATombstoneNorInsertsASecondLegacyRow() throws {
        let context = ModelContext(container)
        let tombstone = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        tombstone.markDeleted(now: t0.addingTimeInterval(9))
        context.insert(tombstone)
        try context.save()

        backfill()
        backfill()

        let all = try workspaces()
        XCTAssertEqual(all.count, 1)
        XCTAssertFalse(all[0].isActive)
    }

    func testDuplicateWorkspaceRowsCollapseToTheLatestModified() throws {
        let context = ModelContext(container)
        let old = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        let latest = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", sortOrder: 4, createdAt: t0)
        latest.updatedAt = t0.addingTimeInterval(50)
        let other = Workspace(termLanguageCode: "de", translationLanguageCode: "ru", sortOrder: 1, createdAt: t0)
        [old, latest, other].forEach(context.insert)
        let word = Word(russian: "в", polish: "w", side: .term, createdAt: t0)
        context.insert(word)
        try context.save()

        backfill()

        let all = try workspaces()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first { $0.id == WorkspaceID.legacy }?.sortOrder, 4)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Word>()).count, 1, "words are never touched")
    }

    func testDuplicateTieKeepsTheActiveRow() throws {
        let context = ModelContext(container)
        let gone = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        gone.deletedAt = t0
        gone.updatedAt = t0
        let live = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        live.updatedAt = t0
        [gone, live].forEach(context.insert)
        try context.save()
        backfill()
        let all = try workspaces()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all[0].isActive)
    }

    func testFailedSaveWritesNoMarkerAndKeepsTheStoreUntouched() throws {
        try insertLegacyRows()
        struct Boom: Error {}
        XCTAssertFalse(backfill(save: { _ in throw Boom() }))
        XCTAssertFalse(defaults.bool(forKey: WorkspaceBackfill.markerKey))
        XCTAssertEqual(try workspaces().count, 0)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Word>()).allSatisfy { $0.workspaceID == nil })

        XCTAssertTrue(backfill(), "the next launch retries")
        XCTAssertTrue(defaults.bool(forKey: WorkspaceBackfill.markerKey))
        XCTAssertEqual(try workspaces().count, 1)
    }

    // MARK: Legacy memberships (phase 2)

    func testLegacyFolderIDsMigrateOnceAndLeaveTheArrayAndWordsUntouched() throws {
        let context = ModelContext(container)
        let live = WordFolder(name: "Живая")
        let dead = WordFolder(name: "Удалённая")
        dead.markDeleted(now: t0)
        let word = Word(russian: "в", polish: "w", side: .term, createdAt: t0)
        let dangling = UUID()
        word.folderIDs = [live.id, live.id, dead.id, dangling]
        let noUUID = Word(russian: "н", polish: "n", side: .term, createdAt: t0)
        noUUID.uuid = nil
        noUUID.folderIDs = [live.id]
        for model in [live, dead] as [any PersistentModel] { context.insert(model) }
        context.insert(word)
        context.insert(noUUID)
        try context.save()

        XCTAssertTrue(backfill())

        let check = ModelContext(container)
        let memberships = try check.fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 1, "deduplicated; deleted and dangling folders are not migrated")
        XCTAssertEqual(memberships[0].folderID, live.id)
        XCTAssertEqual(memberships[0].id, MembershipID.make(wordID: try XCTUnwrap(word.uuid), folderID: live.id))
        XCTAssertEqual(memberships[0].workspaceID, WorkspaceID.legacy)
        XCTAssertEqual(memberships[0].createdAt, word.lastModifiedAt)
        XCTAssertNil(memberships[0].serverUpdatedAt)
        let words = try check.fetch(FetchDescriptor<Word>())
        let saved = try XCTUnwrap(words.first { $0.polish == "w" })
        XCTAssertEqual(saved.folderIDs, [live.id, live.id, dead.id, dangling], "the legacy array is never edited")
        XCTAssertEqual(saved.updatedAt, t0, "word updatedAt untouched")
        XCTAssertTrue(saved.legacyFolderIDsMigrated)
        XCTAssertFalse(try XCTUnwrap(words.first { $0.polish == "n" }).legacyFolderIDsMigrated,
                       "a word without a uuid waits for WordIdentityBackfill")

        XCTAssertTrue(backfill())
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<FolderMembership>()).count, 1,
                       "a second run creates nothing")
    }

    func testMembershipsCreatedAfterTheMigrationAreNeverRecreatedFromTheArray() throws {
        let context = ModelContext(container)
        let folder = WordFolder(name: "Урок")
        let word = Word(russian: "в", polish: "w", side: .term, createdAt: t0)
        word.folderIDs = [folder.id]
        context.insert(folder)
        context.insert(word)
        try context.save()
        XCTAssertTrue(backfill())
        let edit = ModelContext(container)
        try XCTUnwrap(edit.fetch(FetchDescriptor<FolderMembership>()).first).markDeleted(now: now)
        try edit.save()

        XCTAssertTrue(backfill())

        let rows = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows[0].deletedAt, "the user's removal is not undone by the legacy array")
    }

    func testDuplicateMembershipRowsKeepTheLatestModified() throws {
        let context = ModelContext(container)
        let word = UUID(), folder = UUID()
        let older = FolderMembership(wordID: word, folderID: folder, workspaceID: WorkspaceID.legacy, createdAt: t0)
        let newer = FolderMembership(wordID: word, folderID: folder, workspaceID: WorkspaceID.legacy,
                                     createdAt: t0.addingTimeInterval(50))
        context.insert(older)
        context.insert(newer)
        try context.save()

        XCTAssertTrue(backfill())

        let rows = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].createdAt, t0.addingTimeInterval(50))
    }
}
