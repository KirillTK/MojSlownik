import Foundation
import SwiftUI

enum ReviewGrade: CaseIterable {
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
    static func apply(_ grade: ReviewGrade, to word: Word, now: Date = .now) {
        switch grade {
        case .again:
            word.repetitions = 0
            word.easeFactor = max(1.3, word.easeFactor - 0.2)
            word.intervalDays = 0
            word.dueDate = now.addingTimeInterval(10 * 60) // показать ещё раз через 10 минут

        case .hard:
            word.repetitions += 1
            word.easeFactor = max(1.3, word.easeFactor - 0.15)
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
