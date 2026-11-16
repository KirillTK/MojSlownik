import Foundation
import Observation
import SwiftUI

/// App-scoped achievements state: unlock persistence, practice ledger and banner presentation.
@MainActor
@Observable
final class AchievementStore {
    private struct Stored: Codable {
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

    private static let storageKey = "achievements.v1"
    private let defaults: UserDefaults
    private let calendar: Calendar
    private var didInitialSync: Bool

    let catalog: [AchievementDefinition]
    let displayDuration: Duration
    private(set) var unlocked: [String: Date]
    private(set) var ledger: AchievementLedger
    private(set) var pendingAnnouncements: [AchievementDefinition] = []

    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private(set) var announcedIDs: Set<String> = []
    @ObservationIgnored private var isSceneActive = true

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent,
         catalog: [AchievementDefinition] = AchievementCatalog.all,
         displayDuration: Duration = .seconds(4)) {
        self.defaults = defaults
        self.calendar = calendar
        self.catalog = catalog
        self.displayDuration = displayDuration
        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? Stored()
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

    func sync(vocabulary: AchievementMetrics, now: Date = .now) {
        let metrics = vocabulary.merging(ledger.metrics)
        let ids = AchievementEvaluator.newlyUnlocked(catalog: catalog, metrics: metrics,
                                                     unlocked: Set(unlocked.keys))
        guard !ids.isEmpty || !didInitialSync else { return }
        for id in ids { unlocked[id] = now }
        let announce = didInitialSync
        didInitialSync = true
        persist()
        if announce {
            pendingAnnouncements.append(contentsOf: ids.compactMap { id in catalog.first { $0.id == id } })
            presentNextIfNeeded()
        }
    }

    private func persist() {
        let stored = Stored(unlocked: unlocked, ledger: ledger, didInitialSync: didInitialSync)
        do {
            defaults.set(try JSONEncoder().encode(stored), forKey: Self.storageKey)
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
