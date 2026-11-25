import Foundation
import os
import SwiftData

/// Clamps schedules longer than `SRSEngine.maxLibraryIntervalDays` (set by older versions, or
/// pulled from the server) so well-learned words come back about monthly. A safety net for corrupt
/// or foreign rows: it never shortens a schedule FSRS produced.
///
/// Local-only repair like `WordIdentityBackfill`: it rewrites SRS fields and never touches
/// `updatedAt`/`serverUpdatedAt`, so it never makes a row dirty. A dirty normalized row would win
/// the merge over a newer remote edit and then overwrite the server.
@MainActor
enum ScheduleNormalizer {
    private static let logger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

    /// The clamped state, or nil when nothing needs to change. Idempotent.
    nonisolated static func normalized(_ state: SRSState, uuid: UUID?, now: Date) -> SRSState? {
        let cap = SRSEngine.maxLibraryIntervalDays
        let day: TimeInterval = 86_400
        let intervalIsFinite = state.intervalDays.isFinite
        let needsClamp = !intervalIsFinite || state.intervalDays > cap
            || state.dueDate > now.addingTimeInterval((cap + 1) * day)
        guard needsClamp else { return nil }

        var result = state
        result.intervalDays = intervalIsFinite ? min(state.intervalDays, cap) : cap
        // An already overdue word keeps its due date: it is due anyway.
        if state.dueDate <= now { return result == state ? nil : result }

        let review = intervalIsFinite
            ? min(now, state.dueDate.addingTimeInterval(-state.intervalDays * day))
            : now
        var due = min(state.dueDate, review.addingTimeInterval(cap * day))
        if due < now {
            // Spread what the clamp moved into the past over the next week, stable per word.
            let offset = Int(uuid?.uuid.0 ?? 0) % 7
            due = now.addingTimeInterval(Double(offset) * day)
        }
        result.dueDate = due
        return result
    }

    /// Normalizes every active word; one save. Returns how many words changed.
    static func normalize(in context: ModelContext, now: Date = .now) throws -> Int {
        let words = try context.fetch(FetchDescriptor<Word>()).filter(\.isActive)
        var changed = 0
        for word in words {
            guard let fixed = normalized(SRSState(word: word), uuid: word.uuid, now: now) else { continue }
            fixed.write(to: word)
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
            return try normalize(in: ModelContext(container), now: now)
        } catch {
            logger.error("Schedule normalization failed: \(String(describing: type(of: error)), privacy: .public)")
            return 0
        }
    }
}
