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

    static func create(name: String, container: ModelContainer) throws -> WordFolder {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try create(name: name, context: context)
    }

    static func create(name: String, context: ModelContext) throws -> WordFolder {
        let name = try validatedName(name, excluding: nil, context: context)
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        let folder = WordFolder(name: name)
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

    static func rename(id: UUID, name: String, context: ModelContext) throws {
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        guard let folder = folders.first(where: { $0.id == id }) else {
            throw StoreError.missingFolder
        }
        let normalizedName = try validatedName(name, excluding: id, context: context)
        let previousName = folder.name
        folder.name = normalizedName
        do { try context.save() }
        catch {
            folder.name = previousName
            throw error
        }
    }

    static func reorder(ids: [UUID], container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        let currentIDs = Set(folders.map(\.id))
        guard ids.count == folders.count, Set(ids).count == ids.count, Set(ids) == currentIDs else {
            throw StoreError.invalidOrder
        }

        let previousOrders = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.sortOrder) })
        for (index, id) in ids.enumerated() {
            folders.first { $0.id == id }?.sortOrder = index
        }
        do { try context.save() }
        catch {
            for folder in folders { folder.sortOrder = previousOrders[folder.id] ?? folder.sortOrder }
            throw error
        }
    }

    static func folders(in context: ModelContext) throws -> [WordFolder] {
        try context.fetch(FetchDescriptor<WordFolder>()).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private static func nameKey(_ name: String) -> String {
        normalizedName(name)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func validatedName(_ name: String, excluding id: UUID?, context: ModelContext) throws -> String {
        let cleanedName = normalizedName(name)
        guard !cleanedName.isEmpty else { throw StoreError.emptyName }
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        guard !folders.contains(where: { $0.id != id && nameKey($0.name) == nameKey(cleanedName) }) else {
            throw StoreError.duplicateName
        }
        return cleanedName
    }

    static func delete(id: UUID, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        for folder in folders where folder.id == id { context.delete(folder) }
        let words = try context.fetch(FetchDescriptor<Word>())
        for word in words where word.folderIDs.contains(id) {
            word.folderIDs.removeAll { $0 == id }
        }
        try save(context)
    }

    static func setMembership(wordID: PersistentIdentifier, folderID: UUID,
                              included: Bool, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try setMembership(wordID: wordID, folderID: folderID, included: included, context: context)
    }

    static func setMembership(wordID: PersistentIdentifier, folderID: UUID,
                              included: Bool, context: ModelContext) throws {
        try requireFolder(folderID, in: context)
        let words = try context.fetch(FetchDescriptor<Word>())
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        let previousFolderIDs = word.folderIDs
        word.folderIDs.removeAll { $0 == folderID }
        if included { word.folderIDs.append(folderID) }
        try saveMembership(context, word: word, previousFolderIDs: previousFolderIDs)
    }

    static func removeFromAllFolders(wordID: PersistentIdentifier, context: ModelContext) throws {
        let words = try context.fetch(FetchDescriptor<Word>())
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        let previousFolderIDs = word.folderIDs
        word.folderIDs.removeAll()
        try saveMembership(context, word: word, previousFolderIDs: previousFolderIDs)
    }

    static func words(_ words: [Word], in folderID: UUID?) -> [Word] {
        guard let folderID else { return words }
        return words.filter { $0.folderIDs.contains(folderID) }
    }

    static func requireFolder(_ id: UUID, in context: ModelContext) throws {
        guard try context.fetch(FetchDescriptor<WordFolder>()).contains(where: { $0.id == id }) else {
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
                                       previousFolderIDs: [UUID]) throws {
        do { try context.save() }
        catch {
            word.folderIDs = previousFolderIDs
            throw error
        }
    }
}
