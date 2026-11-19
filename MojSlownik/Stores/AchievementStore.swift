import Foundation
import Observation
import SwiftUI

/// App-scoped achievements state: unlock persistence, practice ledger and banner presentation.
@MainActor
@Observable
final class AchievementStore {
    private let repository: any AchievementStateRepository
    private let calendar: Calendar
    private let logger: any AppLogging
    private var didInitialSync: Bool

    let catalog: [AchievementDefinition]
    let displayDuration: Duration
    private(set) var unlocked: [String: Date]
    private(set) var ledger: AchievementLedger
    private(set) var pendingAnnouncements: [AchievementDefinition] = []

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private(set) var announcedIDs: Set<String> = []
    @ObservationIgnored private var isSceneActive = true
    /// One-shot, in-memory: unlocks caused by just-pulled vocabulary are recorded without a banner.
    @ObservationIgnored private var quietUntil: Date?
    /// A sync cycle is applying pulled vocabulary: every unlock is silent until it ends.
    @ObservationIgnored private var quietActive = false
    @ObservationIgnored private var syncedWhileQuiet = false
    /// After the cycle: the next `sync` (the tracker's re-sync of the pulled words) is silent too.
    @ObservationIgnored private var drainUntil: Date?

    convenience init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent,
                     catalog: [AchievementDefinition] = AchievementCatalog.all,
                     displayDuration: Duration = .seconds(4)) {
        self.init(repository: UserDefaultsAchievementStateRepository(defaults: defaults), calendar: calendar,
                  catalog: catalog, displayDuration: displayDuration)
    }

    init(repository: any AchievementStateRepository, calendar: Calendar = .autoupdatingCurrent,
         catalog: [AchievementDefinition] = AchievementCatalog.all,
         displayDuration: Duration = .seconds(4), logger: (any AppLogging)? = nil) {
        self.repository = repository
        self.logger = logger ?? NoopAppLogger()
        self.calendar = calendar
        self.catalog = catalog
        self.displayDuration = displayDuration
        let stored = repository.load()
        unlocked = stored.unlocked
        ledger = stored.ledger
        didInitialSync = stored.didInitialSync
    }

    // MARK: Totals

    private var catalogUnlockedIDs: [String] {
        catalog.map(\.id).filter { unlocked[$0] != nil }
    }

    var unlockedCount: Int { catalogUnlockedIDs.count }
    var totalPoints: Int { catalog.filter { unlocked[$0.id] != nil }.reduce(0) { $0 + $1.points } }
    var possiblePoints: Int { catalog.reduce(0) { $0 + $1.points } }

    func currentStreak(now: Date = .now) -> Int {
        ledger.currentStreak(now: now, calendar: calendar)
    }

    func progress(for definition: AchievementDefinition, vocabulary: AchievementMetrics) -> AchievementProgress {
        AchievementEvaluator.progress(for: definition, metrics: vocabulary.merging(ledger.metrics),
                                      unlocked: unlocked)
    }

    // MARK: Recording and sync

    /// Non-throwing: the answer is already saved, achievements must never block practice.
    func record(_ event: AchievementEvent, now: Date = .now) {
        var next = ledger
        next.apply(event, now: now, calendar: calendar)
        guard next != ledger else { return }
        ledger = next
        persist()
    }

    /// The next `sync(vocabulary:)` that unlocks something within 10 s records it silently
    /// (no banner, no `achievement.unlocked` log), like the first-install sync.
    func recordNextUnlocksSilently(now: Date = .now) {
        quietUntil = now.addingTimeInterval(10)
    }

    /// Sync cycle start of applying pulled rows (before the first page is saved, so the
    /// tracker's re-sync of those rows cannot announce them). Ended by `endQuietUnlocks`.
    func beginQuietUnlocks() {
        quietActive = true
        syncedWhileQuiet = false
    }

    /// Cycle end. If the tracker has not re-synced yet, the next `sync` (within 10 s) is still
    /// silent and then the mode is over; if it already did, the mode ends now.
    func endQuietUnlocks(now: Date = .now) {
        guard quietActive else { return }
        quietActive = false
        drainUntil = syncedWhileQuiet ? nil : now.addingTimeInterval(10)
    }

    func sync(vocabulary: AchievementMetrics, now: Date = .now) {
        let draining = !quietActive && (drainUntil.map { now < $0 } ?? false)
        defer {
            if draining { drainUntil = nil }
            if quietActive { syncedWhileQuiet = true }
        }
        let metrics = vocabulary.merging(ledger.metrics)
        let ids = AchievementEvaluator.newlyUnlocked(catalog: catalog, metrics: metrics,
                                                     unlocked: Set(unlocked.keys))
        guard !ids.isEmpty || !didInitialSync else { return }
        let quiet = (quietUntil.map { now < $0 } ?? false) || quietActive || draining
        if !ids.isEmpty { quietUntil = nil }
        for id in ids { unlocked[id] = now }
        let announce = didInitialSync && !quiet
        didInitialSync = true
        persist()
        if announce {
            // Catalog ids are static identifiers (e.g. "vocabulary.words.50"), not user content.
            for id in ids { logger.log(.achievementUnlocked, [.achievement: .name(id)]) }
            pendingAnnouncements.append(contentsOf: ids.compactMap { id in catalog.first { $0.id == id } })
            presentNextIfNeeded()
        }
    }

    private func persist() {
        let state = AchievementState(unlocked: unlocked, ledger: ledger, didInitialSync: didInitialSync)
        do {
            try logger.logged("achievements.save") { try repository.save(state) }
        } catch {
            assertionFailure("Unable to save achievements: \(error)")
        }
    }

    // MARK: Banner presentation

    var currentAnnouncement: AchievementDefinition? { pendingAnnouncements.first }

    func setSceneActive(_ active: Bool) {
        isSceneActive = active
        if active {
            presentNextIfNeeded()
        } else {
            dismissTask?.cancel()
            dismissTask = nil
        }
    }

    func dismissAnnouncement() {
        dismissTask?.cancel()
        dismissTask = nil
        if !pendingAnnouncements.isEmpty { pendingAnnouncements.removeFirst() }
        presentNextIfNeeded()
    }

    private func presentNextIfNeeded() {
        guard let current = currentAnnouncement, isSceneActive, dismissTask == nil else { return }
        if announcedIDs.insert(current.id).inserted {
            AccessibilityNotification.Announcement("Достижение получено: \(current.title)").post()
        }
        let duration = displayDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismissAnnouncement()
        }
    }
}
