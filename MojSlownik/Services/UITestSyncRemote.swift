#if DEBUG
import Foundation

/// Network-free server model for unit tests and UI tests. It mimics the database: rows are
/// keyed by `(userID, id)`, `updated_at` is assigned like the trigger (`max(clock cut to ms,
/// previous + 1 ms)`, one clock reading per upsert call so batches tie), and fetches use the
/// exact keyset semantics of the real query.
@MainActor
final class InMemorySyncRemote: SyncRemote {
    struct Key: Hashable, Sendable {
        let userID: UUID
        let id: UUID
    }

    struct Server: Sendable {
        var words: [Key: RemoteWordRecord] = [:]
        var folders: [Key: RemoteFolderRecord] = [:]

        /// Writes a row as the trigger would: a new, strictly larger `updated_at`.
        mutating func put(_ record: RemoteWordRecord, at clock: Date) {
            let key = Key(userID: record.userID, id: record.id)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: words[key]?.updatedAt)
            words[key] = record.replacing(updatedAt: updatedAt)
        }

        mutating func put(_ record: RemoteFolderRecord, at clock: Date) {
            let key = Key(userID: record.userID, id: record.id)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: folders[key]?.updatedAt)
            folders[key] = RemoteFolderRecord(id: record.id, userID: record.userID, name: record.name,
                                              sortOrder: record.sortOrder, createdAt: record.createdAt,
                                              updatedAt: updatedAt, deletedAt: record.deletedAt)
        }
    }

    var server = Server()
    /// The session's user: an upsert row for anyone else is refused (RLS WITH CHECK).
    var currentUserID: UUID
    private let clock: () -> Date

    // Hooks.
    /// Thrown by the next call (fetch or upsert), then cleared.
    var nextError: Error?
    /// Thrown by the next upsert after it stored its rows (a lost response), then cleared.
    var nextErrorAfterStore: Error?
    var failAll: Error?
    /// The first N calls throw a transient `URLError(.notConnectedToInternet)`.
    var failNextCalls = 0
    /// Every call sleeps this long first (cancellable), to model a slow network.
    var callDelay: Duration?
    var rejectWhere: ((RemoteWordUpsert) -> Bool)?
    /// Runs after an upsert stored its rows and before the acks return (simulates an edit
    /// made during the request).
    var beforeAck: (() -> Void)?
    /// Runs at the start of every call with its name, before failures are decided (a test can
    /// arm `nextError` for "the second fetch").
    var onCall: ((String) -> Void)?
    /// Rewrites the rows a words fetch returns after the owner filter (to inject a foreign row).
    var wordFetchTransform: (([RemoteWordRecord]) -> [RemoteWordRecord])?
    /// Server-side changes applied once by `armScriptedChanges()`.
    var scriptedChanges: ((inout Server, Date) -> Void)?

    // Assertion logs.
    private(set) var requestedCursors: [SyncCursor?] = []
    private(set) var requestedOwners: [UUID] = []
    private(set) var upsertedWordBatches: [[RemoteWordUpsert]] = []
    private(set) var upsertedFolderBatches: [[RemoteFolderUpsert]] = []
    private(set) var callCount = 0
    /// Every fetch and upsert call, in order ("fetchFolders", "fetchWords", "upsertFolders", ...).
    private(set) var callLog: [String] = []

    init(currentUserID: UUID, clock: @escaping () -> Date = { Date() }) {
        self.currentUserID = currentUserID
        self.clock = clock
    }

    nonisolated static func stamp(_ clock: Date, after previous: Date?) -> Date {
        let truncated = UITestFixture.truncatedToMillis(clock)
        guard let previous else { return truncated }
        return max(truncated, previous.addingTimeInterval(0.001))
    }

    func seed(words: [RemoteWordRecord] = [], folders: [RemoteFolderRecord] = []) {
        for word in words { server.words[Key(userID: word.userID, id: word.id)] = word }
        for folder in folders { server.folders[Key(userID: folder.userID, id: folder.id)] = folder }
    }

    /// Applies `scriptedChanges` to the server once; later calls do nothing.
    func armScriptedChanges() {
        guard let changes = scriptedChanges else { return }
        scriptedChanges = nil
        changes(&server, clock())
    }

    func word(id: UUID, userID: UUID) -> RemoteWordRecord? { server.words[Key(userID: userID, id: id)] }
    func folder(id: UUID, userID: UUID) -> RemoteFolderRecord? { server.folders[Key(userID: userID, id: id)] }

    // MARK: SyncRemote

    func fetchFolders(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteFolderRecord] {
        try enter("fetchFolders")
        try await pause()
        requestedCursors.append(cursor)
        requestedOwners.append(ownerID)
        let rows = server.folders.values.filter { $0.userID == ownerID }
        return Self.page(rows, after: cursor, limit: limit, updatedAt: \.updatedAt, id: \.id)
    }

    func fetchWords(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWordRecord] {
        try enter("fetchWords")
        try await pause()
        requestedCursors.append(cursor)
        requestedOwners.append(ownerID)
        var rows = server.words.values.filter { $0.userID == ownerID }
        if let wordFetchTransform { rows = wordFetchTransform(rows) }
        return Self.page(rows, after: cursor, limit: limit, updatedAt: \.updatedAt, id: \.id)
    }

    func upsertFolders(_ rows: [RemoteFolderUpsert]) async throws -> [RemoteAck] {
        try enter("upsertFolders")
        try await pause()
        guard rows.allSatisfy({ $0.userID == currentUserID }) else { throw SyncRemoteError.unauthorized }
        upsertedFolderBatches.append(rows)
        let at = clock()
        var acks: [RemoteAck] = []
        for row in rows {
            server.put(RemoteFolderRecord(id: row.id, userID: row.userID, name: row.name,
                                          sortOrder: row.sortOrder, createdAt: row.createdAt,
                                          updatedAt: at, deletedAt: row.deletedAt), at: at)
            if let stored = folder(id: row.id, userID: row.userID) {
                acks.append(RemoteAck(id: stored.id, updatedAt: stored.updatedAt))
            }
        }
        return try finishUpsert(acks)
    }

    func upsertWords(_ rows: [RemoteWordUpsert]) async throws -> [RemoteAck] {
        try enter("upsertWords")
        try await pause()
        guard rows.allSatisfy({ $0.userID == currentUserID }) else { throw SyncRemoteError.unauthorized }
        if let rejectWhere, rows.contains(where: rejectWhere) { throw SyncRemoteError.rejected }
        upsertedWordBatches.append(rows)
        let at = clock()
        var acks: [RemoteAck] = []
        for row in rows {
            server.put(RemoteWordRecord(
                id: row.id, userID: row.userID, term: row.term, termLanguage: row.termLanguage,
                translation: row.translation, translationLanguage: row.translationLanguage,
                enteredLanguage: row.enteredLanguage, category: row.category, folderIDs: row.folderIDs,
                createdAt: row.createdAt, updatedAt: at, deletedAt: row.deletedAt,
                easeFactor: row.easeFactor, intervalDays: row.intervalDays, repetitions: row.repetitions,
                dueDate: row.dueDate, lastReviewGrade: row.lastReviewGrade, knowledgeTier: row.knowledgeTier,
                consecutiveSoftMisses: row.consecutiveSoftMisses), at: at)
            if let stored = word(id: row.id, userID: row.userID) {
                acks.append(RemoteAck(id: stored.id, updatedAt: stored.updatedAt))
            }
        }
        return try finishUpsert(acks)
    }

    // MARK: Internals

    private func pause() async throws {
        if let callDelay { try await Task.sleep(for: callDelay) }
    }

    private func enter(_ name: String) throws {
        callCount += 1
        callLog.append(name)
        onCall?(name)
        if failNextCalls > 0 {
            failNextCalls -= 1
            throw URLError(.notConnectedToInternet)
        }
        if let failAll { throw failAll }
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private func finishUpsert(_ acks: [RemoteAck]) throws -> [RemoteAck] {
        if let error = nextErrorAfterStore {
            nextErrorAfterStore = nil
            throw error
        }
        beforeAck?()
        return acks
    }

    /// Keyset: `(updated_at, id)` strictly after the cursor, ordered, limited.
    private static func page<Row>(_ rows: [Row], after cursor: SyncCursor?, limit: Int,
                                  updatedAt: KeyPath<Row, Date>, id: KeyPath<Row, UUID>) -> [Row] {
        func millis(_ row: Row) -> Int64 { SyncCursor(updatedAt: row[keyPath: updatedAt], id: row[keyPath: id]).updatedAtMillis }
        func idText(_ row: Row) -> String { row[keyPath: id].uuidString }
        let after = rows.filter { row in
            guard let cursor else { return true }
            let time = millis(row)
            return time > cursor.updatedAtMillis
                || (time == cursor.updatedAtMillis && idText(row) > cursor.id.uuidString)
        }
        let sorted = after.sorted { lhs, rhs in
            (millis(lhs), idText(lhs)) < (millis(rhs), idText(rhs))
        }
        return Array(sorted.prefix(limit))
    }
}

