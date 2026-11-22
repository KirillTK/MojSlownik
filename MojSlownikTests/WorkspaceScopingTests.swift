import SwiftData
import XCTest
@testable import MojSlownik

/// Phase 1: folders, words and the v1 sync store respect the workspace of a row.
@MainActor
final class WorkspaceScopingTests: XCTestCase {
    private typealias Kit = SyncTestKit
    private let t0 = SyncTestKit.t0
    private let pl = WorkspaceID.legacy
    private let de = WorkspaceID.make(term: "de", translation: "ru")
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try Kit.makeContainer()
    }

    private func moveWord(_ id: UUID, to workspace: UUID) throws {
        try Kit.edit(container, id, at: t0) { $0.workspaceID = workspace }
    }

    private func moveFolder(_ id: UUID, to workspace: UUID) throws {
        let context = ModelContext(container)
        let folder = try XCTUnwrap(context.fetch(FetchDescriptor<WordFolder>()).first { $0.id == id })
        folder.workspaceID = workspace
        try context.save()
    }

    // MARK: Folders

    func testSameFolderNameIsAllowedInTwoWorkspacesAndRejectedWithinOne() throws {
        let first = try FolderStore.create(name: "Урок 1", workspaceID: pl, container: container)
        let second = try FolderStore.create(name: "урок 1", workspaceID: de, container: container)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.workspaceID, pl)
        XCTAssertEqual(second.workspaceID, de)
        XCTAssertThrowsError(try FolderStore.create(name: "УРОК 1", workspaceID: de, container: container)) {
            XCTAssertEqual($0 as? FolderStore.StoreError, .duplicateName)
        }
    }

    func testFoldersAreListedAndOrderedPerWorkspace() throws {
        let a = try FolderStore.create(name: "A", workspaceID: pl, container: container)
        let b = try FolderStore.create(name: "B", workspaceID: pl, container: container)
        let x = try FolderStore.create(name: "X", workspaceID: de, container: container)
        XCTAssertEqual(x.sortOrder, 0, "sort order is per workspace")
        let context = ModelContext(container)
        XCTAssertEqual(try FolderStore.folders(in: context, workspaceID: pl).map(\.name), ["A", "B"])
        XCTAssertEqual(try FolderStore.folders(in: context, workspaceID: de).map(\.name), ["X"])

        try FolderStore.reorder(ids: [b.id, a.id], workspaceID: pl, container: container)
        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container), workspaceID: pl).map(\.name), ["B", "A"])
        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container), workspaceID: de).map(\.name), ["X"])
        XCTAssertThrowsError(try FolderStore.reorder(ids: [b.id, a.id, x.id], workspaceID: pl, container: container))
        XCTAssertThrowsError(try FolderStore.reorder(ids: [a.id], workspaceID: pl, container: container))
    }

    func testRenameValidatesWithinTheFoldersWorkspace() throws {
        _ = try FolderStore.create(name: "Общее", workspaceID: pl, container: container)
        let german = try FolderStore.create(name: "Lektion", workspaceID: de, container: container)
        let context = ModelContext(container)
        try FolderStore.rename(id: german.id, name: "Общее", context: context)
        XCTAssertEqual(try FolderStore.folders(in: ModelContext(container), workspaceID: de).map(\.name), ["Общее"])
    }

    func testLegacyFoldersWithoutAWorkspaceBelongToPolishRussian() throws {
        _ = try Kit.insertFolder(container, name: "Старая")
        let context = ModelContext(container)
        XCTAssertEqual(try FolderStore.folders(in: context, workspaceID: pl).map(\.name), ["Старая"])
        XCTAssertTrue(try FolderStore.folders(in: context, workspaceID: de).isEmpty)
        XCTAssertThrowsError(try FolderStore.create(name: "старая", workspaceID: pl, container: container))
    }

    func testRequireFolderAndMembershipRejectAFolderOfAnotherWorkspace() throws {
        let folder = try FolderStore.create(name: "Lektion", workspaceID: de, container: container)
        let word = try Kit.insertWord(container, polish: "kot")
        try moveWord(word, to: pl)
        let context = ModelContext(container)
        XCTAssertNoThrow(try FolderStore.requireFolder(folder.id, in: context, workspaceID: de))
        XCTAssertThrowsError(try FolderStore.requireFolder(folder.id, in: context, workspaceID: pl)) {
            XCTAssertEqual($0 as? FolderStore.StoreError, .missingFolder)
        }
        let id = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first).persistentModelID
        XCTAssertThrowsError(try FolderStore.setMembership(wordID: id, folderID: folder.id, included: true,
                                                           container: container)) {
            XCTAssertEqual($0 as? FolderStore.StoreError, .missingFolder)
        }
    }

    func testFolderRepositoryContractWithTwoWorkspacesOnBothImplementations() throws {
        let swiftData = SwiftDataFolderRepository(container: container)
        for repo in [swiftData as any FolderRepository, InMemoryFolderRepository()] {
            let a = try repo.createFolder(name: "Урок", workspaceID: pl)
            let b = try repo.createFolder(name: "Урок", workspaceID: de)
            XCTAssertNotEqual(a, b)
            XCTAssertThrowsError(try repo.createFolder(name: " урок ", workspaceID: pl))
            XCTAssertEqual(try repo.folders(in: pl).map(\.id), [a])
            XCTAssertEqual(try repo.folders(in: de).map(\.id), [b])
            XCTAssertThrowsError(try repo.reorderFolders(ids: [a, b], workspaceID: pl))
            try repo.reorderFolders(ids: [b], workspaceID: de)
            try repo.deleteFolder(id: a)
            XCTAssertTrue(try repo.folders(in: pl).isEmpty)
            XCTAssertEqual(try repo.folders(in: de).map(\.id), [b])
            // Fresh state for the next implementation.
            try repo.deleteFolder(id: b)
        }
    }

    func testFolderLibraryStoreListsOnlyItsWorkspaceAndNeedsOne() throws {
        let repo = SwiftDataFolderRepository(container: container)
        let library = FolderLibraryStore(repository: repo)
        XCTAssertThrowsError(try library.create(name: "Нет")) {
            XCTAssertEqual($0 as? RepositoryError, .noWorkspace)
        }
        library.workspaceID = pl
        let a = try library.create(name: "Урок")
        library.workspaceID = de
        try library.load()
        XCTAssertTrue(library.options.isEmpty)
        let b = try library.create(name: "Урок")
        XCTAssertEqual(library.options.map(\.id), [b])
        library.workspaceID = pl
        try library.load()
        XCTAssertEqual(library.options.map(\.id), [a])
        library.workspaceID = nil
        try library.load()
        XCTAssertTrue(library.options.isEmpty)
    }

    // MARK: Words

    func testNewWordsGetTheWorkspaceAndTheEnteredLanguageCode() throws {
        try ScanWordStore.add(WordEntry(term: "das haus", translation: "дом", enteredSide: .term),
                              workspace: .germanRussian, container: container, now: t0)
        try ScanWordStore.add(WordEntry(term: "lernen", translation: "учить", enteredSide: .translation),
                              workspace: .germanRussian, container: container, now: t0)
        let words = try Kit.words(container).sorted { $0.term < $1.term }
        XCTAssertEqual(words.map(\.workspaceID), [de, de])
        XCTAssertEqual(words.map(\.term), ["das haus", "lernen"])
        XCTAssertEqual(words.map(\.translation), ["дом", "учить"])
        XCTAssertEqual(words.map(\.sourceLanguageCode), ["de", "ru"])
    }

    func testDuplicatesAreMatchedPerWorkspace() throws {
        let entry = WordEntry(term: "kot", translation: "кот", enteredSide: .term)
        try ScanWordStore.add(entry, workspace: .legacy, container: container, now: t0)
        try ScanWordStore.add(entry, workspace: .legacy, container: container, now: t0)
        try ScanWordStore.add(entry, workspace: .germanRussian, container: container, now: t0)
        XCTAssertEqual(try Kit.words(container).count, 2, "one per workspace")
        XCTAssertFalse(try ScanWordStore.toggle(entry, category: .other, workspace: .germanRussian,
                                                container: container, now: t0),
                       "toggle removes only the German copy")
        let remaining = try Kit.words(container).filter(\.isActive)
        XCTAssertEqual(remaining.map(\.workspaceID), [pl])
    }

    func testLegacyWordsWithoutAWorkspaceMatchInThePolishRussianWorkspace() throws {
        _ = try Kit.insertWord(container, russian: "кот", polish: "kot")
        try ScanWordStore.add(WordEntry.legacy(source: "kot", translation: "кот"), workspace: .legacy,
                              container: container, now: t0)
        XCTAssertEqual(try Kit.words(container).count, 1)
    }

    func testChangeCategoryOnlyTouchesTheWorkspaceWord() throws {
        let entry = WordEntry(term: "kot", translation: "кот", enteredSide: .term)
        try ScanWordStore.add(entry, category: .other, workspace: .legacy, container: container, now: t0)
        try ScanWordStore.add(entry, category: .other, workspace: .germanRussian, container: container, now: t0)
        try ScanWordStore.changeCategory(.food, entry: entry, workspace: .germanRussian, container: container, now: t0)
        let words = try Kit.words(container)
        XCTAssertEqual(words.first { $0.workspaceID == de }?.category, .food)
        XCTAssertEqual(words.first { $0.workspaceID == pl }?.category, .other)
    }

    func testScanFolderMustBelongToTheWorkspace() throws {
        let folder = try FolderStore.create(name: "Lektion", workspaceID: de, container: container)
        let entry = WordEntry(term: "kot", translation: "кот", enteredSide: .term)
        XCTAssertThrowsError(try ScanWordStore.add(entry, folderID: folder.id, workspace: .legacy,
                                                   container: container)) {
            XCTAssertEqual($0 as? FolderStore.StoreError, .missingFolder)
        }
        XCTAssertThrowsError(try ScanWordStore.toggle(entry, category: .other, folderID: folder.id,
                                                      workspace: .legacy, container: container))
        XCTAssertTrue(try Kit.words(container).isEmpty)
        try ScanWordStore.add(entry, folderID: folder.id, workspace: .germanRussian, container: container)
        XCTAssertEqual(try memberFolders(try XCTUnwrap(Kit.words(container).first), container), [folder.id])
    }

    func testVocabularyStoreWritesNeedAWorkspaceAndPassItThrough() throws {
        let repo = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repo)
        let entry = WordEntry(term: "kot", translation: "кот", enteredSide: .term)
        XCTAssertThrowsError(try store.add(entry)) { XCTAssertEqual($0 as? RepositoryError, .noWorkspace) }
        XCTAssertThrowsError(try store.toggleScanned(entry, category: .other))
        XCTAssertThrowsError(try store.changeCategory(.food, entry: entry))
        XCTAssertTrue(repo.calls.isEmpty)
        XCTAssertEqual(RepositoryError.noWorkspace.localizedDescription, "Choose a dictionary language")

        store.workspace = .germanRussian
        try store.add(entry)
        XCTAssertEqual(repo.calls, [.addWord(entry, nil, nil, .germanRussian)])
    }

    func testVocabularyStoreLogsTheEnteredLanguageCode() throws {
        let spy = AppLogSpy()
        let store = VocabularyStore(repository: RecordingVocabularyRepository(), logger: spy)
        store.workspace = .germanRussian
        try store.add(WordEntry(term: "haus", translation: "дом", enteredSide: .term))
        try store.add(WordEntry(term: "haus", translation: "дом", enteredSide: .translation))
        XCTAssertEqual(spy.entries.map { $0.properties[.language] }, [.name("de"), .name("ru")])
    }

    // MARK: WordEntry and Word accessors

    func testLegacyEntryMapsCyrillicToTheTranslationSide() {
        XCTAssertEqual(WordEntry.legacy(source: "кот", translation: "kot"),
                       WordEntry(term: "kot", translation: "кот", enteredSide: .translation))
        XCTAssertEqual(WordEntry.legacy(source: "kot", translation: "кот"),
                       WordEntry(term: "kot", translation: "кот", enteredSide: .term))
        XCTAssertEqual(WordEntry.legacy(source: "dom", translation: "дом").enteredSide, .term)
    }

    func testWordAccessorsAreTheStoredProperties() {
        let word = Word(russian: "кот", polish: "kot", side: .translation)
        XCTAssertEqual(word.term, "kot")
        XCTAssertEqual(word.translation, "кот")
        XCTAssertEqual(word.text(on: .term), "kot")
        XCTAssertEqual(word.text(on: .translation), "кот")
        word.term = "pies"
        word.translation = "пёс"
        XCTAssertEqual(word.polish, "pies")
        XCTAssertEqual(word.russian, "пёс")
        XCTAssertEqual(word.effectiveWorkspaceID, WorkspaceID.legacy)
        XCTAssertEqual(word.enteredSide(in: .legacy), .translation)
        XCTAssertEqual(Word(russian: "в", polish: "w", side: .term).enteredSide(in: .legacy), .term)
        word.workspaceID = de
        XCTAssertEqual(word.effectiveWorkspaceID, de)
    }

    func testMatchesEntryIgnoresCaseWhitespaceAndUnicodeForm() {
        let word = Word(russian: "спасибо", polish: "dziękuję", side: .term)
        XCTAssertTrue(word.matches(WordEntry(term: " DZIĘKUJĘ".decomposedStringWithCanonicalMapping,
                                             translation: "СПАСИБО ", enteredSide: .term)))
        XCTAssertFalse(word.matches(WordEntry(term: "dziekuje", translation: "спасибо", enteredSide: .term)))
        XCTAssertFalse(word.matches(WordEntry(term: "спасибо", translation: "dziękuję", enteredSide: .term)),
                       "sides are not interchangeable")
    }

    // MARK: Sync v1 stays on the legacy workspace

    func testPulledRowsGetTheLegacyWorkspace() throws {
        let store = SwiftDataSyncStore(container: container, now: { self.t0 })
        let wordID = UUID()
        let folderID = UUID()
        _ = try store.applyFolders([try Kit.validated(Kit.remoteFolder(id: folderID, updatedAt: t0))])
        _ = try store.applyWords([try Kit.validated(Kit.remoteWord(id: wordID, updatedAt: t0))])
        XCTAssertEqual(try Kit.word(container, wordID)?.workspaceID, pl)
        XCTAssertEqual(try Kit.folders(container).first?.workspaceID, pl)
    }

    func testAdoptionIgnoresRowsOfOtherWorkspaces() throws {
        let store = SwiftDataSyncStore(container: container, now: { self.t0 })
        let germanWord = try Kit.insertWord(container, russian: "кот", polish: "kot")
        try moveWord(germanWord, to: de)
        let germanFolder = try Kit.insertFolder(container, name: "Урок")
        try moveFolder(germanFolder, to: de)

        let remoteWordID = UUID()
        let wordResult = try store.applyWords([try Kit.validated(Kit.remoteWord(
            id: remoteWordID, term: "kot", translation: "кот", updatedAt: t0.addingTimeInterval(-60)))])
        let folderResult = try store.applyFolders([try Kit.validated(Kit.remoteFolder(
            name: "урок", updatedAt: t0.addingTimeInterval(-60)))])

        XCTAssertEqual(wordResult.adopted, 0)
        XCTAssertEqual(wordResult.inserted, 1)
        XCTAssertEqual(folderResult.adopted, 0)
        XCTAssertEqual(folderResult.inserted, 1)
        XCTAssertEqual(try Kit.words(container).count, 2)
        XCTAssertEqual(try Kit.word(container, germanWord)?.workspaceID, de, "the German row is untouched")
    }

    func testAdoptionStillWorksInTheLegacyWorkspace() throws {
        let store = SwiftDataSyncStore(container: container, now: { self.t0 })
        let local = try Kit.insertWord(container, russian: "кот", polish: "kot")
        let remoteID = UUID()
        let result = try store.applyWords([try Kit.validated(Kit.remoteWord(
            id: remoteID, term: "kot", translation: "кот", updatedAt: t0.addingTimeInterval(-60)))])
        XCTAssertEqual(result.adopted, 1)
        XCTAssertNil(try Kit.word(container, local))
        XCTAssertEqual(try Kit.word(container, remoteID)?.workspaceID, pl)
    }

    /// Sync v2 sends every workspace's rows, each tagged with its own workspace id.
    func testPendingRowsCarryTheirOwnWorkspace() throws {
        let store = SwiftDataSyncStore(container: container, now: { self.t0 })
        try Kit.insertWorkspace(container)
        try Kit.insertWorkspace(container, term: "de", translation: "ru")
        let legacyWord = try Kit.insertWord(container, polish: "kot")
        let germanWord = try Kit.insertWord(container, polish: "haus")
        try moveWord(germanWord, to: de)
        _ = try Kit.insertFolder(container, name: "Pl")
        let germanFolder = try Kit.insertFolder(container, name: "De")
        try moveFolder(germanFolder, to: de)

        let words = try store.pendingWords(ownerID: Kit.owner, now: t0, excluding: [])
        let folders = try store.pendingFolders(ownerID: Kit.owner, now: t0, excluding: [])

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: words.rows.map { ($0.id, $0.payload.workspaceID) }),
                       [legacyWord: pl, germanWord: de])
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: folders.rows.map { ($0.payload.name, $0.payload.workspaceID) }),
                       ["Pl": pl, "De": de])
    }
}
