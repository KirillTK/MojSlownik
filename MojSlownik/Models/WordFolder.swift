import Foundation
import SwiftData

@Model
final class WordFolder {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date
    var sortOrder: Int = 0
    var updatedAt: Date? = nil
    var deletedAt: Date? = nil
    // server updated_at of the last synced version; nil = never synced to the linked account;
    // .distantPast = re-link sentinel
    var serverUpdatedAt: Date? = nil

    init(name: String) {
        self.name = name
        self.createdAt = .now
        self.updatedAt = createdAt
    }
}

extension WordFolder {
    var isActive: Bool { deletedAt == nil }
    var lastModifiedAt: Date { updatedAt ?? createdAt }
    var isSyncDirty: Bool { serverUpdatedAt != lastModifiedAt }

    func markDeleted(now: Date) {
        deletedAt = now
        updatedAt = now
    }
}
