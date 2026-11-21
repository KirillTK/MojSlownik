import Foundation
import Observation

@MainActor
@Observable
final class ScanResultDraft {
    var sourceText: String
    private(set) var translatedText = ""
    private(set) var isTranslating = false
    private(set) var translationError: String?
    private(set) var translations: [String: String] = [:]
    private(set) var wordErrors: [String: String] = [:]

    private let debounce: Duration
    private let translator: (String, TranslationPair) async throws -> String
    let pair: LanguagePair
    @ObservationIgnored private nonisolated(unsafe) var task: Task<Void, Never>?
    private var revision = 0

    init(sourceText: String, pair: LanguagePair, debounce: Duration = .milliseconds(500),
         translate: @escaping (String, TranslationPair) async throws -> String = { text, pair in
             try await Translator.translate(text, from: pair.source, to: pair.target)
         }) {
        self.sourceText = sourceText
        self.pair = pair
        self.debounce = debounce
        self.translator = translate
    }

    deinit { task?.cancel() }

    var words: [String] {
        var seen = Set<String>()
        return ScannedTextTokenizer.words(in: sourceText).filter {
            seen.insert(normalize($0)).inserted
        }
    }

    func startTranslationIfNeeded() {
        guard task == nil, hasMissingTranslation else { return }
        scheduleTranslation()
    }

    func setSource(_ text: String) {
        sourceText = text
        translatedText = ""
        translationError = nil
        translations = [:]
        wordErrors = [:]
        scheduleTranslation()
    }

    func retryContent() {
        translationError = nil
        scheduleTranslation()
    }

    func retryWord(_ word: String) {
        wordErrors[word] = nil
        scheduleTranslation()
    }

    func cancelTranslation() {
        revision += 1
        task?.cancel()
        task = nil
        isTranslating = false
    }

    private var hasMissingTranslation: Bool {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return (translatedText.isEmpty && translationError == nil) || words.contains {
            translations[$0] == nil && wordErrors[$0] == nil
        }
    }

    private func scheduleTranslation() {
        cancelTranslation()
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let requestRevision = revision
        let requestWords = words
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.debounce ?? .zero)
                guard let self, !Task.isCancelled, self.revision == requestRevision else { return }
                self.isTranslating = true
                await self.translate(text: text, words: requestWords, revision: requestRevision)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.revision == requestRevision else { return }
                self.isTranslating = false
                self.task = nil
            }
        }
    }

    private func translate(text: String, words: [String], revision: Int) async {
        if translatedText.isEmpty && translationError == nil {
            do {
                let result = try await translator(text, pair.translationPair(from: side(of: text)))
                guard isActive(revision) else { return }
                translatedText = result
            } catch is CancellationError {
                return
            } catch {
                guard isActive(revision) else { return }
                translationError = error.localizedDescription
            }
        }

        for word in words where translations[word] == nil && wordErrors[word] == nil {
            guard isActive(revision) else { return }
            do {
                let result = try await translator(word, pair.translationPair(from: side(of: word)))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard isActive(revision) else { return }
                guard !result.isEmpty else { throw TranslationError.emptyResult }
                translations[word] = result
            } catch is CancellationError {
                return
            } catch {
                guard isActive(revision) else { return }
                wordErrors[word] = error.localizedDescription
            }
        }

        guard isActive(revision) else { return }
        isTranslating = false
        task = nil
    }

    /// Side of scanned text: by script in different-script pairs; same-script pairs scan the studied
    /// language (open decision O3).
    func side(of text: String) -> WordSide {
        pair.detectSide(text) ?? .term
    }

    private func isActive(_ requestRevision: Int) -> Bool {
        !Task.isCancelled && revision == requestRevision
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }
}
