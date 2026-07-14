import XCTest

/// Сквозная проверка основного сценария: слово (через путь сканера/префилла) →
/// автоперевод → сохранение → список → флешкарточки.
final class AddWordFlowTests: XCTestCase {

    private func launchApp(prefill: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UITEST_PREFILL"] = prefill
        app.launch()
        return app
    }

    private func waitForTranslation(in app: XCUIApplication) -> String {
        let field = app.textFields["translationField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Поле перевода не появилось")
        let filled = NSPredicate { _, _ in
            let value = field.value as? String ?? ""
            return !value.isEmpty && value != "Перевод появится автоматически…"
        }
        let expectation = XCTNSPredicateExpectation(predicate: filled, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed, "Автоперевод не пришёл за 20 с")
        return field.value as? String ?? ""
    }

    @MainActor
    func testRussianWordFullFlow() throws {
        let app = launchApp(prefill: "привет")

        let translation = waitForTranslation(in: app)
        XCTAssertNil(translation.range(of: "[а-яА-ЯёЁ]", options: .regularExpression),
                     "Перевод «\(translation)» содержит кириллицу — направление не переключилось")

        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["привет"].waitForExistence(timeout: 5), "Слово не появилось в списке")

        // Тренировка: карточка переворачивается, оценка завершает сессию.
        app.tabBars.buttons["Тренировка"].tap()
        let flashcards = app.staticTexts["Флешкарточки"]
        XCTAssertTrue(flashcards.waitForExistence(timeout: 5))
        flashcards.tap()

        let card = app.descendants(matching: .any)["flashcard"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Карточка не показалась")
        card.tap()

        let goodButton = app.buttons["Хорошо"]
        XCTAssertTrue(goodButton.waitForExistence(timeout: 5), "Кнопки оценки не появились после переворота")
        goodButton.tap()
    }

    @MainActor
    func testPolishWordTranslatesToRussian() throws {
        let app = launchApp(prefill: "dziękuję")

        let translation = waitForTranslation(in: app)
        XCTAssertNotNil(translation.range(of: "[а-яА-ЯёЁ]", options: .regularExpression),
                        "Перевод «\(translation)» не содержит кириллицы")

        app.buttons["Сохранить"].tap()
        XCTAssertTrue(app.staticTexts["dziękuję"].waitForExistence(timeout: 5), "Слово не появилось в списке")
    }
}
