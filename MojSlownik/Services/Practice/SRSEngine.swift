import Foundation
import SwiftUI

enum ReviewGrade: String, CaseIterable {
    case again, hard, good, easy

    var title: String {
        switch self {
        case .again: String(localized: "Again")
        case .hard: String(localized: "Hard")
        case .good: String(localized: "Good")
        case .easy: String(localized: "Easy")
        }
    }

    var color: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .appAccent
        case .easy: .green
        }
    }
}

/// The scheduling fields of a word as a value, so the next state can be computed without mutating.
struct SRSState: Equatable {
    /// Legacy SM-2 ease: no longer written, read by the FSRS conversion.
    var easeFactor: Double
    var intervalDays: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewGradeRawValue: String?
    var lapseCount: Int
    var fsrsState: Int?
    var fsrsStability: Double?
    var fsrsDifficulty: Double?
    var fsrsLearningStep: Int
    var fsrsLastReviewedAt: Date?

    init(easeFactor: Double, intervalDays: Double, repetitions: Int, dueDate: Date,
         lastReviewGradeRawValue: String?, lapseCount: Int, fsrsState: Int? = nil,
         fsrsStability: Double? = nil, fsrsDifficulty: Double? = nil, fsrsLearningStep: Int = 0,
         fsrsLastReviewedAt: Date? = nil) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewGradeRawValue = lastReviewGradeRawValue
        self.lapseCount = lapseCount
        self.fsrsState = fsrsState
        self.fsrsStability = fsrsStability
        self.fsrsDifficulty = fsrsDifficulty
        self.fsrsLearningStep = fsrsLearningStep
        self.fsrsLastReviewedAt = fsrsLastReviewedAt
    }

    init(word: Word) {
        self.init(easeFactor: word.easeFactor, intervalDays: word.intervalDays,
                  repetitions: word.repetitions, dueDate: word.dueDate,
                  lastReviewGradeRawValue: word.lastReviewGradeRawValue, lapseCount: word.lapseCount,
                  fsrsState: word.fsrsStateRawValue, fsrsStability: word.fsrsStability,
                  fsrsDifficulty: word.fsrsDifficulty, fsrsLearningStep: word.fsrsLearningStep,
                  fsrsLastReviewedAt: word.fsrsLastReviewedAt)
    }

    /// The stored FSRS memory, nil when the block is incomplete (it still has to be derived).
    var memory: FSRSMemory? {
        get {
            guard let fsrsState, let fsrsStability, let fsrsDifficulty else { return nil }
            return FSRSMemory(state: fsrsState, stability: fsrsStability, difficulty: fsrsDifficulty,
                              learningStep: fsrsLearningStep, lastReviewedAt: fsrsLastReviewedAt)
        }
        set {
            fsrsState = newValue?.state
            fsrsStability = newValue?.stability
            fsrsDifficulty = newValue?.difficulty
            fsrsLearningStep = newValue?.learningStep ?? 0
            fsrsLastReviewedAt = newValue?.lastReviewedAt
        }
    }

    func write(to word: Word) {
        word.easeFactor = easeFactor
        word.intervalDays = intervalDays
        word.repetitions = repetitions
        word.dueDate = dueDate
        word.lastReviewGradeRawValue = lastReviewGradeRawValue
        word.lapseCount = lapseCount
        writeFSRS(to: word)
    }

    /// Only the FSRS block (the conversion and the pull use it; schedule fields stay).
    func writeFSRS(to word: Word) {
        word.fsrsStateRawValue = fsrsState
        word.fsrsStability = fsrsStability
        word.fsrsDifficulty = fsrsDifficulty
        word.fsrsLearningStep = fsrsLearningStep
        word.fsrsLastReviewedAt = fsrsLastReviewedAt
    }
}

/// One review as a value: the schedule before and after, the FSRS memory on both sides and the
/// whole UTC days since the previous review. The review log is built from it.
struct ReviewTransition: Equatable {
    let before: SRSState
    let after: SRSState
    let beforeMemory: FSRSMemory
    let afterMemory: FSRSMemory
    let elapsedDays: Double
}

/// The delay until the next review, for the grade buttons.
enum ScheduleDelay: Equatable {
    case minutes(Int)
    case days(Int)
}

extension ScheduleDelay {
    /// Short caption under a grade button ("10 min", "3 d").
    var caption: String {
        switch self {
        case .minutes(let count): String(localized: "\(count) min")
        case .days(let count): String(localized: "\(count) d")
        }
    }

    /// Spoken value for VoiceOver.
    var accessibilityText: String {
        switch self {
        case .minutes(let count): String(localized: "Next review in \(count) minutes")
        case .days(let count): String(localized: "Next review in \(count) days")
        }
    }
}

