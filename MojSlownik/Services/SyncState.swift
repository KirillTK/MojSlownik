import Foundation

/// Persisted sync bookkeeping (`sync.v1`): which account the local data is linked to, the pull
/// cursors, and ids of server rows this build could not read.
struct SyncState: Codable, Equatable {
    var linkedAccountID: UUID?
    var capabilityVersion: Int
    var foldersCursor: SyncCursor?
    var wordsCursor: SyncCursor?
    var lastSyncedAt: Date?
    /// When the current link was made (device clock). Compared only with this device's own
    /// `updatedAt`, to tell a sentinel row edited after the link from an untouched stale copy.
    var linkedAt: Date?
    /// Ids of server rows skipped as unreadable (a newer client may have written them). Their
    /// local rows are never pushed. Capped at `maxHeldIDs`.
    var heldIDs: Set<UUID>

    static let maxHeldIDs = 5_000

    init(linkedAccountID: UUID? = nil, capabilityVersion: Int = 0, foldersCursor: SyncCursor? = nil,
         wordsCursor: SyncCursor? = nil, lastSyncedAt: Date? = nil, linkedAt: Date? = nil,
         heldIDs: Set<UUID> = []) {
        self.linkedAccountID = linkedAccountID
        self.capabilityVersion = capabilityVersion
        self.foldersCursor = foldersCursor
        self.wordsCursor = wordsCursor
        self.lastSyncedAt = lastSyncedAt
        self.linkedAt = linkedAt
        self.heldIDs = heldIDs
    }

    enum CodingKeys: String, CodingKey {
        case linkedAccountID, capabilityVersion, foldersCursor, wordsCursor, lastSyncedAt, linkedAt, heldIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        linkedAccountID = try container.decodeIfPresent(UUID.self, forKey: .linkedAccountID)
        capabilityVersion = try container.decodeIfPresent(Int.self, forKey: .capabilityVersion) ?? 0
        foldersCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .foldersCursor)
        wordsCursor = try container.decodeIfPresent(SyncCursor.self, forKey: .wordsCursor)
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
