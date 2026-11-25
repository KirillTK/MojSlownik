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
    private let changeSignal: LocalChangeSignal?

    convenience init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent,
                     now: Date = .now) {
        self.init(repository: UserDefaultsDailyActivityRepository(defaults: defaults),
                  calendar: calendar, now: now)
    }

    init(repository: any DailyActivityRepository, calendar: Calendar = .autoupdatingCurrent, now: Date = .now,
         logger: (any AppLogging)? = nil, changeSignal: LocalChangeSignal? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.changeSignal = changeSignal
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

    /// Today's practice. A word answered correctly today (a flashcard Hard/Good/Easy or a correct
    /// quiz/listening answer) stays completed for the rest of the local day, even if FSRS makes it
    /// due again sooner, so the bar never goes backwards. An "Again" (forgot) or wrong answer keeps the
    /// word pending (remaining). A correct quiz answer on a due word also schedules like Good; on a
    /// not-due word the schedule is left alone.
    func progress(for words: [Word], now: Date = .now) -> Summary {
        let words = words.filter(\.isActive)
        let isToday = calendar.isDate(activity.day, inSameDayAs: now)
        let completedIDs = isToday ? activity.completedIDs : []
        let pendingIDs = isToday ? activity.pendingIDs : []
        let remaining = reviewWords(for: words, now: now).count
        let completed = words.filter {
            completedIDs.contains($0.persistentModelID) && !pendingIDs.contains($0.persistentModelID)
        }.count
        return Summary(completed: completed, remaining: remaining)
    }

    /// Pending words (kept visible during their ten-minute FSRS (re)learning step) plus due words
    /// not already answered correctly today.
    func reviewWords(for words: [Word], now: Date = .now) -> [Word] {
        let words = words.filter(\.isActive)
        let isToday = calendar.isDate(activity.day, inSameDayAs: now)
        let pendingIDs = isToday ? activity.pendingIDs : []
        let doneIDs = isToday ? Set(activity.completedIDs).union(activity.quizCompletedIDs ?? []) : []
        return words.filter {
            pendingIDs.contains($0.persistentModelID)
                || ($0.dueDate <= now && !doneIDs.contains($0.persistentModelID))
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
        let previousSRS = SRSState(word: word)
        let previousUpdatedAt = word.updatedAt
        let isDue = word.dueDate <= now
        let assessment = KnowledgeProgressService.apply(answer, to: word)
        let entry: ReviewLogEntry?
        if let grade = SRSEngine.practiceGrade(for: answer, isDue: isDue) {
            let transition = SRSEngine.transition(grade, from: previousSRS, now: now)
            transition.after.write(to: word)
            entry = makeLogEntry(for: word, mode: mode, transition: transition, rating: grade,
                                 affectsSchedule: true, now: now)
        } else {
            entry = makeLogEntry(for: word, mode: mode,
                                 transition: SRSEngine.observation(previousSRS, now: now),
                                 rating: SRSEngine.wouldBeGrade(for: answer), affectsSchedule: false, now: now)
        }
        word.updatedAt = now
        if let entry { context.insert(entry) }
        do {
            try logger.logged("word_progress.save") { try context.save() }
        } catch {
            (word.knowledgeTier, word.consecutiveSoftMisses) = previous
            previousSRS.write(to: word)
            word.updatedAt = previousUpdatedAt
            if let entry { discard(entry, in: context) }
            throw error
        }
        activity = next
        commit()
        logAnswer(mode, isCorrect: isCorrect)
        changeSignal?.notify()
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
        let previous = SRSState(word: word)
        let previousKnowledge = (word.knowledgeTier, word.consecutiveSoftMisses)
        let previousUpdatedAt = word.updatedAt
        KnowledgeProgressService.setTier(from: grade, on: word)
        let transition = SRSEngine.transition(grade, from: previous, now: now)
        transition.after.write(to: word)
        let entry = makeLogEntry(for: word, mode: .flashcards, transition: transition, rating: grade,
                                 affectsSchedule: true, now: now)
        word.updatedAt = now
        if let entry { context.insert(entry) }
        do {
            try logger.logged("word_progress.save") { try context.save() }
        } catch {
            previous.write(to: word)
            (word.knowledgeTier, word.consecutiveSoftMisses) = previousKnowledge
            word.updatedAt = previousUpdatedAt
            if let entry { discard(entry, in: context) }
            throw error
        }
        activity = next
        commit()
        logAnswer(.flashcards, isCorrect: grade != .again, grade: grade)
        changeSignal?.notify()
    }

    /// Drops an entry whose save failed. Nothing was written to the store; the delete also takes
    /// the pending insert out of the context so a later save cannot persist it. (On iOS 26 the
    /// same context may still return the dropped object from a fetch until it is reloaded; other
    /// contexts, which sync and the views use, never see it.)
    private func discard(_ entry: ReviewLogEntry, in context: ModelContext) {
        context.delete(entry)
        context.processPendingChanges()
    }

    /// The review-log entry saved together with the word; nil for a word without a sync uuid.
    private func makeLogEntry(for word: Word, mode: PracticeMode, transition: ReviewTransition,
                              rating: ReviewGrade, affectsSchedule: Bool, now: Date) -> ReviewLogEntry? {
        guard let wordID = word.uuid else { return nil }
        return ReviewLogEntry(wordID: wordID, workspaceID: word.effectiveWorkspaceID, mode: mode,
                              transition: transition, rating: rating, affectsSchedule: affectsSchedule,
                              reviewedAt: now)
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
