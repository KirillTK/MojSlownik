import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var initialText: String = ""
    @State private var selectedFolderID: UUID?
    @State private var saveError: String?

    @State private var selectedCategory: WordCategory?
    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var translationTask: Task<Void, Never>?
    @FocusState private var sourceFieldFocused: Bool

    init(initialText: String = "", initialFolderID: UUID? = nil) {
        self.initialText = initialText
        _selectedFolderID = State(initialValue: initialFolderID)
    }

    private var detectedLanguage: AppLanguage {
        LanguageDetector.detect(sourceText)
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
                        .disabled(sourceText.trimmingCharacters(in: .whitespaces).isEmpty
                                  || translatedText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .errorAlert(title: "Не удалось сохранить слово", error: $saveError)
            .onDisappear { translationTask?.cancel() }
            .onAppear {
                if sourceText.isEmpty {
                    sourceText = initialText
                    if !sourceText.isEmpty {
                        scheduleTranslation()
                    }
                }
                sourceFieldFocused = true
            }
        }
    }

    private var automaticCategory: WordCategory {
        WordCategory.detect(
            russian: detectedLanguage == .russian ? sourceText : translatedText,
            polish: detectedLanguage == .polish ? sourceText : translatedText
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
                Text("\(detectedLanguage.flag) \(detectedLanguage.displayName)")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.12))
                    .foregroundStyle(Color.appAccent)
                    .clipShape(Capsule())
                    .opacity(sourceText.isEmpty ? 0 : 1)
            }
            TextField("Введите слово…", text: $sourceText, axis: .vertical)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 44)
                .focused($sourceFieldFocused)
                .autocorrectionDisabled()
                .accessibilityIdentifier("sourceField")
                .onChange(of: sourceText) {
                    scheduleTranslation()
                }
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
                if isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Перевод появится автоматически…", text: $translatedText, axis: .vertical)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.appInk)
                .frame(minHeight: 44)
                .autocorrectionDisabled()
                .accessibilityIdentifier("translationField")

            if let translationError {
                Label(translationError, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(Color.appError)
            }

            if !translatedText.isEmpty {
                HStack {
                    Spacer()
                    PronounceButton(
                        text: detectedLanguage == .russian ? translatedText : sourceText,
                        language: .polish
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduleTranslation() {
        translationTask?.cancel()
        translationError = nil
        // Перевод всегда сбрасывается: иначе при быстрой правке слова можно
        // сохранить пару со старым переводом.
        translatedText = ""

        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isTranslating = false
            return
        }

        let source = LanguageDetector.detect(text)
        translationTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600)) // debounce после окончания ввода
                await MainActor.run { isTranslating = true }
                let result = try await Translator.translate(text, from: source, to: source.other)
                try Task.checkCancellation()
                await MainActor.run {
                    translatedText = result
                    isTranslating = false
                }
            } catch is CancellationError {
                // Начали печатать дальше — молча отменяем.
            } catch {
                await MainActor.run {
                    isTranslating = false
                    translationError = error.localizedDescription
                }
            }
        }
    }

    private func save() {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
