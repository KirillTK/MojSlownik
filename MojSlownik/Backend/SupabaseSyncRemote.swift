import Foundation
import Supabase

/// `SyncRemote` over supabase-swift (PostgREST). The client is created lazily by the provider,
/// so constructing this performs no I/O. No SDK logger and no `print`: row content must never
/// reach a log.
@MainActor
final class SupabaseSyncRemote: SyncRemote {
    static let workspacesTable = "workspaces"
    static let membershipsTable = "word_folders"
    static let wordsTable = "words"
    static let foldersTable = "folders"
    static let reviewLogsTable = "review_logs"

    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider) {
        self.provider = provider
    }

    func fetchWorkspaces(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWorkspaceRecord] {
        let data = try await fetch(table: Self.workspacesTable, columns: RemoteWorkspaceUpsert.selectColumns,
                                   ownerID: ownerID, after: cursor, limit: limit)
        return try RemoteRecordDecoder.workspaces(from: data)
    }

    func fetchMemberships(ownerID: UUID, after cursor: SyncCursor?,
                          limit: Int) async throws -> [RemoteMembershipRecord] {
        do {
            var query = provider.client.from(Self.membershipsTable).select(RemoteMembershipUpsert.selectColumns)
                .eq("user_id", value: ownerID)
            if let cursor {
                query = query.gte("updated_at", value: cursor.timestampString)
                    .or(Self.membershipKeysetFilter(after: cursor))
            }
            let data = try await query.order("updated_at").order("word_id").order("folder_id")
                .limit(limit).execute().data
            return try RemoteRecordDecoder.memberships(from: data)
        } catch {
            throw Self.classify(error)
        }
    }

    func upsertWorkspaces(_ rows: [RemoteWorkspaceUpsert]) async throws -> [RemoteAck] {
        try await upsert(rows, table: Self.workspacesTable)
    }

    func upsertMemberships(_ rows: [RemoteMembershipUpsert]) async throws -> [RemoteMembershipAck] {
        guard !rows.isEmpty else { return [] }
        do {
            let response: PostgrestResponse<[RemoteMembershipAck]> = try await provider.client
                .from(Self.membershipsTable)
                .upsert(rows, onConflict: "user_id,word_id,folder_id", returning: .representation)
                .select("word_id,folder_id,updated_at")
                .execute()
            return response.value
        } catch {
            throw Self.classify(error)
        }
    }

    /// `INSERT ... ON CONFLICT (user_id, id) DO NOTHING`: a retried batch is idempotent.
    func insertReviewLogs(_ rows: [RemoteReviewLogInsert]) async throws {
        guard !rows.isEmpty else { return }
        do {
            try await provider.client.from(Self.reviewLogsTable)
                .upsert(rows, onConflict: "user_id,id", returning: .minimal, ignoreDuplicates: true)
                .execute()
        } catch {
            throw Self.classify(error)
        }
    }

    func fetchFolders(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteFolderRecord] {
        let data = try await fetch(table: Self.foldersTable, columns: RemoteFolderUpsert.selectColumns,
                                   ownerID: ownerID, after: cursor, limit: limit)
        return try RemoteRecordDecoder.folders(from: data)
    }

    func fetchWords(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWordRecord] {
        let data = try await fetch(table: Self.wordsTable, columns: RemoteWordUpsert.selectColumns,
                                   ownerID: ownerID, after: cursor, limit: limit)
        return try RemoteRecordDecoder.words(from: data)
    }

    func upsertFolders(_ rows: [RemoteFolderUpsert]) async throws -> [RemoteAck] {
        try await upsert(rows, table: Self.foldersTable)
    }

    func upsertWords(_ rows: [RemoteWordUpsert]) async throws -> [RemoteAck] {
        try await upsert(rows, table: Self.wordsTable)
    }

    /// `user_id` filter (only this account's rows), a redundant `gte` so the
    /// `(user_id, updated_at, id)` index has a range start, and the keyset `or` filter.
    private func fetch(table: String, columns: String, ownerID: UUID, after cursor: SyncCursor?,
                       limit: Int) async throws -> Data {
        do {
            var query = provider.client.from(table).select(columns).eq("user_id", value: ownerID)
            if let cursor {
                query = query.gte("updated_at", value: cursor.timestampString)
                    .or(Self.keysetFilter(after: cursor))
            }
            return try await query.order("updated_at").order("id").limit(limit).execute().data
        } catch {
            throw Self.classify(error)
        }
    }

    private func upsert<Row: Encodable & Sendable>(_ rows: [Row], table: String) async throws -> [RemoteAck] {
        guard !rows.isEmpty else { return [] }
        do {
            let response: PostgrestResponse<[RemoteAck]> = try await provider.client.from(table)
                .upsert(rows, onConflict: "user_id,id", returning: .representation)
                .select("id,updated_at")
                .execute()
            return response.value
        } catch {
            throw Self.classify(error)
        }
    }

    /// Rows strictly after the cursor in `(updated_at, id)` order.
    nonisolated static func keysetFilter(after cursor: SyncCursor) -> String {
        let timestamp = cursor.timestampString
        return "updated_at.gt.\"\(timestamp)\",and(updated_at.eq.\"\(timestamp)\",id.gt.\(cursor.id.uuidString.lowercased()))"
    }

    /// Memberships strictly after the cursor in `(updated_at, word_id, folder_id)` order
    /// (`id` = word_id, `secondaryID` = folder_id).
    nonisolated static func membershipKeysetFilter(after cursor: SyncCursor) -> String {
        let timestamp = cursor.timestampString
        let word = cursor.id.uuidString.lowercased()
        let folder = cursor.secondaryID?.uuidString.lowercased() ?? "00000000-0000-0000-0000-000000000000"
        return "updated_at.gt.\"\(timestamp)\",and(updated_at.eq.\"\(timestamp)\",word_id.gt.\(word)),"
            + "and(updated_at.eq.\"\(timestamp)\",word_id.eq.\(word),folder_id.gt.\(folder))"
    }

    /// Permanent row rejections (SQLSTATE 22/23, HTTP 413) become `.rejected` so the engine
    /// isolates the bad row; session/permission problems become `.unauthorized`; everything
    /// else (network, 5xx, schema mismatch, rate limit) stays transient.
    nonisolated static func classify(_ error: Error) -> Error {
        if let error = error as? PostgrestError, let code = error.code {
            if code.hasPrefix("22") || code.hasPrefix("23") { return SyncRemoteError.rejected }
            if code == "42501" || code == "PGRST301" || code == "PGRST302" { return SyncRemoteError.unauthorized }
        }
        if let error = error as? HTTPError {
            switch error.response.statusCode {
            case 413: return SyncRemoteError.rejected
            case 401: return SyncRemoteError.unauthorized
            default: break
            }
        }
        return error
    }
}
