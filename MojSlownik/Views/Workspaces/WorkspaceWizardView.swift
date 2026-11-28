import SwiftUI
import SwiftData

/// Two-step language wizard: the studied language, then the translation language. Shown full screen
/// on the first launch (no cancel) and as a sheet from “New language…” (with “Cancel”).
struct WorkspaceWizardView: View {
    enum Presentation { case firstLaunch, sheet }

    let presentation: Presentation

    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(\.dismiss) private var dismiss
    @Query private var storedWorkspaces: [Workspace]
    @State private var studied: Language = .polish
    @State private var translation: Language? = .russian
    @State private var showTranslationStep = false
    @State private var errorMessage: String?

    private var choices: WorkspaceWizardChoices {
        let deleted = storedWorkspaces.filter { !$0.isActive }
        return WorkspaceWizardChoices(
            activeIDs: Set(storedWorkspaces.filter(\.isActive).map(\.id)),
            deletedIDs: Set(deleted.map(\.id)),
            deletedPairs: deleted.compactMap { LanguagePair(termCode: $0.termLanguageCode, translationCode: $0.translationLanguageCode) })
    }

    var body: some View {
        NavigationStack {
            WizardStepView(step: 1, title: "Which language are you learning?",
                           message: "Each language gets its own dictionary, folders and practice.",
                           languages: choices.studyLanguages, selection: studied, identifierPrefix: "wizardLanguage",
                           subtitle: { $0.endonym == $0.localizedName ? "" : $0.endonym }, isDisabled: { _ in false },
                           select: selectStudied) {
                Button("Next") { showTranslationStep = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("wizardNextButton")
            }
            .toolbar {
                if presentation == .sheet {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .tint(Color.appAccentText)
                    }
                }
            }
            .navigationDestination(isPresented: $showTranslationStep) {
                translationStep
                    .accessibilityAction(.escape) { showTranslationStep = false }
            }
        }
        .tint(.appAccentText)
        .interactiveDismissDisabled(presentation == .firstLaunch)
        .errorAlert(title: "Couldn’t add the language", error: $errorMessage)
    }

    private var translationStep: some View {
        WizardStepView(step: 2, title: "Translate into which language?",
                       message: "Usually your native language. The app interface follows your iPhone’s language.",
                       languages: choices.translationLanguages(for: studied), selection: translation, identifierPrefix: "wizardTranslation",
                       subtitle: translationSubtitle, isDisabled: { $0 == studied },
                       select: { translation = $0 }, footnote: "You can add a pair later: “New language…” in the dictionary title.") {
            Button { start() } label: {
                if let translation {
                    Text("Start — \(studied.flag) ← \(translation.flag)")
                } else {
                    Text("Start")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(translation == nil)
            .accessibilityLabel(startAccessibilityLabel)
            .accessibilityIdentifier("wizardStartButton")
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showTranslationStep = false } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .tint(Color.appAccentText)
            }
        }
    }

    private var startAccessibilityLabel: String {
        guard let translation else { return String(localized: "Start") }
        return String(localized: "Start: \(studied.names.inline), translated into \(translation.names.inline)")
    }

    private func translationSubtitle(_ language: Language) -> String {
        if language == studied { return String(localized: "already chosen as the language you’re learning") }
        switch choices.status(term: studied, translation: language) {
        case .existing: return String(localized: "already exists — will open")
        case .restorable: return String(localized: "will return with its words")
        case .available, .sameAsStudied: return language.endonym == language.localizedName ? "" : language.endonym
        }
    }

    private func selectStudied(_ language: Language) {
        studied = language
        translation = choices.translation(afterStudying: language, current: translation)
    }

    private func start() {
        guard let translation else { return }
        do {
            try workspaces.create(term: studied.code, translation: translation.code)
            // First launch: the gate sees the active workspace and closes the cover.
            if presentation == .sheet { dismiss() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One wizard page: progress, kicker, title, language list, optional footnote and a bottom action.
private struct WizardStepView<Action: View>: View {
    let step: Int
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let languages: [Language]
    let selection: Language?
    let identifierPrefix: String
    let subtitle: (Language) -> String
    let isDisabled: (Language) -> Bool
    let select: (Language) -> Void
    var footnote: LocalizedStringKey?
    @ViewBuilder var action: Action

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(step: Int, title: LocalizedStringKey, message: LocalizedStringKey, languages: [Language], selection: Language?,
         identifierPrefix: String, subtitle: @escaping (Language) -> String,
         isDisabled: @escaping (Language) -> Bool, select: @escaping (Language) -> Void,
         footnote: LocalizedStringKey? = nil, @ViewBuilder action: () -> Action) {
        self.step = step
        self.title = title
        self.message = message
        self.languages = languages
        self.selection = selection
        self.identifierPrefix = identifierPrefix
        self.subtitle = subtitle
        self.isDisabled = isDisabled
        self.select = select
        self.footnote = footnote
        self.action = action()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                header
                languageCard
                if let footnote { infoLine(footnote) }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.top, AppSpacing.xs)
            .padding(.bottom, AppSpacing.l)
        }
        .background(Color.appBackground)
        .foregroundStyle(Color.appInk)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            action
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.s)
                .background(Color.appBackground)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(1...2, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.appAccentStrong : Color.appSecondarySurface)
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            .padding(.bottom, AppSpacing.xs)
            Text("Step \(step) of 2")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Color.subtleText)
            Text(title)
                .font(.title.weight(.heavy))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.subtleText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languageCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(languages.enumerated()), id: \.element.id) { index, language in
                if index > 0 {
                    Rectangle()
                        .fill(Color.appBorder)
                        .frame(height: 1)
                        .padding(.leading, AppSpacing.m + 40)
                        .accessibilityHidden(true)
                }
                row(language)
            }
        }
        .cardStyle(cornerRadius: AppRadius.card)
    }

    private func row(_ language: Language) -> some View {
        let isSelected = selection == language
        let disabled = isDisabled(language)
        let detail = subtitle(language)
        return Button {
            select(language)
        } label: {
            HStack(spacing: AppSpacing.s) {
                Text(language.flag)
                    .font(.title2)
                    .opacity(disabled ? 0.45 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: language.localizedName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.appInk)
                        .opacity(disabled ? 0.45 : 1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Color.subtleText)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.xs)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.appAccentStrong)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, AppSpacing.m)
            .padding(.vertical, AppSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(WorkspaceLabels.accessibilityName(of: language) + (detail.isEmpty || detail == language.endonym ? "" : ", " + detail))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("\(identifierPrefix)-\(language.code)")
    }

    private func infoLine(_ text: LocalizedStringKey) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: AppSpacing.xs))
        return layout {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(Color.subtleText)
    }
}
