import Foundation
import SwiftData

@MainActor
enum FolderStore {
    enum StoreError: LocalizedError {
        case emptyName
        case duplicateName
        case missingFolder
        case missingWord

        var errorDescription: String? {
            switch self {
            case .emptyName: "Введите название папки"
            case .duplicateName: "Папка с таким названием уже существует"
            case .missingFolder: "Папка больше не существует"
            case .missingWord: "Слово больше не существует"
            }
        }
    }

    static func create(name: String, container: ModelContainer) throws -> WordFolder {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return try create(name: name, context: context)
    }

    static func create(name: String, context: ModelContext) throws -> WordFolder {
        let name = name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !name.isEmpty else { throw StoreError.emptyName }
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        guard !folders.contains(where: { nameKey($0.name) == nameKey(name) }) else {
            throw StoreError.duplicateName
        }
        let folder = WordFolder(name: name)
        context.insert(folder)
        do { try context.save() }
        catch {
            // Preserve unrelated pending changes in the observed screen context.
            context.delete(folder)
            throw error
        }
        return folder
    }

    private static func nameKey(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .precomposedStringWithCanonicalMapping.lowercased()
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
        try requireFolder(folderID, in: context)
        let words = try context.fetch(FetchDescriptor<Word>())
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw StoreError.missingWord
        }
        word.folderIDs.removeAll { $0 == folderID }
        if included { word.folderIDs.append(folderID) }
        try save(context)
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
}
