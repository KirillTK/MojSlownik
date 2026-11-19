import Foundation
import Supabase

/// `SyncRemote` over supabase-swift (PostgREST). The client is created lazily by the provider,
/// so constructing this performs no I/O. No SDK logger and no `print`: row content must never
/// reach a log.
@MainActor
final class SupabaseSyncRemote: SyncRemote {
    static let wordsTable = "words"
    static let foldersTable = "folders"

    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider) {
        self.provider = provider
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
