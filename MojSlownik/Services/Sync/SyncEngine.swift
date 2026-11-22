import Foundation

enum SyncEngineError: Error, Equatable {
    /// `run` was asked to sync an account the local data is not linked to.
    case notLinked
    /// The server returned a row of another account: the whole response is untrustworthy.
    case untrustedResponse
}

struct SyncReport: Equatable, Sendable {
    /// Rows a pull inserted, updated, soft-deleted or adopted.
    var pulled = 0
    /// Rows the server acknowledged.
    var pushed = 0
    /// Skipped rows per reason name (no ids, no text).
    var skipped: [String: Int] = [:]
    var workspacesChanged = false
    var foldersChanged = false
    var membershipsChanged = false
    var vocabularyChanged = false
}

/// One sync cycle: pull workspaces, folders, words and memberships (the foreign-key order), then
/// push them in the same order (plan S5-S9, S14). Foundation and SwiftData only; the transport is `SyncRemote`. No logging
/// and no UI: `SyncStore` owns triggers, status and logs.
@MainActor
final class SyncEngine {
    static let pageSize = 500
    static let pushBatchSize = 200
    /// Bump when this build can read rows an older build skipped: cursors and held ids reset.
    static let capabilityVersion = 2
    static let overlapMillis: Int64 = 60_000

    struct RowVersion: Hashable {
        let id: UUID
        let modifiedAt: Date
    }

    private let remote: any SyncRemote
    private let local: SwiftDataSyncStore
    private let state: any SyncStateRepository
    private let now: () -> Date

    /// Rows the server permanently rejected this session; not retried until edited or relaunch.
    private(set) var rejected: Set<RowVersion> = []
    /// Called once per cycle, right before the first pulled rows are applied to SwiftData.
    /// `SyncStore` uses it to silence achievement banners for unlocks caused by pulled words.
    var willApplyPulledRows: (() -> Void)?
    /// Called once per cycle, after the workspace pull finished (the phase-4 gate input).
    var onWorkspacesPulled: (() -> Void)?
    private var announcedPull = false

    init(remote: any SyncRemote, local: SwiftDataSyncStore, state: any SyncStateRepository,
         now: @escaping () -> Date = { .now }) {
        self.remote = remote
        self.local = local
        self.state = state
        self.now = now
    }

    var linkedAccountID: UUID? { state.load().linkedAccountID }

    /// Links local data to `accountID`: per-row state is reset and the cursors are cleared.
    func link(to accountID: UUID) throws {
        try local.prepareLink()
        try state.save(SyncState(linkedAccountID: accountID, capabilityVersion: Self.capabilityVersion,
                                 linkedAt: now()))
    }

    func run(ownerID: UUID) async throws -> SyncReport {
        var current = state.load()
        guard current.linkedAccountID == ownerID else { throw SyncEngineError.notLinked }
        announcedPull = false
        // The link this cycle started under: a cycle that outlives its link (sign-out, another
        // account, a re-link) must never write over the newer one.
        let link = current
        if current.capabilityVersion < Self.capabilityVersion {
            current.capabilityVersion = Self.capabilityVersion
            current.workspacesCursor = nil
            current.foldersCursor = nil
            current.wordsCursor = nil
            current.membershipsCursor = nil
            current.heldIDs = []
            try persist(current, startedUnder: link)
        }
        var report = SyncReport()
        try await pullWorkspaces(ownerID: ownerID, state: &current, link: link, report: &report)
        onWorkspacesPulled?()
        try await pullFolders(ownerID: ownerID, state: &current, link: link, report: &report)
        try await pullWords(ownerID: ownerID, state: &current, link: link, report: &report)
        try await pullMemberships(ownerID: ownerID, state: &current, link: link, report: &report)
        try await pushWorkspaces(ownerID: ownerID, state: current, report: &report)
        try await pushFolders(ownerID: ownerID, state: current, report: &report)
        try await pushWords(ownerID: ownerID, state: current, report: &report)
        try await pushMemberships(ownerID: ownerID, state: current, report: &report)
        current.lastSyncedAt = now()
        try persist(current, startedUnder: link)
        return report
    }

