import Foundation
import SwiftData

enum SyncKind: Sendable {
    case workspaces, folders, words, memberships
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
/// partial change. Nothing here hard-deletes a word, folder or workspace.
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
        for workspace in try context.fetch(FetchDescriptor<Workspace>()) {
            workspace.serverUpdatedAt = Self.linkedState(workspace.serverUpdatedAt, dirty: workspace.isSyncDirty)
        }
        for word in try context.fetch(FetchDescriptor<Word>()) {
            word.serverUpdatedAt = Self.linkedState(word.serverUpdatedAt, dirty: word.isSyncDirty)
        }
        for folder in try context.fetch(FetchDescriptor<WordFolder>()) {
            folder.serverUpdatedAt = Self.linkedState(folder.serverUpdatedAt, dirty: folder.isSyncDirty)
        }
        for membership in try context.fetch(FetchDescriptor<FolderMembership>()) {
            membership.serverUpdatedAt = Self.linkedState(membership.serverUpdatedAt, dirty: membership.isSyncDirty)
        }
        try save(context)
    }

    private static func linkedState(_ current: Date?, dirty: Bool) -> Date? {
        guard let current else { return nil }
        if current == relinkSentinel { return relinkSentinel }
        return dirty ? nil : relinkSentinel
    }

    /// Ids of all local rows in any state, with the workspace each word/folder belongs to: the
    /// validator's known sets. Built per cycle after the preceding pull step finished.
    func knownIDs() throws -> KnownRemoteIDs {
        let context = makeContext()
        var known = KnownRemoteIDs()
        known.workspaceIDs = Set(try context.fetch(FetchDescriptor<Workspace>()).map(\.id))
        for word in try context.fetch(FetchDescriptor<Word>()) {
            if let id = word.uuid { known.words[id] = word.effectiveWorkspaceID }
        }
        for folder in try context.fetch(FetchDescriptor<WordFolder>()) {
            known.folders[folder.id] = folder.effectiveWorkspaceID
        }
        return known
    }

    // MARK: Apply (pull)

    func applyWorkspaces(_ rows: [ValidatedRemoteWorkspace], linkedAt: Date? = nil) throws -> SyncApplyResult {
        let context = makeContext()
        var byID: [UUID: Workspace] = [:]
        for workspace in try context.fetch(FetchDescriptor<Workspace>()) where byID[workspace.id] == nil {
            byID[workspace.id] = workspace
        }
        var result = SyncApplyResult()
        for remote in rows {
            let local = byID[remote.id]
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert, .insertTombstone:
                let workspace = Workspace(termLanguageCode: remote.termLanguage,
                                          translationLanguageCode: remote.translationLanguage,
                                          sortOrder: remote.sortOrder, createdAt: remote.createdAt)
                workspace.deletedAt = remote.deletedAt
                stamp(workspace, remote.updatedAt)
                context.insert(workspace)
                byID[remote.id] = workspace
                result.inserted += 1
            case .update:
                guard let workspace = local else { continue }
                workspace.sortOrder = remote.sortOrder
                workspace.deletedAt = remote.deletedAt
                stamp(workspace, remote.updatedAt)
                result.updated += 1
            case .softDelete(let at):
                guard let workspace = local else { continue }
                workspace.deletedAt = at
                stamp(workspace, remote.updatedAt)
                result.softDeleted += 1
            case .acknowledge:
                if let workspace = local { stamp(workspace, remote.updatedAt) }
            case .keepLocal:
                break
            }
        }
        try save(context)
        return result
    }

    func applyFolders(_ rows: [ValidatedRemoteFolder], linkedAt: Date? = nil) throws -> SyncApplyResult {
        let context = makeContext()
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        var byID: [UUID: WordFolder] = [:]
        for folder in folders { byID[folder.id] = folder }
        var adoptable: [String: WordFolder] = [:]
        for folder in folders where folder.isActive && Self.isUnsynced(folder.serverUpdatedAt) {
            let key = Self.folderKey(workspaceID: folder.effectiveWorkspaceID, name: folder.name)
            if adoptable[key] == nil { adoptable[key] = folder }
        }
        var memberships: [FolderMembership]?
        func loadMemberships() throws -> [FolderMembership] {
            if memberships == nil { memberships = try context.fetch(FetchDescriptor<FolderMembership>()) }
            return memberships ?? []
        }
        var result = SyncApplyResult()

        for remote in rows {
            let local = byID[remote.id]
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert:
                let key = Self.folderKey(workspaceID: remote.workspaceID, name: remote.name)
                if let adopted = adoptable.removeValue(forKey: key) {
                    let oldID = adopted.id
                    adopted.id = remote.id
                    adopted.name = remote.name
                    adopted.workspaceID = remote.workspaceID
                    adopted.sortOrder = remote.sortOrder
                    adopted.deletedAt = nil
                    stamp(adopted, remote.updatedAt)
                    rekeyMemberships(folder: oldID, to: remote.id, in: try loadMemberships(), context: context)
                    byID[oldID] = nil
                    byID[remote.id] = adopted
                    result.adopted += 1
                } else {
                    let folder = WordFolder(name: remote.name)
                    folder.id = remote.id
                    folder.workspaceID = remote.workspaceID
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
                if remote.deletedAt != nil { tombstone(folderID: remote.id, in: try loadMemberships()) }
                result.updated += 1
            case .softDelete(let at):
                guard let folder = local else { continue }
                folder.deletedAt = at
                stamp(folder, remote.updatedAt)
                tombstone(folderID: remote.id, in: try loadMemberships())
                result.softDeleted += 1
            case .acknowledge:
                if let folder = local { stamp(folder, remote.updatedAt) }
            case .insertTombstone, .keepLocal:
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
        var languages: [UUID: (term: String, translation: String)] = [:]
        for workspace in try context.fetch(FetchDescriptor<Workspace>()) {
            languages[workspace.id] = (workspace.termLanguageCode, workspace.translationLanguageCode)
        }
        var byID: [UUID: Word] = [:]
        var adoptable: [String: Word] = [:]
        for word in words {
            if let id = word.uuid { byID[id] = word }
            if word.isActive, Self.isUnsynced(word.serverUpdatedAt) {
                let key = Self.wordKey(workspaceID: word.effectiveWorkspaceID, pair: word.syncPairKey)
                if adoptable[key] == nil { adoptable[key] = word }
            }
        }
        Self.adoptionIndexBuilds += 1
        var memberships: [FolderMembership]?
        func loadMemberships() throws -> [FolderMembership] {
            if memberships == nil { memberships = try context.fetch(FetchDescriptor<FolderMembership>()) }
            return memberships ?? []
        }
        var result = SyncApplyResult()

        for remote in rows {
            let local = byID[remote.id]
            let pair = languages[remote.workspaceID] ?? (term: "pl", translation: "ru")
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert:
                let key = Self.wordKey(workspaceID: remote.workspaceID, pair: Self.pairKey(remote, pair: pair))
                if let adopted = adoptable.removeValue(forKey: key) {
                    if let oldID = adopted.uuid {
                        rekeyMemberships(word: oldID, to: remote.id, in: try loadMemberships(), context: context)
                    }
                    apply(remote, to: adopted, pair: pair)
                    adopted.uuid = remote.id
                    adopted.workspaceID = remote.workspaceID
                    markSynced(adopted, remote.updatedAt)
                    byID[remote.id] = adopted
                    result.adopted += 1
                } else {
                    let word = Word(russian: remote.translation, polish: remote.term, sourceLanguage: .polish,
                                    createdAt: remote.createdAt, category: remote.category)
                    word.uuid = remote.id
                    word.workspaceID = remote.workspaceID
                    apply(remote, to: word, pair: pair)
                    markSynced(word, remote.updatedAt)
                    context.insert(word)
                    byID[remote.id] = word
                    result.inserted += 1
                }
            case .update:
                guard let word = local else { continue }
                apply(remote, to: word, pair: pair)
                markSynced(word, remote.updatedAt)
                if remote.deletedAt != nil { tombstone(wordID: remote.id, in: try loadMemberships()) }
                result.updated += 1
            case .softDelete(let at):
                guard let word = local else { continue }
                word.deletedAt = at
                markSynced(word, remote.updatedAt)
                tombstone(wordID: remote.id, in: try loadMemberships())
                result.softDeleted += 1
            case .acknowledge:
                if let word = local { markSynced(word, remote.updatedAt) }
            case .insertTombstone, .keepLocal:
                break
            }
        }
        try save(context)
        return result
    }

    func applyMemberships(_ rows: [ValidatedRemoteMembership], linkedAt: Date? = nil) throws -> SyncApplyResult {
        let context = makeContext()
        var byID: [UUID: FolderMembership] = [:]
        for membership in try context.fetch(FetchDescriptor<FolderMembership>()) where byID[membership.id] == nil {
            byID[membership.id] = membership
        }
        var result = SyncApplyResult()
        for remote in rows {
            let local = byID[remote.id]
            switch RemoteMergePolicy.decide(local: local?.localRecordState(linkedAt: linkedAt), remote: remote) {
            case .insert:
                let membership = FolderMembership(wordID: remote.wordID, folderID: remote.folderID,
                                                  workspaceID: remote.workspaceID, createdAt: remote.createdAt)
                membership.deletedAt = nil
                stamp(membership, remote.updatedAt)
                context.insert(membership)
                byID[remote.id] = membership
                result.inserted += 1
            case .update:
                guard let membership = local else { continue }
                membership.deletedAt = remote.deletedAt
                stamp(membership, remote.updatedAt)
                result.updated += 1
            case .softDelete(let at):
                guard let membership = local else { continue }
                membership.deletedAt = at
                stamp(membership, remote.updatedAt)
                result.softDeleted += 1
            case .acknowledge:
                if let membership = local { stamp(membership, remote.updatedAt) }
            case .insertTombstone, .keepLocal:
                break
            }
        }
        try save(context)
        return result
    }

    private static func isUnsynced(_ serverUpdatedAt: Date?) -> Bool {
        serverUpdatedAt == nil || serverUpdatedAt == relinkSentinel
    }

    private static func folderKey(workspaceID: UUID, name: String) -> String {
        workspaceID.uuidString + "\u{1F}" + FolderStore.nameKey(name)
    }

    private static func wordKey(workspaceID: UUID, pair: String) -> String {
        workspaceID.uuidString + "\u{1F}" + pair
    }

    /// Normalized (polish = term, russian = translation) pair of the stored form, as `Word.syncPairKey`.
    private static func pairKey(_ remote: ValidatedRemoteWord, pair: (term: String, translation: String)) -> String {
        Word.normalizedText(LanguageCodes.storedForm(remote.term, language: pair.term)) + "\u{1F}"
            + Word.normalizedText(LanguageCodes.storedForm(remote.translation, language: pair.translation))
    }

    /// Remote content onto a local word (text keeps the per-language case rule).
    private func apply(_ remote: ValidatedRemoteWord, to word: Word, pair: (term: String, translation: String)) {
        word.term = LanguageCodes.storedForm(remote.term, language: pair.term)
        word.translation = LanguageCodes.storedForm(remote.translation, language: pair.translation)
        word.categoryRawValue = remote.category.rawValue
        word.sourceLanguageCode = remote.enteredSide == .term ? pair.term : pair.translation
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

    private func stamp(_ workspace: Workspace, _ serverTime: Date) {
        workspace.updatedAt = serverTime
        workspace.serverUpdatedAt = serverTime
    }

    private func stamp(_ membership: FolderMembership, _ serverTime: Date) {
        membership.updatedAt = serverTime
        membership.serverUpdatedAt = serverTime
    }

    /// A pulled folder tombstone tombstones the folder's active memberships, like a local
    /// `FolderStore.delete`; they become dirty and push. Words are never deleted.
    private func tombstone(folderID: UUID, in memberships: [FolderMembership]) {
        let stamp = now()
        for membership in memberships where membership.folderID == folderID && membership.isActive {
            membership.markDeleted(now: stamp)
        }
    }

    /// A pulled word tombstone tombstones the word's active memberships, mirroring folder deletion.
    private func tombstone(wordID: UUID, in memberships: [FolderMembership]) {
        let stamp = now()
        for membership in memberships where membership.wordID == wordID && membership.isActive {
            membership.markDeleted(now: stamp)
        }
    }

    /// Adoption re-keyed a folder: its memberships follow (new id, dirty).
    private func rekeyMemberships(folder oldID: UUID, to newID: UUID, in memberships: [FolderMembership],
                                  context: ModelContext) {
        guard oldID != newID else { return }
        rekey(memberships.filter { $0.folderID == oldID }, all: memberships, context: context) {
            ($0.wordID, newID)
        }
    }

    /// Adoption re-keyed a word: its memberships follow (new id, dirty).
    private func rekeyMemberships(word oldID: UUID, to newID: UUID, in memberships: [FolderMembership],
                                  context: ModelContext) {
        guard oldID != newID else { return }
        rekey(memberships.filter { $0.wordID == oldID }, all: memberships, context: context) {
            (newID, $0.folderID)
        }
    }

    private func rekey(_ moving: [FolderMembership], all memberships: [FolderMembership], context: ModelContext,
                       target: (FolderMembership) -> (wordID: UUID, folderID: UUID)) {
        let stamp = now()
        var taken = Set(memberships.map(\.id))
        for membership in moving {
            let (wordID, folderID) = target(membership)
            let newID = MembershipID.make(wordID: wordID, folderID: folderID)
            taken.remove(membership.id)
            if taken.contains(newID) {
                // The target membership already exists: the duplicate row goes (membership rows only).
                context.delete(membership)
                continue
            }
            membership.wordID = wordID
            membership.folderID = folderID
            membership.id = newID
            membership.serverUpdatedAt = nil
            membership.updatedAt = stamp
            taken.insert(newID)
        }
    }

    // MARK: Push

    func pendingWorkspaces(ownerID: UUID, now: Date, excluding: Set<UUID>) throws -> PendingBatch<RemoteWorkspaceUpsert> {
        let workspaces = try makeContext().fetch(FetchDescriptor<Workspace>())
            .filter { $0.isSyncDirty && !excluding.contains($0.id) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var batch = PendingBatch<RemoteWorkspaceUpsert>()
        for workspace in workspaces {
            let record = RemoteWorkspaceRecord(
                id: workspace.id, userID: ownerID, termLanguage: workspace.termLanguageCode,
                translationLanguage: workspace.translationLanguageCode, sortOrder: workspace.sortOrder,
                createdAt: workspace.createdAt, updatedAt: now, deletedAt: workspace.deletedAt)
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, now: now)
                batch.rows.append(PendingRow(
                    id: workspace.id, snapshot: workspace.lastModifiedAt,
                    payload: RemoteWorkspaceUpsert(
                        id: valid.id, userID: ownerID, termLanguage: valid.termLanguage,
                        translationLanguage: valid.translationLanguage, sortOrder: valid.sortOrder,
                        createdAt: valid.createdAt, deletedAt: valid.deletedAt)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    func pendingFolders(ownerID: UUID, now: Date, excluding: Set<UUID>) throws -> PendingBatch<RemoteFolderUpsert> {
        let context = makeContext()
        let known = try knownIDs()
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
            .filter { $0.isSyncDirty && !excluding.contains($0.id) }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var batch = PendingBatch<RemoteFolderUpsert>()
        for folder in folders {
            let record = RemoteFolderRecord(id: folder.id, userID: ownerID, workspaceID: folder.effectiveWorkspaceID,
                                            name: folder.name, sortOrder: folder.sortOrder,
                                            createdAt: folder.createdAt, updatedAt: now, deletedAt: folder.deletedAt)
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: now)
                batch.rows.append(PendingRow(
                    id: folder.id, snapshot: folder.lastModifiedAt,
                    payload: RemoteFolderUpsert(id: valid.id, userID: ownerID, workspaceID: valid.workspaceID,
                                                name: valid.name, sortOrder: valid.sortOrder,
                                                createdAt: valid.createdAt, deletedAt: valid.deletedAt)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    func pendingWords(ownerID: UUID, now: Date, excluding: Set<UUID>) throws -> PendingBatch<RemoteWordUpsert> {
        let context = makeContext()
        _ = try WordIdentityBackfill.assignMissing(in: context, rollbackOnFailure: true)
        let known = try knownIDs()
        var languages: [UUID: WorkspaceContext] = [:]
        for workspace in try context.fetch(FetchDescriptor<Workspace>()) {
            languages[workspace.id] = WorkspaceContext(id: workspace.id, termCode: workspace.termLanguageCode,
                                                       translationCode: workspace.translationLanguageCode)
        }
        let words = try context.fetch(FetchDescriptor<Word>())
            .filter { word in word.uuid.map { word.isSyncDirty && !excluding.contains($0) } ?? false }
            .sorted { ($0.createdAt, $0.uuid?.uuidString ?? "") < ($1.createdAt, $1.uuid?.uuidString ?? "") }
        let latestDue = now.addingTimeInterval(SRSEngine.maxIntervalDays * 86_400)
        var batch = PendingBatch<RemoteWordUpsert>()
        for word in words {
            guard let id = word.uuid else { continue }
            // Outgoing schedules are clamped on the wire only; the local row is untouched.
            let ease = word.easeFactor.isFinite ? word.easeFactor : 2.5
            let interval = word.intervalDays.isFinite ? word.intervalDays : 0
            let tierRange = KnowledgeProgressService.minimumTier...KnowledgeProgressService.maximumTier
            // An unknown side code pushes `term`.
            let side = languages[word.effectiveWorkspaceID].map { word.enteredSide(in: $0) } ?? .term
            let record = RemoteWordRecord(
                id: id, userID: ownerID, workspaceID: word.effectiveWorkspaceID, term: word.term,
                translation: word.translation, enteredSide: side.rawValue,
                category: word.category.stableID,
                createdAt: word.createdAt, updatedAt: now, deletedAt: word.deletedAt,
                easeFactor: min(SRSEngine.maxEaseFactor, max(SRSEngine.minEaseFactor, ease)),
                intervalDays: min(SRSEngine.maxIntervalDays, max(0, interval)),
                repetitions: max(0, word.repetitions),
                dueDate: min(word.dueDate, latestDue),
                lastReviewGrade: word.lastReviewGradeRawValue.flatMap { ReviewGrade(rawValue: $0)?.rawValue },
                knowledgeTier: word.knowledgeTier.flatMap { tierRange.contains($0) ? $0 : nil },
                consecutiveSoftMisses: max(0, word.consecutiveSoftMisses))
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: now)
                batch.rows.append(PendingRow(
                    id: id, snapshot: word.lastModifiedAt,
                    payload: RemoteWordUpsert(
                        id: valid.id, userID: ownerID, workspaceID: valid.workspaceID, term: valid.term,
                        translation: valid.translation, enteredSide: valid.enteredSide.rawValue,
                        category: valid.category.stableID, createdAt: valid.createdAt,
                        deletedAt: valid.deletedAt, easeFactor: valid.easeFactor,
                        intervalDays: valid.intervalDays, repetitions: valid.repetitions, dueDate: valid.dueDate,
                        lastReviewGrade: valid.lastReviewGrade?.rawValue, knowledgeTier: valid.knowledgeTier,
                        consecutiveSoftMisses: valid.consecutiveSoftMisses)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    /// Dirty memberships. A membership whose word or folder is held, rejected this session or not
    /// yet synced stays dirty and is not sent (the server's foreign key would reject it).
    func pendingMemberships(ownerID: UUID, now: Date, excluding: Set<UUID>,
                            rejected: Set<UUID> = []) throws -> PendingBatch<RemoteMembershipUpsert> {
        let context = makeContext()
        let known = try knownIDs()
        var syncedWords = Set<UUID>()
        for word in try context.fetch(FetchDescriptor<Word>()) {
            if let id = word.uuid, !Self.isUnsynced(word.serverUpdatedAt) { syncedWords.insert(id) }
        }
        var syncedFolders = Set<UUID>()
        for folder in try context.fetch(FetchDescriptor<WordFolder>()) where !Self.isUnsynced(folder.serverUpdatedAt) {
            syncedFolders.insert(folder.id)
        }
        let blocked = excluding.union(rejected)
        let memberships = try context.fetch(FetchDescriptor<FolderMembership>())
            .filter { membership in
                membership.isSyncDirty && !blocked.contains(membership.wordID) && !blocked.contains(membership.folderID)
                    && !blocked.contains(membership.id)
                    && syncedWords.contains(membership.wordID) && syncedFolders.contains(membership.folderID)
            }
            .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var batch = PendingBatch<RemoteMembershipUpsert>()
        for membership in memberships {
            let record = RemoteMembershipRecord(userID: ownerID, workspaceID: membership.workspaceID,
                                                wordID: membership.wordID, folderID: membership.folderID,
                                                createdAt: membership.createdAt, updatedAt: now,
                                                deletedAt: membership.deletedAt)
            do {
                let valid = try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: now)
                batch.rows.append(PendingRow(
                    id: membership.id, snapshot: membership.lastModifiedAt,
                    payload: RemoteMembershipUpsert(userID: ownerID, workspaceID: valid.workspaceID,
                                                    wordID: valid.wordID, folderID: valid.folderID,
                                                    createdAt: valid.createdAt, deletedAt: valid.deletedAt)))
            } catch {
                batch.invalid[Self.reason(for: error), default: 0] += 1
            }
        }
        return batch
    }

    /// Records server acks: only rows still equal to the snapshot take the server time.
    /// Memberships are keyed by `MembershipID`.
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
        case .workspaces:
            var byID: [UUID: Workspace] = [:]
            for workspace in try context.fetch(FetchDescriptor<Workspace>()) { byID[workspace.id] = workspace }
            for ack in acks {
                guard let workspace = byID[ack.id], let snapshot = snapshots[ack.id],
                      workspace.lastModifiedAt == snapshot else { continue }
                stamp(workspace, ack.updatedAt)
                changed = true
            }
        case .memberships:
            var byID: [UUID: FolderMembership] = [:]
            for membership in try context.fetch(FetchDescriptor<FolderMembership>()) { byID[membership.id] = membership }
            for ack in acks {
                guard let membership = byID[ack.id], let snapshot = snapshots[ack.id],
                      membership.lastModifiedAt == snapshot else { continue }
                stamp(membership, ack.updatedAt)
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
        case .unknownWorkspace: "unknown_workspace"
        case .invalidSide: "invalid_side"
        case .unknownReference: "unknown_reference"
        case .invalidDate: "invalid_date"
        case .invalidSchedule: "invalid_schedule"
        case nil: "invalid_row"
        }
    }
}
