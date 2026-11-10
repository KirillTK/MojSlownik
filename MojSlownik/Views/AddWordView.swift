import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    var initialText: String = ""
    @State private var selectedFolderID: UUID?
    @State private var saveError: String?

    @State private var selectedCategory: WordCategory?
    @State private var draft = AddWordDraft()
    @State private var speech = SpeechRecognitionService()
    @State private var isVisible = false
    @FocusState private var sourceFieldFocused: Bool

    init(initialText: String = "", initialFolderID: UUID? = nil) {
        self.initialText = initialText
        _selectedFolderID = State(initialValue: initialFolderID)
    }

    private var detectedLanguage: AppLanguage {
        LanguageDetector.detect(draft.sourceText)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(spacing: 0) {
                        inputCard
                        Divider().overlay(Color.appBorder.opacity(0.5))
                            .padding(.horizontal, 20)
                        translationCard
                    }
                    .cardStyle(cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Размещение")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.subtleText)
                        FolderPicker(selectedFolderID: $selectedFolderID)
                        categoryPicker
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground)
            .foregroundStyle(Color.appInk)
            .tint(Color.appAccent)
            .navigationTitle("Новое слово")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }
                        .fontWeight(.semibold)
                        .disabled(speech.isBusy || draft.sourceText.trimmingCharacters(in: .whitespaces).isEmpty
                                  || draft.translatedText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert(title: "Не удалось сохранить слово", error: $saveError)
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
    }

    private var automaticCategory: WordCategory {
        WordCategory.detect(
            russian: detectedLanguage == .russian ? draft.sourceText : draft.translatedText,
            polish: detectedLanguage == .polish ? draft.sourceText : draft.translatedText
        )
    }

    private var categoryPicker: some View {
        Picker("Категория", selection: $selectedCategory) {
            Text("Автоматически: \(automaticCategory.rawValue)").tag(WordCategory?.none)
            ForEach(WordCategory.allCases) { category in
                Text(category.rawValue).tag(Optional(category))
            }
        }
        .font(.subheadline)
        .tint(Color.appAccent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .cardStyle(cornerRadius: 14)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Слово")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                Text("\((speech.isBusy ? AppLanguage.polish : detectedLanguage).flag) \((speech.isBusy ? AppLanguage.polish : detectedLanguage).displayName)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(Capsule())
                    .opacity(draft.sourceText.isEmpty && speech.draft.isEmpty ? 0 : 1)
            }
            HStack(alignment: .top) {
                TextField("Введите слово…", text: Binding(
                    get: { speech.isBusy && !speech.draft.isEmpty ? speech.draft : draft.sourceText },
                    set: { draft.setSource($0) }
                ), axis: .vertical)
                .font(.title2.weight(.semibold))
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
                        speech.start { text in
                            guard isVisible && scenePhase != .background else { return }
                            draft.commitDictation(text)
                        }
                    }
                } label: {
                    Image(systemName: speech.state == .listening ? "stop.fill" : "mic.fill")
                        .frame(width: 44, height: 44)
                }
                .disabled(speech.isBusy && speech.state != .listening)
                .accessibilityLabel(speech.state == .listening ? "Остановить запись" : "Продиктовать по-польски")
            }
            voiceStatus
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Перевод — \(detectedLanguage.other.flag) \(detectedLanguage.other.displayName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if draft.isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Перевод появится автоматически…", text: $draft.translatedText, axis: .vertical)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 44)
                .autocorrectionDisabled()
                .accessibilityIdentifier("translationField")
                .disabled(speech.isBusy)

            if let translationError = draft.translationError {
                Label(translationError, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.appError)
            }

            if !draft.translatedText.isEmpty {
                HStack {
                    Spacer()
                    PronounceButton(
                        text: detectedLanguage == .russian ? draft.translatedText : draft.sourceText,
                        language: .polish
                    )
                    .disabled(speech.isBusy)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var voiceStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if speech.isBusy {
                HStack {
                    Text(speech.state == .requestingPermission ? "Запрашиваем доступ…" :
                         speech.state == .finishing ? "Завершаем распознавание…" : "Говорите по-польски…")
                    Spacer()
                    Button("Отменить запись") { speech.cancel() }
                        .frame(minHeight: 44)
                }
            }
            if let error = speech.errorMessage {
                Label(error, systemImage: "mic.slash")
                    .foregroundStyle(Color.appError)
            }
            Text("Речь может обрабатываться на серверах Apple. Распознанный текст отправляется сервису перевода.")
                .foregroundStyle(Color.subtleText)
        }
        .font(.caption)
    }

    private func save() {
        let text = draft.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = draft.translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try ScanWordStore.add(source: text, translation: translation, category: selectedCategory,
                                  folderID: selectedFolderID, container: modelContext.container)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}

#Preview {
    AddWordView()
        .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
        .environment(FolderLibraryStore())
}
