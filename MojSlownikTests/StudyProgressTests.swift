import XCTest
@testable import MojSlownik

final class StudyProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }

    private func word(repetitions: Int = 0, interval: Double = 0, grade: String? = nil,
                      lapses: Int = 0, due: Date? = nil) -> Word {
        let word = Word(russian: "вода", polish: "woda", side: .term, createdAt: now)
        word.repetitions = repetitions
        word.intervalDays = interval
        word.lastReviewGradeRawValue = grade
        word.lapseCount = lapses
        word.dueDate = due ?? now
        return word
    }

    func testStagesIncludingAnAgainResetAndTheTwentyOneDayBoundary() {
        XCTAssertEqual(StudyProgress.stage(of: word()), .new)
        XCTAssertEqual(StudyProgress.stage(of: word(repetitions: 0, grade: "again")), .learning,
                       "an Again-reset word was graded, so it is learning")
        XCTAssertEqual(StudyProgress.stage(of: word(repetitions: 2, interval: 3, grade: "good")), .learning)
        XCTAssertEqual(StudyProgress.stage(of: word(repetitions: 4, interval: 20.9, grade: "good")), .learning)
        XCTAssertEqual(StudyProgress.stage(of: word(repetitions: 4, interval: 21, grade: "good")), .learned)
        XCTAssertEqual(StudyProgress.stage(of: word(repetitions: 6, interval: 30)), .learned)
    }

    func testBreakdownCountsActiveWordsOnly() {
        let deleted = word(repetitions: 4, interval: 30)
        deleted.markDeleted(now: now)
        let breakdown = StudyProgress.breakdown([word(), word(repetitions: 1, interval: 1, grade: "good"),
                                                 word(repetitions: 4, interval: 30), deleted])
        XCTAssertEqual(breakdown, .init(new: 1, learning: 1, learned: 1))
        XCTAssertEqual(breakdown.total, 3)
        XCTAssertEqual(StudyProgress.breakdown([]).total, 0)
    }

    /// The folder-sheet footer copy ("Learned" means 21+ days, at most 30 days) hardcodes these values
    /// in Localizable.xcstrings; change the copy together with them.
    func testLearnedCopyMatchesTheConstants() {
        XCTAssertEqual(StudyProgress.learnedThresholdDays, 21)
        XCTAssertEqual(SRSEngine.maxScheduledIntervalDays, 30)
    }

    func testLapseCountSaturates() {
        let state = SRSState(easeFactor: 2.5, intervalDays: 3, repetitions: 2, dueDate: now,
                             lastReviewGradeRawValue: nil, lapseCount: 10_000)
        XCTAssertEqual(SRSEngine.next(.again, from: state, now: now).lapseCount, 10_000)
        let huge = SRSState(easeFactor: 2.5, intervalDays: 3, repetitions: 2, dueDate: now,
                            lastReviewGradeRawValue: nil, lapseCount: Int.max)
        XCTAssertEqual(SRSEngine.next(.again, from: huge, now: now).lapseCount, 10_000)
    }

    func testHardWordRule() {
        XCTAssertTrue(StudyProgress.isHardWord(word(repetitions: 1, interval: 1, lapses: 6)))
        XCTAssertFalse(StudyProgress.isHardWord(word(repetitions: 1, interval: 1, lapses: 5)))
        XCTAssertFalse(StudyProgress.isHardWord(word(repetitions: 4, interval: 21, lapses: 6)),
                       "the flag clears once the word is learned")
        let deleted = word(repetitions: 1, interval: 1, lapses: 9)
        deleted.markDeleted(now: now)
        let hard = word(repetitions: 1, interval: 1, lapses: 7)
        XCTAssertEqual(StudyProgress.hardWords([hard, deleted, word()]).count, 1)
    }

    func testForecastCountsOnlyWordsNotDueYet() {
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int, hours: Double = 0, seconds: Double = 0) -> Date {
            calendar.date(byAdding: .day, value: offset, to: startOfToday)!
                .addingTimeInterval(hours * 3600 + seconds)
        }
        let later = now.addingTimeInterval(60)
        // A word due later today counts as "by tomorrow".
        let words = [
            word(due: now.addingTimeInterval(-60)),             // already due: excluded
            word(due: now),                                      // due now: excluded
            word(due: later),                                    // soon: tomorrow + week
            word(due: day(2, seconds: -1)),                      // last second of tomorrow
            word(due: day(2)),                                   // start of day 2: week only
            word(due: day(7, seconds: -1)),                      // inside week
            word(due: day(8)),                                   // day 8: outside
            word(due: day(30)),
        ]
        let forecast = StudyProgress.forecast(words, now: now, calendar: calendar)
        XCTAssertEqual(forecast, .init(tomorrow: 2, week: 4))
    }

    func testForecastIgnoresDeletedWords() {
        let deleted = word(due: now.addingTimeInterval(3600))
        deleted.markDeleted(now: now)
        XCTAssertEqual(StudyProgress.forecast([deleted], now: now, calendar: calendar), .init(tomorrow: 0, week: 0))
    }
}
