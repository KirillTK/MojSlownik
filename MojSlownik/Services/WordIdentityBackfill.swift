import Foundation
import SwiftData
import os

/// Assigns a stable `Word.uuid` to legacy rows. It never touches `updatedAt`.
@MainActor
enum WordIdentityBackfill {
    private static let logger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")

    static func assignMissing(in context: ModelContext, rollbackOnFailure: Bool) throws -> Int {
        let words = try context.fetch(FetchDescriptor<Word>()).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            if lhs.polish != rhs.polish { return lhs.polish < rhs.polish }
            if lhs.russian != rhs.russian { return lhs.russian < rhs.russian }
            return lhs.sourceLanguageCode < rhs.sourceLanguageCode
        }
        var seen = Set<UUID>()
        var changes: [(word: Word, previous: UUID?)] = []
        for word in words {
            if let current = word.uuid, !seen.contains(current) {
                seen.insert(current)
                continue
            }
            var fresh = UUID()
            while seen.contains(fresh) { fresh = UUID() }
            changes.append((word, word.uuid))
            word.uuid = fresh
            seen.insert(fresh)
        }
        guard !changes.isEmpty else { return 0 }
        do {
            try context.save()
        } catch {
            if rollbackOnFailure {
                context.rollback()
            } else {
                for change in changes { change.word.uuid = change.previous }
            }
            throw error
        }
        return changes.count
    }

    @discardableResult
    static func run(container: ModelContainer) -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            return try assignMissing(in: context, rollbackOnFailure: true)
        } catch {
            logger.error("Word identity backfill failed: \(String(describing: error), privacy: .public)")
            return 0
        }
    }
}
