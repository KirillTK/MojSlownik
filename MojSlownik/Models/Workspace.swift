import Foundation
import SwiftData

/// A language pair (studied ← translation) with its own words, folders and practice scope.
/// `id` is always `WorkspaceID.make(term:translation:)`: one workspace per pair on every device.
@Model
final class Workspace {
    var id: UUID = UUID()
    var termLanguageCode: String = "pl"
    var translationLanguageCode: String = "ru"
    var sortOrder: Int = 0
    var createdAt: Date = Date.now
    var updatedAt: Date? = nil
    var deletedAt: Date? = nil
    // server updated_at of the last synced version; nil = never synced to the linked account;
    // .distantPast = re-link sentinel
    var serverUpdatedAt: Date? = nil

    init(termLanguageCode: String, translationLanguageCode: String, sortOrder: Int = 0, createdAt: Date = .now) {
        self.id = WorkspaceID.make(term: termLanguageCode, translation: translationLanguageCode)
        self.termLanguageCode = termLanguageCode
        self.translationLanguageCode = translationLanguageCode
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

extension Workspace {
    var isActive: Bool { deletedAt == nil }
    var lastModifiedAt: Date { updatedAt ?? createdAt }
    var isSyncDirty: Bool { serverUpdatedAt != lastModifiedAt }

    func markDeleted(now: Date) {
        deletedAt = now
        updatedAt = now
    }
}
