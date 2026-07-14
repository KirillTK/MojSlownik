import SwiftUI
import SwiftData

struct AddWordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var initialText: String = ""

    @State private var sourceText = ""
    @State private var translatedText = ""
    @State private var isTranslating = false
    @State private var translationError: String?
    @State private var translationTask: Task<Void, Never>?
    @FocusState private var sourceFieldFocused: Bool

    private var detectedLanguage: AppLanguage {
        LanguageDetector.detect(sourceText)
    }

    /// Слова из отсканированной строки — быстрый выбор одного слова чипами.
    private var scannedWords: [String] {
        let parts = initialText
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ'-")).inverted)
            .filter { $0.count > 1 }
        return parts.count > 1 ? parts : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if !scannedWords.isEmpty {
                        scannedWordChips
                    }

                    inputCard

                    translationCard
                }
                .padding()
            }
            .background(Color.appBackground)
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
            .onAppear {
                if sourceText.isEmpty {
                    sourceText = scannedWords.isEmpty ? initialText : ""
                    if !sourceText.isEmpty {
                        scheduleTranslation()
                    }
                }
                sourceFieldFocused = true
            }
        }
    }

    private var scannedWordChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Распознанные слова")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.subtleText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(scannedWords, id: \.self) { word in
                        Button {
                            sourceText = word
                            scheduleTranslation()
                        } label: {
                            Text(word)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    sourceText == word
                                        ? Color.appAccent
                                        : Color.appAccent.opacity(0.12)
                                )
                                .foregroundStyle(sourceText == word ? .white : Color.appAccent)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Слово")
                    .font(.footnote.weight(.medium))
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
                .font(.title3.weight(.medium))
                .focused($sourceFieldFocused)
                .autocorrectionDisabled()
                .onChange(of: sourceText) {
                    scheduleTranslation()
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var translationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Перевод — \(detectedLanguage.other.flag) \(detectedLanguage.other.displayName)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.subtleText)
                Spacer()
                if isTranslating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextField("Перевод появится автоматически…", text: $translatedText, axis: .vertical)
                .font(.title3.weight(.medium))
                .autocorrectionDisabled()

            if let translationError {
                Label(translationError, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
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
        let language = LanguageDetector.detect(text)

        let word = Word(
            russian: language == .russian ? text : translation,
            polish: language == .polish ? text : translation,
            sourceLanguage: language
        )
        modelContext.insert(word)
        dismiss()
    }
}

#Preview {
    AddWordView()
        .modelContainer(for: Word.self, inMemory: true)
}
