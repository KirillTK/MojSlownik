import Foundation
import SwiftData

@MainActor
enum ScanWordStore {
    /// A separate context keeps failed scan writes from rolling back unrelated edits.
    static func toggle(_ entry: WordEntry, category: WordCategory, folderID: UUID? = nil,
                       workspace: WorkspaceContext, container: ModelContainer,
                       now: Date = .now) throws -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let words = WorkspaceScope.words(try context.fetch(FetchDescriptor<Word>()), workspaceID: workspace.id)
        let existing = words.filter { $0.matches(entry) }
        let isIncluded: Bool
        if let folderID {
            try FolderStore.requireFolder(folderID, in: context, workspaceID: workspace.id)
            if existing.isEmpty {
                let word = makeWord(entry, category: category, workspace: workspace, now: now)
                word.folderIDs = [folderID]
                context.insert(word)
                isIncluded = true
            } else {
                let wasIncluded = existing.contains { $0.folderIDs.contains(folderID) }
                let previousFolders = existing.map(\.folderIDs)
                // Legacy duplicates must not leave hidden membership behind.
                for word in existing { word.folderIDs.removeAll { $0 == folderID } }
                if !wasIncluded { existing[0].folderIDs.append(folderID) }
                for (word, previous) in zip(existing, previousFolders) where word.folderIDs != previous {
                    word.updatedAt = now
                }
                isIncluded = !wasIncluded
            }
        } else if !existing.isEmpty {
            for word in existing { word.markDeleted(now: now) }
            isIncluded = false
        } else {
            context.insert(makeWord(entry, category: category, workspace: workspace, now: now))
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

    /// Soft delete: the row stays as a tombstone.
    static func delete(wordID: PersistentIdentifier, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        guard let word = words.first(where: { $0.persistentModelID == wordID }) else {
            throw FolderStore.StoreError.missingWord
        }
        word.markDeleted(now: now)
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    static func add(_ entry: WordEntry, category: WordCategory? = nil, folderID: UUID? = nil,
                    workspace: WorkspaceContext, container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if let folderID { try FolderStore.requireFolder(folderID, in: context, workspaceID: workspace.id) }
        let words = WorkspaceScope.words(try context.fetch(FetchDescriptor<Word>()), workspaceID: workspace.id)
        let word: Word
        if let existing = words.first(where: { $0.matches(entry) }) {
            word = existing
            var changed = false
            if let category, word.category != category {
                word.category = category
                changed = true
            }
            if let folderID, !word.folderIDs.contains(folderID) {
                word.folderIDs.append(folderID)
                changed = true
            }
            if changed { word.updatedAt = now }
        } else {
            word = makeWord(entry, category: category, workspace: workspace, now: now)
            context.insert(word)
            if let folderID { word.folderIDs.append(folderID) }
        }
        do { try context.save() }
        catch {
            context.rollback()
            throw error
        }
    }

    static func changeCategory(_ category: WordCategory, entry: WordEntry, workspace: WorkspaceContext,
                               container: ModelContainer, now: Date = .now) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let words = WorkspaceScope.words(try context.fetch(FetchDescriptor<Word>()), workspaceID: workspace.id)
        guard let existing = words.first(where: { $0.matches(entry) }) else { return }
        guard existing.category != category else { return }
        existing.category = category
        existing.updatedAt = now
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func makeWord(_ entry: WordEntry, category: WordCategory?, workspace: WorkspaceContext,
                                 now: Date) -> Word {
        let word = Word(russian: entry.translation, polish: entry.term,
                        sourceLanguage: entry.enteredSide == .term ? .polish : .russian,
                        createdAt: now, category: category)
        word.sourceLanguageCode = workspace.code(of: entry.enteredSide)
        word.workspaceID = workspace.id
        return word
    }
}
