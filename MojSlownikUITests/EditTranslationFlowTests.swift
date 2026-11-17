import XCTest

/// Editing and choosing translations before saving.
final class EditTranslationFlowTests: E2ETestCase {
    @MainActor
    func testManualTranslationEditIsSaved() throws {
        launch(.empty, prefill: "собака")

        let chip = element("scanWordChip-собака-0")
        waitForEnabled(chip)
        chip.press(forDuration: 1.0)
        let edit = element("scanEditWordButton")
        waitForHittable(edit)
        edit.tap()

        let translation = element("translationField")
        waitForValue(translation, equals: "pies")
        replaceText(in: translation, with: "piesek")

        let save = element("saveWordButton")
        waitForEnabled(save)
        save.tap()
        dismissAchievementBannerIfPresent()

        let done = element("scanDoneButton")
        waitForHittable(done)
        done.tap()

        XCTAssertTrue(app.staticTexts["собака"].waitForExistence(timeout: 10), "Word missing in list")
        XCTAssertTrue(app.staticTexts["piesek"].waitForExistence(timeout: 10), "Edited translation missing in list")
    }

    @MainActor
    func testAlternativeChipReplacesTranslation() throws {
        launch(.empty)

        let add = element("addWordButton")
        waitForHittable(add)
        add.tap()

        let source = element("sourceField")
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        source.typeText("dom")
        waitForValue(element("translationField"), equals: "дом")

        let option = element("translationOption-жилище")
        waitForHittable(option)
        option.tap()
        waitForValue(element("translationField"), equals: "жилище")

        let save = element("saveWordButton")
        waitForEnabled(save)
        save.tap()
        dismissAchievementBannerIfPresent()

        XCTAssertTrue(app.staticTexts["жилище"].waitForExistence(timeout: 10), "Chosen translation missing in list")
    }
}
