import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FolderLibraryStore {
    struct Option: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    private(set) var options: [Option] = []

    func load(context: ModelContext) throws {
        options = try context.fetch(FetchDescriptor<WordFolder>(sortBy: [SortDescriptor(\WordFolder.createdAt)]))
            .map { Option(id: $0.id, name: $0.name) }
    }

    @discardableResult
    func create(name: String, context: ModelContext) throws -> UUID {
        let folder = try FolderStore.create(name: name, context: context)
        try load(context: context)
        return folder.id
    }

    func delete(id: UUID, context: ModelContext) throws {
        try FolderStore.delete(id: id, container: context.container)
        try load(context: context)
    }
}
