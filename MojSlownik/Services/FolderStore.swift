import Foundation
import SwiftData

@MainActor
enum FolderStore {
    enum StoreError: LocalizedError {
        case emptyName
        case duplicateName
        case missingFolder
        case missingWord
        case invalidOrder

        var errorDescription: String? {
            switch self {
            case .emptyName: "Введите название папки"
            case .duplicateName: "Папка с таким названием уже существует"
            case .missingFolder: "Папка больше не существует"
            case .missingWord: "Слово больше не существует"
            case .invalidOrder: "Не удалось изменить порядок папок"
            }
        }
    }

    static func create(name: String, workspaceID: UUID, container: ModelContainer,
                       now: Date = .now) throws -> WordFolder {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try create(name: name, workspaceID: workspaceID, context: context, now: now)
    }

    static func create(name: String, workspaceID: UUID, context: ModelContext,
                       now: Date = .now) throws -> WordFolder {
        let name = try validatedName(name, excluding: nil, workspaceID: workspaceID, context: context)
        let folders = try scoped(context, workspaceID: workspaceID)
        let folder = WordFolder(name: name)
        folder.workspaceID = workspaceID
        folder.createdAt = now
        folder.updatedAt = now
        folder.sortOrder = (folders.map(\.sortOrder).max() ?? -1) + 1
        context.insert(folder)
        do { try context.save() }
        catch {
            // Preserve unrelated pending changes in the observed screen context.
            context.delete(folder)
            throw error
        }
        return folder
    }

    static func rename(id: UUID, name: String, context: ModelContext, now: Date = .now) throws {
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
        guard let folder = folders.first(where: { $0.id == id }) else {
            throw StoreError.missingFolder
        }
        let normalizedName = try validatedName(name, excluding: id, workspaceID: folder.effectiveWorkspaceID,
                                               context: context)
        guard normalizedName != folder.name else { return }
        let previousName = folder.name
        let previousUpdatedAt = folder.updatedAt
        folder.name = normalizedName
        folder.updatedAt = now
        do { try context.save() }
        catch {
            folder.name = previousName
            folder.updatedAt = previousUpdatedAt
            throw error
        }
    }

