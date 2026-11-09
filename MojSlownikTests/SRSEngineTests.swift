import XCTest
@testable import MojSlownik

final class SRSEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testGoodAnswersAdvanceFirstIntervalsAndScheduleFromProvidedTime() {
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
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
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
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
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.easeFactor = 1.3
        SRSEngine.apply(.hard, to: word, now: now)
        XCTAssertEqual(word.repetitions, 1)
        XCTAssertEqual(word.intervalDays, 1)
        XCTAssertEqual(word.easeFactor, 1.3)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(86_400))
    }

    func testEasyRewardsLongerIntervalThanGoodAndIncreasesEase() {
        let good = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        let easy = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        SRSEngine.apply(.good, to: good, now: now)
        SRSEngine.apply(.easy, to: easy, now: now)
        XCTAssertGreaterThan(easy.intervalDays, good.intervalDays)
        XCTAssertGreaterThan(easy.easeFactor, good.easeFactor)
        XCTAssertEqual(easy.repetitions, 1)
        XCTAssertEqual(easy.dueDate, now.addingTimeInterval(easy.intervalDays * 86_400))
    }
}
