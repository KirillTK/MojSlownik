import XCTest

/// The app follows the system language: English, Russian, an unsupported language (falls back
/// to English) and a preferred-language list (the first supported language wins).
final class LocalizationFlowTests: E2ETestCase {
    @MainActor
    private func exists(_ label: String) -> Bool {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            .waitForExistence(timeout: 10)
    }

    @MainActor
    private func openLanguagesSheet(menuTitle: String, manage: String, sheetTitle: String) {
        openTitleMenu(menuTitle)
        let item = app.buttons[manage]
        waitForHittable(item)
        item.tap()
        XCTAssertTrue(app.navigationBars[sheetTitle].waitForExistence(timeout: 10), "Missing \(sheetTitle)")
    }

    @MainActor
    func testEnglishLaunchShowsEnglishCopy() {
        launch(.multiWorkspace, language: .english)
        waitForDictionary()
        XCTAssertTrue(app.tabBars.buttons["Dictionary"].exists)
        XCTAssertTrue(app.tabBars.buttons["Practice"].exists)
        openTab("Practice")
        XCTAssertTrue(exists("Flashcards"))
        openTab("Dictionary")
        waitForDictionary()
        openLanguagesSheet(menuTitle: "🇵🇱 Polish", manage: "Manage languages", sheetTitle: "Languages")
        XCTAssertTrue(exists("5 words · 1 folder"))
        XCTAssertTrue(exists("2 words · 1 folder"))
    }

    @MainActor
    func testRussianLaunchShowsRussianCopy() {
        launch(.multiWorkspace, language: .russian)
        waitForDictionary()
        XCTAssertTrue(app.tabBars.buttons["Словарь"].exists)
        XCTAssertTrue(app.tabBars.buttons["Практика"].exists)
        openLanguagesSheet(menuTitle: "🇵🇱 Польский", manage: "Управлять языками", sheetTitle: "Языки")
        XCTAssertTrue(exists("5 слов · 1 папка"))
        XCTAssertTrue(exists("2 слова · 1 папка"))
    }

    @MainActor
    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        launch(.basicVocabulary, language: .german)
        waitForDictionary()
        XCTAssertTrue(app.tabBars.buttons["Dictionary"].exists)
        XCTAssertTrue(app.tabBars.buttons["Practice"].exists)
        XCTAssertTrue(app.navigationBars.buttons["🇵🇱 Polish"].exists)
    }

    @MainActor
    func testFirstSupportedPreferredLanguageWins() {
        launch(.multiWorkspace, language: .germanThenRussian)
        waitForDictionary()
        XCTAssertTrue(app.tabBars.buttons["Словарь"].exists)
        XCTAssertTrue(app.navigationBars.buttons["🇵🇱 Польский"].exists)
        openLanguagesSheet(menuTitle: "🇵🇱 Польский", manage: "Управлять языками", sheetTitle: "Языки")
        XCTAssertTrue(exists("5 слов · 1 папка"))
    }
}
