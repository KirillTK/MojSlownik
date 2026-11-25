import XCTest
@testable import MojSlownik

final class SRSEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let day: TimeInterval = 86_400

    func testGoodAnswersFollowFSRSFromProvidedTime() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.good, to: word, now: now)
        XCTAssertEqual(word.repetitions, 1)
        XCTAssertEqual(word.intervalDays, 2)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(2 * day))
        XCTAssertEqual(word.fsrsStateRawValue, 2)
        XCTAssertEqual(word.fsrsLastReviewedAt, now)
        let later = now.addingTimeInterval(2 * day)
        SRSEngine.apply(.good, to: word, now: later)
        XCTAssertEqual(word.repetitions, 2)
        XCTAssertGreaterThan(word.intervalDays, 2)
        XCTAssertEqual(word.dueDate, later.addingTimeInterval(word.intervalDays * day))
    }

    func testAgainResetsProgressSchedulesTenMinutesAndLeavesEaseAlone() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 4
        word.intervalDays = 20
        word.easeFactor = 1.7
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.repetitions, 0)
        XCTAssertEqual(word.intervalDays, 0)
        XCTAssertEqual(word.easeFactor, 1.7, "ease is legacy and never written")
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(600))
        XCTAssertEqual(word.fsrsStateRawValue, 3)
        XCTAssertEqual(word.lastReviewGradeRawValue, ReviewGrade.again.rawValue)
    }

    func testHardOnANewWordStaysInTheLearningStep() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.hard, to: word, now: now)
        XCTAssertEqual(word.repetitions, 1)
        XCTAssertEqual(word.intervalDays, 0)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(900))
        XCTAssertEqual(word.fsrsStateRawValue, 1)
    }

    func testEasyRewardsLongerIntervalThanGoodAndEaseStaysFrozen() {
        let good = Word(russian: "вода", polish: "woda", side: .term)
        let easy = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.good, to: good, now: now)
        SRSEngine.apply(.easy, to: easy, now: now)
        XCTAssertGreaterThan(easy.intervalDays, good.intervalDays)
        XCTAssertEqual(easy.easeFactor, 2.5)
        XCTAssertEqual(easy.repetitions, 1)
        XCTAssertEqual(easy.dueDate, now.addingTimeInterval(easy.intervalDays * day))
    }

    /// With the 30-day setting the package returns at most 32 days; nothing is clamped on top.
    func testRepeatedEasyStaysWithinTheLibraryBound() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        for _ in 0..<80 { SRSEngine.apply(.easy, to: word, now: now) }
        XCTAssertEqual(word.intervalDays, SRSEngine.maxLibraryIntervalDays)
        XCTAssertEqual(word.easeFactor, 2.5)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(32 * day))
    }

    func testAgainIsUnchangedAtTheCap() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 6
        word.intervalDays = 30
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.intervalDays, 0)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(SRSEngine.againDelay))
    }

    /// The library's ordering: Hard < Good < Easy in review state; Again < Hard < Good <= Easy while
    /// (re)learning; every interval within the longest the package can return.
    func testLibraryOrderingAcrossStatesAndIntervals() {
        for interval in [0.0, 1, 2, 3, 5, 8, 13, 21, 25, 30, 31, 32] {
            for ease in [1.3, 1.8, 2.5, 3.0] {
                for repetitions in [0, 1, 3] {
                    for elapsed in [0.0, 1, 10, 60] {
                        let due = now.addingTimeInterval(interval * day - elapsed * day)
                        let state = SRSState(easeFactor: ease, intervalDays: interval, repetitions: repetitions,
                                             dueDate: due, lastReviewGradeRawValue: repetitions > 0 ? "good" : nil,
                                             lapseCount: 0)
                        let label = "I \(interval) E \(ease) R \(repetitions) elapsed \(elapsed)"
                        let transitions = ReviewGrade.allCases.map { SRSEngine.transition($0, from: state, now: now) }
                        let dues = transitions.map(\.after.dueDate)
                        let intervals = transitions.map(\.after.intervalDays)
                        XCTAssertTrue(intervals.allSatisfy { $0 <= SRSEngine.maxLibraryIntervalDays }, label)
                        XCTAssertEqual(dues[0], now.addingTimeInterval(SRSEngine.againDelay), label)
                        XCTAssertLessThan(dues[0], dues[1], label)
                        XCTAssertLessThanOrEqual(dues[2], dues[3], label)
                        if transitions[0].beforeMemory.state == 2 {
                            XCTAssertLessThan(dues[1], dues[2], label)
                            XCTAssertLessThan(dues[2], dues[3], label)
                        } else {
                            XCTAssertLessThan(dues[1], dues[2], label)
                        }
                    }
                }
            }
        }
    }

    func testLeechExampleSchedulesTenMinutesThenTwoThreeFourDays() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 1
        word.intervalDays = 1
        word.easeFactor = 1.3
        word.dueDate = now.addingTimeInterval(-day)
        XCTAssertEqual(SRSEngine.preview(.again, for: word, now: now), .minutes(10))
        XCTAssertEqual(SRSEngine.preview(.hard, for: word, now: now), .days(2))
        XCTAssertEqual(SRSEngine.preview(.good, for: word, now: now), .days(3))
        XCTAssertEqual(SRSEngine.preview(.easy, for: word, now: now), .days(4))
    }

    func testNewWordCaptionsAreTenMinutesFifteenMinutesTwoAndEightDays() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        XCTAssertEqual(SRSEngine.preview(.again, for: word, now: now), .minutes(10))
        XCTAssertEqual(SRSEngine.preview(.hard, for: word, now: now), .minutes(15))
        XCTAssertEqual(SRSEngine.preview(.good, for: word, now: now), .days(2))
        XCTAssertEqual(SRSEngine.preview(.easy, for: word, now: now), .days(8))
    }

    func testPreviewEqualsApplyAndDoesNotMutate() {
        for grade in ReviewGrade.allCases {
            let word = Word(russian: "вода", polish: "woda", side: .term)
            word.repetitions = 4
            word.intervalDays = 20
            word.easeFactor = 2.8
            word.dueDate = now
            let before = SRSState(word: word)
            let preview = SRSEngine.preview(grade, for: word, now: now)
            XCTAssertEqual(SRSState(word: word), before)
            SRSEngine.apply(grade, to: word, now: now)
            switch preview {
            case .minutes(let minutes):
                XCTAssertEqual(word.dueDate, now.addingTimeInterval(Double(minutes) * 60))
                XCTAssertEqual(word.intervalDays, 0)
            case .days(let days):
                XCTAssertLessThanOrEqual(Double(days), SRSEngine.maxLibraryIntervalDays)
                XCTAssertEqual(word.intervalDays, Double(days))
                XCTAssertEqual(word.dueDate, now.addingTimeInterval(Double(days) * day))
            }
        }
    }

    func testTransitionCarriesMemoryAndElapsedDaysForTheLog() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.good, to: word, now: now)
        let later = now.addingTimeInterval(3 * day + 60)
        let transition = SRSEngine.transition(.good, from: SRSState(word: word), now: later)
        XCTAssertEqual(transition.beforeMemory.state, 2)
        XCTAssertEqual(transition.beforeMemory.lastReviewedAt, now)
        XCTAssertEqual(transition.afterMemory.lastReviewedAt, later)
        XCTAssertEqual(transition.before.intervalDays, 2)
        XCTAssertEqual(transition.after.intervalDays, transition.after.intervalDays.rounded())
        XCTAssertEqual(transition.elapsedDays, FSRSScheduler.elapsedDays(since: now, now: later))
        XCTAssertEqual(SRSEngine.next(.good, from: SRSState(word: word), now: later), transition.after)
    }

    func testObservationLeavesTheStateAlone() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        let state = SRSState(word: word)
        let observation = SRSEngine.observation(state, now: now)
        XCTAssertEqual(observation.before, state)
        XCTAssertEqual(observation.after, state)
        XCTAssertEqual(observation.beforeMemory, observation.afterMemory)
        XCTAssertEqual(observation.beforeMemory, .new)
    }

    func testLapseCountsOnlyAnAgainFromReviewState() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 0, "a never-learned word is not forgotten")
        SRSEngine.apply(.easy, to: word, now: now)
        XCTAssertEqual(word.fsrsStateRawValue, 2)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 1)
        SRSEngine.apply(.again, to: word, now: now)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 1, "Again while relearning does not count")
        SRSEngine.apply(.good, to: word, now: now)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 2)
    }

    func testWouldBeGradeTable() {
        XCTAssertEqual(SRSEngine.wouldBeGrade(for: .choice(isCorrect: true)), .good)
        XCTAssertEqual(SRSEngine.wouldBeGrade(for: .choice(isCorrect: false)), .again)
        XCTAssertEqual(SRSEngine.wouldBeGrade(for: .typed(expected: "kot", submitted: "kot")), .good)
        XCTAssertEqual(SRSEngine.wouldBeGrade(for: .typed(expected: "kot", submitted: "dom")), .again)
        XCTAssertEqual(SRSEngine.wouldBeGrade(for: .typed(expected: "kotek", submitted: "kotex")), .hard)
    }

    func testPracticeGradeTable() {
        let typedExact = KnowledgeAnswer.typed(expected: "kot", submitted: "kot")
        let typedSoft = KnowledgeAnswer.typed(expected: "kotek", submitted: "kotex")
        let typedWrong = KnowledgeAnswer.typed(expected: "kot", submitted: "dom")
        for answer in [KnowledgeAnswer.choice(isCorrect: true), .choice(isCorrect: false),
                       typedExact, typedSoft, typedWrong] {
            XCTAssertNil(SRSEngine.practiceGrade(for: answer, isDue: false))
        }
        XCTAssertEqual(SRSEngine.practiceGrade(for: .choice(isCorrect: true), isDue: true), .good)
        XCTAssertEqual(SRSEngine.practiceGrade(for: .choice(isCorrect: false), isDue: true), .again)
        XCTAssertEqual(SRSEngine.practiceGrade(for: typedExact, isDue: true), .good)
        XCTAssertEqual(SRSEngine.practiceGrade(for: typedWrong, isDue: true), .again)
        XCTAssertNil(SRSEngine.practiceGrade(for: typedSoft, isDue: true))
    }

    func testScheduleDelayCaptionAndAccessibilityText() {
        XCTAssertEqual(ScheduleDelay.minutes(10).caption, String(localized: "\(10) min"))
        XCTAssertEqual(ScheduleDelay.days(3).caption, String(localized: "\(3) d"))
        XCTAssertEqual(ScheduleDelay.days(3).accessibilityText, String(localized: "Next review in \(3) days"))
        XCTAssertEqual(ScheduleDelay.minutes(10).accessibilityText, String(localized: "Next review in \(10) minutes"))
        XCTAssertFalse(ScheduleDelay.days(1).caption.isEmpty)
    }
}
