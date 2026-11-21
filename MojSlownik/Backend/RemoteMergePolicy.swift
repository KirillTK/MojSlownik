import Foundation

/// What a validated server row may do to the local store. There is deliberately no hard-delete
/// case: the server can at most soft-delete (tombstone) a local row, so stored words are never
/// lost because of a server response. A row missing from a server response means nothing.
enum RemoteMergeDecision: Equatable, Sendable {
    case insert
    case update
    case softDelete(at: Date)
    case keepLocal
    /// Workspaces only: no local row and a remote tombstone. The tombstone is stored (clean).
    case insertTombstone(at: Date)
    /// The local row already holds the server's state; only the sync timestamps are recorded.
    case acknowledge
}

/// The local row's sync-relevant state (from Word/WordFolder `serverUpdatedAt`, `isSyncDirty`
/// and `isActive`).
struct LocalRecordState: Equatable, Sendable {
    /// Server `updated_at` of the last synced version; nil = never synced to the linked
    /// account; `Date.distantPast` = re-link sentinel (the server wins).
    let serverUpdatedAt: Date?
    let isDirty: Bool
    let isDeleted: Bool
    /// A sentinel row the user changed after the link was made (this device's clock against
    /// this device's own `updatedAt`). It is a real local edit, not a stale copy.
    var editedSinceLink = false
}

/// Server-time last-write-wins (plan S5). Compares only server timestamps with each other, or
/// local equality (dirty); never the device clock. Pure, so it is fully unit-testable.
enum RemoteMergePolicy {
    static let relinkSentinel = Date.distantPast

    static func decide(local: LocalRecordState?, remoteUpdatedAt: Date, remoteDeletedAt: Date?) -> RemoteMergeDecision {
        // 1. No local row. Never materialize a row only to tombstone it.
        guard let local else {
            return remoteDeletedAt == nil ? .insert : .keepLocal
        }
        // 2. Re-link sentinel: the account's version wins, unless the row was edited after the
        // link (then it is an ordinary dirty edit: branch 5, last device to sync wins).
        if local.serverUpdatedAt == relinkSentinel, !local.editedSinceLink {
            return serverWins(local: local, remoteDeletedAt: remoteDeletedAt)
        }
        // 3. Echo or stale row: both values are server time.
        if let synced = local.serverUpdatedAt, remoteUpdatedAt <= synced { return .keepLocal }
        // 4. Local row not changed since the last sync.
        if !local.isDirty {
            return serverWins(local: local, remoteDeletedAt: remoteDeletedAt)
        }
        // 5. True concurrent change: delete wins, otherwise the next push overwrites the server.
        if let remoteDeletedAt, !local.isDeleted { return .softDelete(at: remoteDeletedAt) }
        return .keepLocal
    }

    static func isEditedSinceLink(serverUpdatedAt: Date?, modifiedAt: Date, linkedAt: Date?) -> Bool {
        guard serverUpdatedAt == relinkSentinel, let linkedAt else { return false }
        return modifiedAt > linkedAt
    }

    private static func serverWins(local: LocalRecordState, remoteDeletedAt: Date?) -> RemoteMergeDecision {
        if let remoteDeletedAt {
            return local.isDeleted ? .acknowledge : .softDelete(at: remoteDeletedAt)
        }
        return .update
    }

    static func decide(local: LocalRecordState?, remote: ValidatedRemoteWord) -> RemoteMergeDecision {
        decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }

    static func decide(local: LocalRecordState?, remote: ValidatedRemoteFolder) -> RemoteMergeDecision {
        decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }

    static func decide(local: LocalRecordState?, remote: ValidatedRemoteMembership) -> RemoteMergeDecision {
        decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }

    /// Documented exception to rule 1, for workspaces only: a remote tombstone with no local row
    /// is materialized. The row holds only language codes and order (no user text), and without it
    /// every word and folder of a workspace deleted on another device would be held forever on a
    /// newly linked device, so re-adding the pair could never bring them back.
    static func decide(local: LocalRecordState?, remote: ValidatedRemoteWorkspace) -> RemoteMergeDecision {
        if local == nil, let deletedAt = remote.deletedAt { return .insertTombstone(at: deletedAt) }
        return decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }
}

extension Word {
    var localRecordState: LocalRecordState { localRecordState(linkedAt: nil) }

    /// `linkedAt`: when the current account link was made (device clock); nil = unknown.
    func localRecordState(linkedAt: Date?) -> LocalRecordState {
        LocalRecordState(serverUpdatedAt: serverUpdatedAt, isDirty: isSyncDirty, isDeleted: !isActive,
                         editedSinceLink: RemoteMergePolicy.isEditedSinceLink(
                             serverUpdatedAt: serverUpdatedAt, modifiedAt: lastModifiedAt, linkedAt: linkedAt))
    }
}

extension Workspace {
    func localRecordState(linkedAt: Date?) -> LocalRecordState {
        LocalRecordState(serverUpdatedAt: serverUpdatedAt, isDirty: isSyncDirty, isDeleted: !isActive,
                         editedSinceLink: RemoteMergePolicy.isEditedSinceLink(
                             serverUpdatedAt: serverUpdatedAt, modifiedAt: lastModifiedAt, linkedAt: linkedAt))
    }
}

extension FolderMembership {
    func localRecordState(linkedAt: Date?) -> LocalRecordState {
        LocalRecordState(serverUpdatedAt: serverUpdatedAt, isDirty: isSyncDirty, isDeleted: !isActive,
                         editedSinceLink: RemoteMergePolicy.isEditedSinceLink(
                             serverUpdatedAt: serverUpdatedAt, modifiedAt: lastModifiedAt, linkedAt: linkedAt))
    }
}

extension WordFolder {
    var localRecordState: LocalRecordState { localRecordState(linkedAt: nil) }

    func localRecordState(linkedAt: Date?) -> LocalRecordState {
        LocalRecordState(serverUpdatedAt: serverUpdatedAt, isDirty: isSyncDirty, isDeleted: !isActive,
                         editedSinceLink: RemoteMergePolicy.isEditedSinceLink(
                             serverUpdatedAt: serverUpdatedAt, modifiedAt: lastModifiedAt, linkedAt: linkedAt))
    }
}
