import Foundation
import SwiftData

/// A word's membership in a folder, mirroring `word_folders`. `id` is always
/// `MembershipID.make(wordID:folderID:)` (client-only: held ids, acks, de-duplication; the server
/// keys the row by word and folder). Removing a membership is a tombstone; adding it again revives it.
@Model
final class FolderMembership {
    var id: UUID = UUID()
    var wordID: UUID = UUID()
    var folderID: UUID = UUID()
    var workspaceID: UUID = WorkspaceID.legacy
    var createdAt: Date = Date.now
    var updatedAt: Date? = nil
    var deletedAt: Date? = nil
    // server updated_at of the last synced version; nil = never synced to the linked account;
    // .distantPast = re-link sentinel
    var serverUpdatedAt: Date? = nil

    init(wordID: UUID, folderID: UUID, workspaceID: UUID, createdAt: Date = .now) {
        self.id = MembershipID.make(wordID: wordID, folderID: folderID)
        self.wordID = wordID
        self.folderID = folderID
        self.workspaceID = workspaceID
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension FolderMembership {
    var isActive: Bool { deletedAt == nil }
    var lastModifiedAt: Date { updatedAt ?? createdAt }
    var isSyncDirty: Bool { serverUpdatedAt != lastModifiedAt }

    func markDeleted(now: Date) {
        deletedAt = now
        updatedAt = now
    }
}
