import Foundation
import os
import SwiftData

/// Converts SM-2 progress to FSRS memory once and deterministically (a port of fsrs-rs
/// `memory_state_from_sm2`, with the SM-2 retention equal to the target retention).
///
/// Local-only repair like `ScheduleNormalizer`: it writes only the FSRS fields and never touches
/// `dueDate`, `intervalDays`, `repetitions`, `lapseCount`, `updatedAt` or `serverUpdatedAt`, so
/// no due date moves and no row becomes dirty. The result depends only on synced fields, so every
/// device derives the same memory.
@MainActor
enum FSRSMigration {
    private static let logger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

    nonisolated static let maxStability = 36_500.0
    nonisolated static let minStability = 0.001
    nonisolated static let maxLearningStep = 100

    /// The FSRS memory derived from the SM-2 fields of `state`.
    nonisolated static func derive(from state: SRSState, now: Date) -> FSRSMemory {
        if state.intervalDays == 0, state.repetitions == 0, state.lastReviewGradeRawValue == nil {
            return .new
        }
        let intervalIsFinite = state.intervalDays.isFinite
        if intervalIsFinite, state.intervalDays < 1 {
            // An Again-reset word: (re)learning without memory; the next review initialises it.
            return FSRSMemory(state: state.lapseCount > 0 ? 3 : 1, stability: 0, difficulty: 0, learningStep: 0,
                              lastReviewedAt: min(now, state.dueDate.addingTimeInterval(-SRSEngine.againDelay)))
        }
        let interval = intervalIsFinite
            ? min(state.intervalDays, SRSEngine.maxLibraryIntervalDays) : 1
        let ease = state.easeFactor.isFinite ? state.easeFactor : 2.5
        let w = FSRSScheduler.weights
        let stability = interval
        let denominator = exp(w[8]) * pow(stability, -w[9]) * (exp(0.1 * w[10]) - 1)
        let difficulty = min(10, max(1, 11 - (ease - 1) / denominator))
        return FSRSMemory(state: 2, stability: stability, difficulty: difficulty, learningStep: 0,
                          lastReviewedAt: min(now, state.dueDate.addingTimeInterval(-interval * 86_400)))
    }

    /// Every field present and in range for its state.
    nonisolated static func isValid(_ memory: FSRSMemory) -> Bool {
        guard (0...3).contains(memory.state), (0...maxLearningStep).contains(memory.learningStep),
              memory.stability.isFinite, memory.difficulty.isFinite else { return false }
        // A card that was reviewed needs its last review: without it the package counts 0 elapsed days.
        guard memory.state == 0 || memory.lastReviewedAt != nil else { return false }
        let zero = memory.stability == 0 && memory.difficulty == 0
        let inRange = (minStability...maxStability).contains(memory.stability)
            && (1.0...10.0).contains(memory.difficulty)
        switch memory.state {
        case 0: return zero
        case 1, 3: return zero || inRange
        default: return inRange
        }
    }

    /// The stored memory when valid, otherwise one derived from the SM-2 fields.
    nonisolated static func effective(_ state: SRSState, now: Date) -> FSRSMemory {
        if let stored = state.memory, isValid(stored) { return stored }
        return derive(from: state, now: now)
    }

    /// `state` with a derived FSRS block, or nil when it already holds a valid one. Idempotent.
    nonisolated static func migrated(_ state: SRSState, now: Date) -> SRSState? {
        if let stored = state.memory, isValid(stored) { return nil }
        var result = state
        result.memory = derive(from: state, now: now)
        return result
    }

    /// Fills the FSRS state of every active word without a valid one; one save. Returns how many
    /// words changed.
    static func migrate(in context: ModelContext, now: Date = .now) throws -> Int {
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        var changed = 0
        for word in words {
            guard let fixed = migrated(SRSState(word: word), now: now) else { continue }
            fixed.writeFSRS(to: word)
            changed += 1
        }
        guard changed > 0 else { return 0 }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return changed
    }

    @discardableResult
    static func run(container: ModelContainer, now: Date = .now) -> Int {
        do {
            return try migrate(in: ModelContext(container), now: now)
        } catch {
            logger.error("FSRS migration failed: \(String(describing: type(of: error)), privacy: .public)")
            return 0
        }
    }
}
