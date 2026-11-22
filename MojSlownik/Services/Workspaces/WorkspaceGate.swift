import Foundation

/// What the root shows before the tabs: a waiting state, the first-launch wizard or the app.
enum WorkspaceGatePhase: Equatable {
    /// The session is still being restored.
    case loading
    /// Signed in and linked: the first workspace pull decides whether the account already has workspaces.
    case waitingForAccount
    /// No workspace exists and none is coming: the first-launch wizard.
    case needsSetup
    case ready

    var isWaiting: Bool { self == .loading || self == .waitingForAccount }
}

/// Pure gate logic (the view feeds it store state and a single 10 s timer).
enum WorkspaceGate {
    enum Auth: Equatable {
        case unknown, signedOut, signedIn
    }

    /// `timedOut` covers `loading` and `waitingForAccount` together: once it fires the wizard shows.
    /// `setupShown` keeps the wizard up once shown (a sync retry must not tear it down mid-choice and
    /// return to an untimed wait); only an active workspace ends it.
    static func phase(hasActiveWorkspace: Bool, auth: Auth, syncAvailable: Bool,
                      linkedToCurrentAccount: Bool, workspacePullFinished: Bool,
                      syncFailed: Bool, timedOut: Bool, setupShown: Bool = false) -> WorkspaceGatePhase {
        if hasActiveWorkspace { return .ready }
        if timedOut || setupShown { return .needsSetup }
        switch auth {
        case .unknown:
            return .loading
        case .signedIn where syncAvailable && linkedToCurrentAccount && !workspacePullFinished && !syncFailed:
            return .waitingForAccount
        case .signedIn, .signedOut:
            return .needsSetup
        }
    }

    /// The seconds after which waiting gives up (loading and waiting share one timer).
    static let timeout: Duration = .seconds(10)
}
