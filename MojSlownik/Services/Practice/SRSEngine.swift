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
    var easeFactor: Double
    var intervalDays: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewGradeRawValue: String?
    var lapseCount: Int

    init(easeFactor: Double, intervalDays: Double, repetitions: Int, dueDate: Date,
         lastReviewGradeRawValue: String?, lapseCount: Int) {
        self.easeFactor = easeFactor
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.dueDate = dueDate
        self.lastReviewGradeRawValue = lastReviewGradeRawValue
        self.lapseCount = lapseCount
    }

    init(word: Word) {
        self.init(easeFactor: word.easeFactor, intervalDays: word.intervalDays,
                  repetitions: word.repetitions, dueDate: word.dueDate,
                  lastReviewGradeRawValue: word.lastReviewGradeRawValue, lapseCount: word.lapseCount)
    }

    func write(to word: Word) {
        word.easeFactor = easeFactor
        word.intervalDays = intervalDays
        word.repetitions = repetitions
        word.dueDate = dueDate
        word.lastReviewGradeRawValue = lastReviewGradeRawValue
        word.lapseCount = lapseCount
    }
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

/// Simplified SM-2 (as in Anki): every answer moves the interval and the next review date.
/// Intervals are clamped to `maxScheduledIntervalDays`, so learned words return about monthly.
enum SRSEngine {
    static let minEaseFactor = 1.3
    /// Upper bounds keep every schedule representable and inside what sync accepts
    /// (Backend/RemoteRecords.swift validates against these).
    static let maxEaseFactor = 10.0
    /// Storage/sync acceptance bound (server rows from older versions may hold long intervals).
    static let maxIntervalDays = 36_500.0
    /// The longest interval this app schedules.
    static let maxScheduledIntervalDays = 30.0
    static let againDelay: TimeInterval = 600

    static func apply(_ grade: ReviewGrade, to word: Word, now: Date = .now) {
        next(grade, from: SRSState(word: word), now: now).write(to: word)
    }

    /// What the next review delay would be; nothing is mutated.
    static func preview(_ grade: ReviewGrade, for word: Word, now: Date = .now) -> ScheduleDelay {
        let state = next(grade, from: SRSState(word: word), now: now)
        if state.intervalDays == 0 { return .minutes(Int((againDelay / 60).rounded())) }
        return .days(Int(state.intervalDays))
    }

    /// Pure scheduling. Hard <= Good < Easy below the cap, and Hard < Good once the word has an
    /// interval, so a better answer never schedules sooner.
    static func next(_ grade: ReviewGrade, from state: SRSState, now: Date) -> SRSState {
        var result = state
        result.lastReviewGradeRawValue = grade.rawValue
        let interval = state.intervalDays
        let ease = state.easeFactor

        if grade == .again {
            // A lapse is a failure after a success since the last failure.
            if state.repetitions > 0 { result.lapseCount = min(state.lapseCount, 9_999) + 1 }
            result.repetitions = 0
            result.easeFactor = min(maxEaseFactor, max(minEaseFactor, ease - 0.2))
            result.intervalDays = 0
            result.dueDate = now.addingTimeInterval(againDelay)
            return result
        }

        let hard = max(1, (interval * 1.2).rounded())
        let goodStep: Double = switch state.repetitions + 1 {
        case 1: 1
        case 2: 3
        default: (interval * ease).rounded()
        }
        let good = max(goodStep, (interval * ease).rounded(), interval >= 1 ? hard + 1 : hard)
        let easy = max(2, ((interval == 0 ? 2 : interval) * (ease + 0.15) * 1.3).rounded(), good + 1)

        result.repetitions += 1
        switch grade {
        case .again:
            break // handled by the early return above; kept for exhaustiveness
        case .hard:
            result.easeFactor = max(minEaseFactor, ease - 0.15)
            result.intervalDays = hard
        case .good:
            result.intervalDays = good
        case .easy:
            result.easeFactor = ease + 0.15
            result.intervalDays = easy
        }
        result.easeFactor = min(maxEaseFactor, max(minEaseFactor, result.easeFactor))
        result.intervalDays = min(maxScheduledIntervalDays, result.intervalDays)
        result.dueDate = now.addingTimeInterval(result.intervalDays * 86_400)
        return result
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
