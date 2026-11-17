import XCTest

/// Flashcard review on the `dueForReview` fixture (2 due words).
final class FlashcardsFlowTests: E2ETestCase {
    @MainActor
    private func startSession() {
        launch(.dueForReview)
        openTab("Практика")
        let start = element("practiceStartButton")
        waitForLabel(start, equals: "Начать повторение · 2")
        start.tap()
    }

    /// The outgoing card fades for ~0.3 s; wait until exactly one card exists, then flip it.
    @MainActor
    private func flipCurrentCard() {
        let cards = app.descendants(matching: .any).matching(identifier: "flashcard")
        let single = NSPredicate { object, _ in (object as? XCUIElementQuery)?.count == 1 }
        let expectation = XCTNSPredicateExpectation(predicate: single, object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "Expected one flashcard")
        let card = cards.firstMatch
        waitForHittable(card)
        card.tap()
    }

    @MainActor
    func testGoodRatingClearsDueWords() throws {
        startSession()

        for answered in 1...2 {
            flipCurrentCard()
            let good = element("gradeButton-good")
            XCTAssertTrue(good.waitForExistence(timeout: 10), "Grade buttons did not appear")
            good.tap()
            if answered < 2 {
                waitForValue(element("sessionProgress"), equals: "Ответов: \(answered) из 2")
            }
        }

        XCTAssertTrue(element("flashcardsCompleted").waitForExistence(timeout: 10), "Completion view missing")
        XCTAssertTrue(app.staticTexts["Повторено слов: 2"].waitForExistence(timeout: 5))

        let back = element("backToPracticeButton")
        waitForHittable(back)
        back.tap()

        waitForLabel(element("practiceStartButton"), equals: "Свободная практика")
        waitForValue(element("todayProgress"), equals: "2 из 2. Осталось: 0")
    }

    @MainActor
    func testAgainRequeuesWord() throws {
        startSession()

        flipCurrentCard()
        let again = element("gradeButton-again")
        XCTAssertTrue(again.waitForExistence(timeout: 10), "Grade buttons did not appear")
        again.tap()

        waitForValue(element("sessionProgress"), equals: "Ответов: 1 из 3")
    }
}
