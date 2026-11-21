import XCTest
import SwiftData
@testable import MojSlownik

final class FolderStoreTests: XCTestCase {
    @MainActor
    func testCreateTrimsNameAndRejectsEmptyAndDuplicateNames() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "  Урок 1\n", container: container)
        XCTAssertEqual(folder.name, "Урок 1")
        XCTAssertThrowsError(try FolderStore.create(name: " \n ", container: container))
        XCTAssertThrowsError(try FolderStore.create(name: "УРОК 1", container: container))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 1)
    }

    @MainActor
    func testWordCanBelongToMultipleFoldersWithoutDuplicateMembership() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Сложные", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: second.id, included: true, container: container)
        var saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual((try memberFolders(saved, container)), Set([first.id, second.id]))
        XCTAssertEqual((try memberFolders(saved, container)).count, 2)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: false, container: container)
        saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try memberFolders(saved, container), [second.id])
        XCTAssertEqual(try words(in: container).count, 1)
    }

    @MainActor
    func testMembershipChangesUpdateObservedContextAndPersistImmediately() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let folder = try FolderStore.create(name: "Урок 1", context: context)
        let word = try insertWord(in: container)
        let observedWord = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first)

        try FolderStore.setMembership(wordID: observedWord.persistentModelID, folderID: folder.id,
                                      included: true, context: context)

        XCTAssertEqual((try memberFolders(observedWord, container)), [folder.id])
        XCTAssertEqual(try memberFolders(try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first), container), [folder.id])
        XCTAssertEqual(word.persistentModelID, observedWord.persistentModelID)
    }

    @MainActor
    func testRemoveFromAllFoldersPreservesWordAndStudyProgress() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: second.id, included: true, container: container)
        let context = ModelContext(container)
        let observedWord = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first)

        try FolderStore.removeFromAllFolders(wordID: observedWord.persistentModelID, context: context)

        XCTAssertTrue((try memberFolders(observedWord, container)).isEmpty)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertTrue((try memberFolders(saved, container)).isEmpty)
        XCTAssertEqual(saved.polish, "woda")
        assertProgress(saved)
    }

    @MainActor
    func testDeletingFolderPreservesVocabularyOtherMembershipAndSRS() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: second.id, included: true, container: container)
        try FolderStore.delete(id: first.id, container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try memberFolders(saved, container), [second.id])
        assertProgress(saved)
        XCTAssertEqual(try words(in: container).count, 1)
        let rows = try ModelContext(container).fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(rows.filter(\.isActive).map(\.id), [second.id])
        let tombstone = try XCTUnwrap(rows.first { $0.id == first.id })
        XCTAssertNotNil(tombstone.deletedAt)
        XCTAssertEqual(tombstone.updatedAt, tombstone.deletedAt)
        XCTAssertNil(saved.deletedAt)
    }

    @MainActor
    func testScanFolderToggleReusesExistingWordAndNeverDeletesProgress() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        _ = try insertWord(in: container)
        XCTAssertTrue(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .other,
                                               folderID: folder.id, container: container))
        var saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try memberFolders(saved, container), [folder.id])
        XCTAssertEqual(saved.category, .food)
        assertProgress(saved)
        XCTAssertFalse(try ScanWordStore.toggle(source: "вода", translation: "woda", category: .other,
                                                folderID: folder.id, container: container))
        saved = try XCTUnwrap(words(in: container).first)
        XCTAssertTrue((try memberFolders(saved, container)).isEmpty)
        assertProgress(saved)
        XCTAssertEqual(try words(in: container).count, 1)
    }

    @MainActor
    func testScanIntoTwoFoldersCreatesOnlyOnePair() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        XCTAssertTrue(try ScanWordStore.toggle(source: "WODA", translation: "ВОДА", category: .food,
                                               folderID: first.id, container: container))
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                               folderID: second.id, container: container))
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual((try memberFolders(saved, container)), Set([first.id, second.id]))
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.russian, "вода")
    }

    @MainActor
    func testMissingFolderDoesNotInsertOrDeleteVocabulary() throws {
        let container = try makeContainer()
        let word = try insertWord(in: container)
        let missingID = UUID()
        XCTAssertThrowsError(try FolderStore.setMembership(wordID: word.persistentModelID, folderID: missingID,
                                                           included: true, container: container))
        XCTAssertThrowsError(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food,
                                                      folderID: missingID, container: container))
        XCTAssertThrowsError(try ScanWordStore.toggle(source: "kawa", translation: "кофе", category: .food,
                                                      folderID: missingID, container: container))
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertTrue(try memberFolders(try XCTUnwrap(words(in: container).first), container).isEmpty)
    }

    @MainActor
    func testFolderFilteringIncludesOnlyMembersAndNilIncludesAll() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id, included: true, container: container)
        let context = ModelContext(container)
        context.insert(Word(russian: "кофе", polish: "kawa", side: .term))
        try context.save()
        let all = try words(in: container)
        let index = MembershipIndex(try ModelContext(container).fetch(FetchDescriptor<FolderMembership>()))
        XCTAssertEqual(FolderStore.words(all, in: nil, memberships: index).count, 2)
        XCTAssertEqual(FolderStore.words(all, in: folder.id, memberships: index).map(\.polish), ["woda"])
        XCTAssertTrue(FolderStore.words(all, in: UUID(), memberships: index).isEmpty)
    }

    @MainActor
    func testNoFolderRetainsGlobalToggleBehavior() throws {
        let container = try makeContainer()
        XCTAssertTrue(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertTrue(try memberFolders(try XCTUnwrap(words(in: container).first), container).isEmpty)
        XCTAssertFalse(try ScanWordStore.toggle(source: "woda", translation: "вода", category: .food, container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
        let rows = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNotNil(rows.first?.deletedAt)
    }

    @MainActor
    func testReorderBumpsOnlyFoldersWhoseOrderChanged() throws {
        let container = try makeContainer()
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 2_000)
        let first = try FolderStore.create(name: "A", container: container, now: t0)
        let second = try FolderStore.create(name: "B", container: container, now: t0)
        let third = try FolderStore.create(name: "C", container: container, now: t0)
        try FolderStore.reorder(ids: [first.id, third.id, second.id], container: container, now: t1)
        let rows = try ModelContext(container).fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(rows.first { $0.id == first.id }?.updatedAt, t0)
        XCTAssertEqual(rows.first { $0.id == second.id }?.updatedAt, t1)
        XCTAssertEqual(rows.first { $0.id == third.id }?.updatedAt, t1)
    }

    @MainActor
    func testFolderSoftDeleteLeavesMemberWordsUntouchedAndNeverDeletesThem() throws {
        let container = try makeContainer()
        let t1 = Date(timeIntervalSince1970: 5_000)
        let folder = try FolderStore.create(name: "Урок", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id, included: true, container: container)
        let before = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first).updatedAt
        try FolderStore.delete(id: folder.id, container: container, now: t1)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertNil(saved.deletedAt)
        XCTAssertEqual(saved.updatedAt, before, "memberships are tombstoned, the word row is not touched")
        XCTAssertTrue((try memberFolders(saved, container)).isEmpty)
        XCTAssertThrowsError(try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                                           included: true, container: container))
        // The name can be reused: a new row with a new id.
        let recreated = try FolderStore.create(name: "Урок", container: container)
        XCTAssertNotEqual(recreated.id, folder.id)
    }

    @MainActor
    func testFolderDeleteTombstonesMembershipsAndLeavesWordsUntouched() throws {
        let container = try makeContainer()
        let t1 = Date(timeIntervalSince1970: 5_000)
        let t2 = Date(timeIntervalSince1970: 6_000)
        let folder = try FolderStore.create(name: "Урок", container: container)
        let context = ModelContext(container)
        let active = Word(russian: "вода", polish: "woda", side: .term)
        let deleted = Word(russian: "кофе", polish: "kawa", side: .term)
        for word in [active, deleted] {
            context.insert(word)
            context.insert(FolderMembership(wordID: try XCTUnwrap(word.uuid), folderID: folder.id,
                                            workspaceID: WorkspaceID.legacy))
        }
        deleted.markDeleted(now: t1)
        let activeUpdatedAt = active.updatedAt
        try context.save()

        try FolderStore.delete(id: folder.id, container: container, now: t2)

        let rows = try ModelContext(container).fetch(FetchDescriptor<Word>())
        let savedDeleted = try XCTUnwrap(rows.first { $0.polish == "kawa" })
        let savedActive = try XCTUnwrap(rows.first { $0.polish == "woda" })
        XCTAssertTrue(try memberFolders(savedDeleted, container).isEmpty)
        XCTAssertTrue(try memberFolders(savedActive, container).isEmpty)
        XCTAssertEqual(savedDeleted.updatedAt, t1, "words are not touched by a folder delete")
        XCTAssertEqual(savedActive.updatedAt, activeUpdatedAt)
        XCTAssertNil(savedActive.deletedAt)
        let memberships = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 2, "tombstones stay (they sync)")
        XCTAssertTrue(memberships.allSatisfy { $0.deletedAt == t2 && $0.updatedAt == t2 })
    }

    @MainActor
    func testMembershipEditsOnlyTouchMembershipRows() throws {
        let container = try makeContainer()
        let t1 = Date(timeIntervalSince1970: 5_000)
        let t2 = Date(timeIntervalSince1970: 6_000)
        let t3 = Date(timeIntervalSince1970: 7_000)
        let folder = try FolderStore.create(name: "Урок", container: container)
        let word = try insertWord(in: container)
        let wordUpdatedAt = try XCTUnwrap(words(in: container).first).updatedAt
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                      included: true, container: container, now: t1)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                      included: true, container: container, now: t2)
        var memberships = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships[0].updatedAt, t1, "a repeated include is a no-op")
        XCTAssertEqual(memberships[0].id, MembershipID.make(wordID: try XCTUnwrap(word.uuid), folderID: folder.id))
        XCTAssertEqual(try XCTUnwrap(words(in: container).first).updatedAt, wordUpdatedAt,
                       "the word row is not touched by a membership edit")

        // Remove = tombstone; add again revives the same row.
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                      included: false, container: container, now: t2)
        memberships = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships[0].deletedAt, t2)
        XCTAssertEqual(memberships[0].updatedAt, t2)
        XCTAssertTrue(try memberFolders(word, container).isEmpty)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id,
                                      included: true, container: container, now: t3)
        memberships = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 1, "revived, not duplicated")
        XCTAssertNil(memberships[0].deletedAt)
        XCTAssertEqual(memberships[0].updatedAt, t3)
        XCTAssertEqual(try memberFolders(word, container), [folder.id])
        XCTAssertEqual(try XCTUnwrap(words(in: container).first).updatedAt, wordUpdatedAt)
    }

    @MainActor
    func testRemoveFromAllFoldersTombstonesEveryActiveMembership() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let word = try insertWord(in: container)
        for folder in [first, second] {
            try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id, included: true,
                                          container: container)
        }
        let t1 = Date(timeIntervalSince1970: 9_000)
        try FolderStore.removeFromAllFolders(wordID: word.persistentModelID, context: ModelContext(container),
                                             now: t1)
        let memberships = try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
        XCTAssertEqual(memberships.count, 2)
        XCTAssertTrue(memberships.allSatisfy { $0.deletedAt == t1 })
        XCTAssertEqual(try words(in: container).count, 1, "the word stays")
    }

    @MainActor
    func testManualAddReusesExistingPairAndAddsFolderWithoutResettingProgress() throws {
        let container = try makeContainer()
        let folder = try FolderStore.create(name: "Урок 1", container: container)
        _ = try insertWord(in: container)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", folderID: folder.id, container: container)
        try ScanWordStore.add(source: "вода", translation: "woda", folderID: folder.id, container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(try memberFolders(saved, container), [folder.id])
        XCTAssertEqual(saved.category, .food)
        assertProgress(saved)
    }

    @MainActor
    func testManualAddOnlyChangesExistingCategoryWhenExplicitlySelected() throws {
        let container = try makeContainer()
        _ = try insertWord(in: container)
        try ScanWordStore.add(source: "woda", translation: "вода", category: .travel, container: container)
        try ScanWordStore.add(source: "woda", translation: "вода", container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(try words(in: container).count, 1)
        XCTAssertEqual(saved.category, .travel)
        assertProgress(saved)
    }

    @MainActor
    func testManualAddCreatesCategorizedPairAndRejectsMissingFolder() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try ScanWordStore.add(source: "woda", translation: "вода", folderID: UUID(), container: container))
        XCTAssertTrue(try words(in: container).isEmpty)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", container: container)
        let saved = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(saved.polish, "woda")
        XCTAssertEqual(saved.russian, "вода")
        XCTAssertEqual(saved.category, .food)
        XCTAssertTrue((try memberFolders(saved, container)).isEmpty)
    }

    @MainActor
    func testCreationImmediatelyAppearsInObservedContextAndPersists() throws {
        let container = try makeContainer()
        let observedContext = ModelContext(container)
        observedContext.autosaveEnabled = false

        let folder = try FolderStore.create(name: "Урок 1", context: observedContext)

        XCTAssertTrue(folder.modelContext === observedContext)
        let visible = try observedContext.fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(visible.map(\.id), [folder.id])
        XCTAssertEqual(visible.first?.name, "Урок 1")
        let persisted = try ModelContext(container).fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(persisted.map(\.id), [folder.id])
    }

    @MainActor
    func testDuplicateNameFailureKeepsUnrelatedPendingWordInsertion() throws {
        let container = try makeContainer()
        let observedContext = ModelContext(container)
        observedContext.autosaveEnabled = false
        _ = try FolderStore.create(name: "Урок 1", context: observedContext)
        let pending = Word(russian: "кофе", polish: "kawa", side: .term)
        observedContext.insert(pending)

        XCTAssertThrowsError(try FolderStore.create(name: " УРОК 1 ", context: observedContext))

        XCTAssertTrue(observedContext.hasChanges)
        XCTAssertTrue(pending.modelContext === observedContext)
        XCTAssertEqual(try observedContext.fetch(FetchDescriptor<Word>()).map(\.polish), ["kawa"])
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<Word>()).isEmpty)
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 1)
    }

    @MainActor
    func testFolderNamesAreUniqueAcrossWhitespaceCaseAndCanonicalUnicode() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        _ = try FolderStore.create(name: "Урок 1", context: context)
        XCTAssertThrowsError(try FolderStore.create(name: "  УРОК\n\t  1  ", context: context))
        _ = try FolderStore.create(name: "GÓRA", context: context)
        XCTAssertThrowsError(try FolderStore.create(name: "góra".decomposedStringWithCanonicalMapping, context: context))
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<WordFolder>()).count, 2)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @MainActor
    private func insertWord(in container: ModelContainer) throws -> Word {
        let context = ModelContext(container)
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 7
        word.intervalDays = 14
        word.easeFactor = 2.8
        word.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        context.insert(word)
        try context.save()
        return word
    }

    @MainActor
    private func words(in container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>()).filter(\.isActive)
    }

    private func assertProgress(_ word: Word, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(word.repetitions, 7, file: file, line: line)
        XCTAssertEqual(word.intervalDays, 14, file: file, line: line)
        XCTAssertEqual(word.easeFactor, 2.8, file: file, line: line)
        XCTAssertEqual(word.dueDate, Date(timeIntervalSince1970: 1_700_000_000), file: file, line: line)
    }
}


