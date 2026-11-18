import Foundation
import SwiftUI

enum ReviewGrade: String, CaseIterable {
    case again, hard, good, easy

    var title: String {
        switch self {
        case .again: "Не помню"
        case .hard: "Трудно"
        case .good: "Хорошо"
        case .easy: "Легко"
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

/// Упрощённый SM-2 (как в Anki): каждый ответ двигает интервал и дату следующего показа.
enum SRSEngine {
    static let minEaseFactor = 1.3
    /// Upper bounds keep every schedule representable and inside what sync accepts
    /// (Backend/RemoteRecords.swift validates against these): 100 years is "learned".
    static let maxEaseFactor = 10.0
    static let maxIntervalDays = 36_500.0

    static func apply(_ grade: ReviewGrade, to word: Word, now: Date = .now) {
        schedule(grade, word: word, now: now)
        word.easeFactor = min(maxEaseFactor, word.easeFactor)
        if word.intervalDays > maxIntervalDays {
            word.intervalDays = maxIntervalDays
            word.dueDate = now.addingTimeInterval(maxIntervalDays * 86_400)
        }
    }

    private static func schedule(_ grade: ReviewGrade, word: Word, now: Date) {
        word.lastReviewGradeRawValue = grade.rawValue
        switch grade {
        case .again:
            word.repetitions = 0
            word.easeFactor = max(minEaseFactor, word.easeFactor - 0.2)
            word.intervalDays = 0
            word.dueDate = now.addingTimeInterval(10 * 60) // показать ещё раз через 10 минут

        case .hard:
            word.repetitions += 1
            word.easeFactor = max(minEaseFactor, word.easeFactor - 0.15)
            word.intervalDays = max(1, (word.intervalDays * 1.2).rounded())
            word.dueDate = now.addingTimeInterval(word.intervalDays * 86_400)

        case .good:
            word.repetitions += 1
            switch word.repetitions {
            case 1: word.intervalDays = 1
            case 2: word.intervalDays = 3
            default: word.intervalDays = max(1, (word.intervalDays * word.easeFactor).rounded())
            }
            word.dueDate = now.addingTimeInterval(word.intervalDays * 86_400)

        case .easy:
            word.repetitions += 1
            word.easeFactor += 0.15
            let base = word.intervalDays == 0 ? 2 : word.intervalDays
            word.intervalDays = max(2, (base * word.easeFactor * 1.3).rounded())
            word.dueDate = now.addingTimeInterval(word.intervalDays * 86_400)
        }
    }
}
