import Foundation
import Observation
import SwiftData

/// Local daily activity, separate from vocabulary and the spaced-repetition schedule.
@MainActor
@Observable
final class DailyStudyStore {
    struct Summary: Equatable {
        let completed: Int
        let remaining: Int

        var total: Int { completed + remaining }
        var fraction: Double { total == 0 ? 0 : Double(completed) / Double(total) }
    }

    struct AnswerTotals: Equatable {
        let correct: Int
        let incorrect: Int

        var total: Int { correct + incorrect }
    }

    private struct Answer: Codable {
        let wordID: PersistentIdentifier
        let isCorrect: Bool
    }

    private struct Activity: Codable {
        var day: Date
        // Decoded SwiftData IDs can be equal to live IDs but have different hashes.
        // Arrays keep equality-based matching and decode the previous Set JSON arrays.
        var completedIDs: [PersistentIdentifier] = []
        var pendingIDs: [PersistentIdentifier] = []
        // Optional additions preserve the existing v1 daily activity on upgrade.
        var quizCompletedIDs: [PersistentIdentifier]?
        var answers: [Answer]?
    }

    private static let storageKey = "dailyStudyActivity.v1"
    private let defaults: UserDefaults
    private let calendar: Calendar
    private var activity: Activity

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent, now: Date = .now) {
        self.defaults = defaults
        self.calendar = calendar
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(Activity.self, from: data),
           calendar.isDate(stored.day, inSameDayAs: now) {
            activity = stored
        } else {
            activity = Activity(day: now)
        }
    }

    func refresh(now: Date = .now) {
        guard !calendar.isDate(activity.day, inSameDayAs: now) else { return }
        activity = Activity(day: now)
        defaults.removeObject(forKey: Self.storageKey)
    }

    /// A quiz success completes today's practice without changing the SRS schedule.
    func progress(for words: [Word], now: Date = .now) -> Summary {
        let completedIDs = calendar.isDate(activity.day, inSameDayAs: now) ? activity.completedIDs : []
        let existingIDs = Set(words.map(\.persistentModelID))
        let dueIDs = Set(reviewWords(for: words, now: now).map(\.persistentModelID))
        let completed = existingIDs.filter { completedIDs.contains($0) && !dueIDs.contains($0) }.count
        return Summary(completed: completed, remaining: dueIDs.count)
    }

    /// Keep "Не помню" retries visible even during their ten-minute SRS delay.
    func reviewWords(for words: [Word], now: Date = .now) -> [Word] {
        let isToday = calendar.isDate(activity.day, inSameDayAs: now)
        let pendingIDs = isToday ? activity.pendingIDs : []
        let quizCompletedIDs = isToday ? activity.quizCompletedIDs ?? [] : []
        return words.filter {
            pendingIDs.contains($0.persistentModelID)
                || ($0.dueDate <= now && !quizCompletedIDs.contains($0.persistentModelID))
        }
    }

    func answerTotals(for words: [Word], now: Date = .now) -> AnswerTotals {
        guard calendar.isDate(activity.day, inSameDayAs: now) else {
            return AnswerTotals(correct: 0, incorrect: 0)
        }
        let existingIDs = words.map(\.persistentModelID)
        let answers = (activity.answers ?? []).filter { existingIDs.contains($0.wordID) }
        let correct = answers.filter(\.isCorrect).count
        return AnswerTotals(correct: correct, incorrect: answers.count - correct)
    }

    func recordQuizAnswer(wordID: PersistentIdentifier, isCorrect: Bool, now: Date = .now) throws {
        let next = nextActivity(wordID: wordID, isCorrect: isCorrect, isQuiz: true, now: now)
        let data = try JSONEncoder().encode(next)
        activity = next
        defaults.set(data, forKey: Self.storageKey)
    }

    func record(wordID: PersistentIdentifier, grade: ReviewGrade, now: Date = .now) throws {
        let next = nextActivity(wordID: wordID, isCorrect: grade != .again, isQuiz: false, now: now)
        let data = try JSONEncoder().encode(next)
        activity = next
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Save the schedule before publishing completion. Restore only this word on failure.
    func review(_ grade: ReviewGrade, to word: Word, context: ModelContext, now: Date = .now) throws {
        // Encoding is prepared first so a serialization failure cannot leave a half-recorded review.
        let next = nextActivity(wordID: word.persistentModelID, isCorrect: grade != .again, isQuiz: false, now: now)
        let data = try JSONEncoder().encode(next)
        let previous = (word.easeFactor, word.intervalDays, word.repetitions, word.dueDate)
        SRSEngine.apply(grade, to: word, now: now)
        do {
            try context.save()
        } catch {
            (word.easeFactor, word.intervalDays, word.repetitions, word.dueDate) = previous
            throw error
        }
        activity = next
        defaults.set(data, forKey: Self.storageKey)
    }

    private func nextActivity(wordID: PersistentIdentifier, isCorrect: Bool, isQuiz: Bool, now: Date) -> Activity {
        var next = calendar.isDate(activity.day, inSameDayAs: now) ? activity : Activity(day: now)
        var quizCompletedIDs = next.quizCompletedIDs ?? []
        quizCompletedIDs.removeAll { $0 == wordID }
        next.completedIDs.removeAll { $0 == wordID }
        next.pendingIDs.removeAll { $0 == wordID }
        if !isCorrect {
            next.pendingIDs.append(wordID)
        } else {
            next.completedIDs.append(wordID)
            if isQuiz { quizCompletedIDs.append(wordID) }
        }
        next.quizCompletedIDs = quizCompletedIDs
        var answers = next.answers ?? []
        answers.append(Answer(wordID: wordID, isCorrect: isCorrect))
        next.answers = answers
        return next
    }
}