extension FolderStoreTests {
    @MainActor
    func testManuallyAddedWordUsesNewlyCreatedFolderInsteadOfOriginalFolder() throws {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let original = try FolderStore.create(name: "Урок 1", context: context)
        let created = try FolderStore.create(name: "Урок 2", context: context)
        try ScanWordStore.add(source: "WODA", translation: "ВОДА", folderID: created.id, container: container)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(try memberFolders(saved, container), [created.id])
        XCTAssertFalse((try memberFolders(saved, container)).contains(original.id))
    }

    @MainActor
    func testRenamePreservesFolderIdentityMembershipAndStudyProgress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let folder = try FolderStore.create(name: "Урок 1", context: context)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folder.id, included: true, container: container)

        try FolderStore.rename(id: folder.id, name: "  Первый   урок ", context: context)

        let savedFolder = try XCTUnwrap(FolderStore.folders(in: ModelContext(container)).first)
        let savedWord = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual(savedFolder.id, folder.id)
        XCTAssertEqual(savedFolder.name, "Первый урок")
        XCTAssertEqual((try memberFolders(savedWord, container)), [folder.id])
        assertProgress(savedWord)
        try FolderStore.rename(id: folder.id, name: "ПЕРВЫЙ УРОК", context: context)
        XCTAssertEqual(try XCTUnwrap(FolderStore.folders(in: context).first).name, "ПЕРВЫЙ УРОК")
    }

    @MainActor
    func testRejectedRenameLeavesFoldersAndWordsUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let first = try FolderStore.create(name: "Урок 1", context: context)
        let second = try FolderStore.create(name: "GÓRA", context: context)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)

        XCTAssertThrowsError(try FolderStore.rename(id: first.id, name: " \n ", context: context))
        XCTAssertThrowsError(try FolderStore.rename(id: first.id, name: "góra".decomposedStringWithCanonicalMapping, context: context))
        XCTAssertThrowsError(try FolderStore.rename(id: UUID(), name: "Новое", context: context)) { error in
            XCTAssertNotNil(error as? FolderStore.StoreError)
        }

        XCTAssertEqual(try FolderStore.folders(in: context).map(\.name), ["Урок 1", "GÓRA"])
        let savedWord = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual((try memberFolders(savedWord, container)), [first.id])
        assertProgress(savedWord)
        XCTAssertEqual(second.name, "GÓRA")
    }

    @MainActor
    func testReorderPersistsAndPreservesWordStudyData() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let third = try FolderStore.create(name: "Урок 3", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: third.id, included: true, container: container)

        try FolderStore.reorder(ids: [third.id, first.id, second.id], container: container)

        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container)).map(\.id), [third.id, first.id, second.id])
        let savedWord = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual((try memberFolders(savedWord, container)), [first.id, third.id])
        assertProgress(savedWord)
    }

    @MainActor
    func testRejectedReorderDoesNotPartiallyChangeOrderOrWordData() throws {
        let container = try makeContainer()
        let first = try FolderStore.create(name: "Урок 1", container: container)
        let second = try FolderStore.create(name: "Урок 2", container: container)
        let word = try insertWord(in: container)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: first.id, included: true, container: container)
        let originalOrder = try FolderStore.folders(in: ModelContext(container)).map(\.id)

        XCTAssertThrowsError(try FolderStore.reorder(ids: [second.id, second.id], container: container))
        XCTAssertThrowsError(try FolderStore.reorder(ids: [first.id], container: container))
        XCTAssertThrowsError(try FolderStore.reorder(ids: [first.id, UUID()], container: container))

        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container)).map(\.id), originalOrder)
        let savedWord = try XCTUnwrap(words(in: container).first)
        XCTAssertEqual((try memberFolders(savedWord, container)), [first.id])
        assertProgress(savedWord)
    }

    @MainActor
    func testLegacyOrderHasStableFallbackAndNewFolderAppends() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let laterID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let earlierID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let firstTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000010")!
        let secondTieID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
        let later = WordFolder(name: "Позже")
        later.id = laterID
        later.createdAt = Date(timeIntervalSince1970: 20)
        later.sortOrder = 0
        let earlier = WordFolder(name: "Раньше")
        earlier.id = earlierID
        earlier.createdAt = Date(timeIntervalSince1970: 10)
        earlier.sortOrder = 0
        let firstTie = WordFolder(name: "Одинаковая дата 1")
        firstTie.id = firstTieID
        firstTie.createdAt = Date(timeIntervalSince1970: 15)
        firstTie.sortOrder = 0
        let secondTie = WordFolder(name: "Одинаковая дата 2")
        secondTie.id = secondTieID
        secondTie.createdAt = Date(timeIntervalSince1970: 15)
        secondTie.sortOrder = 0
        context.insert(later)
        context.insert(earlier)
        context.insert(secondTie)
        context.insert(firstTie)
        try context.save()

        XCTAssertEqual(try FolderStore.folders(in: context).map(\.id), [earlierID, firstTieID, secondTieID, laterID])
        let appended = try FolderStore.create(name: "Новая", context: context)
        XCTAssertEqual(try FolderStore.folders(in: context).map(\.id), [earlierID, firstTieID, secondTieID, laterID, appended.id])
        try FolderStore.reorder(ids: [laterID, earlierID, firstTieID, secondTieID, appended.id], container: container)
        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container)).map(\.id), [laterID, earlierID, firstTieID, secondTieID, appended.id])
        try FolderStore.delete(id: earlierID, container: container)
        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container)).map(\.id), [laterID, firstTieID, secondTieID, appended.id])
    }
}
