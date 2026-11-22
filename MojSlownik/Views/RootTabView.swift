import SwiftUI

/// Shows the tabs once a workspace exists. Before that: a waiting state while the session is restored
/// or the first pull runs, and the first-launch wizard when the install really has no workspace.
struct RootTabView: View {
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(AuthStore.self) private var auth
    @Environment(SyncStore.self) private var sync
    /// One timer for loading and waiting together (not restarted between them).
    @State private var timedOut = false
    @State private var timerStarted = false
    /// Set once the wizard has shown; it stays until a workspace exists.
    @State private var setupShown = false

    private var phase: WorkspaceGatePhase {
        let authState: WorkspaceGate.Auth
        switch auth.state {
        case .unknown: authState = .unknown
        case .signedOut: authState = .signedOut
        case .signedIn: authState = .signedIn
        }
        return WorkspaceGate.phase(
            hasActiveWorkspace: workspaces.activeID != nil, auth: authState,
            syncAvailable: sync.isAvailable, linkedToCurrentAccount: sync.isLinkedToCurrentAccount,
            workspacePullFinished: sync.workspacePullFinished, syncFailed: sync.status == .failed,
            timedOut: timedOut, setupShown: setupShown)
    }

    var body: some View {
        let phase = phase
        Group {
            if phase == .ready {
                tabs
            } else {
                Color.appBackground
                    .ignoresSafeArea()
                    .overlay { if phase.isWaiting { loading } }
            }
        }
        .task(id: phase.isWaiting) {
            guard phase.isWaiting, !timerStarted else { return }
            timerStarted = true
            try? await Task.sleep(for: WorkspaceGate.timeout)
            if !Task.isCancelled { timedOut = true }
        }
        .fullScreenCover(isPresented: Binding(get: { phase == .needsSetup }, set: { _ in })) {
            WorkspaceWizardView(presentation: .firstLaunch)
        }
        .onChange(of: phase == .needsSetup, initial: true) { _, needsSetup in
            if needsSetup { setupShown = true }
        }
    }

    private var loading: some View {
        VStack(spacing: AppSpacing.s) {
            ProgressView()
            Text("Loading dictionary…")
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("workspaceLoading")
    }

    private var tabs: some View {
        TabView {
            WordListView()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }

            TrainingView()
                .tabItem { Label("Practice", systemImage: "rectangle.stack") }
        }
        .tint(.appAccentStrong)
        .background { AchievementTracker() }
        .achievementBanner()
        .modifier(AppleTranslationHost())
    }
}

#Preview {
    let resources = AppResources.preview
    RootTabView()
        .modelContainer(resources.container)
        .environment(resources.workspaces)
        .environment(resources.folders)
        .environment(resources.vocabulary)
        .environment(resources.dailyStudy)
        .environment(resources.achievements)
        .environment(resources.auth)
        .environment(resources.sync)
}