    static func reorder(ids: [UUID], workspaceID: UUID, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try scoped(context, workspaceID: workspaceID)
        let currentIDs = Set(folders.map(\.id))
        guard ids.count == folders.count, Set(ids).count == ids.count, Set(ids) == currentIDs else {
            throw StoreError.invalidOrder
        }

        let previousOrders = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.sortOrder) })
        let previousUpdates = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.updatedAt) })
        for (index, id) in ids.enumerated() {
            guard let folder = folders.first(where: { $0.id == id }), folder.sortOrder != index else { continue }
            folder.sortOrder = index
            folder.updatedAt = now
        }
        do { try context.save() }
        catch {
            for folder in folders {
                folder.sortOrder = previousOrders[folder.id] ?? folder.sortOrder
                folder.updatedAt = previousUpdates[folder.id] ?? folder.updatedAt
            }
            throw error
        }
    }

    /// Active folders of one workspace, unsorted.
    private static func scoped(_ context: ModelContext, workspaceID: UUID) throws -> [WordFolder] {
        WorkspaceScope.folders(try context.fetch(FetchDescriptor<WordFolder>()), workspaceID: workspaceID)
    }

    static func folders(in context: ModelContext, workspaceID: UUID) throws -> [WordFolder] {
        try scoped(context, workspaceID: workspaceID).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func nameKey(_ name: String) -> String {
        normalizedName(name)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func validatedName(_ name: String, excluding id: UUID?, workspaceID: UUID,
                                      context: ModelContext) throws -> String {
        let folders = try scoped(context, workspaceID: workspaceID)
        return try validatedName(name, excluding: id, existing: folders.map { FolderRecord(id: $0.id, name: $0.name) })
    }

    /// Shared name rule; `existing` must contain active folders only.
    static func validatedName(_ name: String, excluding id: UUID?, existing: [FolderRecord]) throws -> String {
        let cleanedName = normalizedName(name)
        guard !cleanedName.isEmpty else { throw StoreError.emptyName }
        guard !existing.contains(where: { $0.id != id && nameKey($0.name) == nameKey(cleanedName) }) else {
            throw StoreError.duplicateName
        }
        return cleanedName
    }

    /// Soft delete: the folder row stays as a tombstone, and so do its memberships (they sync).
    /// Words are never deleted.
    static func delete(id: UUID, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
        for folder in folders where folder.id == id { folder.markDeleted(now: now) }
        for membership in try context.fetch(FetchDescriptor<FolderMembership>())
        where membership.folderID == id && membership.isActive {
            membership.markDeleted(now: now)
        }
        try save(context)
    }

    static func setMembership(wordID: PersistentIdentifier, folderID: UUID,
                              included: Bool, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try setMembership(wordID: wordID, folderID: folderID, included: included, context: context, now: now)
    }

    static func setMembership(wordID: PersistentIdentifier, folderID: UUID,
                              included: Bool, context: ModelContext, now: Date = .now) throws {
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        guard let uuid = word.uuid else { throw RepositoryError.missingIdentity }
        try requireFolder(folderID, in: context, workspaceID: word.effectiveWorkspaceID)
        var undo = MembershipUndo()
        let memberships = try context.fetch(FetchDescriptor<FolderMembership>())
        setMembership(wordID: uuid, folderID: folderID, workspaceID: word.effectiveWorkspaceID,
                      included: included, among: memberships, context: context, now: now, undo: &undo)
        try saveMembership(context, undo: undo)
    }

    static func removeFromAllFolders(wordID: PersistentIdentifier, context: ModelContext,
                                     now: Date = .now) throws {
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        guard let uuid = word.uuid else { throw RepositoryError.missingIdentity }
        var undo = MembershipUndo()
        tombstoneMemberships(ofWord: uuid, among: try context.fetch(FetchDescriptor<FolderMembership>()),
                             now: now, undo: &undo)
        try saveMembership(context, undo: undo)
    }

    static func words(_ words: [Word], in folderID: UUID?, memberships: MembershipIndex) -> [Word] {
        let words = words.filter(\.isActive)
        guard let folderID else { return words }
        return words.filter { memberships.contains(wordID: $0.uuid, folderID: folderID) }
    }

    // MARK: Membership rows

    /// Reverts membership changes of a failed save without touching unrelated pending changes.
    struct MembershipUndo {
        fileprivate var inserted: [FolderMembership] = []
        fileprivate var modified: [(FolderMembership, deletedAt: Date?, updatedAt: Date?)] = []
        var isEmpty: Bool { inserted.isEmpty && modified.isEmpty }
    }

    /// Adds (creates or revives) or removes (tombstones) one membership. Does not save and does
    /// not touch the word: only the membership row changes.
    static func setMembership(wordID: UUID, folderID: UUID, workspaceID: UUID, included: Bool,
                              among memberships: [FolderMembership], context: ModelContext, now: Date,
                              undo: inout MembershipUndo) {
        let id = MembershipID.make(wordID: wordID, folderID: folderID)
        let existing = memberships.first { $0.id == id }
        if included {
            if let existing {
                guard !existing.isActive else { return }
                undo.modified.append((existing, existing.deletedAt, existing.updatedAt))
                existing.deletedAt = nil
                existing.updatedAt = now
            } else {
                let membership = FolderMembership(wordID: wordID, folderID: folderID,
                                                  workspaceID: workspaceID, createdAt: now)
                context.insert(membership)
                undo.inserted.append(membership)
            }
        } else if let existing, existing.isActive {
            undo.modified.append((existing, existing.deletedAt, existing.updatedAt))
            existing.markDeleted(now: now)
        }
    }

    /// Tombstones every active membership of the word (word deletion, remove from all folders).
    static func tombstoneMemberships(ofWord wordID: UUID, among memberships: [FolderMembership], now: Date,
                                     undo: inout MembershipUndo) {
        for membership in memberships where membership.wordID == wordID && membership.isActive {
            undo.modified.append((membership, membership.deletedAt, membership.updatedAt))
            membership.markDeleted(now: now)
        }
    }

    static func saveMembership(_ context: ModelContext, undo: MembershipUndo) throws {
        guard !undo.isEmpty else { return }
        do { try context.save() }
        catch {
            for (membership, deletedAt, updatedAt) in undo.modified {
                membership.deletedAt = deletedAt
                membership.updatedAt = updatedAt
            }
            for membership in undo.inserted { context.delete(membership) }
            throw error
        }
    }

    static func requireFolder(_ id: UUID, in context: ModelContext, workspaceID: UUID) throws {
        guard try scoped(context, workspaceID: workspaceID).contains(where: { $0.id == id }) else {
            throw StoreError.missingFolder
        }
    }

    private static func save(_ context: ModelContext) throws {
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }
}