extension RemoteWordRecord {
    func replacing(term: String? = nil, translation: String? = nil, folderIDs: [UUID]? = nil,
                   deletedAt: Date?? = nil, updatedAt: Date? = nil) -> RemoteWordRecord {
        RemoteWordRecord(
            id: id, userID: userID, term: term ?? self.term, termLanguage: termLanguage,
            translation: translation ?? self.translation, translationLanguage: translationLanguage,
            enteredLanguage: enteredLanguage, category: category, folderIDs: folderIDs ?? self.folderIDs,
            createdAt: createdAt, updatedAt: updatedAt ?? self.updatedAt,
            deletedAt: deletedAt ?? self.deletedAt, easeFactor: easeFactor, intervalDays: intervalDays,
            repetitions: repetitions, dueDate: dueDate, lastReviewGrade: lastReviewGrade,
            knowledgeTier: knowledgeTier, consecutiveSoftMisses: consecutiveSoftMisses)
    }
}

/// Server states for UI tests (`UITEST_SYNC`); always a network-free `InMemorySyncRemote`.
enum UITestSyncState: String, CaseIterable, Sendable {
    /// An empty server, no link.
    case empty
    /// The test account's server holds a folder and three words (one duplicates a fixture word).
    case remoteVocabulary
    /// An empty server; the first call fails once.
    case failsOnce
    /// Local data is linked to another account.
    case linkedToOtherAccount
    /// For the `syncedVocabulary` fixture: the server mirrors it, linked, and after the first
    /// successful cycle two newer server versions appear (`дом` deleted, `кот` -> `котик`).
    case syncedThenRemoteChanges

