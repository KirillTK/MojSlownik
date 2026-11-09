import Foundation
import SwiftData

@MainActor
enum ScanWordStore {
    /// A separate context keeps failed scan writes from rolling back unrelated edits.
    static func toggle(source: String, translation: String, category: WordCategory,
                       folderID: UUID? = nil, container: ModelContainer) throws -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let language = LanguageDetector.detect(source)
        let words = try context.fetch(FetchDescriptor<Word>())
        let existing = words.filter { $0.matches(source: source, translation: translation, language: language) }
        let isIncluded: Bool
        if let folderID {
            try FolderStore.requireFolder(folderID, in: context)
            if existing.isEmpty {
                let word = Word(
                    russian: language == .russian ? source : translation,
                    polish: language == .polish ? source : translation,
                    sourceLanguage: language, category: category
                )
                word.folderIDs = [folderID]
                context.insert(word)
                isIncluded = true
            } else {
                let wasIncluded = existing.contains { $0.folderIDs.contains(folderID) }
                // Legacy duplicates must not leave hidden membership behind.
                for word in existing { word.folderIDs.removeAll { $0 == folderID } }
                if !wasIncluded { existing[0].folderIDs.append(folderID) }
                isIncluded = !wasIncluded
            }
        } else if !existing.isEmpty {
            for word in existing { context.delete(word) }
            isIncluded = false
        } else {
            context.insert(Word(
                russian: language == .russian ? source : translation,
                polish: language == .polish ? source : translation,
                sourceLanguage: language,
                category: category
            ))
            isIncluded = true
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return isIncluded
    }

    static func add(source: String, translation: String, category: WordCategory? = nil,
                    folderID: UUID? = nil, container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let folderID { try FolderStore.requireFolder(folderID, in: context) }
        let language = LanguageDetector.detect(source)
        let words = try context.fetch(FetchDescriptor<Word>())
        let word: Word
        if let existing = words.first(where: {
            $0.matches(source: source, translation: translation, language: language)
        }) {
            word = existing
            if let category { word.category = category }
        } else {
            word = Word(
                russian: language == .russian ? source : translation,
                polish: language == .polish ? source : translation,
                sourceLanguage: language, category: category
            )
            context.insert(word)
        }
        if let folderID, !word.folderIDs.contains(folderID) { word.folderIDs.append(folderID) }
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    static func changeCategory(_ category: WordCategory, source: String, translation: String,
                               container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let language = LanguageDetector.detect(source)
        let words = try context.fetch(FetchDescriptor<Word>())
        guard let existing = words.first(where: {
            $0.matches(source: source, translation: translation, language: language)
        }) else { return }
        existing.category = category
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
