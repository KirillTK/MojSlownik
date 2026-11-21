import Foundation
import SwiftData
@testable import MojSlownik

// Test helpers for the legacy pl ← ru workspace. Production APIs are explicit about the workspace;
// most store tests exercise one workspace, so these overloads keep them short.

extension WorkspaceContext {
    static let legacy = WorkspaceContext(id: WorkspaceID.legacy, termCode: "pl", translationCode: "ru")
    static let germanRussian = WorkspaceContext(id: WorkspaceID.make(term: "de", translation: "ru"),
                                                termCode: "de", translationCode: "ru")
}

@MainActor
extension FolderStore {
    static func create(name: String, container: ModelContainer, now: Date = .now) throws -> WordFolder {
        try create(name: name, workspaceID: WorkspaceID.legacy, container: container, now: now)
    }

    static func create(name: String, context: ModelContext, now: Date = .now) throws -> WordFolder {
        try create(name: name, workspaceID: WorkspaceID.legacy, context: context, now: now)
    }

    static func reorder(ids: [UUID], container: ModelContainer, now: Date = .now) throws {
        try reorder(ids: ids, workspaceID: WorkspaceID.legacy, container: container, now: now)
    }

    static func folders(in context: ModelContext) throws -> [WordFolder] {
        try folders(in: context, workspaceID: WorkspaceID.legacy)
    }

    static func requireFolder(_ id: UUID, in context: ModelContext) throws {
        try requireFolder(id, in: context, workspaceID: WorkspaceID.legacy)
    }
}

@MainActor
extension ScanWordStore {
    static func toggle(source: String, translation: String, category: WordCategory, folderID: UUID? = nil,
                       container: ModelContainer, now: Date = .now) throws -> Bool {
        try toggle(WordEntry.legacy(source: source, translation: translation), category: category,
                   folderID: folderID, workspace: .legacy, container: container, now: now)
    }

    static func add(source: String, translation: String, category: WordCategory? = nil, folderID: UUID? = nil,
                    container: ModelContainer, now: Date = .now) throws {
        try add(WordEntry.legacy(source: source, translation: translation), category: category,
                folderID: folderID, workspace: .legacy, container: container, now: now)
    }

    static func changeCategory(_ category: WordCategory, source: String, translation: String,
                               container: ModelContainer, now: Date = .now) throws {
        try changeCategory(category, entry: WordEntry.legacy(source: source, translation: translation),
                           workspace: .legacy, container: container, now: now)
    }
}

@MainActor
extension FolderLibraryStore {
    /// A store already scoped to the legacy pl ← ru workspace.
    static func inLegacyWorkspace(repository: any FolderRepository, logger: (any AppLogging)? = nil,
                                  changeSignal: LocalChangeSignal? = nil) -> FolderLibraryStore {
        let store = FolderLibraryStore(repository: repository, logger: logger, changeSignal: changeSignal)
        store.workspaceID = WorkspaceID.legacy
        return store
    }
}
