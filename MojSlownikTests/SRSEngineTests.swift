import XCTest
@testable import MojSlownik

final class SRSEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testGoodAnswersAdvanceFirstIntervalsAndScheduleFromProvidedTime() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.good, to: word, now: now)
        XCTAssertEqual(word.repetitions, 1)
        XCTAssertEqual(word.intervalDays, 1)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(86_400))
        SRSEngine.apply(.good, to: word, now: now)
        XCTAssertEqual(word.repetitions, 2)
        XCTAssertEqual(word.intervalDays, 3)
        SRSEngine.apply(.good, to: word, now: now)
        XCTAssertEqual(word.intervalDays, 8)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(8 * 86_400))
    }

    func testAgainResetsProgressSchedulesTenMinutesAndFloorsEase() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 4
        word.intervalDays = 20
        word.easeFactor = 1.3
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.repetitions, 0)
        XCTAssertEqual(word.intervalDays, 0)
        XCTAssertEqual(word.easeFactor, 1.3)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(600))
    }

    func testHardHasAtLeastOneDayIntervalAndMinimumEase() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.easeFactor = 1.3
        SRSEngine.apply(.hard, to: word, now: now)
        XCTAssertEqual(word.repetitions, 1)
        XCTAssertEqual(word.intervalDays, 1)
        XCTAssertEqual(word.easeFactor, 1.3)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(86_400))
    }

    func testEasyRewardsLongerIntervalThanGoodAndIncreasesEase() {
        let good = Word(russian: "вода", polish: "woda", side: .term)
        let easy = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.good, to: good, now: now)
        SRSEngine.apply(.easy, to: easy, now: now)
        XCTAssertGreaterThan(easy.intervalDays, good.intervalDays)
        XCTAssertGreaterThan(easy.easeFactor, good.easeFactor)
        XCTAssertEqual(easy.repetitions, 1)
        XCTAssertEqual(easy.dueDate, now.addingTimeInterval(easy.intervalDays * 86_400))
    }

    /// Intervals never exceed the 30-day scheduling cap, so learned words return about monthly.
    func testRepeatedEasyStaysWithinTheThirtyDayCap() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        for _ in 0..<80 { SRSEngine.apply(.easy, to: word, now: now) }
        XCTAssertEqual(word.intervalDays, SRSEngine.maxScheduledIntervalDays)
        XCTAssertEqual(word.easeFactor, SRSEngine.maxEaseFactor)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(30 * 86_400))
        SRSEngine.apply(.good, to: word, now: now)
        XCTAssertEqual(word.intervalDays, 30, "good on a capped word stays capped")
    }

    func testComputedIntervalsOverTheCapAreClampedForEveryGrade() {
        for grade in [ReviewGrade.hard, .good, .easy] {
            let word = Word(russian: "вода", polish: "woda", side: .term)
            word.repetitions = 5
            word.intervalDays = 29
            word.easeFactor = 2.5
            SRSEngine.apply(grade, to: word, now: now)
            XCTAssertEqual(word.intervalDays, 30, "\(grade)")
            XCTAssertEqual(word.dueDate, now.addingTimeInterval(30 * 86_400))
        }
        let high = Word(russian: "вода", polish: "woda", side: .term)
        high.repetitions = 9
        high.intervalDays = 30
        high.easeFactor = SRSEngine.maxEaseFactor
        SRSEngine.apply(.good, to: high, now: now)
        XCTAssertEqual(high.intervalDays, 30)
    }

    func testAgainIsUnchangedAtTheCap() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 6
        word.intervalDays = 30
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.intervalDays, 0)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(SRSEngine.againDelay))
    }

    func testGradesAreMonotonicAcrossStates() {
        let cap = SRSEngine.maxScheduledIntervalDays
        for interval in [0.0, 1, 2, 3, 5, 8, 13, 21, 25, 30] {
            for ease in [1.3, 1.8, 2.5, 3.0] {
                for repetitions in [0, 1, 2, 3, 5] {
                    let state = SRSState(easeFactor: ease, intervalDays: interval, repetitions: repetitions,
                                         dueDate: now, lastReviewGradeRawValue: nil, lapseCount: 0)
                    let hard = SRSEngine.next(.hard, from: state, now: now).intervalDays
                    let good = SRSEngine.next(.good, from: state, now: now).intervalDays
                    let easy = SRSEngine.next(.easy, from: state, now: now).intervalDays
                    let label = "I \(interval) E \(ease) R \(repetitions)"
                    XCTAssertLessThanOrEqual(hard, good, label)
                    XCTAssertLessThanOrEqual(good, easy, label)
                    XCTAssertLessThanOrEqual(easy, cap, label)
                    if good < cap { XCTAssertLessThan(good, easy, label) }
                    if interval >= 1, good < cap { XCTAssertLessThan(hard, good, label) }
                    if interval >= 1 {
                        XCTAssertGreaterThanOrEqual(good, interval, label)
                        XCTAssertGreaterThanOrEqual(hard, interval, label)
                    }
                }
            }
        }
    }

    func testLeechExampleSchedulesOneThreeFourDays() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.repetitions = 1
        word.intervalDays = 1
        word.easeFactor = 1.3
        XCTAssertEqual(SRSEngine.preview(.again, for: word, now: now), .minutes(10))
        XCTAssertEqual(SRSEngine.preview(.hard, for: word, now: now), .days(1))
        XCTAssertEqual(SRSEngine.preview(.good, for: word, now: now), .days(3))
        XCTAssertEqual(SRSEngine.preview(.easy, for: word, now: now), .days(4))
    }

    func testPreviewMatchesApplyDoesNotMutateAndStaysWithinTheCap() {
        for grade in ReviewGrade.allCases {
            let word = Word(russian: "вода", polish: "woda", side: .term)
            word.repetitions = 4
            word.intervalDays = 20
            word.easeFactor = 2.8
            let before = SRSState(word: word)
            let preview = SRSEngine.preview(grade, for: word, now: now)
            XCTAssertEqual(SRSState(word: word), before)
            SRSEngine.apply(grade, to: word, now: now)
            switch preview {
            case .minutes(let minutes):
                XCTAssertEqual(word.dueDate, now.addingTimeInterval(Double(minutes) * 60))
            case .days(let days):
                XCTAssertLessThanOrEqual(days, 30)
                XCTAssertEqual(word.intervalDays, Double(days))
                XCTAssertEqual(word.dueDate, now.addingTimeInterval(Double(days) * 86_400))
            }
        }
    }

    func testLapseCountsOnlyAFailureAfterASuccess() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 0, "a never-learned word is not forgotten")
        SRSEngine.apply(.good, to: word, now: now)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 1)
        SRSEngine.apply(.again, to: word, now: now)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 1, "repeated Again counts once")
        SRSEngine.apply(.hard, to: word, now: now)
        SRSEngine.apply(.again, to: word, now: now)
        XCTAssertEqual(word.lapseCount, 2)
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
