import Foundation
import SwiftData

/// One practice answer, append-only, mirroring `public.review_logs`. No relationship to `Word`:
/// entries outlive soft-deleted words, and `wordID` is the word's sync uuid. `uploadedAt == nil`
/// means not yet uploaded to the linked account.
@Model
final class ReviewLogEntry {
    var id: UUID = UUID()
    var wordID: UUID
    var workspaceID: UUID
    var reviewedAt: Date
    var ratingRawValue: String
    var modeRawValue: String
    /// False for answers that left the schedule alone (word not due, typed soft miss).
    var affectsSchedule: Bool = true
    var elapsedDays: Double = 0
    var intervalDaysBefore: Double = 0
    var intervalDaysAfter: Double = 0
    var dueBefore: Date
    var dueAfter: Date
    var stateBefore: Int = 0
    var stateAfter: Int = 0
    var stabilityBefore: Double = 0
    var stabilityAfter: Double = 0
    var difficultyBefore: Double = 0
    var difficultyAfter: Double = 0
    var lastReviewedAtBefore: Date? = nil
    var uploadedAt: Date? = nil

    init(wordID: UUID, workspaceID: UUID, mode: PracticeMode, transition: ReviewTransition,
         rating: ReviewGrade, affectsSchedule: Bool, reviewedAt: Date) {
        self.wordID = wordID
        self.workspaceID = workspaceID
        self.reviewedAt = reviewedAt
        self.ratingRawValue = rating.rawValue
        self.modeRawValue = mode.rawValue
        self.affectsSchedule = affectsSchedule
        self.elapsedDays = transition.elapsedDays
        self.intervalDaysBefore = transition.before.intervalDays
        self.intervalDaysAfter = transition.after.intervalDays
        self.dueBefore = transition.before.dueDate
        self.dueAfter = transition.after.dueDate
        self.stateBefore = transition.beforeMemory.state
        self.stateAfter = transition.afterMemory.state
        self.stabilityBefore = transition.beforeMemory.stability
        self.stabilityAfter = transition.afterMemory.stability
        self.difficultyBefore = transition.beforeMemory.difficulty
        self.difficultyAfter = transition.afterMemory.difficulty
        self.lastReviewedAtBefore = transition.beforeMemory.lastReviewedAt
    }
}
