import Foundation
import SwiftData
import os

private let repositoryLogger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

@MainActor
final class SwiftDataFolderRepository: FolderRepository {
    private let container: ModelContainer
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.now = now
    }

    func folders() throws -> [FolderRecord] {
        try FolderStore.folders(in: container.mainContext).map { FolderRecord(id: $0.id, name: $0.name) }
    }

    func createFolder(name: String) throws -> UUID {
        try FolderStore.create(name: name, context: container.mainContext, now: now()).id
    }

    func renameFolder(id: UUID, name: String) throws {
        try FolderStore.rename(id: id, name: name, context: container.mainContext, now: now())
    }

    func reorderFolders(ids: [UUID]) throws {
        try FolderStore.reorder(ids: ids, container: container, now: now())
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

    func addWord(source: String, translation: String, category: WordCategory?, folderID: UUID?) throws {
        try ScanWordStore.add(source: source, translation: translation, category: category,
                              folderID: folderID, container: container, now: now())
    }

    func toggleScannedWord(source: String, translation: String, category: WordCategory,
                           folderID: UUID?) throws -> Bool {
        try ScanWordStore.toggle(source: source, translation: translation, category: category,
                                 folderID: folderID, container: container, now: now())
    }

    func changeCategory(_ category: WordCategory, source: String, translation: String) throws {
        try ScanWordStore.changeCategory(category, source: source, translation: translation,
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
