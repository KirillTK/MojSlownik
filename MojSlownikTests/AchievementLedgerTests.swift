import XCTest
@testable import MojSlownik

final class AchievementLedgerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func answer(_ ledger: inout AchievementLedger, _ mode: PracticeMode = .flashcards,
                        correct: Bool = true, at now: Date) {
        ledger.apply(.answer(mode: mode, isCorrect: correct), now: now, calendar: calendar)
    }

    func testAnswerCountingPerMode() {
        var ledger = AchievementLedger()
        let now = date(2026, 11, 16)
        answer(&ledger, .flashcards, correct: true, at: now)
        answer(&ledger, .quiz, correct: false, at: now)
        answer(&ledger, .listening, correct: true, at: now)
        answer(&ledger, .listening, correct: false, at: now)
        XCTAssertEqual(ledger.totalAnswers, 4)
        XCTAssertEqual(ledger.correctAnswers, 2)
        XCTAssertEqual(ledger.listeningCorrect, 1)
        XCTAssertEqual(ledger.metrics[.totalAnswers], 4)
        XCTAssertEqual(ledger.metrics[.listeningCorrect], 1)
    }

    func testStreakSameDayConsecutiveAndGap() {
        var ledger = AchievementLedger()
        answer(&ledger, at: date(2026, 11, 1, 9))
        answer(&ledger, at: date(2026, 11, 1, 20))
        XCTAssertEqual(ledger.currentStreakDays, 1)
        answer(&ledger, at: date(2026, 11, 2))
        answer(&ledger, at: date(2026, 11, 3))
        XCTAssertEqual(ledger.currentStreakDays, 3)
        XCTAssertEqual(ledger.longestStreakDays, 3)
        answer(&ledger, at: date(2026, 11, 6))
        XCTAssertEqual(ledger.currentStreakDays, 1)
        XCTAssertEqual(ledger.longestStreakDays, 3)
    }

    func testStreakAcrossDaylightSavingChange() {
        var ledger = AchievementLedger()
        answer(&ledger, at: date(2026, 3, 28, 23))
        answer(&ledger, at: date(2026, 3, 29, 12))
        answer(&ledger, at: date(2026, 3, 30, 0))
        XCTAssertEqual(ledger.currentStreakDays, 3)
    }

    func testClockMovedBackwardsOnlyIncrementsTotals() {
        var ledger = AchievementLedger()
        answer(&ledger, at: date(2026, 11, 10))
        answer(&ledger, at: date(2026, 11, 11))
        let last = ledger.lastStudyDay
        answer(&ledger, at: date(2026, 11, 5))
        XCTAssertEqual(ledger.totalAnswers, 3)
        XCTAssertEqual(ledger.currentStreakDays, 2)
        XCTAssertEqual(ledger.longestStreakDays, 2)
        XCTAssertEqual(ledger.lastStudyDay, last)
    }

    func testPerfectQuizRule() {
        XCTAssertTrue(AchievementLedger.isPerfectQuiz(correct: 4, total: 4))
        XCTAssertFalse(AchievementLedger.isPerfectQuiz(correct: 3, total: 3))
        XCTAssertFalse(AchievementLedger.isPerfectQuiz(correct: 9, total: 10))
    }

    func testQuizAnswerEvents() {
        XCTAssertEqual(AchievementEvent.quizAnswer(index: 2, count: 10, scoreAfter: 3, isCorrect: true),
                       [.answer(mode: .quiz, isCorrect: true)])
        let perfect = AchievementEvent.quizAnswer(index: 9, count: 10, scoreAfter: 10, isCorrect: true)
        XCTAssertEqual(perfect, [.answer(mode: .quiz, isCorrect: true), .quizFinished(correct: 10, total: 10)])
        var ledger = AchievementLedger()
        perfect.forEach { ledger.apply($0, now: date(2026, 11, 16), calendar: calendar) }
        XCTAssertEqual(ledger.perfectQuizzes, 1)

        var wrong = AchievementLedger()
        AchievementEvent.quizAnswer(index: 9, count: 10, scoreAfter: 9, isCorrect: false)
            .forEach { wrong.apply($0, now: date(2026, 11, 16), calendar: calendar) }
        XCTAssertEqual(wrong.perfectQuizzes, 0)

        var short = AchievementLedger()
        let shortEvents = AchievementEvent.quizAnswer(index: 2, count: 3, scoreAfter: 3, isCorrect: true)
        XCTAssertEqual(shortEvents.count, 2)
        shortEvents.forEach { short.apply($0, now: date(2026, 11, 16), calendar: calendar) }
        XCTAssertEqual(short.perfectQuizzes, 0)

        XCTAssertEqual(AchievementEvent.quizAnswer(index: 0, count: 0, scoreAfter: 0, isCorrect: true),
                       [.answer(mode: .quiz, isCorrect: true)])
        XCTAssertEqual(AchievementEvent.quizAnswer(index: 5, count: 3, scoreAfter: 3, isCorrect: true).count, 1)
    }

    func testCurrentStreakDisplay() {
        var ledger = AchievementLedger()
        let now = date(2026, 11, 16)
        XCTAssertEqual(ledger.currentStreak(now: now, calendar: calendar), 0)
        answer(&ledger, at: date(2026, 11, 14))
        answer(&ledger, at: date(2026, 11, 15))
        XCTAssertEqual(ledger.currentStreak(now: date(2026, 11, 15, 23), calendar: calendar), 2)
        XCTAssertEqual(ledger.currentStreak(now: now, calendar: calendar), 2)
        XCTAssertEqual(ledger.currentStreak(now: date(2026, 11, 17), calendar: calendar), 0)
    }

    func testLegacyPayloadDecodesWithDefaults() throws {
        let ledger = try JSONDecoder().decode(AchievementLedger.self, from: Data(#"{"totalAnswers":7}"#.utf8))
        XCTAssertEqual(ledger.totalAnswers, 7)
        XCTAssertEqual(ledger.longestStreakDays, 0)
        XCTAssertNil(ledger.lastStudyDay)
    }
}
