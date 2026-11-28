import XCTest

/// Language workspaces: the first-launch wizard, the gate and the title menu (phase 4 pilot).
final class WorkspaceFlowTests: E2ETestCase {
    @MainActor
    private func tapRow(_ id: String) {
        let row = element(id)
        waitForHittable(row)
        row.tap()
    }

    @MainActor
    func testFreshInstallWizardCreatesWorkspace() {
        launch(.freshInstall)
        waitForHittable(element("wizardLanguage-de"))
        XCTAssertFalse(element("wizardLanguage-fr").exists, "only pl, en and de are offered")
        XCTAssertFalse(element("wizardLanguage-ru").exists)
        tapRow("wizardLanguage-de")
        tapRow("wizardNextButton")
        let russian = element("wizardTranslation-ru")
        waitForHittable(russian)
        XCTAssertTrue(russian.isSelected, "Russian is preselected")
        XCTAssertTrue(element("wizardTranslation-en").exists)
        XCTAssertFalse(element("wizardTranslation-pl").exists, "only ru, uk and en are offered")
        tapRow("wizardStartButton")
        waitForDictionary()
        XCTAssertTrue(app.navigationBars.buttons["🇩🇪 Немецкий"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Словарь пуст"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testExistingDataSkipsWizard() {
        launch(.basicVocabulary)
        waitForDictionary()
        XCTAssertFalse(element("wizardStartButton").exists)
        XCTAssertFalse(element("wizardNextButton").exists)
        XCTAssertTrue(app.navigationBars.buttons["🇵🇱 Польский"].exists)
        XCTAssertTrue(app.staticTexts["kot"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func choose(_ language: String) {
        let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", language)).firstMatch
        waitForHittable(option)
        option.tap()
    }

    @MainActor
    func testSwitchingScopesDictionaryFoldersAndPractice() {
        launch(.multiWorkspace)
        waitForDictionary()
        XCTAssertTrue(app.staticTexts["kot"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["das Haus"].exists)

        openTitleMenu("🇵🇱 Польский")
        choose("Немецкий")

        XCTAssertTrue(app.navigationBars.buttons["🇩🇪 Немецкий"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["das Haus"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["kot"].exists)

        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()
        XCTAssertTrue(element("folderOption-Lektion 1").waitForExistence(timeout: 10))
        XCTAssertFalse(element("folderOption-Урок 1").exists, "folders are scoped to the workspace")
        element("folderOption-Lektion 1").tap()
        waitForLabel(element("folderPickerButton"), equals: "Папка: Lektion 1")

        openTab("Практика")
        XCTAssertTrue(app.navigationBars.buttons["🇩🇪 Немецкий"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Слов в выбранном наборе: 2"].waitForExistence(timeout: 10),
                      "the folder filter resets and the count is the workspace's")
        waitForValue(element("studyProgressSummary"), equals: "выучено 2, учу 0, новые 0 из 2")

        openTitleMenu("🇩🇪 Немецкий")
        choose("Польский")
        XCTAssertTrue(app.staticTexts["Слов в выбранном наборе: 5"].waitForExistence(timeout: 10))
        waitForValue(element("studyProgressSummary"), equals: "выучено 5, учу 0, новые 0 из 5")
        openTab("Словарь")
        XCTAssertTrue(app.staticTexts["kot"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testDeleteAndRestoreWorkspace() {
        launch(.multiWorkspace)
        waitForDictionary()
        openTitleMenu("🇵🇱 Польский")
        let manage = app.buttons["Управлять языками"]
        waitForHittable(manage)
        manage.tap()

        XCTAssertTrue(app.navigationBars["Языки"].waitForExistence(timeout: 10))
        let edit = element("editWorkspacesButton")
        waitForHittable(edit)
        edit.tap()
        let row = app.cells.containing(NSPredicate(format: "identifier == 'workspaceRow-de-ru'")).firstMatch
        waitForHittable(row)
        // The system delete control (label follows the system language) reveals the swipe action.
        let deleteLabel = NSPredicate(format: "label BEGINSWITH 'Remove' OR label BEGINSWITH 'Delete' OR label BEGINSWITH 'Удалить'")
        let control = row.buttons.matching(deleteLabel).firstMatch
        waitForHittable(control)
        // The minus sits at the leading edge of the row.
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        let swipeDelete = app.buttons.matching(NSPredicate(format: "label == 'Delete' OR label == 'Удалить'")).firstMatch
        waitForHittable(swipeDelete)
        swipeDelete.tap()
        // Confirmation dialog (an action sheet, or a popover inside the sheet): a destructive "Delete".
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Удалить'")).firstMatch
        waitForHittable(confirm)
        confirm.tap()
        XCTAssertFalse(element("workspaceRow-de-ru").waitForExistence(timeout: 3), "German is deleted")
        edit.tap()
        let done = element("manageWorkspacesDone")
        waitForHittable(done)
        done.tap()

        openTitleMenu("🇵🇱 Польский")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Немецкий'")).firstMatch.exists)
        let newLanguage = app.buttons["Новый язык…"]
        waitForHittable(newLanguage)
        newLanguage.tap()
        tapRow("wizardLanguage-de")
        tapRow("wizardNextButton")
        tapRow("wizardStartButton")
        XCTAssertTrue(app.staticTexts["das Haus"].waitForExistence(timeout: 10), "the words return with the pair")
    }

    @MainActor
    func testSameScriptDirectionControl() {
        launch(.sameScriptWorkspace)
        let add = element("addWordButton")
        waitForHittable(add)
        add.tap()
        let control = element("inputSideControl")
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        let polish = control.buttons["Польский"]
        waitForHittable(polish)
        polish.tap()
        let source = element("sourceField")
        source.tap()
        source.typeText("dom")
        waitForValue(element("translationField"), equals: "house")
        let save = element("saveWordButton")
        waitForEnabled(save)
        save.tap()
        dismissAchievementBannerIfPresent()
        XCTAssertTrue(app.staticTexts["house"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["dom"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testNewLanguageSheetCreatesAndOpensTheWorkspace() {
        launch(.basicVocabulary)
        waitForDictionary()
        openTitleMenu("🇵🇱 Польский")
        let newLanguage = app.buttons["Новый язык…"]
        waitForHittable(newLanguage)
        newLanguage.tap()
        tapRow("wizardLanguage-de")
        tapRow("wizardNextButton")
        tapRow("wizardStartButton")
        XCTAssertTrue(app.navigationBars.buttons["🇩🇪 Немецкий"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["kot"].exists)
    }

    @MainActor
    func testSignedInFreshInstallOpensAccountWorkspace() {
        launch(.freshInstall, auth: .signedIn, sync: .remoteWorkspaces)
        waitForDictionary()
        XCTAssertFalse(element("wizardStartButton").exists, "the wizard never shows for an account with workspaces")
        XCTAssertTrue(app.navigationBars.buttons["🇩🇪 Немецкий"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["das Haus"].waitForExistence(timeout: 20))
        openTitleMenu("🇩🇪 Немецкий")
        let polish = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Польский'")).firstMatch
        XCTAssertTrue(polish.waitForExistence(timeout: 10))
    }

    @MainActor
    func testSignedInFreshInstallWithFailedPullShowsWizard() {
        launch(.freshInstall, auth: .signedIn, sync: .failsOnce)
        XCTAssertTrue(element("wizardLanguage-pl").waitForExistence(timeout: 15))
    }

    @MainActor
    func testSignedInFreshInstallWithEmptyAccountShowsWizard() {
        launch(.freshInstall, auth: .signedIn, sync: .empty)
        XCTAssertTrue(element("wizardLanguage-pl").waitForExistence(timeout: 15))
    }
}
