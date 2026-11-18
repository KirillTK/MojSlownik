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

    private let repository: any DailyActivityRepository
    private let calendar: Calendar
    private let logger: any AppLogging
    private var activity: DailyActivity

    convenience init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent,
                     now: Date = .now) {
        self.init(repository: UserDefaultsDailyActivityRepository(defaults: defaults),
                  calendar: calendar, now: now)
    }

    init(repository: any DailyActivityRepository, calendar: Calendar = .autoupdatingCurrent, now: Date = .now,
         logger: (any AppLogging)? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.logger = logger
        self.repository = LoggingDailyActivityRepository(repository, logger: logger)
        self.calendar = calendar
        if let stored = repository.load(), calendar.isDate(stored.day, inSameDayAs: now) {
            activity = stored
        } else {
            activity = DailyActivity(day: now)
        }
    }

    func refresh(now: Date = .now) {
        guard !calendar.isDate(activity.day, inSameDayAs: now) else { return }
        activity = DailyActivity(day: now)
        repository.clear()
    }

    /// A quiz success completes today's practice without changing the SRS schedule.
    func progress(for words: [Word], now: Date = .now) -> Summary {
        let words = words.filter(\.isActive)
        let completedIDs = calendar.isDate(activity.day, inSameDayAs: now) ? activity.completedIDs : []
        let existingIDs = Set(words.map(\.persistentModelID))
        let dueIDs = Set(reviewWords(for: words, now: now).map(\.persistentModelID))
        let completed = existingIDs.filter { completedIDs.contains($0) && !dueIDs.contains($0) }.count
        return Summary(completed: completed, remaining: dueIDs.count)
    }

    /// Keep "Не помню" retries visible even during their ten-minute SRS delay.
    func reviewWords(for words: [Word], now: Date = .now) -> [Word] {
        let words = words.filter(\.isActive)
        let isToday = calendar.isDate(activity.day, inSameDayAs: now)
        let pendingIDs = isToday ? activity.pendingIDs : []
        let quizCompletedIDs = isToday ? activity.quizCompletedIDs ?? [] : []
        return words.filter {
            pendingIDs.contains($0.persistentModelID)
                || ($0.dueDate <= now && !quizCompletedIDs.contains($0.persistentModelID))
        }
    }

    func answerTotals(for words: [Word], now: Date = .now) -> AnswerTotals {
        let words = words.filter(\.isActive)
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
        let commit = try repository.prepareSave(next)
        activity = next
        commit()
        logAnswer(.quiz, isCorrect: isCorrect)
    }

    @discardableResult
    func recordPracticeAnswer(word: Word, answer: KnowledgeAnswer, context: ModelContext,
                              mode: PracticeMode,
                              now: Date = .now) throws -> KnowledgeProgressService.Assessment {
        // Quiz and listening count toward quiz completion; derived so the two cannot disagree.
        let isQuiz = mode != .flashcards
        let isCorrect = KnowledgeProgressService.isCorrect(answer)
        let next = nextActivity(wordID: word.persistentModelID, isCorrect: isCorrect, isQuiz: isQuiz, now: now)
        let commit = try repository.prepareSave(next)
        let previous = (word.knowledgeTier, word.consecutiveSoftMisses)
        let previousUpdatedAt = word.updatedAt
        let assessment = KnowledgeProgressService.apply(answer, to: word)
        word.updatedAt = now
        do {
            try logger.logged("word_progress.save") { try context.save() }
        } catch {
            (word.knowledgeTier, word.consecutiveSoftMisses) = previous
            word.updatedAt = previousUpdatedAt
            throw error
        }
        activity = next
        commit()
        logAnswer(mode, isCorrect: isCorrect)
        return assessment
    }

    func record(wordID: PersistentIdentifier, grade: ReviewGrade, now: Date = .now) throws {
        let next = nextActivity(wordID: wordID, isCorrect: grade != .again, isQuiz: false, now: now)
        let commit = try repository.prepareSave(next)
        activity = next
        commit()
        logAnswer(.flashcards, isCorrect: grade != .again, grade: grade)
    }

    /// Save the schedule before publishing completion. Restore only this word on failure.
    func review(_ grade: ReviewGrade, to word: Word, context: ModelContext, now: Date = .now) throws {
        // Encoding is prepared first so a serialization failure cannot leave a half-recorded review.
        let next = nextActivity(wordID: word.persistentModelID, isCorrect: grade != .again, isQuiz: false, now: now)
        let commit = try repository.prepareSave(next)
        let previous = (word.easeFactor, word.intervalDays, word.repetitions, word.dueDate, word.lastReviewGradeRawValue)
        let previousKnowledge = (word.knowledgeTier, word.consecutiveSoftMisses)
        let previousUpdatedAt = word.updatedAt
        KnowledgeProgressService.setTier(from: grade, on: word)
        SRSEngine.apply(grade, to: word, now: now)
        word.updatedAt = now
        do {
            try logger.logged("word_progress.save") { try context.save() }
        } catch {
            (word.easeFactor, word.intervalDays, word.repetitions, word.dueDate, word.lastReviewGradeRawValue) = previous
            (word.knowledgeTier, word.consecutiveSoftMisses) = previousKnowledge
            word.updatedAt = previousUpdatedAt
            throw error
        }
        activity = next
        commit()
        logAnswer(.flashcards, isCorrect: grade != .again, grade: grade)
    }

    /// Practice screen and result only (never the word); listening also counts toward quiz completion.
    private func logAnswer(_ mode: PracticeMode, isCorrect: Bool, grade: ReviewGrade? = nil) {
        var properties: [LogKey: LogValue] = [.mode: .name(mode), .correct: .bool(isCorrect)]
        if let grade { properties[.grade] = .name(grade) }
        logger.log(.practiceAnswered, properties)
    }

    private func nextActivity(wordID: PersistentIdentifier, isCorrect: Bool, isQuiz: Bool, now: Date) -> DailyActivity {
        var next = calendar.isDate(activity.day, inSameDayAs: now) ? activity : DailyActivity(day: now)
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
        answers.append(DailyActivityAnswer(wordID: wordID, isCorrect: isCorrect))
        next.answers = answers
        return next
    }
}
