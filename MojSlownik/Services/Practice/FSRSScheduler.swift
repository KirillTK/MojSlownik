import FSRS
import Foundation

/// The FSRS memory of a card as plain values: the only FSRS data the app stores and syncs.
/// `state` is 0 new, 1 learning, 2 review, 3 relearning (the swift-fsrs raw values).
struct FSRSMemory: Equatable, Sendable {
    var state: Int
    var stability: Double
    var difficulty: Double
    var learningStep: Int
    var lastReviewedAt: Date?

    /// A card that was never reviewed.
    static let new = FSRSMemory(state: 0, stability: 0, difficulty: 0, learningStep: 0, lastReviewedAt: nil)

    var isLearning: Bool { state == 1 || state == 3 }
}

/// The single place that talks to the swift-fsrs package (FSRS-6 default weights, fixed target
/// retention, no fuzz). App code reaches FSRS only through this wrapper (used by SRSEngine and
/// FSRSMigration); intervals are the package's own, with no post-processing.
enum FSRSScheduler {
    static let targetRetention = 0.9
    /// Passed to the package as `maximumInterval`; it may return up to two days more
    /// (see `SRSEngine.maxLibraryIntervalDays`).
    static let maxIntervalDays = SRSEngine.maxScheduledIntervalDays
    static let learningSteps = ["10m"]
    static let relearningSteps = ["10m"]
    static var weights: [Double] { FSRSDefaults.defaultWv6 }

    private static let fsrs = FSRS(parameters: FSRSParameters(
        requestRetention: targetRetention, maximumInterval: maxIntervalDays, w: FSRSDefaults.defaultWv6,
        enableFuzz: false, enableShortTerm: true, learningSteps: learningSteps,
        relearningSteps: relearningSteps))

    /// The package result for one grade, unchanged.
    struct Outcome: Equatable, Sendable {
        let memory: FSRSMemory
        let due: Date
        /// 0 while the card is (re)learning.
        let scheduledDays: Double
        /// The card's lapse counter after the review (FSRS counts Again from review state).
        let lapses: Int
        /// Whole UTC calendar days since the previous review, as the package counts them.
        let elapsedDays: Double
    }

    /// The outcome of every grade for a card in the given memory. Never throws: corrupt memory
    /// falls back to S = D = 0 in the same state, then to a new card.
    static func outcomes(memory: FSRSMemory, due: Date, intervalDays: Double, lapses: Int,
                         now: Date) -> [ReviewGrade: Outcome] {
        let attempts = [memory,
                        FSRSMemory(state: memory.state, stability: 0, difficulty: 0,
                                   learningStep: memory.learningStep, lastReviewedAt: memory.lastReviewedAt),
                        FSRSMemory.new]
        for attempt in attempts {
            let card = makeCard(attempt, due: due, intervalDays: intervalDays, lapses: lapses, now: now)
            guard let preview = try? fsrs.repeat(card: card, now: now) else { continue }
            var result: [ReviewGrade: Outcome] = [:]
            for grade in ReviewGrade.allCases {
                guard let item = preview[rating(for: grade)] else { continue }
                result[grade] = Outcome(memory: fsrsMemory(of: item.card), due: item.card.due,
                                        scheduledDays: item.card.scheduledDays, lapses: item.card.lapses,
                                        elapsedDays: item.log.elapsedDays)
            }
            if result.count == ReviewGrade.allCases.count { return result }
        }
        // Unreachable in practice: a new card always schedules.
        return [:]
    }

    static func review(memory: FSRSMemory, due: Date, intervalDays: Double, lapses: Int, grade: ReviewGrade,
                       now: Date) -> Outcome {
        let all = outcomes(memory: memory, due: due, intervalDays: intervalDays, lapses: lapses, now: now)
        if let outcome = all[grade] { return outcome }
        return Outcome(memory: memory, due: due, scheduledDays: intervalDays, lapses: lapses, elapsedDays: 0)
    }

    /// Whole UTC calendar days from `last` to `now` (0 when there was no review or the clock moved back).
    static func elapsedDays(since last: Date?, now: Date) -> Double {
        guard let last, last <= now else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let start = calendar.startOfDay(for: last)
        let end = calendar.startOfDay(for: now)
        return max(0, ((end.timeIntervalSince1970 - start.timeIntervalSince1970) / 86_400).rounded(.down))
    }

    /// Probability of recall now, 0 for a new card.
    static func retrievability(memory: FSRSMemory, now: Date) -> Double {
        guard memory.state != 0 else { return 0 }
        let card = makeCard(memory, due: now, intervalDays: 0, lapses: 0, now: now)
        return fsrs.getRetrievability(card: card, now: now).number
    }

    // MARK: Mapping

    private static func makeCard(_ memory: FSRSMemory, due: Date, intervalDays: Double, lapses: Int,
                                 now: Date) -> Card {
        let state = CardState(rawValue: memory.state) ?? .new
        return Card(due: due, stability: memory.stability, difficulty: memory.difficulty, elapsedDays: 0,
                    scheduledDays: intervalDays, learningSteps: memory.learningStep,
                    reps: state == .new ? 0 : 1, lapses: lapses, state: state,
                    lastReview: memory.lastReviewedAt.map { min($0, now) })
    }

    private static func fsrsMemory(of card: Card) -> FSRSMemory {
        FSRSMemory(state: card.state.rawValue, stability: card.stability, difficulty: card.difficulty,
                   learningStep: card.learningSteps, lastReviewedAt: card.lastReview)
    }

    private static func rating(for grade: ReviewGrade) -> Rating {
        switch grade {
        case .again: .again
        case .hard: .hard
        case .good: .good
        case .easy: .easy
        }
    }
}
