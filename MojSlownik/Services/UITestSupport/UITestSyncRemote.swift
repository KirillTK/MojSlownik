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

    struct MembershipKey: Hashable, Sendable {
        let userID: UUID
        let wordID: UUID
        let folderID: UUID
    }

    struct Server: Sendable {
        var workspaces: [Key: RemoteWorkspaceRecord] = [:]
        var words: [Key: RemoteWordRecord] = [:]
        var folders: [Key: RemoteFolderRecord] = [:]
        var memberships: [MembershipKey: RemoteMembershipRecord] = [:]

        mutating func put(_ record: RemoteWorkspaceRecord, at clock: Date) {
            let key = Key(userID: record.userID, id: record.id)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: workspaces[key]?.updatedAt)
            workspaces[key] = RemoteWorkspaceRecord(
                id: record.id, userID: record.userID, termLanguage: record.termLanguage,
                translationLanguage: record.translationLanguage, sortOrder: record.sortOrder,
                createdAt: record.createdAt, updatedAt: updatedAt, deletedAt: record.deletedAt)
        }

        mutating func put(_ record: RemoteMembershipRecord, at clock: Date) {
            let key = MembershipKey(userID: record.userID, wordID: record.wordID, folderID: record.folderID)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: memberships[key]?.updatedAt)
            memberships[key] = RemoteMembershipRecord(
                userID: record.userID, workspaceID: record.workspaceID, wordID: record.wordID,
                folderID: record.folderID, createdAt: record.createdAt, updatedAt: updatedAt,
                deletedAt: record.deletedAt)
        }

        /// Writes a row as the trigger would: a new, strictly larger `updated_at`.
        mutating func put(_ record: RemoteWordRecord, at clock: Date) {
            let key = Key(userID: record.userID, id: record.id)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: words[key]?.updatedAt)
            words[key] = record.replacing(updatedAt: updatedAt)
        }

        mutating func put(_ record: RemoteFolderRecord, at clock: Date) {
            let key = Key(userID: record.userID, id: record.id)
            let updatedAt = InMemorySyncRemote.stamp(clock, after: folders[key]?.updatedAt)
            folders[key] = RemoteFolderRecord(id: record.id, userID: record.userID,
                                              workspaceID: record.workspaceID, name: record.name,
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
    private(set) var upsertedWorkspaceBatches: [[RemoteWorkspaceUpsert]] = []
    private(set) var upsertedWordBatches: [[RemoteWordUpsert]] = []
    private(set) var upsertedMembershipBatches: [[RemoteMembershipUpsert]] = []
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

    func seed(workspaces: [RemoteWorkspaceRecord] = [], words: [RemoteWordRecord] = [],
              folders: [RemoteFolderRecord] = [], memberships: [RemoteMembershipRecord] = []) {
        for workspace in workspaces { server.workspaces[Key(userID: workspace.userID, id: workspace.id)] = workspace }
        for membership in memberships {
            server.memberships[MembershipKey(userID: membership.userID, wordID: membership.wordID,
                                             folderID: membership.folderID)] = membership
        }
        for word in words { server.words[Key(userID: word.userID, id: word.id)] = word }
        for folder in folders { server.folders[Key(userID: folder.userID, id: folder.id)] = folder }
    }

    /// Applies `scriptedChanges` to the server once; later calls do nothing.
    func armScriptedChanges() {
        guard let changes = scriptedChanges else { return }
        scriptedChanges = nil
        changes(&server, clock())
    }

    func workspace(id: UUID, userID: UUID) -> RemoteWorkspaceRecord? { server.workspaces[Key(userID: userID, id: id)] }
    func membership(wordID: UUID, folderID: UUID, userID: UUID) -> RemoteMembershipRecord? {
        server.memberships[MembershipKey(userID: userID, wordID: wordID, folderID: folderID)]
    }
    func word(id: UUID, userID: UUID) -> RemoteWordRecord? { server.words[Key(userID: userID, id: id)] }
    func folder(id: UUID, userID: UUID) -> RemoteFolderRecord? { server.folders[Key(userID: userID, id: id)] }

    // MARK: SyncRemote

    func fetchWorkspaces(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteWorkspaceRecord] {
        try enter("fetchWorkspaces")
        try await pause()
        requestedCursors.append(cursor)
        requestedOwners.append(ownerID)
        let rows = server.workspaces.values.filter { $0.userID == ownerID }
        return Self.page(rows, after: cursor, limit: limit, updatedAt: \.updatedAt, id: \.id)
    }

    func fetchMemberships(ownerID: UUID, after cursor: SyncCursor?, limit: Int) async throws -> [RemoteMembershipRecord] {
        try enter("fetchMemberships")
        try await pause()
        requestedCursors.append(cursor)
        requestedOwners.append(ownerID)
        let rows = server.memberships.values.filter { $0.userID == ownerID }
        return Self.page(rows, after: cursor, limit: limit, updatedAt: \.updatedAt, id: \.wordID,
                         secondary: \.folderID)
    }

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

    func upsertWorkspaces(_ rows: [RemoteWorkspaceUpsert]) async throws -> [RemoteAck] {
        try enter("upsertWorkspaces")
        try await pause()
        guard rows.allSatisfy({ $0.userID == currentUserID }) else { throw SyncRemoteError.unauthorized }
        upsertedWorkspaceBatches.append(rows)
        let at = clock()
        var acks: [RemoteAck] = []
        for row in rows {
            server.put(RemoteWorkspaceRecord(id: row.id, userID: row.userID, termLanguage: row.termLanguage,
                                             translationLanguage: row.translationLanguage,
                                             sortOrder: row.sortOrder, createdAt: row.createdAt, updatedAt: at,
                                             deletedAt: row.deletedAt), at: at)
            if let stored = workspace(id: row.id, userID: row.userID) {
                acks.append(RemoteAck(id: stored.id, updatedAt: stored.updatedAt))
            }
        }
        return try finishUpsert(acks)
    }

    func upsertMemberships(_ rows: [RemoteMembershipUpsert]) async throws -> [RemoteMembershipAck] {
        try enter("upsertMemberships")
        try await pause()
        guard rows.allSatisfy({ $0.userID == currentUserID }) else { throw SyncRemoteError.unauthorized }
        // The composite foreign keys: word and folder exist in the membership's workspace.
        guard rows.allSatisfy({ row in
            server.words[Key(userID: row.userID, id: row.wordID)]?.workspaceID == row.workspaceID
                && server.folders[Key(userID: row.userID, id: row.folderID)]?.workspaceID == row.workspaceID
        }) else { throw SyncRemoteError.rejected }
        upsertedMembershipBatches.append(rows)
        let at = clock()
        var acks: [RemoteMembershipAck] = []
        for row in rows {
            server.put(RemoteMembershipRecord(userID: row.userID, workspaceID: row.workspaceID, wordID: row.wordID,
                                              folderID: row.folderID, createdAt: row.createdAt, updatedAt: at,
                                              deletedAt: row.deletedAt), at: at)
            if let stored = membership(wordID: row.wordID, folderID: row.folderID, userID: row.userID) {
                acks.append(RemoteMembershipAck(wordID: stored.wordID, folderID: stored.folderID,
                                                updatedAt: stored.updatedAt))
            }
        }
        if let error = nextErrorAfterStore {
            nextErrorAfterStore = nil
            throw error
        }
        beforeAck?()
        return acks
    }

    func upsertFolders(_ rows: [RemoteFolderUpsert]) async throws -> [RemoteAck] {
        try enter("upsertFolders")
        try await pause()
        guard rows.allSatisfy({ $0.userID == currentUserID }) else { throw SyncRemoteError.unauthorized }
        upsertedFolderBatches.append(rows)
        let at = clock()
        var acks: [RemoteAck] = []
        for row in rows {
            server.put(RemoteFolderRecord(id: row.id, userID: row.userID, workspaceID: row.workspaceID,
                                          name: row.name, sortOrder: row.sortOrder, createdAt: row.createdAt,
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
                id: row.id, userID: row.userID, workspaceID: row.workspaceID, term: row.term,
                translation: row.translation, enteredSide: row.enteredSide, category: row.category,
                createdAt: row.createdAt, updatedAt: at, deletedAt: row.deletedAt,
                easeFactor: row.easeFactor, intervalDays: row.intervalDays, repetitions: row.repetitions,
                dueDate: row.dueDate, lastReviewGrade: row.lastReviewGrade, knowledgeTier: row.knowledgeTier,
                consecutiveSoftMisses: row.consecutiveSoftMisses, lapseCount: row.lapseCount), at: at)
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

    /// Keyset: `(updated_at, id[, secondary])` strictly after the cursor, ordered, limited.
    private static func page<Row>(_ rows: [Row], after cursor: SyncCursor?, limit: Int,
                                  updatedAt: KeyPath<Row, Date>, id: KeyPath<Row, UUID>,
                                  secondary: KeyPath<Row, UUID>? = nil) -> [Row] {
        func millis(_ row: Row) -> Int64 { SyncCursor(updatedAt: row[keyPath: updatedAt], id: row[keyPath: id]).updatedAtMillis }
        func key(_ row: Row) -> String {
            row[keyPath: id].uuidString + (secondary.map { row[keyPath: $0].uuidString } ?? "")
        }
        let cursorKey = cursor.map { $0.id.uuidString + (secondary == nil ? "" : ($0.secondaryID?.uuidString ?? "")) }
        let after = rows.filter { row in
            guard let cursor, let cursorKey else { return true }
            let time = millis(row)
            return time > cursor.updatedAtMillis || (time == cursor.updatedAtMillis && key(row) > cursorKey)
        }
        let sorted = after.sorted { lhs, rhs in (millis(lhs), key(lhs)) < (millis(rhs), key(rhs)) }
        return Array(sorted.prefix(limit))
    }
}

extension RemoteWordRecord {
    func replacing(term: String? = nil, translation: String? = nil,
                   deletedAt: Date?? = nil, updatedAt: Date? = nil) -> RemoteWordRecord {
        RemoteWordRecord(
            id: id, userID: userID, workspaceID: workspaceID, term: term ?? self.term,
            translation: translation ?? self.translation, enteredSide: enteredSide, category: category,
            createdAt: createdAt, updatedAt: updatedAt ?? self.updatedAt,
            deletedAt: deletedAt ?? self.deletedAt, easeFactor: easeFactor, intervalDays: intervalDays,
            repetitions: repetitions, dueDate: dueDate, lastReviewGrade: lastReviewGrade,
            knowledgeTier: knowledgeTier, consecutiveSoftMisses: consecutiveSoftMisses,
            lapseCount: lapseCount)
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
    /// successful cycle two newer server versions appear (`dom` deleted, `kot` renamed).
    case syncedThenRemoteChanges
    /// For `freshInstall` + signed in: the server holds de ← ru at sort 0 («das Haus») and pl ← ru at
    /// sort 1 with the cloud words, so the opened workspace proves the pull (a local default would be pl).
    case remoteWorkspaces

    static let otherAccountID = UUID(uuidString: "00000000-0000-4000-8000-0000000000e2")!
    static let cloudFolderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F9")!
    static let germanWordID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B4")!
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
        case .remoteWorkspaces:
            let stamp = UITestFixture.truncatedToMillis(now.addingTimeInterval(-600))
            let german = WorkspaceID.make(term: "de", translation: "ru")
            remote.seed(
                workspaces: [Self.workspaceRecord(id: german, term: "de", sortOrder: 0, now: now, updatedAt: stamp),
                             Self.workspaceRecord(sortOrder: 1, now: now, updatedAt: stamp)],
                words: [Self.wordRecord(id: Self.germanWordID, polish: "das Haus", russian: "дом", category: "other", // l10n:data
                                        now: now, updatedAt: stamp, workspaceID: german),
                        Self.wordRecord(id: Self.cloudWordIDs[0], polish: "most", russian: "мост", category: "other", // l10n:data
                                        now: now, updatedAt: stamp),
                        Self.wordRecord(id: Self.cloudWordIDs[1], polish: "ser", russian: "сыр", category: "food", // l10n:data
                                        now: now, updatedAt: stamp)])
        case .failsOnce:
            remote.failNextCalls = 1
        case .remoteVocabulary:
            let stamp = UITestFixture.truncatedToMillis(now.addingTimeInterval(-600))
            remote.seed(
                workspaces: [Self.workspaceRecord(now: now, updatedAt: stamp)],
                words: [Self.wordRecord(id: Self.cloudWordIDs[0], polish: "most", russian: "мост", category: "other", // l10n:data
                                        now: now, updatedAt: stamp),
                        Self.wordRecord(id: Self.cloudWordIDs[1], polish: "ser", russian: "сыр", category: "food", // l10n:data
                                        now: now, updatedAt: stamp),
                        // Same pair as the `kot` fixture word under another id: adopted, not duplicated.
                        Self.wordRecord(id: Self.cloudWordIDs[2], polish: "kot", russian: "кот", category: "nature", // l10n:data
                                        now: now, updatedAt: stamp)],
                folders: [RemoteFolderRecord(id: Self.cloudFolderID, userID: Self.owner,
                                             workspaceID: WorkspaceID.legacy, name: "Из облака", // l10n:data
                                             sortOrder: 0, createdAt: now.addingTimeInterval(-3_600),
                                             updatedAt: stamp, deletedAt: nil)],
                memberships: [RemoteMembershipRecord(userID: Self.owner, workspaceID: WorkspaceID.legacy,
                                                     wordID: Self.cloudWordIDs[0], folderID: Self.cloudFolderID,
                                                     createdAt: now.addingTimeInterval(-3_600), updatedAt: stamp,
                                                     deletedAt: nil)])
        case .syncedThenRemoteChanges:
            let specs = UITestFixture.syncedWords(now: now)
            remote.seed(
                workspaces: [Self.workspaceRecord(now: now, updatedAt: UITestFixture.syncedWorkspaceStamp(now: now))],
                words: specs.map { spec in
                    Self.wordRecord(id: spec.id, polish: spec.polish, russian: spec.russian,
                                    category: WordCategory.detect(term: spec.polish, translation: spec.russian).stableID,
                                    now: now, updatedAt: spec.syncedAt, createdAt: spec.createdAt,
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
                    server.put(kot.replacing(translation: "котик"), at: clock) // l10n:data
                }
            }
        }
        return remote
    }

    /// Persists the link state this scenario starts from (before the stores are built).
    @MainActor
    func seedState(into repository: any SyncStateRepository, now: Date) {
        switch self {
        case .empty, .remoteVocabulary, .failsOnce, .remoteWorkspaces:
            break
        case .linkedToOtherAccount:
            try? repository.save(SyncState(linkedAccountID: Self.otherAccountID,
                                           capabilityVersion: SyncEngine.capabilityVersion))
        case .syncedThenRemoteChanges:
            let newest = UITestFixture.syncedWords(now: now).max { $0.syncedAt < $1.syncedAt }
            try? repository.save(SyncState(
                linkedAccountID: Self.owner, capabilityVersion: SyncEngine.capabilityVersion,
                workspacesCursor: SyncCursor(updatedAt: UITestFixture.syncedWorkspaceStamp(now: now),
                                             id: WorkspaceID.legacy),
                wordsCursor: newest.map { SyncCursor(updatedAt: $0.syncedAt, id: $0.id) }))
        }
    }

    @MainActor private static func workspaceRecord(id: UUID = WorkspaceID.legacy, term: String = "pl",
                                                   sortOrder: Int = 0, now: Date,
                                                   updatedAt: Date) -> RemoteWorkspaceRecord {
        RemoteWorkspaceRecord(id: id, userID: owner, termLanguage: term, translationLanguage: "ru",
                              sortOrder: sortOrder, createdAt: now.addingTimeInterval(-7_200), updatedAt: updatedAt,
                              deletedAt: nil)
    }

    @MainActor private static func wordRecord(id: UUID, polish: String, russian: String, category: String,
                                              now: Date, updatedAt: Date, createdAt: Date? = nil,
                                              entered: WordSide = .translation,
                                              workspaceID: UUID = WorkspaceID.legacy) -> RemoteWordRecord {
        RemoteWordRecord(
            id: id, userID: owner, workspaceID: workspaceID, term: polish, translation: russian,
            enteredSide: entered.rawValue, category: category,
            createdAt: createdAt ?? now.addingTimeInterval(-3_600), updatedAt: updatedAt,
            deletedAt: nil, easeFactor: 2.5, intervalDays: 30, repetitions: 3,
            dueDate: now.addingTimeInterval(30 * 86_400), lastReviewGrade: nil, knowledgeTier: nil,
            consecutiveSoftMisses: 0)
    }
}
#endif
