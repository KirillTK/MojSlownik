import SwiftUI

/// Account sheet: sign in with Apple or Google (supabase-swift OAuth), or the signed-in account
/// with sign-out. A successful sign-in closes the sheet. Signing out never touches local words.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(SyncStore.self) private var sync
    @State private var confirmingMerge = false
    /// Set by the manual button; the next terminal status is announced to VoiceOver.
    @State private var announceNextResult = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var tileSize: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var providerLogoSize: CGFloat = 20

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.m) {
                    switch auth.state {
                    case .unknown:
                        ProgressView()
                            .padding(.top, AppSpacing.xxl)
                    case .signedOut:
                        signedOut
                    case .signedIn(let account):
                        signedIn(account)
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.m)
            }
            .onChange(of: sync.status) { _, status in announceIfManual(status) }
            .background(Color.appBackground)
            .onDisappear { auth.dismissError() }
            // A successful sign-in closes the sheet; opening it while signed in shows the account.
            .onChange(of: auth.state) { previous, state in
                if state.completesSignIn(from: previous) { dismiss() }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Color.appAccentText)
                }
            }
        }
    }

    private var signedOut: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: "person.crop.circle")
                .font(.largeTitle)
                .fontWeight(.medium)
                .foregroundStyle(Color.appInk)
                .frame(width: tileSize, height: tileSize)
                .background(Color.appAccentSoft, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .accessibilityHidden(true)
                .padding(.top, AppSpacing.s)

            Text("Account")
                .font(.title3.bold())
                .foregroundStyle(Color.appInk)
                .padding(.bottom, AppSpacing.xs)

            signInButton(.apple, title: "Sign in with Apple", kind: .ink) {
                Image(systemName: "apple.logo")
            }
            signInButton(.google, title: "Sign in with Google", kind: .card) {
                // Official multicolour "G" (Google sign-in branding), never tinted.
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: providerLogoSize, height: providerLogoSize)
            }

            errorLabel
        }
    }

    /// Calm recoverable-error line (DESIGN.md pattern), shared by both states.
    @ViewBuilder private var errorLabel: some View {
        if let message = auth.errorMessage {
            Label(message, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Color.subtleText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("accountError")
        }
    }

    private func signInButton(_ provider: AuthProvider, title: LocalizedStringKey, kind: PrimaryButtonStyle.Kind,
                              @ViewBuilder icon: () -> some View) -> some View {
        Button {
            Task { await auth.signIn(with: provider) }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                if auth.pendingProvider == provider {
                    ProgressView()
                } else {
                    icon().accessibilityHidden(true)
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(kind: kind))
        .disabled(auth.isBusy)
        .accessibilityIdentifier("signIn.\(provider.rawValue)")
    }

    private func signedIn(_ account: AuthAccount) -> some View {
        VStack(spacing: AppSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                Text(account.email ?? String(localized: "No email"))
                    .font(.body)
                    .foregroundStyle(Color.appInk)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer(minLength: AppSpacing.xs)
                if let provider = account.provider {
                    Text(provider.displayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.subtleText)
                }
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("accountCard")

            syncCard

            Button {
                Task { await auth.signOut() }
            } label: {
                if auth.isSigningOut {
                    ProgressView()
                } else {
                    Text("Sign out").font(.body.weight(.semibold))
                }
            }
            .tint(Color.appAccentText)
            .frame(minHeight: 44)
            .disabled(auth.isBusy)
            .accessibilityIdentifier("signOutButton")

            errorLabel
        }
    }
}

extension AccountView {
    /// Sync status and manual sync; the mismatch block when this iPhone is linked to another
    /// account. Hidden when the build has no sync transport.
    @ViewBuilder fileprivate var syncCard: some View {
        if sync.status != .unavailable {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Sync")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appInk)
                    // A single long word: shrink a little at the largest sizes instead of
                    // breaking mid-word.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)

                if sync.status == .accountMismatch {
                    mismatchBlock
                } else {
                    statusRow
                    Button {
                        announceNextResult = true
                        sync.syncNow()
                    } label: {
                        Text("Sync now")
                            .font(.body.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .tint(Color.appAccentText)
                    .disabled(!sync.canSyncNow)
                    .accessibilityIdentifier("syncNowButton")
                }
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    @ViewBuilder private var statusRow: some View {
        if sync.status == .failed {
            // Calm recoverable-error pattern (DESIGN.md): no red, the next trigger retries.
            calmNote(sync.statusText)
                .accessibilityIdentifier("syncStatus")
        } else {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                if sync.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Text(sync.statusText)
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sync.isSyncing ? String(localized: "Sync in progress") : sync.statusText)
            .accessibilityIdentifier("syncStatus")
        }
    }

    /// The calm `info.circle` footnote; the icon stacks above the text at accessibility sizes.
    @ViewBuilder private func calmNote(_ text: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Image(systemName: "info.circle")
                    Text(text)
                }
            } else {
                Label(text, systemImage: "info.circle")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.subtleText)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func announceIfManual(_ status: SyncStore.Status) {
        guard announceNextResult else { return }
        switch status {
        case .synced, .failed:
            announceNextResult = false
            AccessibilityNotification.Announcement(sync.statusText).post()
        default:
            break
        }
    }

    private var mismatchBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            calmNote(sync.statusText)
                .accessibilityIdentifier("syncMismatch")
            Button {
                confirmingMerge = true
            } label: {
                Text("Merge dictionaries")
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .tint(Color.appAccentText)
            .accessibilityIdentifier("syncMergeButton")
            .confirmationDialog("Merge dictionaries?",
                                isPresented: $confirmingMerge, titleVisibility: .visible) {
                Button("Merge") { sync.confirmLinkToCurrentAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Words and folders from this iPhone will go to the account, and the account’s words will appear on this iPhone. Nothing is deleted.")
            }
        }
    }
}

extension AuthProvider {
    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

#Preview("Signed out") {
    let auth = AuthStore(backend: StaticAuthBackend())
    auth.start()
    return AccountView().environment(auth).environment(AppResources.preview.sync)
}

#Preview("Signed in") {
    let auth = AuthStore(backend: StaticAuthBackend(account: StaticAuthBackend.testAccount))
    auth.start()
    return AccountView().environment(auth).environment(AppResources.preview.sync)
}
