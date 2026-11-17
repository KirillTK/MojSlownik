import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class SwiftDataVocabularyRepositoryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_794_225_600)

    private func makeRepo() throws -> (SwiftDataVocabularyRepository, ModelContainer) {
        let container = try ModelContainer(for: Word.self, WordFolder.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let repo = SwiftDataVocabularyRepository(container: container, now: { [unowned self] in self.clock })
        return (repo, container)
    }

    private func rows(_ container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }

    func testAddSetsUUIDAndReAddOfActivePairReusesRow() throws {
        let (repo, container) = try makeRepo()
        try repo.addWord(source: "woda", translation: "вода", category: .food, folderID: nil)
        try repo.addWord(source: "woda", translation: "вода", category: .food, folderID: nil)
        let all = try rows(container)
        XCTAssertEqual(all.count, 1)
        XCTAssertNotNil(all[0].uuid)
        XCTAssertEqual(all[0].updatedAt, all[0].createdAt)
        XCTAssertEqual(all[0].createdAt, clock)
    }

    func testDeleteWordSoftDeletesAndRejectsUnknownOrTombstoned() throws {
        let (repo, container) = try makeRepo()
        try repo.addWord(source: "woda", translation: "вода", category: nil, folderID: nil)
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
        try repo.addWord(source: "woda", translation: "вода", category: .food, folderID: nil)
        let id = try XCTUnwrap(rows(container).first?.uuid)
        let created = clock

        clock = created.addingTimeInterval(10)
        try repo.setMembership(wordID: id, folderID: folder.id, included: true)
        XCTAssertEqual(try rows(container).first?.folderIDs, [folder.id])
        XCTAssertEqual(try rows(container).first?.updatedAt, clock)

        let afterMembership = clock
        clock = created.addingTimeInterval(20)
        try repo.setMembership(wordID: id, folderID: folder.id, included: true)
        XCTAssertEqual(try rows(container).first?.updatedAt, afterMembership)

        try repo.setCategory(.food, wordID: id)
        XCTAssertEqual(try rows(container).first?.updatedAt, afterMembership)
        try repo.setCategory(.travel, wordID: id)
        XCTAssertEqual(try rows(container).first?.category, .travel)
        XCTAssertEqual(try rows(container).first?.updatedAt, clock)

        clock = created.addingTimeInterval(30)
        try repo.removeFromAllFolders(wordID: id)
        XCTAssertEqual(try rows(container).first?.folderIDs, [])
        XCTAssertEqual(try rows(container).first?.updatedAt, clock)
    }

    func testToggleCreatesTombstoneAndThenNewRow() throws {
        let (repo, container) = try makeRepo()
        XCTAssertTrue(try repo.toggleScannedWord(source: "woda", translation: "вода", category: .food, folderID: nil))
        let firstUUID = try XCTUnwrap(rows(container).first?.uuid)
        clock = clock.addingTimeInterval(5)
        let deletedAt = clock
        XCTAssertFalse(try repo.toggleScannedWord(source: "woda", translation: "вода", category: .food, folderID: nil))
        clock = clock.addingTimeInterval(5)
        XCTAssertTrue(try repo.toggleScannedWord(source: "woda", translation: "вода", category: .food, folderID: nil))
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
        let legacy = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        legacy.uuid = nil
        context.insert(legacy)
        try context.save()

        let assigned = try repo.ensureIdentity(for: legacy)
        XCTAssertEqual(legacy.uuid, assigned)
        XCTAssertEqual(try rows(container).first?.uuid, assigned)
        XCTAssertEqual(try repo.ensureIdentity(for: legacy), assigned)
    }
}
