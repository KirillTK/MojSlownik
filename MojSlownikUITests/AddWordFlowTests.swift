import XCTest

/// Add-word flows on fixture data: scanner quick-add and manual entry.
final class AddWordFlowTests: E2ETestCase {
    @MainActor
    func testAddRussianWordViaScanQuickAdd() throws {
        launch(.empty, prefill: "привет мир")

        waitForLabel(element("scanTranslationText"), equals: "cześć świecie")

        let chip = element("scanWordChip-привет-0")
        waitForEnabled(chip)
        XCTAssertTrue(chip.label.contains("cześć"), "Chip label '\(chip.label)' lacks the translation")
        chip.tap()

        dismissAchievementBannerIfPresent()
        let done = element("scanDoneButton")
        waitForHittable(done)
        done.tap()

        XCTAssertTrue(app.staticTexts["привет"].waitForExistence(timeout: 10), "Word missing in list")
        XCTAssertTrue(app.staticTexts["cześć"].waitForExistence(timeout: 10), "Translation missing in list")
    }

    @MainActor
    func testAddPolishWordManually() throws {
        launch(.empty)

        let add = element("addWordButton")
        waitForHittable(add)
        add.tap()

        let source = element("sourceField")
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        source.typeText("dom")
        waitForValue(element("translationField"), equals: "дом")

        let save = element("saveWordButton")
        waitForEnabled(save)
        save.tap()
        dismissAchievementBannerIfPresent()

        XCTAssertTrue(app.staticTexts["dom"].waitForExistence(timeout: 10), "Word missing in list")
        XCTAssertTrue(app.staticTexts["дом"].waitForExistence(timeout: 10), "Translation missing in list")
    }
}
