import XCTest

/// Progress card, folder progress, hard words and quiz scheduling on the `studyProgress` fixture:
/// 10 words (3 learned, 3 learning with one hard word, 4 new), folders "Lesson 1" (3) and "Lesson 2" (4).
final class StudyProgressFlowTests: E2ETestCase {
    /// Polish and Russian sides of the fixture words in the second lesson folder, for answering the quiz correctly.
    private let lesson2Pairs: [String: String] = [
        "jabłko": "яблоко", "mleko": "молоко", "ser": "сыр", "ryba": "рыба",
        "яблоко": "jabłko", "молоко": "mleko", "сыр": "ser", "рыба": "ryba",
    ]

    @MainActor
    private func scrollTo(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: E2ETestCase.defaultTimeout), "\(element) did not appear")
        for _ in 0..<6 where !(element.exists && !element.frame.isEmpty && element.isHittable) {
            app.swipeUp()
        }
        waitForHittable(element)
    }

    @MainActor
    private func selectFolder(_ name: String) {
        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()
        let option = element("folderOption-\(name)")
        waitForHittable(option)
        option.tap()
        waitForLabel(element("folderPickerButton"), equals: "Папка: \(name)")
    }

    @MainActor
    func testProgressCardShowsBucketsForecastAndHardWords() {
        launch(.studyProgress)
        openTab("Практика")
        waitForValue(element("studyProgressSummary"), equals: "выучено 3, учу 3, новые 4 из 10")
        waitForValue(element("studyForecast"), equals: "Завтра: 1, за неделю: 2")
        waitForValue(element("hardWordsRow"), equals: "1 слово")
    }

    @MainActor
    func testFolderSheetShowsLearnedCounts() {
        launch(.studyProgress)
        openTab("Практика")
        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()
        waitForValue(element("folderOption-all"), equals: "выучено 3 из 10")
        waitForValue(element("folderOption-Урок 1"), equals: "выучено 2 из 3")
        waitForValue(element("folderOption-Урок 2"), equals: "выучено 0 из 4")
        element("folderOption-Урок 1").tap()
        waitForLabel(element("folderPickerButton"), equals: "Папка: Урок 1")

        waitForValue(element("studyProgressSummary"), equals: "выучено 2, учу 1, новые 0 из 3")
        XCTAssertFalse(element("hardWordsRow").exists, "the folder has no hard words")
    }

    @MainActor
    func testHardWordsSessionShowsPillAndCaptions() {
        launch(.studyProgress)
        openTab("Практика")
        let row = element("hardWordsRow")
        scrollTo(row)
        row.tap()

        let card = element("flashcard")
        waitForHittable(card)
        let value = card.value as? String ?? ""
        XCTAssertTrue(value.contains("трудное слово"), "Hard-word card value is '\(value)'")
        card.tap()

        waitForValue(element("gradeButton-again"), equals: "Следующий показ через 10 минут")
        waitForValue(element("gradeButton-hard"), equals: "Следующий показ через 2 дня")
        waitForValue(element("gradeButton-good"), equals: "Следующий показ через 3 дня")
        waitForValue(element("gradeButton-easy"), equals: "Следующий показ через 4 дня")
    }

    /// FSRS learning steps on a brand-new word: 10 min, 15 min, then 2 and 8 days.
    @MainActor
    func testNewWordCaptionsFollowFSRSSteps() {
        launch(.studyProgress)
        openTab("Практика")
        selectFolder("Урок 2")
        let start = element("practiceStartButton")
        waitForHittable(start)
        start.tap()

        let card = element("flashcard")
        waitForHittable(card)
        card.tap()

        waitForValue(element("gradeButton-again"), equals: "Следующий показ через 10 минут")
        waitForValue(element("gradeButton-hard"), equals: "Следующий показ через 15 минут")
        waitForValue(element("gradeButton-good"), equals: "Следующий показ через 2 дня")
        waitForValue(element("gradeButton-easy"), equals: "Следующий показ через 8 дней")
    }

    /// FSRS makes a new word answered Hard due again in 15 minutes, but a word answered correctly
    /// today stays completed: Today never counts it as remaining.
    @MainActor
    func testHardOnNewWordsKeepsTodayCompleted() {
        launch(.studyProgress)
        openTab("Практика")
        selectFolder("Урок 2")
        let start = element("practiceStartButton")
        waitForHittable(start)
        start.tap()

        for answered in 1...4 {
            let cards = app.descendants(matching: .any).matching(identifier: "flashcard")
            let single = NSPredicate { object, _ in (object as? XCUIElementQuery)?.count == 1 }
            let expectation = XCTNSPredicateExpectation(predicate: single, object: cards)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed, "Expected one flashcard")
            waitForHittable(cards.firstMatch)
            cards.firstMatch.tap()
            let hard = element("gradeButton-hard")
            waitForValue(hard, equals: "Следующий показ через 15 минут")
            hard.tap()
            if answered < 4 {
                waitForValue(element("sessionProgress"), equals: "Ответов: \(answered) из 4")
            }
        }

        XCTAssertTrue(element("flashcardsCompleted").waitForExistence(timeout: 10), "Completion view missing")
        let back = element("backToPracticeButton")
        waitForHittable(back)
        back.tap()

        waitForLabel(element("practiceStartButton"), equals: "Свободная практика")
        waitForValue(element("todayProgress"), equals: "4 из 4. Осталось: 0")
    }

    @MainActor
    func testCorrectQuizAnswerMovesNewWordToLearning() {
        launch(.studyProgress)
        openTab("Практика")
        selectFolder("Урок 2")
        waitForValue(element("studyProgressSummary"), equals: "выучено 0, учу 0, новые 4 из 4")

        let tile = element("quizModeTile")
        waitForHittable(tile)
        tile.tap()

        let prompt = element("quizPrompt")
        XCTAssertTrue(prompt.waitForExistence(timeout: E2ETestCase.defaultTimeout))
        guard let correct = lesson2Pairs[prompt.label] else { return XCTFail("Unknown quiz prompt '\(prompt.label)'") }
        let options = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'quizOption-'"))
        let answer = options.allElementsBoundByIndex.first { $0.label.hasPrefix(correct) }
        guard let answer else { return XCTFail("No option starts with '\(correct)'") }
        waitForEnabled(answer)
        answer.tap()
        waitForValue(element("sessionProgress"), equals: "Ответов: 1 из 4")

        app.navigationBars.buttons.firstMatch.tap()
        waitForValue(element("studyProgressSummary"), equals: "выучено 0, учу 1, новые 3 из 4")
    }
}
