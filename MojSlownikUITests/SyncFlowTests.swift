import XCTest

/// Sync with the network-free `UITEST_SYNC` server models. The real Supabase transport and
/// real sign-in are manual device checks.
final class SyncFlowTests: E2ETestCase {
    @MainActor
    private func openAccount() {
        let button = app.navigationBars.buttons["accountButton"]
        waitForHittable(button)
        button.tap()
        XCTAssertTrue(app.navigationBars["Аккаунт"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func closeAccount() {
        app.navigationBars["Аккаунт"].buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Словарь"].waitForExistence(timeout: 10))
    }

    /// Polls the status line (label) until it contains `text`.
    @MainActor
    private func waitForStatus(containing text: String, file: StaticString = #filePath, line: UInt = #line) {
        let status = element("syncStatus")
        XCTAssertTrue(status.waitForExistence(timeout: Self.defaultTimeout), "No sync status", file: file, line: line)
        waitFor(status, "label CONTAINS %@".replacingOccurrences(of: "%@", with: "'\(text)'"),
                "Sync status is '\(status.label)', expected to contain '\(text)'", file: file, line: line)
    }

    @MainActor
    func testSignInDownloadsAccountWords() {
        launch(.basicVocabulary, auth: .signedOut, sync: .remoteVocabulary)
        openAccount()
        let google = element("signIn.google")
        waitForHittable(google)
        google.tap()
        XCTAssertTrue(app.navigationBars["Словарь"].waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["мост"].waitForExistence(timeout: 20), "Account word missing")
        XCTAssertTrue(app.staticTexts["сыр"].waitForExistence(timeout: 20), "Account word missing")
        // `кот` exists locally and on the account under another id: adopted, shown once.
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == 'кот'")).count, 1)
        let picker = element("folderPickerButton")
        waitForHittable(picker)
        picker.tap()
        XCTAssertTrue(element("folderOption-Из облака").waitForExistence(timeout: 10), "Account folder missing")
    }

    @MainActor
    func testPulledUpdateAndDeleteChangeOpenDictionary() {
        launch(.syncedVocabulary, auth: .signedIn, sync: .syncedThenRemoteChanges)
        XCTAssertTrue(app.staticTexts["дом"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["кот"].waitForExistence(timeout: 20))
        let before = app.cells.count

        openAccount()
        // The launch cycle finished: the scripted server changes are armed, the button is enabled.
        waitForStatus(containing: "Синхронизировано")
        let syncNow = element("syncNowButton")
        waitForEnabled(syncNow)
        syncNow.tap()
        waitForStatus(containing: "Синхронизировано")
        closeAccount()

        let removed = NSPredicate(format: "exists == false")
        let gone = XCTNSPredicateExpectation(predicate: removed, object: app.staticTexts["дом"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: Self.defaultTimeout), .completed, "`дом` is still shown")
        XCTAssertTrue(app.staticTexts["котик"].waitForExistence(timeout: Self.defaultTimeout), "`котик` is missing")
        XCTAssertEqual(app.cells.count, before - 1)
    }

    @MainActor
    func testFailedSyncRecoversWithManualSync() {
        launch(.basicVocabulary, auth: .signedIn, sync: .failsOnce)
        openAccount()
        waitForStatus(containing: "Не удалось синхронизировать")
        let syncNow = element("syncNowButton")
        waitForEnabled(syncNow)
        syncNow.tap()
        waitForStatus(containing: "Синхронизировано")
    }

    @MainActor
    func testOtherLinkedAccountAsksBeforeMerging() {
        launch(.basicVocabulary, auth: .signedIn, sync: .linkedToOtherAccount)
        openAccount()
        XCTAssertTrue(element("syncMismatch").waitForExistence(timeout: Self.defaultTimeout))
        XCTAssertFalse(element("syncNowButton").exists, "no manual sync while paused")
        let merge = element("syncMergeButton")
        waitForEnabled(merge)
        merge.tap()
        XCTAssertTrue(app.staticTexts["Объединить словари?"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Слова и папки с этого iPhone попадут в аккаунт, а слова аккаунта появятся на iPhone. Ничего не удаляется."].exists)
        let confirm = app.buttons["Объединить"]
        waitForHittable(confirm)
        confirm.tap()
        waitForStatus(containing: "Синхронизировано")
    }

    /// Cancelling the confirmation keeps sync paused.
    @MainActor
    func testCancellingTheMergeDialogKeepsSyncPaused() {
        launch(.basicVocabulary, auth: .signedIn, sync: .linkedToOtherAccount)
        openAccount()
        XCTAssertTrue(element("syncMismatch").waitForExistence(timeout: Self.defaultTimeout))
        let merge = element("syncMergeButton")
        waitForEnabled(merge)
        merge.tap()
        XCTAssertTrue(app.staticTexts["Объединить словари?"].waitForExistence(timeout: 10))
        // iOS 26+ presents the dialog as a popover without the cancel button; tapping outside cancels.
        let cancel = app.buttons["Отмена"]
        if cancel.waitForExistence(timeout: 2) {
            waitForHittable(cancel)
            cancel.tap()
        } else {
            let dismissRegion = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismissRegion.waitForExistence(timeout: 5), "No way to cancel the merge dialog")
            dismissRegion.tap()
        }
        let dialogGone = NSPredicate(format: "exists == false")
        let closed = XCTNSPredicateExpectation(predicate: dialogGone, object: app.staticTexts["Объединить словари?"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed, "Dialog is still shown")
        XCTAssertTrue(element("syncMismatch").exists)
        XCTAssertFalse(element("syncNowButton").exists)
        XCTAssertTrue(element("syncMergeButton").exists)
    }
}
