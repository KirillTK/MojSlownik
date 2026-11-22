import Foundation
import SwiftData

/// Writes to `Workspace` rows (the FolderStore pattern). Deleting a workspace is a soft delete and
/// never touches its words or folders: they stay hidden by scope and return when the pair is re-added.
@MainActor
enum WorkspaceCatalog {
    enum StoreError: LocalizedError, Equatable {
        case lastWorkspace
        case missingWorkspace
        case invalidOrder

        var errorDescription: String? {
            switch self {
            case .lastWorkspace: "Нельзя удалить единственный язык"
            case .missingWorkspace: "Язык больше не существует"
            case .invalidOrder: "Не удалось изменить порядок языков"
            }
        }
    }

    /// Active workspaces in display order.
    static func workspaces(in context: ModelContext) throws -> [Workspace] {
        try context.fetch(FetchDescriptor<Workspace>()).filter(\.isActive).sorted(by: isOrderedBefore)
    }

    static func isOrderedBefore(_ lhs: Workspace, _ rhs: Workspace) -> Bool {
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Inserts the pair, or revives its tombstone; idempotent for an active workspace. The id is
    /// looked up in any state first, so a second row with the same id is never inserted.
    @discardableResult
    static func ensure(term: String, translation: String, context: ModelContext,
                       now: Date = .now) throws -> Workspace {
        let id = WorkspaceID.make(term: term, translation: translation)
        let all = try context.fetch(FetchDescriptor<Workspace>())
        let order = (all.filter(\.isActive).map(\.sortOrder).max() ?? -1) + 1
        if let existing = all.filter({ $0.id == id }).min(by: isPreferred) {
            guard !existing.isActive else { return existing }
            let previous = (existing.deletedAt, existing.updatedAt, existing.sortOrder)
            existing.deletedAt = nil
            existing.updatedAt = now
            existing.sortOrder = order
            do { try context.save() }
            catch {
                (existing.deletedAt, existing.updatedAt, existing.sortOrder) = previous
                throw error
            }
            return existing
        }
        let workspace = Workspace(termLanguageCode: term, translationLanguageCode: translation,
                                  sortOrder: order, createdAt: now)
        context.insert(workspace)
        do { try context.save() }
        catch {
            // Preserve unrelated pending changes in the observed screen context.
            context.delete(workspace)
            throw error
        }
        return workspace
    }

    @discardableResult
    static func ensure(term: String, translation: String, container: ModelContainer,
                       now: Date = .now) throws -> UUID {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try ensure(term: term, translation: translation, context: context, now: now).id
    }

    /// `ensure` plus what it did: a new row, an already active one, or a revived tombstone.
    static func ensureReportingOutcome(term: String, translation: String, container: ModelContainer,
                                       now: Date = .now) throws -> WorkspaceEnsureResult {
        let id = WorkspaceID.make(term: term, translation: translation)
        let before = try ModelContext(container).fetch(FetchDescriptor<Workspace>()).filter { $0.id == id }
        let outcome: WorkspaceEnsureResult.Outcome =
            before.isEmpty ? .created : (before.contains(where: \.isActive) ? .existing : .restored)
        try ensure(term: term, translation: translation, container: container, now: now)
        return WorkspaceEnsureResult(id: id, outcome: outcome)
    }

    /// Soft delete; refuses the last active workspace.
    static func delete(id: UUID, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let active = try context.fetch(FetchDescriptor<Workspace>()).filter(\.isActive)
        let targets = active.filter { $0.id == id }
        guard !targets.isEmpty else { throw StoreError.missingWorkspace }
        guard Set(active.map(\.id)).count > 1 else { throw StoreError.lastWorkspace }
        for workspace in targets { workspace.markDeleted(now: now) }
        try save(context)
    }

    static func reorder(ids: [UUID], container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let active = try context.fetch(FetchDescriptor<Workspace>()).filter(\.isActive)
        guard ids.count == active.count, Set(ids).count == ids.count, Set(ids) == Set(active.map(\.id)) else {
            throw StoreError.invalidOrder
        }
        for (index, id) in ids.enumerated() {
            for workspace in active where workspace.id == id && workspace.sortOrder != index {
                workspace.sortOrder = index
                workspace.updatedAt = now
            }
        }
        try save(context)
    }

    static func wordCount(workspaceID: UUID, in context: ModelContext) throws -> Int {
        WorkspaceScope.words(try context.fetch(FetchDescriptor<Word>()), workspaceID: workspaceID).count
    }

    static func folderCount(workspaceID: UUID, in context: ModelContext) throws -> Int {
        WorkspaceScope.folders(try context.fetch(FetchDescriptor<WordFolder>()), workspaceID: workspaceID).count
    }

    /// Winner among rows sharing an id: latest `lastModifiedAt`; ties the active one, then the earliest `createdAt`.
    static func isPreferred(_ lhs: Workspace, _ rhs: Workspace) -> Bool {
        if lhs.lastModifiedAt != rhs.lastModifiedAt { return lhs.lastModifiedAt > rhs.lastModifiedAt }
        if lhs.isActive != rhs.isActive { return lhs.isActive }
        return lhs.createdAt < rhs.createdAt
    }

    private static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