    /// Saves only what the cycle owns (capability, cursors, held ids, last sync time) onto the
    /// freshly loaded state, and refuses (as a cancellation) if the link changed meanwhile.
    private func persist(_ owned: SyncState, startedUnder link: SyncState) throws {
        try Task.checkCancellation()
        var fresh = state.load()
        guard fresh.linkedAccountID == link.linkedAccountID, fresh.linkedAt == link.linkedAt else {
            throw CancellationError()
        }
        fresh.capabilityVersion = owned.capabilityVersion
        fresh.workspacesCursor = owned.workspacesCursor
        fresh.foldersCursor = owned.foldersCursor
        fresh.wordsCursor = owned.wordsCursor
        fresh.membershipsCursor = owned.membershipsCursor
        fresh.lastSyncedAt = owned.lastSyncedAt
        fresh.heldIDs = owned.heldIDs
        try state.save(fresh)
    }

    private func announcePullOnce() {
        guard !announcedPull else { return }
        announcedPull = true
        willApplyPulledRows?()
    }

    // MARK: Pull

    private func pullWorkspaces(ownerID: UUID, state current: inout SyncState, link: SyncState,
                                report: inout SyncReport) async throws {
        var fetchFrom = current.workspacesCursor?.overlapping(by: Self.overlapMillis)
        while true {
            let page = try await remote.fetchWorkspaces(ownerID: ownerID, after: fetchFrom, limit: Self.pageSize)
            try Task.checkCancellation()
            let at = now()
            var valid: [ValidatedRemoteWorkspace] = []
            var skippedIDs: [UUID] = []
            for record in page {
                do {
                    valid.append(try RemoteRecordValidator.validate(record, ownerID: ownerID, now: at))
                } catch RemoteRecordError.foreignOwner {
                    throw SyncEngineError.untrustedResponse
                } catch {
                    report.skipped[SwiftDataSyncStore.reason(for: error), default: 0] += 1
                    skippedIDs.append(record.id)
                }
            }
            if !valid.isEmpty { announcePullOnce() }
            let result = try local.applyWorkspaces(valid, linkedAt: current.linkedAt)
            report.pulled += result.inserted + result.updated + result.softDeleted + result.adopted
            if result.changedAnything {
                report.workspacesChanged = true
                report.vocabularyChanged = true
            }
            hold(skippedIDs, applied: valid.map(\.id), in: &current)
            if let last = page.last {
                let cursor = SyncCursor(updatedAt: last.updatedAt, id: last.id)
                fetchFrom = cursor
                current.workspacesCursor = Self.later(current.workspacesCursor, cursor)
            }
            try persist(current, startedUnder: link)
            guard page.count >= Self.pageSize else { return }
            try Task.checkCancellation()
        }
    }

