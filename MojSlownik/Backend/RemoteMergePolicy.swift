import Foundation

/// What a validated server row may do to the local store. There is deliberately no hard-delete
/// case: the server can at most soft-delete (tombstone) a local row, so stored words are never
/// lost because of a server response. A row missing from a server response means nothing.
enum RemoteMergeDecision: Equatable, Sendable {
    case insert
    case update
    case softDelete(at: Date)
    case keepLocal
}

/// The local row's sync-relevant state (from Word/WordFolder `lastModifiedAt` and `isActive`).
struct LocalRecordState: Equatable, Sendable {
    let lastModifiedAt: Date
    let isDeleted: Bool
}

/// Last-write-wins by `updatedAt`; ties keep the local row. Pure, so it is fully unit-testable.
enum RemoteMergePolicy {
    static func decide(local: LocalRecordState?, remoteUpdatedAt: Date, remoteDeletedAt: Date?) -> RemoteMergeDecision {
        guard let local else {
            // Never materialize a row only to tombstone it.
            return remoteDeletedAt == nil ? .insert : .keepLocal
        }
        guard remoteUpdatedAt > local.lastModifiedAt else { return .keepLocal }
        if let remoteDeletedAt {
            return local.isDeleted ? .keepLocal : .softDelete(at: remoteDeletedAt)
        }
        return .update
    }

    static func decide(local: LocalRecordState?, remote: ValidatedRemoteWord) -> RemoteMergeDecision {
        decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }

    static func decide(local: LocalRecordState?, remote: ValidatedRemoteFolder) -> RemoteMergeDecision {
        decide(local: local, remoteUpdatedAt: remote.updatedAt, remoteDeletedAt: remote.deletedAt)
    }
}

extension Word {
    var localRecordState: LocalRecordState { LocalRecordState(lastModifiedAt: lastModifiedAt, isDeleted: !isActive) }
}

extension WordFolder {
    var localRecordState: LocalRecordState { LocalRecordState(lastModifiedAt: lastModifiedAt, isDeleted: !isActive) }
}
