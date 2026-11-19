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
        options = try repository.folders().map { Option(id: $0.id, name: $0.name) }
    }

    /// Folder names are user content and are never logged.
    @discardableResult
    func create(name: String) throws -> UUID {
        let id = try repository.createFolder(name: name)
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
        try repository.reorderFolders(ids: ids)
        changeSignal?.notify()
        logger.log(.foldersReordered, [.count: .int(ids.count)])
        try load()
    }
}