/// FSRS scheduling through `FSRSScheduler` (the package is never called from anywhere else).
/// After each review the fields the app still reads are written: `dueDate`, `intervalDays` (the
/// package's scheduled days, 0 while (re)learning), `repetitions` (0 after Again, else +1),
/// `lastReviewGradeRawValue`, `lapseCount` (FSRS lapses) and the FSRS memory. `easeFactor` is no
/// longer written.
enum SRSEngine {
    static let minEaseFactor = 1.3
    /// Upper bounds keep every schedule representable and inside what sync accepts
    /// (Backend/RemoteRecords.swift validates against these).
    static let maxEaseFactor = 10.0
    /// Storage/sync acceptance bound.
    static let maxIntervalDays = 36_500.0
    /// The 30-day max-interval setting, passed to FSRS as `maximumInterval`.
    static let maxScheduledIntervalDays = 30.0
    /// The longest interval the package can return with that setting: it applies the maximum
    /// before keeping Good above Hard and Easy above Good.
    static let maxLibraryIntervalDays = maxScheduledIntervalDays + 2
    /// The first (re)learning step, 10 minutes; equals `FSRSScheduler.learningSteps`.
    static let againDelay: TimeInterval = 600

    static func apply(_ grade: ReviewGrade, to word: Word, now: Date = .now) {
        next(grade, from: SRSState(word: word), now: now).write(to: word)
    }

    /// What the next review delay would be; nothing is mutated.
    static func preview(_ grade: ReviewGrade, for word: Word, now: Date = .now) -> ScheduleDelay {
        let state = next(grade, from: SRSState(word: word), now: now)
        if state.intervalDays == 0 {
            return .minutes(Int((state.dueDate.timeIntervalSince(now) / 60).rounded()))
        }
        return .days(Int(state.intervalDays))
    }

    /// Pure scheduling: the state after answering with `grade`.
    static func next(_ grade: ReviewGrade, from state: SRSState, now: Date) -> SRSState {
        transition(grade, from: state, now: now).after
    }

    /// Pure scheduling plus the FSRS memory on both sides, for the review log.
    static func transition(_ grade: ReviewGrade, from state: SRSState, now: Date) -> ReviewTransition {
        let beforeMemory = FSRSMigration.effective(state, now: now)
        let lapses = min(max(state.lapseCount, 0), 9_999)
        let outcome = FSRSScheduler.review(memory: beforeMemory, due: state.dueDate,
                                           intervalDays: state.intervalDays.isFinite ? state.intervalDays : 0,
                                           lapses: lapses, grade: grade, now: now)
        var after = state
        after.lastReviewGradeRawValue = grade.rawValue
        after.repetitions = grade == .again ? 0 : state.repetitions + 1
        after.lapseCount = lapses + max(0, outcome.lapses - lapses)
        after.intervalDays = outcome.scheduledDays
        after.dueDate = outcome.due
        after.memory = outcome.memory
        return ReviewTransition(before: state, after: after, beforeMemory: beforeMemory,
                                afterMemory: outcome.memory, elapsedDays: outcome.elapsedDays)
    }

    /// An answer that leaves the schedule alone: both sides are the current state.
    static func observation(_ state: SRSState, now: Date) -> ReviewTransition {
        let memory = FSRSMigration.effective(state, now: now)
        return ReviewTransition(before: state, after: state, beforeMemory: memory, afterMemory: memory,
                                elapsedDays: FSRSScheduler.elapsedDays(since: memory.lastReviewedAt, now: now))
    }

    /// The grade a quiz/listening answer is logged as when it does not schedule: correct = good,
    /// wrong = again, a typed soft miss = hard.
    static func wouldBeGrade(for answer: KnowledgeAnswer) -> ReviewGrade {
        switch answer {
        case .choice(let isCorrect):
            return isCorrect ? .good : .again
        case .typed(let expected, let submitted):
            let score = KnowledgeProgressService.similarity(expected: expected, submitted: submitted)
            if score == 1 { return .good }
            return score < KnowledgeProgressService.softMatchThreshold ? .again : .hard
        }
    }

    /// The grade a quiz/listening answer schedules as, or nil to leave the schedule alone.
    /// Not-due words never change (a correct answer would inflate the interval; a wrong one makes
    /// the word pending so the flashcard self-grade decides). Due: correct = Good, wrong = Again;
    /// a typed soft miss is typo-tolerant and changes nothing.
    static func practiceGrade(for answer: KnowledgeAnswer, isDue: Bool) -> ReviewGrade? {
        guard isDue else { return nil }
        switch answer {
        case .choice(let isCorrect):
            return isCorrect ? .good : .again
        case .typed(let expected, let submitted):
            let score = KnowledgeProgressService.similarity(expected: expected, submitted: submitted)
            if score == 1 { return .good }
            return score < KnowledgeProgressService.softMatchThreshold ? .again : nil
        }
    }
}
