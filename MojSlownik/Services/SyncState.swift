import Foundation

/// Persisted sync bookkeeping (`sync.v1`): which account the local data is linked to, the pull
/// cursors, and ids of server rows this build could not read.
struct SyncState: Codable, Equatable {
    var linkedAccountID: UUID?
    var capabilityVersion: Int
    var workspacesCursor: SyncCursor?
    var foldersCursor: SyncCursor?
    var wordsCursor: SyncCursor?
    var membershipsCursor: SyncCursor?
    var lastSyncedAt: Date?
    /// When the current link was made (device clock). Compared only with this device's own
    /// `updatedAt`, to tell a sentinel row edited after the link from an untouched stale copy.
    var linkedAt: Date?
    /// Ids of server rows skipped as unreadable (a newer client may have written them). Their
    /// local rows are never pushed. Capped at `maxHeldIDs`.
    var heldIDs: Set<UUID>

    static let maxHeldIDs = 5_000

    init(linkedAccountID: UUID? = nil, capabilityVersion: Int = 0, workspacesCursor: SyncCursor? = nil,
         foldersCursor: SyncCursor? = nil, wordsCursor: SyncCursor? = nil,
         membershipsCursor: SyncCursor? = nil, lastSyncedAt: Date? = nil, linkedAt: Date? = nil,
         heldIDs: Set<UUID> = []) {
        self.linkedAccountID = linkedAccountID
        self.capabilityVersion = capabilityVersion
        self.workspacesCursor = workspacesCursor
        self.foldersCursor = foldersCursor
        self.wordsCursor = wordsCursor
        self.membershipsCursor = membershipsCursor
        self.lastSyncedAt = lastSyncedAt
        self.linkedAt = linkedAt
        self.heldIDs = heldIDs
    }

    enum CodingKeys: String, CodingKey {
        case linkedAccountID, capabilityVersion, workspacesCursor, foldersCursor, wordsCursor, membershipsCursor
        case lastSyncedAt, linkedAt, heldIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkedAccountID = try container.decodeIfPresent(UUID.self, forKey: .linkedAccountID)
        capabilityVersion = try container.decodeIfPresent(Int.self, forKey: .capabilityVersion) ?? 0
        workspacesCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .workspacesCursor)
        foldersCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .foldersCursor)
        wordsCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .wordsCursor)
        membershipsCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .membershipsCursor)
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        linkedAt = try container.decodeIfPresent(Date.self, forKey: .linkedAt)
        heldIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .heldIDs) ?? []
    }
}

@MainActor
protocol SyncStateRepository {
    func load() -> SyncState
    func save(_ state: SyncState) throws
}

@MainActor
struct UserDefaultsSyncStateRepository: SyncStateRepository {
    nonisolated static let defaultKey = "sync.v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = UserDefaultsSyncStateRepository.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> SyncState {
        guard let data = defaults.data(forKey: key),
              let state = try? JSONDecoder().decode(SyncState.self, from: data) else { return SyncState() }
        return state
    }

    func save(_ state: SyncState) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: key)
    }
}
