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

    init(repository: any FolderRepository) {
        self.repository = repository
    }

    func load() throws {
        options = try repository.folders().map { Option(id: $0.id, name: $0.name) }
    }

    @discardableResult
    func create(name: String) throws -> UUID {
        let id = try repository.createFolder(name: name)
        try load()
        return id
    }

    func delete(id: UUID) throws {
        try repository.deleteFolder(id: id)
        try load()
    }

    func rename(id: UUID, name: String) throws {
        try repository.renameFolder(id: id, name: name)
        try load()
    }

    func reorder(ids: [UUID]) throws {
        try repository.reorderFolders(ids: ids)
        try load()
    }
}
