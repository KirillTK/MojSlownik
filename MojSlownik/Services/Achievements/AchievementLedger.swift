import Foundation

enum PracticeMode: String, Codable {
    case flashcards, quiz, listening
}

enum AchievementEvent: Equatable {
    case answer(mode: PracticeMode, isCorrect: Bool)
    case quizFinished(correct: Int, total: Int)

    /// `scoreAfter` includes this answer. The finish event is emitted only for the last question.
    static func quizAnswer(index: Int, count: Int, scoreAfter: Int, isCorrect: Bool) -> [AchievementEvent] {
        var events: [AchievementEvent] = [.answer(mode: .quiz, isCorrect: isCorrect)]
        if count > 0, index >= 0, index == count - 1 {
            events.append(.quizFinished(correct: scoreAfter, total: count))
        }
        return events
    }
}

/// Lifetime practice counters for events the app does not otherwise keep.
struct AchievementLedger: Codable, Equatable {
    var totalAnswers = 0
    var correctAnswers = 0
    var listeningCorrect = 0
    var perfectQuizzes = 0
    var currentStreakDays = 0
    var longestStreakDays = 0
    var lastStudyDay: Date?

    init() {}

    // decodeIfPresent keeps old payloads readable when fields are added later.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalAnswers = try container.decodeIfPresent(Int.self, forKey: .totalAnswers) ?? 0
        correctAnswers = try container.decodeIfPresent(Int.self, forKey: .correctAnswers) ?? 0
        listeningCorrect = try container.decodeIfPresent(Int.self, forKey: .listeningCorrect) ?? 0
        perfectQuizzes = try container.decodeIfPresent(Int.self, forKey: .perfectQuizzes) ?? 0
        currentStreakDays = try container.decodeIfPresent(Int.self, forKey: .currentStreakDays) ?? 0
        longestStreakDays = try container.decodeIfPresent(Int.self, forKey: .longestStreakDays) ?? 0
        lastStudyDay = try container.decodeIfPresent(Date.self, forKey: .lastStudyDay)
    }

    static func isPerfectQuiz(correct: Int, total: Int) -> Bool {
        total >= 4 && correct == total
    }

    mutating func apply(_ event: AchievementEvent, now: Date, calendar: Calendar) {
        switch event {
        case .answer(let mode, let isCorrect):
            totalAnswers += 1
            if isCorrect {
                correctAnswers += 1
                if mode == .listening { listeningCorrect += 1 }
            }
            updateStreak(now: now, calendar: calendar)
        case .quizFinished(let correct, let total):
            if Self.isPerfectQuiz(correct: correct, total: total) { perfectQuizzes += 1 }
        }
    }

    private mutating func updateStreak(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        if let last = lastStudyDay.map(calendar.startOfDay(for:)) {
            if last == today { return }
            if today < last { return }
            let gap = calendar.dateComponents([.day], from: last, to: today).day
            currentStreakDays = gap == 1 ? currentStreakDays + 1 : 1
        } else {
            currentStreakDays = 1
        }
        longestStreakDays = max(longestStreakDays, currentStreakDays)
        lastStudyDay = today
    }

    var metrics: AchievementMetrics {
        AchievementMetrics([
            .totalAnswers: totalAnswers,
            .correctAnswers: correctAnswers,
            .listeningCorrect: listeningCorrect,
            .perfectQuizzes: perfectQuizzes,
            .currentStreakDays: currentStreakDays,
            .longestStreakDays: longestStreakDays
        ])
    }

    /// Display only: a streak older than yesterday is over.
    func currentStreak(now: Date, calendar: Calendar) -> Int {
        guard let last = lastStudyDay else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last),
                                           to: calendar.startOfDay(for: now)).day ?? Int.max
        return (0...1).contains(days) ? currentStreakDays : 0
    }
}
