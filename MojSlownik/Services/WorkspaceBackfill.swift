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
            // Phases 1-3 fallback (removed in phase 4): without any active workspace the app has no scope.
            let noActive = !workspaces.contains(where: \.isActive)
            if existingInstall || unassigned || noActive {
                let earliest = (words.map(\.createdAt) + folders.map(\.createdAt)).min()
                let created = (existingInstall || unassigned) ? (earliest ?? now) : now
                context.insert(Workspace(termLanguageCode: "pl", translationLanguageCode: "ru",
                                         sortOrder: 0, createdAt: created))
            }
        }

        // 2. Rows from before workspaces join the legacy workspace.
        for word in words where word.workspaceID == nil { word.workspaceID = WorkspaceID.legacy }
        for folder in folders where folder.workspaceID == nil { folder.workspaceID = WorkspaceID.legacy }
    }
}
