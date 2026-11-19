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

    static func create(name: String, container: ModelContainer, now: Date = .now) throws -> WordFolder {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try create(name: name, context: context, now: now)
    }

    static func create(name: String, context: ModelContext, now: Date = .now) throws -> WordFolder {
        let name = try validatedName(name, excluding: nil, context: context)
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
        let folder = WordFolder(name: name)
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
        let normalizedName = try validatedName(name, excluding: id, context: context)
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

    static func reorder(ids: [UUID], container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
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

    static func folders(in context: ModelContext) throws -> [WordFolder] {
        try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive).sorted { lhs, rhs in
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

    private static func validatedName(_ name: String, excluding id: UUID?, context: ModelContext) throws -> String {
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
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

    /// Soft delete: the folder row stays as a tombstone. Words are never deleted.
    static func delete(id: UUID, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try context.fetch(FetchDescriptor<WordFolder>()).filter(\.isActive)
        for folder in folders where folder.id == id { folder.markDeleted(now: now) }
        let words = try context.fetch(FetchDescriptor<Word>())
        for word in words where word.folderIDs.contains(id) {
            word.folderIDs.removeAll { $0 == id }
            // Tombstones keep their deletion-time updatedAt.
            if word.isActive { word.updatedAt = now }
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
        try requireFolder(folderID, in: context)
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        let previousFolderIDs = word.folderIDs
        word.folderIDs.removeAll { $0 == folderID }
        if included { word.folderIDs.append(folderID) }
        try saveMembership(context, word: word, previousFolderIDs: previousFolderIDs, now: now)
    }

    static func removeFromAllFolders(wordID: PersistentIdentifier, context: ModelContext,
                                     now: Date = .now) throws {
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        let previousFolderIDs = word.folderIDs
        word.folderIDs.removeAll()
        try saveMembership(context, word: word, previousFolderIDs: previousFolderIDs, now: now)
    }

    static func words(_ words: [Word], in folderID: UUID?) -> [Word] {
        let words = words.filter(\.isActive)
        guard let folderID else { return words }
        return words.filter { $0.folderIDs.contains(folderID) }
    }

    static func requireFolder(_ id: UUID, in context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<WordFolder>()).contains(where: { $0.id == id && $0.isActive }) else {
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

    private static func saveMembership(_ context: ModelContext, word: Word,
                                       previousFolderIDs: [UUID], now: Date) throws {
        guard word.folderIDs != previousFolderIDs else { return }
        let previousUpdatedAt = word.updatedAt
        word.updatedAt = now
        do { try context.save() }
        catch {
            word.folderIDs = previousFolderIDs
            word.updatedAt = previousUpdatedAt
            throw error
        }
    }
}
