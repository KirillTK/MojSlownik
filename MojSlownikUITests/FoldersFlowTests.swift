import XCTest

/// Folder ordering, filtering and creation on the `foldersOrdered` fixture.
final class FoldersFlowTests: E2ETestCase {
    @MainActor
    func testFolderOrderAndFiltering() throws {
        launch(.foldersOrdered)

        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()

        let lesson1 = element("folderOption-Урок 1")
        let lesson2 = element("folderOption-Урок 2")
        let lesson3 = element("folderOption-Урок 3")
        for option in [lesson1, lesson2, lesson3] {
            XCTAssertTrue(option.waitForExistence(timeout: 10), "Folder option missing: \(option)")
        }
        XCTAssertLessThan(lesson1.frame.minY, lesson2.frame.minY)
        XCTAssertLessThan(lesson2.frame.minY, lesson3.frame.minY)

        lesson1.tap()

        XCTAssertTrue(app.staticTexts["kot"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dom"].exists)
        XCTAssertFalse(app.staticTexts["woda"].exists, "Word outside the folder is visible")
        waitForLabel(element("folderPickerButton"), equals: "Папка: Урок 1")
    }

    @MainActor
    func testCreateFolderSelectsIt() throws {
        launch(.foldersOrdered)

        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()
        let create = element("createFolderButton")
        waitForHittable(create)
        create.tap()

        let name = element("folderNameField")
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Lekcja")
        waitForValue(name, equals: "Lekcja")
        element("confirmCreateFolderButton").tap()

        waitForLabel(element("folderPickerButton"), equals: "Папка: Lekcja")
        XCTAssertTrue(app.buttons["Показать все слова"].waitForExistence(timeout: 10),
                      "Empty-folder state is missing")
    }
}