    private func pullFolders(ownerID: UUID, state current: inout SyncState, link: SyncState,
                             report: inout SyncReport) async throws {
        var fetchFrom = current.foldersCursor?.overlapping(by: Self.overlapMillis)
        let known = try local.knownIDs()
        while true {
            let page = try await remote.fetchFolders(ownerID: ownerID, after: fetchFrom, limit: Self.pageSize)
            try Task.checkCancellation()
            let at = now()
            var valid: [ValidatedRemoteFolder] = []
            var skippedIDs: [UUID] = []
            for record in page {
                do {
                    valid.append(try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: at))
                } catch RemoteRecordError.foreignOwner {
                    throw SyncEngineError.untrustedResponse
                } catch {
                    report.skipped[SwiftDataSyncStore.reason(for: error), default: 0] += 1
                    skippedIDs.append(record.id)
                }
            }
            if !valid.isEmpty { announcePullOnce() }
            let result = try local.applyFolders(valid, linkedAt: current.linkedAt)
            report.pulled += result.inserted + result.updated + result.softDeleted + result.adopted
            if result.foldersChanged {
                report.foldersChanged = true
                report.vocabularyChanged = true
            }
            hold(skippedIDs, applied: valid.map(\.id), in: &current)
            if let last = page.last {
                let cursor = SyncCursor(updatedAt: last.updatedAt, id: last.id)
                fetchFrom = cursor
                current.foldersCursor = Self.later(current.foldersCursor, cursor)
            }
            try persist(current, startedUnder: link)
            guard page.count >= Self.pageSize else { return }
            try Task.checkCancellation()
        }
    }

    private func pullWords(ownerID: UUID, state current: inout SyncState, link: SyncState,
                           report: inout SyncReport) async throws {
        var fetchFrom = current.wordsCursor?.overlapping(by: Self.overlapMillis)
        let known = try local.knownIDs()
        while true {
            let page = try await remote.fetchWords(ownerID: ownerID, after: fetchFrom, limit: Self.pageSize)
            try Task.checkCancellation()
            let at = now()
            var valid: [ValidatedRemoteWord] = []
            var skippedIDs: [UUID] = []
            for record in page {
                do {
                    valid.append(try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: at))
                } catch RemoteRecordError.foreignOwner {
                    throw SyncEngineError.untrustedResponse
                } catch {
                    report.skipped[SwiftDataSyncStore.reason(for: error), default: 0] += 1
                    skippedIDs.append(record.id)
                }
            }
            if !valid.isEmpty { announcePullOnce() }
            let result = try local.applyWords(valid, linkedAt: current.linkedAt)
            report.pulled += result.inserted + result.updated + result.softDeleted + result.adopted
            if result.changedAnything { report.vocabularyChanged = true }
            hold(skippedIDs, applied: valid.map(\.id), in: &current)
            if let last = page.last {
                let cursor = SyncCursor(updatedAt: last.updatedAt, id: last.id)
                fetchFrom = cursor
                current.wordsCursor = Self.later(current.wordsCursor, cursor)
            }
            try persist(current, startedUnder: link)
            guard page.count >= Self.pageSize else { return }
            try Task.checkCancellation()
        }
    }

    /// Memberships have no id: the cursor is `(updated_at, word_id, folder_id)`. A tombstone whose
    /// word or folder is unknown is skipped without holding (nothing to apply; it can never fill
    /// `heldIDs`); an active one is held by its `MembershipID`.
    private func pullMemberships(ownerID: UUID, state current: inout SyncState, link: SyncState,
                                 report: inout SyncReport) async throws {
        var fetchFrom = current.membershipsCursor?.overlapping(by: Self.overlapMillis)
        let known = try local.knownIDs()
        while true {
            let page = try await remote.fetchMemberships(ownerID: ownerID, after: fetchFrom, limit: Self.pageSize)
            try Task.checkCancellation()
            let at = now()
            var valid: [ValidatedRemoteMembership] = []
            var held: [UUID] = []
            for record in page {
                do {
                    valid.append(try RemoteRecordValidator.validate(record, ownerID: ownerID, known: known, now: at))
                } catch RemoteRecordError.foreignOwner {
                    throw SyncEngineError.untrustedResponse
                } catch {
                    if record.deletedAt != nil, error as? RemoteRecordError == .unknownReference {
                        report.skipped["orphan_tombstone", default: 0] += 1
                    } else {
                        report.skipped[SwiftDataSyncStore.reason(for: error), default: 0] += 1
                        held.append(MembershipID.make(wordID: record.wordID, folderID: record.folderID))
                    }
                }
            }
            if !valid.isEmpty { announcePullOnce() }
            let result = try local.applyMemberships(valid, linkedAt: current.linkedAt)
            report.pulled += result.inserted + result.updated + result.softDeleted + result.adopted
            if result.changedAnything {
                report.membershipsChanged = true
                report.vocabularyChanged = true
            }
            hold(held, applied: valid.map(\.id), in: &current)
            if let last = page.last {
                let cursor = SyncCursor(updatedAt: last.updatedAt, id: last.wordID, secondaryID: last.folderID)
                fetchFrom = cursor
                current.membershipsCursor = Self.later(current.membershipsCursor, cursor)
            }
            try persist(current, startedUnder: link)
            guard page.count >= Self.pageSize else { return }
            try Task.checkCancellation()
        }
    }

    /// Keyset order: `updated_at`, then `id`, then `secondaryID` (uuid text order equals Postgres' byte order).
    static func later(_ old: SyncCursor?, _ new: SyncCursor) -> SyncCursor {
        guard let old else { return new }
        if new.updatedAtMillis != old.updatedAtMillis {
            return new.updatedAtMillis > old.updatedAtMillis ? new : old
        }
        if new.id != old.id { return new.id.uuidString > old.id.uuidString ? new : old }
        // Equal millis and id: memberships fall through to the folder id (nil < any).
        guard let newSecondary = new.secondaryID else { return old }
        guard let oldSecondary = old.secondaryID else { return new }
        return newSecondary.uuidString > oldSecondary.uuidString ? new : old
    }

    private func hold(_ skipped: [UUID], applied: [UUID], in current: inout SyncState) {
        current.heldIDs.subtract(applied)
        for id in skipped where current.heldIDs.count < SyncState.maxHeldIDs {
            current.heldIDs.insert(id)
        }
    }

    // MARK: Push

    private func pushWorkspaces(ownerID: UUID, state current: SyncState, report: inout SyncReport) async throws {
        let batch = try local.pendingWorkspaces(ownerID: ownerID, now: now(), excluding: current.heldIDs)
        for (reason, count) in batch.invalid { report.skipped[reason, default: 0] += count }
        try await push(batch.rows, kind: .workspaces, report: &report) { [remote] rows in
            try await remote.upsertWorkspaces(rows)
        }
    }

    private func pushFolders(ownerID: UUID, state current: SyncState, report: inout SyncReport) async throws {
        let batch = try local.pendingFolders(ownerID: ownerID, now: now(), excluding: current.heldIDs)
        for (reason, count) in batch.invalid { report.skipped[reason, default: 0] += count }
        try await push(batch.rows, kind: .folders, report: &report) { [remote] rows in
            try await remote.upsertFolders(rows)
        }
    }

    private func pushWords(ownerID: UUID, state current: SyncState, report: inout SyncReport) async throws {
        let batch = try local.pendingWords(ownerID: ownerID, now: now(), excluding: current.heldIDs)
        for (reason, count) in batch.invalid { report.skipped[reason, default: 0] += count }
        try await push(batch.rows, kind: .words, report: &report) { [remote] rows in
            try await remote.upsertWords(rows)
        }
    }

    private func pushMemberships(ownerID: UUID, state current: SyncState, report: inout SyncReport) async throws {
        let batch = try local.pendingMemberships(ownerID: ownerID, now: now(), excluding: current.heldIDs,
                                                 rejected: Set(rejected.map(\.id)))
        for (reason, count) in batch.invalid { report.skipped[reason, default: 0] += count }
        try await push(batch.rows, kind: .memberships, report: &report) { [remote] rows in
            try await remote.upsertMemberships(rows).map {
                RemoteAck(id: MembershipID.make(wordID: $0.wordID, folderID: $0.folderID), updatedAt: $0.updatedAt)
            }
        }
    }

    private func push<Payload: Sendable>(_ pending: [PendingRow<Payload>], kind: SyncKind, report: inout SyncReport,
                                         send: ([Payload]) async throws -> [RemoteAck]) async throws {
        var rows: [PendingRow<Payload>] = []
        for row in pending {
            if rejected.contains(RowVersion(id: row.id, modifiedAt: row.snapshot)) {
                report.skipped["server_rejected", default: 0] += 1
            } else {
                rows.append(row)
            }
        }
        var start = 0
        while start < rows.count {
            try Task.checkCancellation()
            let chunk = Array(rows[start..<min(start + Self.pushBatchSize, rows.count)])
            start += chunk.count
            var acks: [RemoteAck] = []
            do {
                acks = try await send(chunk.map(\.payload))
            } catch SyncRemoteError.rejected {
                // One bad row must not block the others: retry row by row.
                for row in chunk {
                    if chunk.count > 1 {
                        do {
                            acks += try await send([row.payload])
                            continue
                        } catch SyncRemoteError.rejected {}
                    }
                    rejected.insert(RowVersion(id: row.id, modifiedAt: row.snapshot))
                    report.skipped["server_rejected", default: 0] += 1
                }
            }
            var snapshots: [UUID: Date] = [:]
            for row in chunk { snapshots[row.id] = row.snapshot }
            try local.markPushed(acks, snapshots: snapshots, kind: kind)
            report.pushed += acks.count
        }
    }
}
