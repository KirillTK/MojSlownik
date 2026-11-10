import Foundation
import Observation

@MainActor
@Observable
final class AddWordDraft {
    var sourceText = ""
    var translatedText = ""
    private(set) var isTranslating = false
    private(set) var translationError: String?
    private var task: Task<Void, Never>?
    private var revision = 0
    private var suspended = false
    private var needsResume = false
    private let debounce: Duration
    private let translate: (String, AppLanguage) async throws -> String

    init(debounce: Duration = .milliseconds(600),
         translate: @escaping (String, AppLanguage) async throws -> String = { text, source in
             try await Translator.translate(text, from: source, to: source.other)
         }) {
        self.debounce = debounce
        self.translate = translate
    }

    func setSource(_ text: String) {
        sourceText = text
        scheduleTranslation()
    }

    func beginDictation() {
        needsResume = translatedText.isEmpty
        suspended = true
        cancelTranslation()
    }

    func commitDictation(_ text: String) {
        suspended = false
        needsResume = false
        setSource(text)
    }

    func endDictation() {
        guard suspended else { return }
        suspended = false
        if needsResume { scheduleTranslation() }
        needsResume = false
    }

    func resumeTranslationIfNeeded() {
        guard task == nil, !suspended, translatedText.isEmpty,
              !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        scheduleTranslation()
    }

    func cancelTranslation() {
        revision += 1
        task?.cancel()
        task = nil
        isTranslating = false
    }

    private func scheduleTranslation() {
        cancelTranslation()
        translationError = nil
        translatedText = ""
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let requestRevision = revision
        let source = LanguageDetector.detect(text)
        task = Task {
            do {
                try await Task.sleep(for: debounce)
                guard !Task.isCancelled, revision == requestRevision else { return }
                isTranslating = true
                let result = try await translate(text, source)
                guard !Task.isCancelled, revision == requestRevision else { return }
                translatedText = result
                isTranslating = false
                task = nil
            } catch {
                guard !Task.isCancelled, revision == requestRevision else { return }
                isTranslating = false
                translationError = error.localizedDescription
                task = nil
            }
        }
    }
}
