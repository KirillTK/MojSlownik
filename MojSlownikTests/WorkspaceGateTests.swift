import XCTest
@testable import MojSlownik

final class WorkspaceGateTests: XCTestCase {
    private func phase(active: Bool = false, auth: WorkspaceGate.Auth = .signedOut, available: Bool = true,
                       linked: Bool = false, pulled: Bool = false, failed: Bool = false,
                       timedOut: Bool = false, setupShown: Bool = false) -> WorkspaceGatePhase {
        WorkspaceGate.phase(hasActiveWorkspace: active, auth: auth, syncAvailable: available,
                            linkedToCurrentAccount: linked, workspacePullFinished: pulled,
                            syncFailed: failed, timedOut: timedOut, setupShown: setupShown)
    }

    func testShownWizardStaysWhenASyncRetryStartsWaitingAgain() {
        // A failed first pull showed the wizard; a retry (status back to syncing) must not
        // tear it down into an untimed wait.
        XCTAssertEqual(phase(auth: .signedIn, linked: true, failed: true), .needsSetup)
        XCTAssertEqual(phase(auth: .signedIn, linked: true), .waitingForAccount)
        XCTAssertEqual(phase(auth: .signedIn, linked: true, setupShown: true), .needsSetup)
        XCTAssertEqual(phase(auth: .unknown, setupShown: true), .needsSetup)
        XCTAssertEqual(phase(active: true, auth: .signedIn, linked: true, setupShown: true), .ready)
    }

    func testAnActiveWorkspaceIsAlwaysReady() {
        for auth in [WorkspaceGate.Auth.unknown, .signedOut, .signedIn] {
            XCTAssertEqual(phase(active: true, auth: auth, linked: true, timedOut: true), .ready)
        }
    }

    func testUnknownSessionLoadsUntilTheTimeout() {
        XCTAssertEqual(phase(auth: .unknown), .loading)
        XCTAssertEqual(phase(auth: .unknown, timedOut: true), .needsSetup)
    }

    func testSignedOutFreshInstallNeedsSetup() {
        XCTAssertEqual(phase(auth: .signedOut), .needsSetup)
    }

    func testSignedInAndLinkedWaitsForTheFirstPull() {
        XCTAssertEqual(phase(auth: .signedIn, linked: true), .waitingForAccount)
    }

    func testWaitingEndsWithTheWizardWhenThePullFinishedEmptyFailedOrTimedOut() {
        XCTAssertEqual(phase(auth: .signedIn, linked: true, pulled: true), .needsSetup, "empty account")
        XCTAssertEqual(phase(auth: .signedIn, linked: true, failed: true), .needsSetup, "failed pull")
        XCTAssertEqual(phase(auth: .signedIn, linked: true, timedOut: true), .needsSetup, "timeout")
    }

    func testSignedInWithoutAWorkingSyncGoesStraightToTheWizard() {
        XCTAssertEqual(phase(auth: .signedIn, available: false, linked: true), .needsSetup, "no transport")
        XCTAssertEqual(phase(auth: .signedIn, linked: false), .needsSetup, "linked to another account")
    }

    func testOneTimeoutCoversLoadingAndWaiting() {
        // The same `timedOut` flag ends both waiting phases.
        XCTAssertTrue(phase(auth: .unknown).isWaiting)
        XCTAssertTrue(phase(auth: .signedIn, linked: true).isWaiting)
        XCTAssertFalse(phase(auth: .unknown, timedOut: true).isWaiting)
        XCTAssertFalse(phase(auth: .signedIn, linked: true, timedOut: true).isWaiting)
        XCTAssertEqual(WorkspaceGate.timeout, .seconds(10))
    }

    func testReadyAndNeedsSetupAreNotWaiting() {
        XCTAssertFalse(WorkspaceGatePhase.ready.isWaiting)
        XCTAssertFalse(WorkspaceGatePhase.needsSetup.isWaiting)
    }
}
