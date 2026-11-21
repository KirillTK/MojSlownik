import Foundation
import SwiftData

enum SyncKind: Sendable {
    case words, folders
}

struct SyncApplyResult: Equatable, Sendable {
    var inserted = 0
    var updated = 0
    var softDeleted = 0
    var adopted = 0
    /// Set by `applyFolders` when it changed anything (the folder list must be reloaded).
    var foldersChanged = false

    var changedAnything: Bool { inserted + updated + softDeleted + adopted > 0 }
}

/// An outgoing row with the `lastModifiedAt` it was built from. An ack applies only if the row
/// still has that value, so an edit made during the request keeps the row dirty.
struct PendingRow<Payload: Sendable>: Sendable {
    let id: UUID
    let snapshot: Date
    let payload: Payload
}

extension PendingRow: Equatable where Payload: Equatable {}

/// Dirty rows ready to upload, plus the rows that failed outgoing validation (counted per
/// reason; they stay dirty).
struct PendingBatch<Payload: Sendable>: Sendable {
    var rows: [PendingRow<Payload>] = []
    var invalid: [String: Int] = [:]
}

/// The SwiftData side of sync. Each method uses one fresh context with an explicit save and a
/// rollback on failure (the ScanWordStore pattern), so a failed sync step never leaves a
/// partial change. Nothing here hard-deletes a row.
@MainActor
final class SwiftDataSyncStore {
    static let relinkSentinel = RemoteMergePolicy.relinkSentinel
    /// Test counter: how many times an adoption index was built (once per `applyWords` call).
    static var adoptionIndexBuilds = 0

