import XCTest

/// Account sheet with the network-free UI-test auth backend. The real Apple/Google sheets
/// (ASWebAuthenticationSession via supabase-swift) are a manual device check.
final class AccountFlowTests: E2ETestCase {
    @MainActor
    private func openAccount() {
        let button = app.navigationBars.buttons["accountButton"]
        waitForHittable(button)
        button.tap()
        XCTAssertTrue(app.navigationBars["Аккаунт"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func signOut() {
        let button = element("signOutButton")
        waitForHittable(button)
        button.tap()
        waitForHittable(element("signIn.google"))
    }

    @MainActor
    func testSignInWithGoogleThenSignOut() {
        launch(.basicVocabulary, auth: .signedOut)
        openAccount()

        waitForHittable(element("signIn.apple"))
        let google = element("signIn.google")
        waitForHittable(google)
        XCTAssertFalse(element("accountCard").exists)
        google.tap()

        let card = element("accountCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("tester@example.com"), card.label)
        XCTAssertTrue(card.label.contains("Google"), card.label)
        XCTAssertFalse(element("signIn.google").exists)

        signOut()
        XCTAssertFalse(element("accountCard").exists)
    }

    @MainActor
    func testSignInWithAppleShowsAppleProvider() {
        launch(.empty, auth: .signedOut)
        openAccount()
        let apple = element("signIn.apple")
        waitForHittable(apple)
        apple.tap()
        let card = element("accountCard")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("Apple"), card.label)
    }

    @MainActor
    func testFailedSignInShowsMessageAndStaysSignedOut() {
        launch(.empty, auth: .failing)
        openAccount()
        let apple = element("signIn.apple")
        waitForHittable(apple)
        apple.tap()
        let error = element("accountError")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("Не удалось войти"), error.label)
        waitForEnabled(element("signIn.google"))
        XCTAssertFalse(element("accountCard").exists)
    }

    @MainActor
    func testExistingSessionShowsAccountAndDoneCloses() {
        launch(.basicVocabulary, auth: .signedIn)
        openAccount()
        XCTAssertTrue(element("accountCard").waitForExistence(timeout: 10))
        XCTAssertFalse(element("signIn.apple").exists)
        app.navigationBars["Аккаунт"].buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Словарь"].waitForExistence(timeout: 10))
    }

    /// Signing out must not touch the local dictionary.
    @MainActor
    func testSignOutKeepsWords() {
        launch(.basicVocabulary, auth: .signedIn)
        // Review finding: count only after the seeded list has rendered (not 0 == 0).
        XCTAssertTrue(app.staticTexts["кот"].waitForExistence(timeout: 10), "Seeded word missing")
        let wordCountBefore = app.cells.count
        openAccount()
        signOut()
        app.navigationBars["Аккаунт"].buttons["Готово"].tap()
        XCTAssertTrue(app.navigationBars["Словарь"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["кот"].waitForExistence(timeout: 10), "Words survive sign-out")
        XCTAssertEqual(app.cells.count, wordCountBefore)
        XCTAssertGreaterThan(wordCountBefore, 0)
    }
}
