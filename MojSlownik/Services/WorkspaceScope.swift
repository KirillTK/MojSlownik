import Foundation

/// Read-side scoping: active rows of one workspace. Rows from before workspaces
/// (`workspaceID == nil`) belong to the legacy pl ← ru workspace.
enum WorkspaceScope {
    static func words(_ words: [Word], workspaceID: UUID?) -> [Word] {
        guard let workspaceID else { return [] }
        return words.filter { $0.isActive && $0.effectiveWorkspaceID == workspaceID }
    }

    static func folders(_ folders: [WordFolder], workspaceID: UUID?) -> [WordFolder] {
        guard let workspaceID else { return [] }
        return folders.filter { $0.isActive && $0.effectiveWorkspaceID == workspaceID }
    }
}
