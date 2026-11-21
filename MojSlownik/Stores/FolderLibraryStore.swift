import Foundation
import Observation

@MainActor
@Observable
final class FolderLibraryStore {
    struct Option: Identifiable, Equatable, Hashable {
        let id: UUID
        let name: String
    }

    private(set) var options: [Option] = []
    /// The active workspace (set by the app wiring); nil lists no folders.
    @ObservationIgnored var workspaceID: UUID?
    @ObservationIgnored private let repository: any FolderRepository
    @ObservationIgnored private let logger: any AppLogging

    @ObservationIgnored private let changeSignal: LocalChangeSignal?

    init(repository: any FolderRepository, logger: (any AppLogging)? = nil,
         changeSignal: LocalChangeSignal? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.changeSignal = changeSignal
        self.repository = LoggingFolderRepository(repository, logger: logger)
        self.logger = logger
    }

    func load() throws {
        guard let workspaceID else {
            options = []
            return
        }
        options = try repository.folders(in: workspaceID).map { Option(id: $0.id, name: $0.name) }
    }

    /// Folder names are user content and are never logged.
    @discardableResult
    func create(name: String) throws -> UUID {
        guard let workspaceID else { throw RepositoryError.noWorkspace }
        let id = try repository.createFolder(name: name, workspaceID: workspaceID)
        changeSignal?.notify()
        logger.log(.folderCreated)
        try load()
        return id
    }

    func delete(id: UUID) throws {
        try repository.deleteFolder(id: id)
        changeSignal?.notify()
        logger.log(.folderDeleted)
        try load()
    }

    func rename(id: UUID, name: String) throws {
        try repository.renameFolder(id: id, name: name)
        changeSignal?.notify()
        logger.log(.folderRenamed)
        try load()
    }

    func reorder(ids: [UUID]) throws {
        guard let workspaceID else { throw RepositoryError.noWorkspace }
        try repository.reorderFolders(ids: ids, workspaceID: workspaceID)
        changeSignal?.notify()
        logger.log(.foldersReordered, [.count: .int(ids.count)])
        try load()
    }
}
