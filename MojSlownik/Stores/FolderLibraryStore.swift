import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class FolderLibraryStore {
    struct Option: Identifiable, Equatable, Hashable {
        let id: UUID
        let name: String
    }

    private(set) var options: [Option] = []

    func load(context: ModelContext) throws {
        options = try FolderStore.folders(in: context)
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

    func rename(id: UUID, name: String, context: ModelContext) throws {
        try FolderStore.rename(id: id, name: name, context: context)
        try load(context: context)
    }

    func reorder(ids: [UUID], context: ModelContext) throws {
        try FolderStore.reorder(ids: ids, container: context.container)
        try load(context: context)
    }
}