    static let otherAccountID = UUID(uuidString: "00000000-0000-4000-8000-0000000000e2")!
    static let cloudFolderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F9")!
    static let cloudWordIDs = [UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
                               UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
                               UUID(uuidString: "00000000-0000-0000-0000-0000000000B3")!]

    @MainActor private static var owner: UUID { StaticAuthBackend.testAccount.userID }

    @MainActor
    func makeRemote(now: Date) -> InMemorySyncRemote {
        let remote = InMemorySyncRemote(currentUserID: Self.owner)
        switch self {
        case .empty, .linkedToOtherAccount:
            break
        case .failsOnce:
            remote.failNextCalls = 1
        case .remoteVocabulary:
            let stamp = UITestFixture.truncatedToMillis(now.addingTimeInterval(-600))
            remote.seed(
                words: [Self.wordRecord(id: Self.cloudWordIDs[0], polish: "most", russian: "мост", category: "other",
                                        folders: [Self.cloudFolderID], now: now, updatedAt: stamp),
                        Self.wordRecord(id: Self.cloudWordIDs[1], polish: "ser", russian: "сыр", category: "food",
                                        folders: [], now: now, updatedAt: stamp),
                        // Same pair as the `kot` fixture word under another id: adopted, not duplicated.
                        Self.wordRecord(id: Self.cloudWordIDs[2], polish: "kot", russian: "кот", category: "nature",
                                        folders: [], now: now, updatedAt: stamp)],
                folders: [RemoteFolderRecord(id: Self.cloudFolderID, userID: Self.owner, name: "Из облака",
                                             sortOrder: 0, createdAt: now.addingTimeInterval(-3_600),
                                             updatedAt: stamp, deletedAt: nil)])
        case .syncedThenRemoteChanges:
            let specs = UITestFixture.syncedWords(now: now)
            remote.seed(words: specs.map { spec in
                Self.wordRecord(id: spec.id, polish: spec.polish, russian: spec.russian,
                                category: WordCategory.detect(russian: spec.russian, polish: spec.polish).stableID,
                                folders: [], now: now, updatedAt: spec.syncedAt, createdAt: spec.createdAt,
                                entered: spec.source)
            })
            let owner = Self.owner
            remote.scriptedChanges = { server, clock in
                let ids = UITestFixture.syncedWordIDs
                let key = { InMemorySyncRemote.Key(userID: owner, id: $0) }
                if let dom = server.words[key(ids[1])] {
                    server.put(dom.replacing(deletedAt: .some(clock)), at: clock)
                }
                if let kot = server.words[key(ids[0])] {
                    server.put(kot.replacing(translation: "котик"), at: clock)
                }
            }
        }
        return remote
    }

    /// Persists the link state this scenario starts from (before the stores are built).
    @MainActor
    func seedState(into repository: any SyncStateRepository, now: Date) {
        switch self {
        case .empty, .remoteVocabulary, .failsOnce:
            break
        case .linkedToOtherAccount:
            try? repository.save(SyncState(linkedAccountID: Self.otherAccountID,
                                           capabilityVersion: SyncEngine.capabilityVersion))
        case .syncedThenRemoteChanges:
            let newest = UITestFixture.syncedWords(now: now).max { $0.syncedAt < $1.syncedAt }
            try? repository.save(SyncState(
                linkedAccountID: Self.owner, capabilityVersion: SyncEngine.capabilityVersion,
                wordsCursor: newest.map { SyncCursor(updatedAt: $0.syncedAt, id: $0.id) }))
        }
    }

    @MainActor private static func wordRecord(id: UUID, polish: String, russian: String, category: String,
                                   folders: [UUID], now: Date, updatedAt: Date, createdAt: Date? = nil,
                                   entered: AppLanguage = .russian) -> RemoteWordRecord {
        RemoteWordRecord(
            id: id, userID: owner, term: polish, termLanguage: "pl", translation: russian,
            translationLanguage: "ru", enteredLanguage: entered.rawValue, category: category,
            folderIDs: folders, createdAt: createdAt ?? now.addingTimeInterval(-3_600), updatedAt: updatedAt,
            deletedAt: nil, easeFactor: 2.5, intervalDays: 30, repetitions: 3,
            dueDate: now.addingTimeInterval(30 * 86_400), lastReviewGrade: nil, knowledgeTier: nil,
            consecutiveSoftMisses: 0)
    }
}
#endif
