import XCTest

/// Quiz on the `basicVocabulary` fixture: 5 words, so exactly 5 questions.
final class QuizFlowTests: E2ETestCase {
    @MainActor
    func testQuizCompletesAndRecordsAnswers() throws {
        launch(.basicVocabulary)
        openTab("Практика")
        let tile = element("quizModeTile")
        waitForHittable(tile)
        tile.tap()

        for index in 0..<5 {
            // Options stay disabled until the 900 ms auto-advance after an answer.
            let option = element("quizOption-0")
            waitForEnabled(option)
            option.tap()
            // After the last answer the result screen replaces the progress view within 900 ms.
            if index < 4 {
                waitForValue(element("sessionProgress"), equals: "Ответов: \(index + 1) из 5")
            }
        }

        let score = element("quizScore")
        XCTAssertTrue(score.waitForExistence(timeout: 10), "Result did not appear")
        XCTAssertNotNil(score.label.range(of: "^[0-5] из 5$", options: .regularExpression),
                        "Unexpected score '\(score.label)'")

        app.navigationBars.buttons.firstMatch.tap()
        waitForLabel(element("answerTotal"), equals: "Ответов: 5")
    }
}
