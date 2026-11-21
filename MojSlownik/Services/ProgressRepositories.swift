import Foundation
import SwiftData

// Persistence seams for local progress. Keys, property names and JSON shape are the
// stored format of existing installs and must not change.

struct AchievementState: Codable, Equatable {
    var unlocked: [String: Date] = [:]
    var ledger = AchievementLedger()
    var didInitialSync = false

    init(unlocked: [String: Date] = [:], ledger: AchievementLedger = AchievementLedger(),
         didInitialSync: Bool = false) {
        self.unlocked = unlocked
        self.ledger = ledger
        self.didInitialSync = didInitialSync
    }

    // Missing keys decode to defaults so later additions never drop stored unlocks.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlocked = try container.decodeIfPresent([String: Date].self, forKey: .unlocked) ?? [:]
        ledger = try container.decodeIfPresent(AchievementLedger.self, forKey: .ledger) ?? AchievementLedger()
        didInitialSync = try container.decodeIfPresent(Bool.self, forKey: .didInitialSync) ?? false
    }
}

struct DailyActivityAnswer: Codable, Equatable {
    let wordID: PersistentIdentifier
    let isCorrect: Bool
}

struct DailyActivity: Codable, Equatable {
    var day: Date
    // Decoded SwiftData IDs can be equal to live IDs but have different hashes.
    // Arrays keep equality-based matching and decode the previous Set JSON arrays.
    var completedIDs: [PersistentIdentifier] = []
    var pendingIDs: [PersistentIdentifier] = []
    // Optional additions preserve the existing v1 daily activity on upgrade.
    var quizCompletedIDs: [PersistentIdentifier]?
    var answers: [DailyActivityAnswer]?
}

@MainActor
protocol AchievementStateRepository: AnyObject {
    /// Missing or corrupt data gives a default state.
    func load() -> AchievementState
    func save(_ state: AchievementState) throws
}

@MainActor
protocol DailyActivityRepository: AnyObject {
    /// Missing or corrupt data gives nil.
    func load() -> DailyActivity?
    /// Encodes or validates now and returns a non-throwing commit, so callers can
    /// serialize first, save the model context, and only then publish.
    func prepareSave(_ activity: DailyActivity) throws -> () -> Void
    func clear()
}

@MainActor
final class UserDefaultsAchievementStateRepository: AchievementStateRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "achievements.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> AchievementState {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(AchievementState.self, from: $0) }
            ?? AchievementState()
    }

    func save(_ state: AchievementState) throws {
        defaults.set(try JSONEncoder().encode(state), forKey: key)
    }
}

@MainActor
final class UserDefaultsDailyActivityRepository: DailyActivityRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "dailyStudyActivity.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> DailyActivity? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DailyActivity.self, from: $0) }
    }

    func prepareSave(_ activity: DailyActivity) throws -> () -> Void {
        let data = try JSONEncoder().encode(activity)
        let defaults = defaults
        let key = key
        return { defaults.set(data, forKey: key) }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// The workspace the user last opened (device-local, never synced).
@MainActor
protocol ActiveWorkspaceRepository: AnyObject {
    func load() -> UUID?
    func save(_ id: UUID)
}

@MainActor
final class UserDefaultsActiveWorkspaceRepository: ActiveWorkspaceRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "workspace.active.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    func save(_ id: UUID) {
        defaults.set(id.uuidString, forKey: key)
    }
}

/// The side the user types on per workspace (only same-script pairs need it); device-local.
@MainActor
protocol InputSideRepository: AnyObject {
    func side(for workspaceID: UUID) -> WordSide?
    func setSide(_ side: WordSide, for workspaceID: UUID)
}

@MainActor
final class InMemoryInputSideRepository: InputSideRepository {
    private var sides: [UUID: WordSide] = [:]

    func side(for workspaceID: UUID) -> WordSide? { sides[workspaceID] }
    func setSide(_ side: WordSide, for workspaceID: UUID) { sides[workspaceID] = side }
}

/// `[uuidString: "term"|"translation"]` under one key; unknown values read as unset.
@MainActor
final class UserDefaultsInputSideRepository: InputSideRepository {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults, key: String = "workspace.inputSide.v1") {
        self.defaults = defaults
        self.key = key
    }

    func side(for workspaceID: UUID) -> WordSide? {
        let stored = defaults.dictionary(forKey: key) as? [String: String]
        return stored?[workspaceID.uuidString].flatMap(WordSide.init(rawValue:))
    }

    func setSide(_ side: WordSide, for workspaceID: UUID) {
        var stored = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        stored[workspaceID.uuidString] = side.rawValue
        defaults.set(stored, forKey: key)
    }
}
