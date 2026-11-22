import Foundation
import SwiftData
import os

/// Launch migration to workspaces. Never touches texts, SRS values, `updatedAt` or `serverUpdatedAt`:
/// the server backfill makes the same assignment, so migrated rows stay clean.
@MainActor
enum WorkspaceBackfill {
    static let markerKey = "workspace.backfill.v1"
    private static let logger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

    /// De-duplicates workspace rows, creates the pl ← ru workspace for an existing install and
    /// assigns it to rows without a workspace. Own context, one save, rollback on failure; the
    /// one-time marker is written only after that save succeeded.
    @discardableResult
    static func run(container: ModelContainer, defaults: UserDefaults, now: Date = .now,
                    save: (ModelContext) throws -> Void = { try $0.save() }) -> Bool {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            try apply(in: context, markerPresent: defaults.bool(forKey: markerKey), now: now)
            try save(context)
            defaults.set(true, forKey: markerKey)
            return true
        } catch {
            context.rollback()
            logger.error("Workspace backfill failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static func apply(in context: ModelContext, markerPresent: Bool, now: Date) throws {
        let words = try context.fetch(FetchDescriptor<Word>())
        let folders = try context.fetch(FetchDescriptor<WordFolder>())

        // 0. One row per workspace id (SwiftData has no unique constraint on iOS 17).
        var workspaces = try context.fetch(FetchDescriptor<Workspace>())
        for duplicates in Dictionary(grouping: workspaces, by: \.id).values where duplicates.count > 1 {
            let keep = duplicates.min(by: WorkspaceCatalog.isPreferred)
            for workspace in duplicates where workspace !== keep { context.delete(workspace) }
        }
        workspaces = Dictionary(grouping: workspaces, by: \.id).values.compactMap { $0.min(by: WorkspaceCatalog.isPreferred) }

        // 1. The legacy workspace; a row with its id in any state is never inserted twice or revived.
        let hasLegacy = workspaces.contains { $0.id == WorkspaceID.legacy }
        if !hasLegacy {
            let unassigned = words.contains { $0.workspaceID == nil } || folders.contains { $0.workspaceID == nil }
            let existingInstall = !markerPresent && (!words.isEmpty || !folders.isEmpty)
            // A fresh install gets no workspace here: the gate shows the wizard (or waits for the first pull).
            if existingInstall || unassigned {
                let earliest = (words.map(\.createdAt) + folders.map(\.createdAt)).min()
                context.insert(Workspace(termLanguageCode: "pl", translationLanguageCode: "ru",
                                         sortOrder: 0, createdAt: earliest ?? now))
            }
        }

        // 2. Rows from before workspaces join the legacy workspace.
        for word in words where word.workspaceID == nil { word.workspaceID = WorkspaceID.legacy }
        for folder in folders where folder.workspaceID == nil { folder.workspaceID = WorkspaceID.legacy }

        try migrateLegacyMemberships(words: words, folders: folders, in: context)
    }

    /// 3. Legacy `Word.folderIDs` become `FolderMembership` rows (once per word, flag
    /// `legacyFolderIDsMigrated`); 4. rows sharing an id are de-duplicated. Never touches words'
    /// `updatedAt`, the legacy array, or any word/folder row; ids of missing or deleted folders stay in the
    /// array and are not migrated (the server backfill drops the same ids).
    private static func migrateLegacyMemberships(words: [Word], folders: [WordFolder],
                                                 in context: ModelContext) throws {
        var memberships = try context.fetch(FetchDescriptor<FolderMembership>())

        // 4. Keep the latest modified row per id (membership rows only).
        for duplicates in Dictionary(grouping: memberships, by: \.id).values where duplicates.count > 1 {
            let keep = duplicates.max { $0.lastModifiedAt < $1.lastModifiedAt }
            for membership in duplicates where membership !== keep { context.delete(membership) }
        }
        memberships = Dictionary(grouping: memberships, by: \.id).values.compactMap { rows in
            rows.max { $0.lastModifiedAt < $1.lastModifiedAt }
        }

        var existing = Set(memberships.map(\.id))
        var activeFolders: [UUID: WordFolder] = [:]
        for folder in folders where folder.isActive { activeFolders[folder.id] = folder }
        for word in words where !word.legacyFolderIDsMigrated {
            guard let wordID = word.uuid else { continue }
            var seen = Set<UUID>()
            for folderID in word.folderIDs where seen.insert(folderID).inserted {
                guard let folder = activeFolders[folderID],
                      folder.effectiveWorkspaceID == word.effectiveWorkspaceID else { continue }
                let id = MembershipID.make(wordID: wordID, folderID: folderID)
                guard existing.insert(id).inserted else { continue }
                context.insert(FolderMembership(wordID: wordID, folderID: folderID,
                                                workspaceID: word.effectiveWorkspaceID,
                                                createdAt: word.lastModifiedAt))
            }
            word.legacyFolderIDsMigrated = true
        }
    }
}
