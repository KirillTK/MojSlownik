import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class WorkspaceCatalogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainer(for: AppSchema.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func rows() throws -> [Workspace] {
        try ModelContext(container).fetch(FetchDescriptor<Workspace>())
    }

    func testEnsureInsertsOnceAndIsIdempotent() throws {
        let first = try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        let second = try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container,
                                                 now: t0.addingTimeInterval(10))
        XCTAssertEqual(first, WorkspaceID.legacy)
        XCTAssertEqual(first, second)
        let all = try rows()
        XCTAssertEqual(all.count, 1, "never a duplicate id")
        XCTAssertEqual(all[0].updatedAt, t0, "an active workspace is left alone")
        XCTAssertEqual(all[0].sortOrder, 0)
    }

    func testEnsureAppendsNewPairsAtTheEnd() throws {
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container, now: t0)
        try WorkspaceCatalog.ensure(term: "en", translation: "pl", container: container, now: t0)
        let ordered = try WorkspaceCatalog.workspaces(in: ModelContext(container))
        XCTAssertEqual(ordered.map(\.termLanguageCode), ["pl", "de", "en"])
        XCTAssertEqual(ordered.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(ordered[1].id, WorkspaceID.make(term: "de", translation: "ru"))
    }

    func testEnsureRevivesATombstoneAndBumpsUpdatedAt() throws {
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container, now: t0)
        let germanID = WorkspaceID.make(term: "de", translation: "ru")
        try WorkspaceCatalog.delete(id: germanID, container: container, now: t0.addingTimeInterval(5))

        let revivedAt = t0.addingTimeInterval(60)
        let id = try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container, now: revivedAt)

        XCTAssertEqual(id, germanID)
        let all = try rows()
        XCTAssertEqual(all.count, 2, "revived, not duplicated")
        let german = try XCTUnwrap(all.first { $0.id == germanID })
        XCTAssertNil(german.deletedAt)
        XCTAssertEqual(german.updatedAt, revivedAt)
        XCTAssertTrue(german.isActive)
    }

    func testDeleteIsSoftAndKeepsWordsAndFolders() throws {
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container, now: t0)
        let germanID = WorkspaceID.make(term: "de", translation: "ru")
        let context = ModelContext(container)
        let word = Word(russian: "дом", polish: "das haus", side: .term, createdAt: t0)
        word.workspaceID = germanID
        let folder = WordFolder(name: "Lektion 1")
        folder.workspaceID = germanID
        context.insert(word)
        context.insert(folder)
        try context.save()

        let deletedAt = t0.addingTimeInterval(30)
        try WorkspaceCatalog.delete(id: germanID, container: container, now: deletedAt)

        let german = try XCTUnwrap(rows().first { $0.id == germanID })
        XCTAssertEqual(german.deletedAt, deletedAt)
        XCTAssertEqual(german.updatedAt, deletedAt)
        let check = ModelContext(container)
        XCTAssertEqual(try check.fetch(FetchDescriptor<Word>()).filter(\.isActive).count, 1)
        XCTAssertEqual(try check.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive).count, 1)
        XCTAssertEqual(try WorkspaceCatalog.wordCount(workspaceID: germanID, in: check), 1)
        XCTAssertEqual(try WorkspaceCatalog.folderCount(workspaceID: germanID, in: check), 1)
        XCTAssertEqual(try WorkspaceCatalog.workspaces(in: check).map(\.termLanguageCode), ["pl"])
    }

    func testDeleteRefusesTheLastActiveWorkspaceAndUnknownIDs() throws {
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        XCTAssertThrowsError(try WorkspaceCatalog.delete(id: WorkspaceID.legacy, container: container)) {
            XCTAssertEqual($0 as? WorkspaceCatalog.StoreError, .lastWorkspace)
            XCTAssertEqual($0.localizedDescription, "Нельзя удалить единственный язык")
        }
        XCTAssertThrowsError(try WorkspaceCatalog.delete(id: UUID(), container: container)) {
            XCTAssertEqual($0 as? WorkspaceCatalog.StoreError, .missingWorkspace)
        }
        XCTAssertTrue(try XCTUnwrap(rows().first).isActive)
    }

    func testReorderValidatesAndStoresTheOrder() throws {
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container, now: t0)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container, now: t0)
        let pl = WorkspaceID.legacy
        let de = WorkspaceID.make(term: "de", translation: "ru")

        try WorkspaceCatalog.reorder(ids: [de, pl], container: container, now: t0.addingTimeInterval(1))

        XCTAssertEqual(try WorkspaceCatalog.workspaces(in: ModelContext(container)).map(\.id), [de, pl])
        for bad in [[pl], [pl, pl], [pl, UUID()]] {
            XCTAssertThrowsError(try WorkspaceCatalog.reorder(ids: bad, container: container)) {
                XCTAssertEqual($0 as? WorkspaceCatalog.StoreError, .invalidOrder)
            }
        }
    }

    func testOrderingRuleSortOrderThenCreatedAtThenID() throws {
        let context = ModelContext(container)
        let a = Workspace(termLanguageCode: "de", translationLanguageCode: "ru", sortOrder: 1, createdAt: t0)
        let b = Workspace(termLanguageCode: "en", translationLanguageCode: "ru", sortOrder: 1,
                          createdAt: t0.addingTimeInterval(-10))
        let c = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", sortOrder: 0,
                          createdAt: t0.addingTimeInterval(100))
        [a, b, c].forEach(context.insert)
        try context.save()
        XCTAssertEqual(try WorkspaceCatalog.workspaces(in: context).map(\.termLanguageCode), ["pl", "en", "de"])
    }

    func testEnsureNeverInsertsASecondRowForAnExistingIDInAnyState() throws {
        let context = ModelContext(container)
        let tombstone = Workspace(termLanguageCode: "pl", translationLanguageCode: "ru", createdAt: t0)
        tombstone.markDeleted(now: t0.addingTimeInterval(1))
        context.insert(tombstone)
        try context.save()
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", context: context, now: t0.addingTimeInterval(2))
        XCTAssertEqual(try rows().count, 1)
    }
}
