import Foundation

/// Learned / learning / new buckets, hard words and the review forecast for a set of words.
/// Pure: callers pass the already workspace- and folder-scoped words.
enum StudyProgress {
    enum LearningStage: Equatable {
        case new, learning, learned
    }

    /// "Learned" = the word is reviewed every 21 days or less often (Anki "mature"). `intervalDays` is
    /// the FSRS scheduled interval (up to `SRSEngine.maxLibraryIntervalDays`), 0 while (re)learning.
    static let learnedThresholdDays = 21.0
    /// Forgotten this many times (and not yet learned) = a hard word (leech).
    static let hardWordLapseThreshold = 6

    struct Breakdown: Equatable {
        var new = 0
        var learning = 0
        var learned = 0

        var total: Int { new + learning + learned }
    }

    struct Forecast: Equatable {
        /// Not-due words coming up before the end of tomorrow.
        var tomorrow = 0
        /// Not-due words coming up within the next week (includes `tomorrow`).
        var week = 0
    }

    static func stage(of word: Word) -> LearningStage {
        if word.intervalDays >= learnedThresholdDays { return .learned }
        if word.repetitions == 0, word.lastReviewGradeRawValue == nil { return .new }
        return .learning
    }

    static func breakdown(_ words: [Word]) -> Breakdown {
        var result = Breakdown()
        for word in words where word.isActive {
            switch stage(of: word) {
            case .new: result.new += 1
            case .learning: result.learning += 1
            case .learned: result.learned += 1
            }
        }
        return result
    }

    static func isHardWord(_ word: Word) -> Bool {
        word.lapseCount >= hardWordLapseThreshold && word.intervalDays < learnedThresholdDays
    }

    static func hardWords(_ words: [Word]) -> [Word] {
        words.filter { $0.isActive && isHardWord($0) }
    }

    /// Words not due yet: "tomorrow" = due before the end of tomorrow, "week" = before the start of
    /// day 8. Words already due belong to the Today hero.
    static func forecast(_ words: [Word], now: Date = .now, calendar: Calendar = .autoupdatingCurrent) -> Forecast {
        let startOfToday = calendar.startOfDay(for: now)
        guard let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
              let endOfWeek = calendar.date(byAdding: .day, value: 8, to: startOfToday) else {
            return Forecast()
        }
        var result = Forecast()
        for word in words where word.isActive && word.dueDate > now {
            if word.dueDate < endOfTomorrow { result.tomorrow += 1 }
            if word.dueDate < endOfWeek { result.week += 1 }
        }
        return result
    }
}
