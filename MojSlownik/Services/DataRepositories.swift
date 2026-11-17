import Foundation

// Repository seams for vocabulary and folders. They are synchronous and main-actor on
// purpose: the app is offline-first, local writes complete immediately, and any future
// synchronization happens elsewhere by uuid/id, updatedAt and deletedAt.

struct FolderRecord: Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
}

enum RepositoryError: LocalizedError, Equatable {
    case missingIdentity

    var errorDescription: String? {
        switch self {
        case .missingIdentity: "Не удалось определить слово. Перезапустите приложение."
        }
    }
}

@MainActor
protocol FolderRepository: AnyObject {
    /// Active folders in display order.
    func folders() throws -> [FolderRecord]
    func createFolder(name: String) throws -> UUID
    func renameFolder(id: UUID, name: String) throws
    func reorderFolders(ids: [UUID]) throws
    /// Soft delete. Never deletes words.
    func deleteFolder(id: UUID) throws
}

@MainActor
protocol VocabularyRepository: AnyObject {
    func addWord(source: String, translation: String, category: WordCategory?, folderID: UUID?) throws
    func toggleScannedWord(source: String, translation: String, category: WordCategory,
                           folderID: UUID?) throws -> Bool
    func changeCategory(_ category: WordCategory, source: String, translation: String) throws
    func setCategory(_ category: WordCategory, wordID: UUID) throws
    /// Soft delete.
    func deleteWord(id: UUID) throws
    func setMembership(wordID: UUID, folderID: UUID, included: Bool) throws
    func removeFromAllFolders(wordID: UUID) throws
    func ensureIdentity(for word: Word) throws -> UUID
}
