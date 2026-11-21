import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class SwiftDataVocabularyRepositoryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_794_225_600)

    private func makeRepo() throws -> (SwiftDataVocabularyRepository, ModelContainer) {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repo = SwiftDataVocabularyRepository(container: container, now: { [unowned self] in self.clock })
        return (repo, container)
    }

    private func rows(_ container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }

    func testAddSetsUUIDAndReAddOfActivePairReusesRow() throws {
        let (repo, container) = try makeRepo()
        try repo.addWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy)
        try repo.addWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy)
        let all = try rows(container)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].uuid)
        XCTAssertEqual(all[0].updatedAt, all[0].createdAt)
        XCTAssertEqual(all[0].createdAt, clock)
    }

    func testDeleteWordSoftDeletesAndRejectsUnknownOrTombstoned() throws {
        let (repo, container) = try makeRepo()
        try repo.addWord(WordEntry.legacy(source: "woda", translation: "вода"), category: nil, folderID: nil, workspace: .legacy)
        let id = try XCTUnwrap(rows(container).first?.uuid)
        let deletedAt = clock.addingTimeInterval(60)
        clock = deletedAt
        try repo.deleteWord(id: id)
        let row = try XCTUnwrap(rows(container).first)
        XCTAssertEqual(row.deletedAt, deletedAt)
        XCTAssertEqual(row.updatedAt, deletedAt)
        XCTAssertThrowsError(try repo.deleteWord(id: id)) { XCTAssertEqual($0.localizedDescription, "Слово больше не существует") }
        XCTAssertThrowsError(try repo.deleteWord(id: UUID()))
    }

    func testMembershipAndCategoryPersistAndBumpOnlyOnChange() throws {
        let (repo, container) = try makeRepo()
        let folder = try FolderStore.create(name: "Урок", container: container)
        try repo.addWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy)
        let id = try XCTUnwrap(rows(container).first?.uuid)
        let created = clock

        clock = created.addingTimeInterval(10)
        try repo.setMembership(wordID: id, folderID: folder.id, included: true)
        XCTAssertEqual(try memberFolders(try XCTUnwrap(rows(container).first), container), [folder.id])
        XCTAssertEqual(try rows(container).first?.updatedAt, created, "a membership edit does not touch the word")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<FolderMembership>()).first?.updatedAt, clock)

        let afterMembership = created
        clock = created.addingTimeInterval(20)
        try repo.setMembership(wordID: id, folderID: folder.id, included: true)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<FolderMembership>()).first?.updatedAt,
                       created.addingTimeInterval(10), "a repeated include is a no-op")

        try repo.setCategory(.food, wordID: id)
        XCTAssertEqual(try rows(container).first?.updatedAt, afterMembership)
        try repo.setCategory(.travel, wordID: id)
        XCTAssertEqual(try rows(container).first?.category, .travel)
        XCTAssertEqual(try rows(container).first?.updatedAt, clock)

        clock = created.addingTimeInterval(30)
        try repo.removeFromAllFolders(wordID: id)
        XCTAssertTrue(try memberFolders(try XCTUnwrap(rows(container).first), container).isEmpty)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<FolderMembership>()).first?.deletedAt, clock)
    }

    func testToggleCreatesTombstoneAndThenNewRow() throws {
        let (repo, container) = try makeRepo()
        XCTAssertTrue(try repo.toggleScannedWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy))
        let firstUUID = try XCTUnwrap(rows(container).first?.uuid)
        clock = clock.addingTimeInterval(5)
        let deletedAt = clock
        XCTAssertFalse(try repo.toggleScannedWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy))
        clock = clock.addingTimeInterval(5)
        XCTAssertTrue(try repo.toggleScannedWord(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: nil, workspace: .legacy))
        let all = try rows(container)
        XCTAssertEqual(all.count, 2)
        let tombstone = try XCTUnwrap(all.first { !$0.isActive })
        let active = try XCTUnwrap(all.first { $0.isActive })
        XCTAssertEqual(tombstone.uuid, firstUUID)
        XCTAssertEqual(tombstone.deletedAt, deletedAt)
        XCTAssertNotEqual(active.uuid, firstUUID)
    }

    func testEnsureIdentityAssignsMissingUUIDAndKeepsExisting() throws {
        let (repo, container) = try makeRepo()
        let context = container.mainContext
        let legacy = Word(russian: "вода", polish: "woda", side: .term)
        legacy.uuid = nil
        context.insert(legacy)
        try context.save()

        let assigned = try repo.ensureIdentity(for: legacy)
        XCTAssertEqual(legacy.uuid, assigned)
        XCTAssertEqual(try rows(container).first?.uuid, assigned)
        XCTAssertEqual(try repo.ensureIdentity(for: legacy), assigned)
    }
}
