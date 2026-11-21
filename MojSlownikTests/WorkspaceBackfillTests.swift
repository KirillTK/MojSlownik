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
            let word = Word(russian: "в\(index)", polish: "w\(index)", sourceLanguage: .polish,
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

    func testFreshInstallWithOnlySyncDefaultsInfersNothingAndWritesTheMarker() throws {
        defaults.set(Data("{}".utf8), forKey: "sync.v1")
        defaults.set(Data("{}".utf8), forKey: "achievements.v1")

        XCTAssertTrue(backfill())

        // Phases 1-3 only: the fallback gives an empty install its default workspace, stamped `now`
        // (an inferred existing-install workspace would carry an old word's createdAt).
        let all = try workspaces()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].createdAt, now)
        XCTAssertEqual(all[0].id, WorkspaceID.legacy)
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

    func testMarkerPresentAndNothingToAssignInsertsNoInferredWorkspaceBeyondTheFallback() throws {
        defaults.set(true, forKey: WorkspaceBackfill.markerKey)
        let context = ModelContext(container)
        let word = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0)
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

    func testFallbackNeverRevivesATombstoneNorInsertsASecondLegacyRow() throws {
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
        let word = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0)
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
}
