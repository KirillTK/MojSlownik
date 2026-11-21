import Foundation

// Repository seams for vocabulary and folders. They are synchronous and main-actor on
// purpose: the app is offline-first, local writes complete immediately, and any future
// synchronization happens elsewhere by uuid/id, updatedAt and deletedAt.

struct FolderRecord: Equatable, Hashable, Sendable {
    let id: UUID
    let name: String
}

struct WorkspaceRecord: Equatable, Hashable, Sendable {
    let id: UUID
    let termCode: String
    let translationCode: String
    let sortOrder: Int
}

/// The active workspace as the stores and repositories need it.
struct WorkspaceContext: Equatable, Sendable {
    let id: UUID
    let termCode: String
    let translationCode: String

    /// The workspace languages. Codes are validated when a workspace is created or pulled; an
    /// unsupported pair (not creatable) falls back to pl ← ru rather than crashing.
    var pair: LanguagePair {
        LanguagePair(termCode: termCode, translationCode: translationCode) ?? .polishRussian
    }

    /// Language code of the side that was entered.
    func code(of side: WordSide) -> String {
        side == .term ? termCode : translationCode
    }
}

enum RepositoryError: LocalizedError, Equatable {
    case missingIdentity
    case noWorkspace

    var errorDescription: String? {
        switch self {
        case .missingIdentity: "Не удалось определить слово. Перезапустите приложение."
        case .noWorkspace: "Выберите язык словаря"
        }
    }
}

@MainActor
protocol WorkspaceRepository: AnyObject {
    /// Active workspaces in display order.
    func workspaces() throws -> [WorkspaceRecord]
    /// Adds the pair, or revives it after a delete; returns its id.
    func ensure(term: String, translation: String) throws -> UUID
    /// Soft delete; refuses the last active workspace. Never touches words or folders.
    func delete(id: UUID) throws
    func reorder(ids: [UUID]) throws
}

@MainActor
protocol FolderRepository: AnyObject {
    /// Active folders of the workspace in display order.
    func folders(in workspaceID: UUID) throws -> [FolderRecord]
    func createFolder(name: String, workspaceID: UUID) throws -> UUID
    func renameFolder(id: UUID, name: String) throws
    func reorderFolders(ids: [UUID], workspaceID: UUID) throws
    /// Soft delete. Never deletes words.
    func deleteFolder(id: UUID) throws
}

@MainActor
protocol VocabularyRepository: AnyObject {
    func addWord(_ entry: WordEntry, category: WordCategory?, folderID: UUID?,
                 workspace: WorkspaceContext) throws
    func toggleScannedWord(_ entry: WordEntry, category: WordCategory, folderID: UUID?,
                           workspace: WorkspaceContext) throws -> Bool
    func changeCategory(_ category: WordCategory, entry: WordEntry, workspace: WorkspaceContext) throws
    func setCategory(_ category: WordCategory, wordID: UUID) throws
    /// Soft delete.
    func deleteWord(id: UUID) throws
    func setMembership(wordID: UUID, folderID: UUID, included: Bool) throws
    func removeFromAllFolders(wordID: UUID) throws
    func ensureIdentity(for word: Word) throws -> UUID
}
