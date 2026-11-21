import Foundation
import SwiftData
import os

private let repositoryLogger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

@MainActor
final class SwiftDataWorkspaceRepository: WorkspaceRepository {
    private let container: ModelContainer
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.now = now
    }

    func workspaces() throws -> [WorkspaceRecord] {
        try WorkspaceCatalog.workspaces(in: container.mainContext).map {
            WorkspaceRecord(id: $0.id, termCode: $0.termLanguageCode,
                            translationCode: $0.translationLanguageCode, sortOrder: $0.sortOrder)
        }
    }

    func ensure(term: String, translation: String) throws -> UUID {
        try WorkspaceCatalog.ensure(term: term, translation: translation, container: container, now: now())
    }

    func delete(id: UUID) throws {
        try WorkspaceCatalog.delete(id: id, container: container, now: now())
    }

    func reorder(ids: [UUID]) throws {
        try WorkspaceCatalog.reorder(ids: ids, container: container, now: now())
    }
}

@MainActor
final class SwiftDataFolderRepository: FolderRepository {
    private let container: ModelContainer
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.now = now
    }

    func folders(in workspaceID: UUID) throws -> [FolderRecord] {
        try FolderStore.folders(in: container.mainContext, workspaceID: workspaceID)
            .map { FolderRecord(id: $0.id, name: $0.name) }
    }

    func createFolder(name: String, workspaceID: UUID) throws -> UUID {
        try FolderStore.create(name: name, workspaceID: workspaceID, context: container.mainContext, now: now()).id
    }

    func renameFolder(id: UUID, name: String) throws {
        try FolderStore.rename(id: id, name: name, context: container.mainContext, now: now())
    }

    func reorderFolders(ids: [UUID], workspaceID: UUID) throws {
        try FolderStore.reorder(ids: ids, workspaceID: workspaceID, container: container, now: now())
    }

    func deleteFolder(id: UUID) throws {
        try FolderStore.delete(id: id, container: container, now: now())
    }
}

@MainActor
final class SwiftDataVocabularyRepository: VocabularyRepository {
    private let container: ModelContainer
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.now = now
    }

    func addWord(_ entry: WordEntry, category: WordCategory?, folderID: UUID?,
                 workspace: WorkspaceContext) throws {
        try ScanWordStore.add(entry, category: category, folderID: folderID, workspace: workspace,
                              container: container, now: now())
    }

    func toggleScannedWord(_ entry: WordEntry, category: WordCategory, folderID: UUID?,
                           workspace: WorkspaceContext) throws -> Bool {
        try ScanWordStore.toggle(entry, category: category, folderID: folderID, workspace: workspace,
                                 container: container, now: now())
    }

    func changeCategory(_ category: WordCategory, entry: WordEntry, workspace: WorkspaceContext) throws {
        try ScanWordStore.changeCategory(category, entry: entry, workspace: workspace,
                                         container: container, now: now())
    }

    func setCategory(_ category: WordCategory, wordID: UUID) throws {
        let context = container.mainContext
        let word = try activeWord(uuid: wordID, in: context)
        guard word.category != category else { return }
        let previousCategory = word.categoryRawValue
        let previousUpdatedAt = word.updatedAt
        word.category = category
        word.updatedAt = now()
        do { try context.save() }
        catch {
            word.categoryRawValue = previousCategory
            word.updatedAt = previousUpdatedAt
            throw error
        }
    }

    func deleteWord(id: UUID) throws {
        let word = try activeWord(uuid: id, in: container.mainContext)
        try ScanWordStore.delete(wordID: word.persistentModelID, container: container, now: now())
    }

    func setMembership(wordID: UUID, folderID: UUID, included: Bool) throws {
        let context = container.mainContext
        let word = try activeWord(uuid: wordID, in: context)
        try FolderStore.setMembership(wordID: word.persistentModelID, folderID: folderID,
                                      included: included, context: context, now: now())
    }

    func removeFromAllFolders(wordID: UUID) throws {
        let context = container.mainContext
        let word = try activeWord(uuid: wordID, in: context)
        try FolderStore.removeFromAllFolders(wordID: word.persistentModelID, context: context, now: now())
    }

    func ensureIdentity(for word: Word) throws -> UUID {
        if let uuid = word.uuid { return uuid }
        do {
            _ = try WordIdentityBackfill.assignMissing(in: container.mainContext, rollbackOnFailure: false)
        } catch {
            repositoryLogger.error("Lazy identity backfill failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        guard let uuid = word.uuid else { throw RepositoryError.missingIdentity }
        return uuid
    }

    private func activeWord(uuid: UUID, in context: ModelContext) throws -> Word {
        let words = try context.fetch(FetchDescriptor<Word>())
        guard let word = words.first(where: { $0.uuid == uuid && $0.isActive }) else {
            throw FolderStore.StoreError.missingWord
        }
        return word
    }
}
