import Foundation

/// Keyset position of a table pull: the last applied `(updated_at, id)`. Milliseconds are
/// integers so equality with the server's ms-precision `updated_at` is exact. Memberships have no
/// id: `id` = word_id and `secondaryID` = folder_id.
struct SyncCursor: Codable, Equatable, Sendable {
    let updatedAtMillis: Int64
    let id: UUID
    let secondaryID: UUID?

    private static let nilUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    init(updatedAtMillis: Int64, id: UUID, secondaryID: UUID? = nil) {
        self.updatedAtMillis = updatedAtMillis
        self.id = id
        self.secondaryID = secondaryID
    }

    init(updatedAt: Date, id: UUID, secondaryID: UUID? = nil) {
        self.init(updatedAtMillis: Int64((updatedAt.timeIntervalSince1970 * 1000).rounded()), id: id,
                  secondaryID: secondaryID)
    }

    /// The start of the next pull: `millis` earlier, with the nil UUID so no tied row is skipped.
    /// The overlap covers transactions that committed out of `clock_timestamp()` order.
    func overlapping(by millis: Int64 = 60_000) -> SyncCursor {
        SyncCursor(updatedAtMillis: updatedAtMillis - millis, id: Self.nilUUID,
                   secondaryID: secondaryID == nil ? nil : Self.nilUUID)
    }

    /// UTC `yyyy-MM-ddTHH:mm:ss.SSSZ` from integer arithmetic (never a DateFormatter), so a
    /// PostgREST filter built from it is exact.
    var timestampString: String {
        var seconds = updatedAtMillis / 1000
        var millis = updatedAtMillis % 1000
        if millis < 0 {
            millis += 1000
            seconds -= 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                            from: Date(timeIntervalSince1970: TimeInterval(seconds)))
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", parts.year!, parts.month!, parts.day!,
                      parts.hour!, parts.minute!, parts.second!, Int(millis))
    }
}

/// `id` and server-assigned `updated_at` returned for an upserted row.
struct RemoteAck: Decodable, Equatable, Sendable {
    let id: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case updatedAt = "updated_at"
    }
}

/// `word_id`, `folder_id` and server-assigned `updated_at` returned for an upserted membership.
struct RemoteMembershipAck: Decodable, Equatable, Sendable {
    let wordID: UUID
    let folderID: UUID
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case wordID = "word_id"
        case folderID = "folder_id"
        case updatedAt = "updated_at"
    }
}

/// Errors a transport maps for the engine. Any other error is transient (retry later).
enum SyncRemoteError: Error, Equatable {
    /// The server permanently rejects this request's rows (SQLSTATE 22/23, HTTP 413).
    case rejected
    /// The session is missing or not allowed to write these rows.
    case unauthorized
}

/// Network transport of the sync engine. Foundation only, so the engine is tested with a fake.
@MainActor
protocol SyncRemote: AnyObject {
    func fetchWorkspaces(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWorkspaceRecord]
    func fetchFolders(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteFolderRecord]
    func fetchWords(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWordRecord]
    func fetchMemberships(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteMembershipRecord]
    func upsertWorkspaces(_ rows: [RemoteWorkspaceUpsert]) async throws -> [RemoteAck]
    func upsertFolders(_ rows: [RemoteFolderUpsert]) async throws -> [RemoteAck]
    func upsertWords(_ rows: [RemoteWordUpsert]) async throws -> [RemoteAck]
    func upsertMemberships(_ rows: [RemoteMembershipUpsert]) async throws -> [RemoteMembershipAck]
    /// Insert-only: rows already on the server (same `user_id, id`) are ignored.
    func insertReviewLogs(_ rows: [RemoteReviewLogInsert]) async throws
}
