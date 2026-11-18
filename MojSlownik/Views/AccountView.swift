import SwiftUI

/// Account sheet: sign in with Apple or Google (supabase-swift OAuth), or the signed-in account
/// with sign-out. A successful sign-in closes the sheet. Signing out never touches local words.
struct AccountView: View {
    @Environment(AuthStore.self) private var auth
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
            .background(Color.appBackground)
            .onDisappear { auth.dismissError() }
            // A successful sign-in closes the sheet; opening it while signed in shows the account.
            .onChange(of: auth.state) { previous, state in
                if state.completesSignIn(from: previous) { dismiss() }
            }
            .navigationTitle("Аккаунт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
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

            Text("Аккаунт")
                .font(.title3.bold())
                .foregroundStyle(Color.appInk)
                .padding(.bottom, AppSpacing.xs)

            signInButton(.apple, title: "Войти через Apple", kind: .ink) {
                Image(systemName: "apple.logo")
            }
            signInButton(.google, title: "Войти через Google", kind: .card) {
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

    private func signInButton(_ provider: AuthProvider, title: String, kind: PrimaryButtonStyle.Kind,
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
                Text(account.email ?? "Без почты")
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

            Button {
                Task { await auth.signOut() }
            } label: {
                if auth.isSigningOut {
                    ProgressView()
                } else {
                    Text("Выйти").font(.body.weight(.semibold))
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
    return AccountView().environment(auth)
}

#Preview("Signed in") {
    let auth = AuthStore(backend: StaticAuthBackend(account: StaticAuthBackend.testAccount))
    auth.start()
    return AccountView().environment(auth)
}