    private let container: ModelContainer
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = { .now }) {
        self.container = container
        self.now = now
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func save(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: Linking

    /// Resets per-row sync state for a new link. Clean, previously synced rows get the sentinel
    /// (the account's version wins unless the account lacks the row); every other row gets nil
    /// (real local changes: uploaded and merged by last write). Existing sentinels stay.
    func prepareLink() throws {
        let context = makeContext()
        for word in try context.fetch(FetchDescriptor<Word>()) {
            word.serverUpdatedAt = Self.linkedState(word.serverUpdatedAt, dirty: word.isSyncDirty)
        }
        for folder in try context.fetch(FetchDescriptor<WordFolder>()) {
            folder.serverUpdatedAt = Self.linkedState(folder.serverUpdatedAt, dirty: folder.isSyncDirty)
        }
        try save(context)
    }

    private static func linkedState(_ current: Date?, dirty: Bool) -> Date? {
        guard let current else { return nil }
        if current == relinkSentinel { return relinkSentinel }
        return dirty ? nil : relinkSentinel
    }

    /// All folder ids, tombstones included: the validator's `knownFolderIDs`.
    func knownFolderIDs() throws -> Set<UUID> {
        Set(try makeContext().fetch(FetchDescriptor<WordFolder>()).map(\.id))
    }

    // MARK: Apply (pull)

    func applyFolders(_ rows: [ValidatedRemoteFolder], linkedAt: Date? = nil) throws -> SyncApplyResult {
        let context = makeContext()
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        var byID: [UUID: WordFolder] = [:]
        for folder in folders { byID[folder.id] = folder }
        var adoptable: [String: WordFolder] = [:]
        for folder in folders where folder.isActive && folder.effectiveWorkspaceID == WorkspaceID.legacy
            && Self.isUnsynced(folder.serverUpdatedAt) {
            let key = FolderStore.nameKey(folder.name)
            if adoptable[key] == nil { adoptable[key] = folder }
        }
        var words: [Word]?
        var result = SyncApplyResult()

        for remote in rows {
            let local = byID[remote.id]
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert:
                if let adopted = adoptable.removeValue(forKey: FolderStore.nameKey(remote.name)) {
                    let oldID = adopted.id
                    adopted.id = remote.id
                    adopted.name = remote.name
                    adopted.workspaceID = WorkspaceID.legacy
                    adopted.sortOrder = remote.sortOrder
                    adopted.deletedAt = nil
                    stamp(adopted, remote.updatedAt)
                    if words == nil { words = try context.fetch(FetchDescriptor<Word>()) }
                    rewriteMembership(from: oldID, to: remote.id, in: words ?? [])
                    byID[oldID] = nil
                    byID[remote.id] = adopted
                    result.adopted += 1
                } else {
                    let folder = WordFolder(name: remote.name)
                    folder.id = remote.id
                    folder.workspaceID = WorkspaceID.legacy
                    folder.sortOrder = remote.sortOrder
                    folder.createdAt = remote.createdAt
                    folder.deletedAt = nil
                    stamp(folder, remote.updatedAt)
                    context.insert(folder)
                    byID[remote.id] = folder
                    result.inserted += 1
                }
            case .update:
                guard let folder = local else { continue }
                folder.name = remote.name
                folder.sortOrder = remote.sortOrder
                folder.deletedAt = remote.deletedAt
                stamp(folder, remote.updatedAt)
                if remote.deletedAt != nil {
                    if words == nil { words = try context.fetch(FetchDescriptor<Word>()) }
                    stripMembership(of: remote.id, from: words ?? [])
                }
                result.updated += 1
            case .softDelete(let at):
                guard let folder = local else { continue }
                folder.deletedAt = at
                stamp(folder, remote.updatedAt)
                if words == nil { words = try context.fetch(FetchDescriptor<Word>()) }
                stripMembership(of: remote.id, from: words ?? [])
                result.softDeleted += 1
            case .acknowledge:
                if let folder = local { stamp(folder, remote.updatedAt) }
            case .keepLocal:
                break
            }
        }
        try save(context)
        result.foldersChanged = result.changedAnything
        return result
    }

    func applyWords(_ rows: [ValidatedRemoteWord], linkedAt: Date? = nil) throws -> SyncApplyResult {
        let context = makeContext()
        let words = try context.fetch(FetchDescriptor<Word>())
        var byID: [UUID: Word] = [:]
        var adoptable: [String: Word] = [:]
        for word in words {
            if let id = word.uuid { byID[id] = word }
            if word.isActive, word.effectiveWorkspaceID == WorkspaceID.legacy, Self.isUnsynced(word.serverUpdatedAt) {
                let key = word.syncPairKey
                if adoptable[key] == nil { adoptable[key] = word }
            }
        }
        Self.adoptionIndexBuilds += 1
        let stamp = now()
        var result = SyncApplyResult()

        for remote in rows {
            let local = byID[remote.id]
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert:
                if let adopted = adoptable.removeValue(forKey: Self.pairKey(remote)) {
                    let localFolders = adopted.folderIDs
                    apply(remote, to: adopted)
                    let union = remote.folderIDs + localFolders.filter { !remote.folderIDs.contains($0) }
                    adopted.uuid = remote.id
                    adopted.workspaceID = WorkspaceID.legacy
                    adopted.folderIDs = union
                    markSynced(adopted, remote.updatedAt)
                    if union.count > remote.folderIDs.count { adopted.updatedAt = stamp }
                    byID[remote.id] = adopted
                    result.adopted += 1
                } else {
                    let (russian, polish) = Self.sides(of: remote)
                    let word = Word(russian: russian, polish: polish, sourceLanguage: remote.enteredLanguage,
                                    createdAt: remote.createdAt, category: remote.category)
                    word.uuid = remote.id
                    word.workspaceID = WorkspaceID.legacy
                    apply(remote, to: word)
                    markSynced(word, remote.updatedAt)
                    context.insert(word)
                    byID[remote.id] = word
                    result.inserted += 1
                }
            case .update:
                guard let word = local else { continue }
                apply(remote, to: word)
                markSynced(word, remote.updatedAt)
                result.updated += 1
            case .softDelete(let at):
                guard let word = local else { continue }
                word.deletedAt = at
                markSynced(word, remote.updatedAt)
                result.softDeleted += 1
            case .acknowledge:
                if let word = local { markSynced(word, remote.updatedAt) }
            case .keepLocal:
                break
            }
        }
        try save(context)
        return result
    }

    private static func isUnsynced(_ serverUpdatedAt: Date?) -> Bool {
        serverUpdatedAt == nil || serverUpdatedAt == relinkSentinel
    }

    /// (russian, polish) of a validated pair: the side whose language is Russian is `russian`.
    private static func sides(of remote: ValidatedRemoteWord) -> (russian: String, polish: String) {
        remote.termLanguage == .russian ? (remote.term, remote.translation) : (remote.translation, remote.term)
    }

    private static func pairKey(_ remote: ValidatedRemoteWord) -> String {
        let (russian, polish) = sides(of: remote)
        return Word.normalizedText(polish) + "\u{1F}" + Word.normalizedText(russian)
    }

    /// Remote content onto a local word (text keeps the Word.init lowercase invariant).
    private func apply(_ remote: ValidatedRemoteWord, to word: Word) {
        let (russian, polish) = Self.sides(of: remote)
        word.translation = russian.lowercased()
        word.term = polish.lowercased()
        word.categoryRawValue = remote.category.rawValue
        word.sourceLanguageCode = remote.enteredLanguage.rawValue
        word.folderIDs = remote.folderIDs
        word.deletedAt = remote.deletedAt
        word.easeFactor = remote.easeFactor
        word.intervalDays = remote.intervalDays
        word.repetitions = remote.repetitions
        word.dueDate = remote.dueDate
        word.lastReviewGradeRawValue = remote.lastReviewGrade?.rawValue
        word.knowledgeTier = remote.knowledgeTier
        word.consecutiveSoftMisses = remote.consecutiveSoftMisses
    }

    private func markSynced(_ word: Word, _ serverTime: Date) {
        word.updatedAt = serverTime
        word.serverUpdatedAt = serverTime
    }

    private func stamp(_ folder: WordFolder, _ serverTime: Date) {
        folder.updatedAt = serverTime
        folder.serverUpdatedAt = serverTime
    }

    /// A pulled folder tombstone removes the folder from active words, like a local
    /// `FolderStore.delete`; those words become dirty and push the membership change.
    private func stripMembership(of folderID: UUID, from words: [Word]) {
        let stamp = now()
        for word in words where word.folderIDs.contains(folderID) {
            word.folderIDs.removeAll { $0 == folderID }
            // Tombstones keep their deletion-time updatedAt (as in FolderStore.delete).
            if word.isActive { word.updatedAt = stamp }
        }
    }

    /// Adoption re-keyed a folder: every membership follows, and those words become dirty.
    private func rewriteMembership(from oldID: UUID, to newID: UUID, in words: [Word]) {
        guard oldID != newID else { return }
        let stamp = now()
        for word in words where word.folderIDs.contains(oldID) {
            var seen = Set<UUID>()
            word.folderIDs = word.folderIDs.map { $0 == oldID ? newID : $0 }.filter { seen.insert($0).inserted }
            word.updatedAt = stamp
        }
    }

    // MARK: Push

    func pendingFolders(ownerID: UUID, now: Date, excluding: Set<UUID>) throws -> PendingBatch<RemoteFolderUpsert> {
        let folders = try makeContext().fetch(FetchDescriptor<WordFolder>())
            .filter { $0.isSyncDirty && !excluding.contains($0.id) && $0.effectiveWorkspaceID == WorkspaceID.legacy }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var batch = PendingBatch<RemoteFolderUpsert>()
        for folder in folders {
            let record = RemoteFolderRecord(id: folder.id, userID: ownerID, name: folder.name,
                                            sortOrder: folder.sortOrder, createdAt: folder.createdAt,
                                            updatedAt: now, deletedAt: folder.deletedAt)
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, now: now)
                batch.rows.append(PendingRow(
                    id: folder.id, snapshot: folder.lastModifiedAt,
                    payload: RemoteFolderUpsert(id: valid.id, userID: ownerID, name: valid.name,
                                                sortOrder: valid.sortOrder, createdAt: valid.createdAt,
                                                deletedAt: valid.deletedAt)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    func pendingWords(ownerID: UUID, now: Date, excluding: Set<UUID>) throws -> PendingBatch<RemoteWordUpsert> {
        let context = makeContext()
        _ = try WordIdentityBackfill.assignMissing(in: context, rollbackOnFailure: true)
        let words = try context.fetch(FetchDescriptor<Word>())
            .filter { word in
                word.effectiveWorkspaceID == WorkspaceID.legacy
                    && (word.uuid.map { word.isSyncDirty && !excluding.contains($0) } ?? false)
            }
            .sorted { ($0.createdAt, $0.uuid?.uuidString ?? "") < ($1.createdAt, $1.uuid?.uuidString ?? "") }
        let latestDue = now.addingTimeInterval(SRSEngine.maxIntervalDays * 86_400)
        var batch = PendingBatch<RemoteWordUpsert>()
        for word in words {
            guard let id = word.uuid else { continue }
            // Outgoing schedules are clamped on the wire only; the local row is untouched.
            let ease = word.easeFactor.isFinite ? word.easeFactor : 2.5
            let interval = word.intervalDays.isFinite ? word.intervalDays : 0
            let tierRange = KnowledgeProgressService.minimumTier...KnowledgeProgressService.maximumTier
            let record = RemoteWordRecord(
                id: id, userID: ownerID, term: word.term, termLanguage: AppLanguage.polish.rawValue,
                translation: word.translation, translationLanguage: AppLanguage.russian.rawValue,
                enteredLanguage: AppLanguage(rawValue: word.sourceLanguageCode)?.rawValue
                    ?? AppLanguage.polish.rawValue,
                category: word.category.stableID, folderIDs: word.folderIDs,
                createdAt: word.createdAt, updatedAt: now, deletedAt: word.deletedAt,
                easeFactor: min(SRSEngine.maxEaseFactor, max(SRSEngine.minEaseFactor, ease)),
                intervalDays: min(SRSEngine.maxIntervalDays, max(0, interval)),
                repetitions: max(0, word.repetitions),
                dueDate: min(word.dueDate, latestDue),
                lastReviewGrade: word.lastReviewGradeRawValue.flatMap { ReviewGrade(rawValue: $0)?.rawValue },
                knowledgeTier: word.knowledgeTier.flatMap { tierRange.contains($0) ? $0 : nil },
                consecutiveSoftMisses: max(0, word.consecutiveSoftMisses))
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, knownFolderIDs: [], now: now)
                batch.rows.append(PendingRow(
                    id: id, snapshot: word.lastModifiedAt,
                    payload: RemoteWordUpsert(
                        id: valid.id, userID: ownerID, term: valid.term,
                        termLanguage: valid.termLanguage.rawValue, translation: valid.translation,
                        translationLanguage: valid.translationLanguage.rawValue,
                        enteredLanguage: valid.enteredLanguage.rawValue, category: valid.category.stableID,
                        folderIDs: valid.folderIDs, createdAt: valid.createdAt, deletedAt: valid.deletedAt,
                        easeFactor: valid.easeFactor, intervalDays: valid.intervalDays,
                        repetitions: valid.repetitions, dueDate: valid.dueDate,
                        lastReviewGrade: valid.lastReviewGrade?.rawValue, knowledgeTier: valid.knowledgeTier,
                        consecutiveSoftMisses: valid.consecutiveSoftMisses)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    /// Records server acks: only rows still equal to the snapshot take the server time.
    func markPushed(_ acks: [RemoteAck], snapshots: [UUID: Date], kind: SyncKind) throws {
        guard !acks.isEmpty else { return }
        let context = makeContext()
        var changed = false
        switch kind {
        case .words:
            var byID: [UUID: Word] = [:]
            for word in try context.fetch(FetchDescriptor<Word>()) {
                if let id = word.uuid { byID[id] = word }
            }
            for ack in acks {
                guard let word = byID[ack.id], let snapshot = snapshots[ack.id],
                      word.lastModifiedAt == snapshot else { continue }
                markSynced(word, ack.updatedAt)
                changed = true
            }
        case .folders:
            var byID: [UUID: WordFolder] = [:]
            for folder in try context.fetch(FetchDescriptor<WordFolder>()) { byID[folder.id] = folder }
            for ack in acks {
                guard let folder = byID[ack.id], let snapshot = snapshots[ack.id],
                      folder.lastModifiedAt == snapshot else { continue }
                stamp(folder, ack.updatedAt)
                changed = true
            }
        }
        if changed { try save(context) }
    }

    static func reason(for error: Error) -> String {
        switch error as? RemoteRecordError {
        case .invalidID: "invalid_id"
        case .foreignOwner: "foreign_owner"
        case .invalidText: "invalid_text"
        case .invalidLanguage: "invalid_language"
        case .unsupportedLanguage: "unsupported_language"
        case .invalidCategory: "invalid_category"
        case .unsupportedCategory: "unsupported_category"
        case .tooManyFolders: "too_many_folders"
        case .invalidDate: "invalid_date"
        case .invalidSchedule: "invalid_schedule"
        case nil: "invalid_row"
        }
    }
}
