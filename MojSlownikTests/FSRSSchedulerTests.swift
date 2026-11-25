import FSRS
import XCTest
@testable import MojSlownik

/// Reference values are raw swift-fsrs 6.0.0 output with the app's parameters (FSRS-6 default
/// weights, retention 0.9, maximumInterval 30, no fuzz, steps 10m): the wrapper must add nothing.
final class FSRSSchedulerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    /// (minutes or days) per grade, as the captions show them.
    private enum Delay: Equatable, CustomStringConvertible {
        case minutes(Int)
        case days(Int)
        var description: String {
            switch self {
            case .minutes(let value): "\(value)m"
            case .days(let value): "\(value)d"
            }
        }
    }

    private func delays(_ outcomes: [ReviewGrade: FSRSScheduler.Outcome], at time: Date) -> [Delay] {
        ReviewGrade.allCases.map { grade in
            guard let outcome = outcomes[grade] else { return .days(-1) }
            return outcome.scheduledDays == 0
                ? .minutes(Int((outcome.due.timeIntervalSince(time) / 60).rounded()))
                : .days(Int(outcome.scheduledDays))
        }
    }

    private func converted(ease: Double, interval: Double, dueOffsetDays: Double = 0,
                           repetitions: Int = 3) -> (FSRSMemory, SRSState) {
        let state = SRSState(easeFactor: ease, intervalDays: interval, repetitions: repetitions,
                             dueDate: now.addingTimeInterval(dueOffsetDays * day),
                             lastReviewGradeRawValue: "good", lapseCount: 0)
        return (FSRSMigration.derive(from: state, now: now), state)
    }

    private func outcomes(of memory: FSRSMemory, due: Date? = nil, interval: Double = 0,
                          at time: Date? = nil) -> [ReviewGrade: FSRSScheduler.Outcome] {
        FSRSScheduler.outcomes(memory: memory, due: due ?? now, intervalDays: interval, lapses: 0, now: time ?? now)
    }

    // MARK: Reference table

    func testNewCardAndZeroMemoryLearningCards() {
        let expected: [Delay] = [.minutes(10), .minutes(15), .days(2), .days(8)]
        XCTAssertEqual(delays(outcomes(of: .new), at: now), expected)
        for state in [1, 3] {
            let memory = FSRSMemory(state: state, stability: 0, difficulty: 0, learningStep: 0, lastReviewedAt: now)
            XCTAssertEqual(delays(outcomes(of: memory), at: now), expected, "state \(state)")
        }
    }

    func testConvertedWordsMatchTheReferenceValues() {
        // The E2E hard word: E 1.3, I 1, one day overdue.
        let (hardMemory, hardState) = converted(ease: 1.3, interval: 1, dueOffsetDays: -1)
        XCTAssertEqual(delays(outcomes(of: hardMemory, due: hardState.dueDate, interval: 1), at: now),
                       [.minutes(10), .days(2), .days(3), .days(4)])
        let rows: [(Double, Double, [Delay])] = [
            (2.5, 1, [.minutes(10), .days(2), .days(3), .days(4)]),
            (2.5, 3, [.minutes(10), .days(6), .days(8), .days(11)]),
            (2.5, 10, [.minutes(10), .days(19), .days(25), .days(30)]),
            (2.5, 25, [.minutes(10), .days(30), .days(31), .days(32)]),
            (2.5, 30, [.minutes(10), .days(30), .days(31), .days(32)]),
        ]
        for (ease, interval, expected) in rows {
            let (memory, state) = converted(ease: ease, interval: interval)
            XCTAssertEqual(delays(outcomes(of: memory, due: state.dueDate, interval: interval), at: now),
                           expected, "E \(ease) I \(interval)")
        }
    }

    func testPackageIntervalsAreNotPostProcessed() throws {
        let (memory, state) = converted(ease: 2.5, interval: 25)
        let result = outcomes(of: memory, due: state.dueDate, interval: 25)
        XCTAssertEqual(try XCTUnwrap(result[.hard]).scheduledDays, 30)
        XCTAssertEqual(try XCTUnwrap(result[.good]).scheduledDays, 31)
        XCTAssertEqual(try XCTUnwrap(result[.easy]).scheduledDays, 32)
        XCTAssertEqual(try XCTUnwrap(result[.easy]).due, now.addingTimeInterval(32 * day))
        XCTAssertEqual(SRSEngine.maxLibraryIntervalDays, 32)
    }

    func testAfterAgainAndTenMinutesLater() throws {
        let rows: [(Double, Double, [Delay])] = [
            (10, 6.914, [.minutes(10), .minutes(15), .days(1), .days(2)]),
            (3, 7.657, [.minutes(10), .minutes(15), .days(1), .days(1)]),
            (25, 6.24, [.minutes(10), .minutes(15), .days(2), .days(4)]),
        ]
        for (stability, difficulty, expected) in rows {
            let review = FSRSMemory(state: 2, stability: stability, difficulty: difficulty, learningStep: 0,
                                    lastReviewedAt: now.addingTimeInterval(-stability * day))
            let again = FSRSScheduler.review(memory: review, due: now, intervalDays: stability, lapses: 0,
                                             grade: .again, now: now)
            XCTAssertEqual(again.memory.state, 3)
            XCTAssertEqual(again.lapses, 1)
            XCTAssertEqual(again.scheduledDays, 0)
            let later = now.addingTimeInterval(SRSEngine.againDelay)
            XCTAssertEqual(delays(outcomes(of: again.memory, due: again.due, at: later), at: later), expected,
                           "S \(stability)")
        }
    }

    func testNewWordHardThenFifteenMinutesLater() {
        let hard = FSRSScheduler.review(memory: .new, due: now, intervalDays: 0, lapses: 0, grade: .hard, now: now)
        XCTAssertEqual(hard.memory.state, 1)
        let later = now.addingTimeInterval(900)
        XCTAssertEqual(delays(outcomes(of: hard.memory, due: hard.due, at: later), at: later),
                       [.minutes(10), .minutes(15), .days(1), .days(2)])
    }

    // MARK: Parameters and the wrapper

    func testParametersAreTheChosenOnes() {
        XCTAssertEqual(FSRSScheduler.targetRetention, 0.9)
        XCTAssertEqual(FSRSScheduler.maxIntervalDays, 30)
        XCTAssertEqual(FSRSScheduler.maxIntervalDays, SRSEngine.maxScheduledIntervalDays)
        XCTAssertEqual(FSRSScheduler.weights, FSRSDefaults.defaultWv6)
        XCTAssertEqual(FSRSScheduler.weights.count, 21)
        XCTAssertEqual(FSRSScheduler.learningSteps, ["10m"])
        XCTAssertEqual(FSRSScheduler.relearningSteps, ["10m"])
        XCTAssertEqual(SRSEngine.againDelay, 600, "the 10m step")
    }

    /// The wrapper returns the package's own result: a direct call agrees for random cards.
    func testWrapperEqualsADirectPackageCall() throws {
        let direct = FSRS(parameters: FSRSParameters(
            requestRetention: 0.9, maximumInterval: 30, w: FSRSDefaults.defaultWv6, enableFuzz: false,
            enableShortTerm: true, learningSteps: ["10m"], relearningSteps: ["10m"]))
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let state = Int.random(in: 0...3, using: &generator)
            let stability = state == 0 ? 0 : Double.random(in: 0.5...200, using: &generator)
            let difficulty = state == 0 ? 0 : Double.random(in: 1...10, using: &generator)
            let ago = Double.random(in: 0...90, using: &generator) * day
            let memory = FSRSMemory(state: state, stability: stability, difficulty: difficulty,
                                    learningStep: 0, lastReviewedAt: state == 0 ? nil : now.addingTimeInterval(-ago))
            let interval = state == 2 ? stability.rounded(.up) : 0
            let card = Card(due: now, stability: stability, difficulty: difficulty, elapsedDays: 0,
                            scheduledDays: interval, learningSteps: 0, reps: state == 0 ? 0 : 1, lapses: 2,
                            state: try XCTUnwrap(CardState(rawValue: state)), lastReview: memory.lastReviewedAt)
            let preview = try direct.repeat(card: card, now: now)
            let wrapped = FSRSScheduler.outcomes(memory: memory, due: now, intervalDays: interval, lapses: 2,
                                                 now: now)
            for (grade, rating) in [(ReviewGrade.again, Rating.again), (.hard, .hard), (.good, .good), (.easy, .easy)] {
                let item = try XCTUnwrap(preview[rating])
                let outcome = try XCTUnwrap(wrapped[grade])
                XCTAssertEqual(outcome.due, item.card.due)
                XCTAssertEqual(outcome.scheduledDays, item.card.scheduledDays)
                XCTAssertEqual(outcome.memory.state, item.card.state.rawValue)
                XCTAssertEqual(outcome.memory.stability, item.card.stability)
                XCTAssertEqual(outcome.memory.difficulty, item.card.difficulty)
                XCTAssertEqual(outcome.memory.learningStep, item.card.learningSteps)
                XCTAssertEqual(outcome.lapses, item.card.lapses)
                XCTAssertEqual(outcome.elapsedDays, item.log.elapsedDays)
            }
        }
    }

    func testALastReviewAfterNowDoesNotThrowAndStillSchedules() {
        let memory = FSRSMemory(state: 2, stability: 10, difficulty: 6, learningStep: 0,
                                lastReviewedAt: now.addingTimeInterval(3 * day))
        let result = outcomes(of: memory, interval: 10)
        XCTAssertEqual(result.count, 4)
        XCTAssertTrue(result.values.allSatisfy { $0.due >= now })
    }

    func testCorruptMemoryFallsBackInsteadOfFailing() throws {
        for bad in [FSRSMemory(state: 2, stability: 0.0001, difficulty: 0.5, learningStep: 0, lastReviewedAt: now),
                    FSRSMemory(state: 2, stability: -3, difficulty: 50, learningStep: 0, lastReviewedAt: now),
                    FSRSMemory(state: 9, stability: 5, difficulty: 5, learningStep: 0, lastReviewedAt: now)] {
            let result = outcomes(of: bad, interval: 5)
            XCTAssertEqual(result.count, 4, "\(bad)")
            for outcome in result.values {
                XCTAssertTrue(outcome.memory.stability.isFinite)
                XCTAssertTrue(FSRSMigration.isValid(outcome.memory), "\(outcome.memory)")
            }
        }
    }

    func testElapsedDaysCountWholeUTCCalendarDaysLikeThePackage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 3, day: 10)))
        let last = midnight.addingTimeInterval(-60)
        let current = midnight.addingTimeInterval(60)
        XCTAssertEqual(FSRSScheduler.elapsedDays(since: last, now: current), 1)
        XCTAssertEqual(FSRSScheduler.elapsedDays(since: midnight, now: current), 0)
        XCTAssertEqual(FSRSScheduler.elapsedDays(since: nil, now: current), 0)
        XCTAssertEqual(FSRSScheduler.elapsedDays(since: current, now: last), 0)
        let memory = FSRSMemory(state: 2, stability: 5, difficulty: 5, learningStep: 0, lastReviewedAt: last)
        let outcome = try XCTUnwrap(FSRSScheduler.outcomes(memory: memory, due: current, intervalDays: 5,
                                                            lapses: 0, now: current)[.good])
        XCTAssertEqual(outcome.elapsedDays, 1)
        XCTAssertEqual(outcome.elapsedDays, FSRSScheduler.elapsedDays(since: last, now: current))
    }

    func testRetrievabilityIsAboutNinetyPercentAtOneStability() {
        let memory = FSRSMemory(state: 2, stability: 10, difficulty: 6, learningStep: 0,
                                lastReviewedAt: now.addingTimeInterval(-10 * day))
        XCTAssertEqual(FSRSScheduler.retrievability(memory: memory, now: now), 0.9, accuracy: 0.01)
        XCTAssertEqual(FSRSScheduler.retrievability(memory: .new, now: now), 0)
        XCTAssertLessThan(FSRSScheduler.retrievability(memory: memory, now: now.addingTimeInterval(20 * day)), 0.9)
    }
}
