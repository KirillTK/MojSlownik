import Foundation
import Observation

@MainActor
@Observable
final class AddWordDraft {
    var sourceText = ""
    var translatedText = ""
    private(set) var isTranslating = false
    private(set) var translationError: String?
    private(set) var alternatives: [TranslationAlternative] = []
    private(set) var primaryTranslation: String?
    private var awaitingAlternatives = false
    private var task: Task<Void, Never>?
    private var revision = 0
    private var suspended = false
    private var needsResume = false
    private let debounce: Duration
    private let translate: (String, TranslationPair) async throws -> String
    private let alternativesFetch: (String, TranslationPair) async -> [[TranslationAlternative]]
    let pair: LanguagePair
    /// The side the user types on; nil = detect it from the text (different-script pairs).
    private(set) var inputSide: WordSide?

    init(pair: LanguagePair, inputSide: WordSide? = nil, debounce: Duration = .milliseconds(600),
         translate: @escaping (String, TranslationPair) async throws -> String = { text, pair in
             try await Translator.translate(text, from: pair.source, to: pair.target)
         },
         alternatives: @escaping (String, TranslationPair) async -> [[TranslationAlternative]] = {
             await TranslationAlternativesService.fetch($0, pair: $1)
         }) {
        self.pair = pair
        self.inputSide = inputSide
        self.debounce = debounce
        self.translate = translate
        self.alternativesFetch = alternatives
    }

    /// The side the source text is on: the explicit input side, else the detected one, else `.term`.
    var resolvedSide: WordSide {
        inputSide ?? pair.detectSide(sourceText) ?? .term
    }

    /// Switches the typed side (same-script pairs) and translates again.
    func setInputSide(_ side: WordSide?) {
        guard side != inputSide else { return }
        inputSide = side
        scheduleTranslation()
    }

    /// Primary translation (if any) followed by merged alternatives; empty without alternatives.
    var translationOptions: [TranslationAlternative] {
        guard !alternatives.isEmpty else { return [] }
        var options: [TranslationAlternative] = []
        if let primaryTranslation {
            options.append(TranslationAlternative(text: primaryTranslation, partOfSpeech: nil))
        }
        return options + alternatives
    }

    func isSelected(_ option: TranslationAlternative) -> Bool {
        TranslationAlternatives.normalized(option.text) == TranslationAlternatives.normalized(translatedText)
    }

    func select(_ option: TranslationAlternative) {
        translatedText = option.text
    }

    func setSource(_ text: String) {
        sourceText = text
        scheduleTranslation()
    }

    func beginDictation() {
        needsResume = translatedText.isEmpty && alternatives.isEmpty
        suspended = true
        if !awaitingAlternatives { cancelTask() }
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

    private func cancelTask() {
        revision += 1
        task?.cancel()
        task = nil
        isTranslating = false
        awaitingAlternatives = false
    }

    func cancelTranslation() {
        cancelTask()
        alternatives = []
        primaryTranslation = nil
    }

    private func scheduleTranslation() {
        cancelTranslation()
        translationError = nil
        translatedText = ""
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let requestRevision = revision
        let translationPair = pair.translationPair(from: resolvedSide)
        task = Task {
            do {
                try await Task.sleep(for: debounce)
            } catch {
                return
            }
            guard !Task.isCancelled, revision == requestRevision else { return }
            isTranslating = true
            let fetch = alternativesFetch
            async let groups: [[TranslationAlternative]] = TranslationAlternatives.shouldFetch(text)
                ? await fetch(text, translationPair) : []
            do {
                let result = try await translate(text, translationPair)
                guard !Task.isCancelled, revision == requestRevision else { return }
                translatedText = result
                primaryTranslation = result
            } catch {
                guard !Task.isCancelled, revision == requestRevision else { return }
                translationError = error.localizedDescription
            }
            isTranslating = false
            awaitingAlternatives = true
            let fetched = await groups
            guard !Task.isCancelled, revision == requestRevision else { return }
            alternatives = TranslationAlternatives.merge(
                primary: primaryTranslation, groups: fetched, sourceText: text, pair: translationPair)
            awaitingAlternatives = false
            task = nil
        }
    }
}
