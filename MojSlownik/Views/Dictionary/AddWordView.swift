import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VocabularyStore.self) private var vocabulary
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var initialText: String = ""
    @State private var selectedFolderID: UUID?
    @State private var saveError: String?

    @State private var selectedCategory: WordCategory?
    @State private var draft: AddWordDraft
    @State private var speech = SpeechRecognitionService()
    @State private var isVisible = false
    @State private var selectionTick = 0
    @FocusState private var sourceFieldFocused: Bool

    /// `inputSide`: the stored typing side of a same-script pair; nil detects it from the script.
    init(initialText: String = "", initialFolderID: UUID? = nil, pair: LanguagePair,
         inputSide: WordSide? = nil) {
        self.initialText = initialText
        _selectedFolderID = State(initialValue: initialFolderID)
        _draft = State(initialValue: AddWordDraft(pair: pair, inputSide: inputSide))
    }

    private var pair: LanguagePair { draft.pair }
    private var sourceLanguage: Language { pair.language(of: draft.resolvedSide) }
    private var translationLanguage: Language { pair.language(of: draft.resolvedSide.other) }

    /// Dictation: the studied language, or the typing side's language in a same-script pair.
    private var dictationLanguage: Language {
        pair.isSameScript ? pair.language(of: draft.inputSide ?? .term) : pair.term
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    if pair.isSameScript { inputSideControl }
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        VStack(spacing: 0) {
                            inputCard
                            Divider().overlay(Color.appBorder)
                                .padding(.horizontal, AppSpacing.l)
                            translationCard
                        }
                        .cardStyle(cornerRadius: AppRadius.hero)
                        if pair.isSameScript { sameScriptInfo }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Placement")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Color.subtleText)
                        FolderPicker(selectedFolderID: $selectedFolderID)
                        categoryPicker
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .tint(Color.appAccentText)
            .safeAreaInset(edge: .bottom) {
                Button("Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("saveWordButton")
                    .disabled(speech.isBusy || draft.sourceText.trimmingCharacters(in: .whitespaces).isEmpty
                              || draft.translatedText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.vertical, AppSpacing.s)
                    .background(Color.appBackground)
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .navigationTitle("New word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .errorAlert(title: "Couldn’t save the word", error: $saveError)
            .onDisappear {
                isVisible = false
                speech.cancel()
                draft.cancelTranslation()
            }
            .onChange(of: speech.isBusy) { _, busy in
                if !busy && isVisible && scenePhase != .background { draft.endDictation() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    speech.cancel()
                } else if phase == .active && isVisible && !speech.isBusy {
                    draft.endDictation()
                }
            }
            .onAppear {
                isVisible = true
                if draft.sourceText.isEmpty {
                    draft.setSource(initialText)
                }
                draft.endDictation()
                draft.resumeTranslationIfNeeded()
                sourceFieldFocused = true
            }
        }
        .achievementBanner()
    }

    /// Same-script pairs cannot tell the sides apart by letters: the user picks the typing side, remembered per workspace.
    private var inputSideControl: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("I’m typing in")
                .font(.footnote.weight(.bold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Color.subtleText)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                inputSidePicker.pickerStyle(.menu)
            } else {
                inputSidePicker.pickerStyle(.segmented)
            }
        }
    }

    private var inputSidePicker: some View {
        Picker("I’m typing in", selection: Binding(
            get: { draft.inputSide ?? .term },
            set: { side in
                draft.setInputSide(side)
                if let id = workspaces.activeID { workspaces.setInputSide(side, for: id) }
            }
        )) {
            ForEach([WordSide.term, .translation], id: \.self) { side in
                let language = pair.language(of: side)
                Text(verbatim: "\(language.flag) \(language.names.inputOption)")
                    .accessibilityLabel(Text(verbatim: language.localizedName))
                    .tag(side)
            }
        }
        .accessibilityIdentifier("inputSideControl")
    }

    private var sameScriptInfo: some View {
        Label("\(pair.term.names.genitive) and \(pair.translation.names.genitive) use the same alphabet, so choose the input language manually. Your choice is remembered.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(Color.subtleText)
            .padding(.horizontal, AppSpacing.xxs)
    }

    private var automaticCategory: WordCategory {
        let isTerm = draft.resolvedSide == .term
        return WordCategory.detect(
            term: isTerm ? draft.sourceText : draft.translatedText,
            translation: isTerm ? draft.translatedText : draft.sourceText
        )
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategory) {
            Text("Automatically: \(automaticCategory.title)").tag(WordCategory?.none)
            ForEach(WordCategory.allCases) { category in
                Text(category.title).tag(Optional(category))
            }
        }
        .font(.subheadline)
        .tint(Color.appAccentText)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .cardStyle(cornerRadius: AppRadius.control)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Word")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                Text(verbatim: "\((speech.isBusy ? dictationLanguage : sourceLanguage).flag) \((speech.isBusy ? dictationLanguage : sourceLanguage).endonym)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccentSoft)
                    .foregroundStyle(Color.appInk)
                    .clipShape(Capsule())
                    .opacity(draft.sourceText.isEmpty && speech.draft.isEmpty ? 0 : 1)
            }
            HStack(alignment: .top) {
                TextField("Type a word…", text: Binding(
                    get: { speech.isBusy && !speech.draft.isEmpty ? speech.draft : draft.sourceText },
                    set: { draft.setSource($0) }
                ), axis: .vertical)
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 44)
                .focused($sourceFieldFocused)
                .autocorrectionDisabled()
                .accessibilityIdentifier("sourceField")
                .disabled(speech.isBusy)
                Button {
                    if speech.state == .listening {
                        speech.finish()
                    } else {
                        sourceFieldFocused = false
                        draft.beginDictation()
                        speech.start(locale: dictationLanguage.speechCode) { text in
                            guard isVisible && scenePhase != .background else { return }
                            draft.commitDictation(text)
                        }
                    }
                } label: {
                    Image(systemName: speech.state == .listening ? "waveform" : "mic")
                        .fontWeight(.medium)
                        .symbolEffect(.variableColor.iterative, isActive: speech.state == .listening && !reduceMotion)
                        .frame(width: 44, height: 44)
                }
                .disabled(speech.isBusy && speech.state != .listening)
                .accessibilityLabel(speech.state == .listening ? "Stop recording" : "Dictate \(dictationLanguage.names.adverb)")
            }
            voiceStatus
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Translation — \(translationLanguage.flag) \(translationLanguage.endonym)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if draft.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("The translation will appear automatically…", text: $draft.translatedText, axis: .vertical)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 44)
                .autocorrectionDisabled()
                .accessibilityIdentifier("translationField")
                .disabled(speech.isBusy)

            if let translationError = draft.translationError {
                Label("Auto-translation unavailable — enter the translation manually", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.subtleText)
                    .accessibilityLabel("Auto-translation unavailable. \(translationError)")
            }

            if !draft.translationOptions.isEmpty {
                alternativesRow
            }

            if !draft.translatedText.isEmpty {
                HStack {
                    Spacer()
                    PronounceButton(
                        text: draft.resolvedSide == .term ? draft.sourceText : draft.translatedText,
                        language: pair.term
                    )
                    .disabled(speech.isBusy)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alternativesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alternatives")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.subtleText)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draft.translationOptions, id: \.self) { alternativeChip($0) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.translationOptions, id: \.self) { alternativeChip($0) }
                    }
                }
            }
        }
    }

    private func alternativeChip(_ option: TranslationAlternative) -> some View {
        let selected = draft.isSelected(option)
        return Button {
            draft.select(option)
            selectionTick += 1
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(option.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(selected ? Color.appOnAccent : Color.appInk)
                    .lineLimit(2)
                if let pos = option.partOfSpeech {
                    Text(pos)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.appOnAccent : Color.subtleText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 260, minHeight: 44, alignment: .leading)
            .background(selected ? Color.appAccent : Color.appSecondarySurface,
                        in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(speech.isBusy)
        .accessibilityLabel(option.text + (option.partOfSpeech.map { ", \($0)" } ?? ""))
        .accessibilityIdentifier("translationOption-\(option.text)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var voiceStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if speech.isBusy {
                HStack {
                    Text(speech.state == .requestingPermission ? "Requesting access…" :
                         speech.state == .finishing ? "Finishing recognition…" : "Speak \(dictationLanguage.names.adverb)…")
                    Spacer()
                    Button("Cancel recording") { speech.cancel() }
                        .frame(minHeight: 44)
                }
            }
            if let error = speech.errorMessage {
                Label(error, systemImage: "mic.slash")
                    .foregroundStyle(Color.appError)
            }
            Text("Speech may be processed on Apple servers. Entered and recognized text is sent to translation services (Google, MyMemory).")
                .foregroundStyle(Color.subtleText)
        }
        .font(.caption)
    }

    private func save() {
        let text = draft.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = draft.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try vocabulary.add(WordEntry.make(input: text, translation: translation, side: draft.resolvedSide), category: selectedCategory,
                               folderID: selectedFolderID)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}

#Preview {
    let resources = AppResources.preview
    AddWordView(pair: .polishRussian)
        .modelContainer(resources.container)
        .environment(resources.workspaces)
        .environment(resources.folders)
        .environment(resources.vocabulary)
        .environment(resources.dailyStudy)
        .environment(resources.achievements)
}
