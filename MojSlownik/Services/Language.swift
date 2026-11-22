import Foundation

/// Writing system used to sanity-check provider candidates and to tell the sides of a pair apart.
enum Script: Hashable, Sendable {
    case latin, cyrillic

    /// Unicode scalar ranges; extend when a new language needs a new script.
    var ranges: [ClosedRange<UInt32>] {
        switch self {
        case .latin: return [0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF]
        case .cyrillic: return [0x400...0x4FF]
        }
    }

    private static let all: [Script] = [.latin, .cyrillic]

    /// nil for non-letters and letters of unknown scripts are distinguished by the caller
    /// (see `TranslationAlternatives.isValid`); this returns nil whenever no known range matches.
    static func of(_ scalar: Unicode.Scalar) -> Script? {
        all.first { script in script.ranges.contains { $0.contains(scalar.value) } }
    }
}

/// Central descriptor of a supported language: UI names, codes of every provider and the script.
/// `Language.all` must equal `LanguageCodes.supported` (what sync validates against).
struct Language: Hashable, Sendable, Identifiable {
    let code: String              // stable app code, e.g. "pl"
    let nameRU: String            // «Польский»
    let prepositionalRU: String   // «польском» (в/на …)
    let genitiveRU: String        // «польского»
    let endonym: String           // «Polski»
    let flag: String
    let speechCode: String        // TTS and dictation locale
    let ocrCode: String           // Vision / DataScanner recognition language
    let googleCode: String        // gtx sl/tl
    let myMemoryCode: String      // langpair half
    let appleIdentifier: String?  // Locale.Language(identifier:); nil = Apple Translation unavailable
    let scripts: Set<Script>
    let preservesCase: Bool       // stored text keeps its case (German nouns)

    var id: String { code }

    private init(_ code: String, _ nameRU: String, _ prepositionalRU: String, _ genitiveRU: String,
                 _ endonym: String, _ flag: String, speech: String, ocr: String, apple: String?,
                 script: Script) {
        self.code = code
        self.nameRU = nameRU
        self.prepositionalRU = prepositionalRU
        self.genitiveRU = genitiveRU
        self.endonym = endonym
        self.flag = flag
        self.speechCode = speech
        self.ocrCode = ocr
        self.googleCode = code
        self.myMemoryCode = code
        self.appleIdentifier = apple
        self.scripts = [script]
        self.preservesCase = LanguageCodes.preservesCase(code)
    }

    static let polish = Language("pl", "Польский", "польском", "польского", "Polski", "🇵🇱",
                                 speech: "pl-PL", ocr: "pl-PL", apple: "pl", script: .latin)
    static let russian = Language("ru", "Русский", "русском", "русского", "Русский", "🇷🇺",
                                  speech: "ru-RU", ocr: "ru-RU", apple: "ru", script: .cyrillic)
    static let ukrainian = Language("uk", "Украинский", "украинском", "украинского", "Українська", "🇺🇦",
                                    speech: "uk-UA", ocr: "uk-UA", apple: "uk", script: .cyrillic)
    static let english = Language("en", "Английский", "английском", "английского", "English", "🇬🇧",
                                  speech: "en-GB", ocr: "en-US", apple: "en", script: .latin)
    static let german = Language("de", "Немецкий", "немецком", "немецкого", "Deutsch", "🇩🇪",
                                 speech: "de-DE", ocr: "de-DE", apple: "de", script: .latin)
    static let french = Language("fr", "Французский", "французском", "французского", "Français", "🇫🇷",
                                 speech: "fr-FR", ocr: "fr-FR", apple: "fr", script: .latin)
    static let spanish = Language("es", "Испанский", "испанском", "испанского", "Español", "🇪🇸",
                                  speech: "es-ES", ocr: "es-ES", apple: "es", script: .latin)
    static let italian = Language("it", "Итальянский", "итальянском", "итальянского", "Italiano", "🇮🇹",
                                  speech: "it-IT", ocr: "it-IT", apple: "it", script: .latin)
    static let czech = Language("cs", "Чешский", "чешском", "чешского", "Čeština", "🇨🇿",
                                speech: "cs-CZ", ocr: "cs-CZ", apple: nil, script: .latin)
    static let portuguese = Language("pt", "Португальский", "португальском", "португальского", "Português", "🇵🇹",
                                     speech: "pt-PT", ocr: "pt-BR", apple: "pt", script: .latin)

    /// Same order as `LanguageCodes.supported`.
    static let all: [Language] = [.polish, .russian, .ukrainian, .english, .german,
                                  .french, .spanish, .italian, .czech, .portuguese]

    /// Wizard step 1 order (preselected: pl).
    static let studyOrder: [Language] = [.polish, .english, .german, .spanish, .ukrainian,
                                         .french, .italian, .czech, .portuguese, .russian]
    /// Wizard step 2 order (preselected: ru).
    static let translationOrder: [Language] = [.russian, .ukrainian, .english, .polish, .german,
                                               .french, .spanish, .italian, .czech, .portuguese]

    init?(code: String) {
        guard let match = Self.all.first(where: { $0.code == code }) else { return nil }
        self = match
    }

    /// «по-польски»: every supported name ends in «ий».
    var adverbRU: String { "по-" + nameRU.lowercased().dropLast(2) + "и" }

    /// «Польское»: neuter form for «… слово».
    var neuterRU: String { nameRU.dropLast(2) + "ое" }

    /// Stored text form: trimmed, lowercased unless the language keeps case.
    func storedForm(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return preservesCase ? trimmed : trimmed.lowercased()
    }
}

/// The two languages of a workspace: the studied side (`term`) and the translation side.
struct LanguagePair: Hashable, Sendable {
    let term: Language
    let translation: Language

    static let polishRussian = LanguagePair(term: .polish, translation: .russian)

    init(term: Language, translation: Language) {
        self.term = term
        self.translation = translation
    }

    init?(termCode: String, translationCode: String) {
        guard let term = Language(code: termCode), let translation = Language(code: translationCode) else {
            return nil
        }
        self.init(term: term, translation: translation)
    }

    /// Both sides share a script, so text cannot be assigned to a side by its letters.
    var isSameScript: Bool { term.scripts == translation.scripts }

    func language(of side: WordSide) -> Language {
        side == .term ? term : translation
    }

    /// Pair for translating text written on `side` into the other side.
    func translationPair(from side: WordSide) -> TranslationPair {
        side == .term ? TranslationPair(source: term, target: translation)
                      : TranslationPair(source: translation, target: term)
    }

    /// Different-script pairs: the side of a letter whose script belongs to exactly one side; a
    /// non-Latin letter wins over Latin ones, so Latin brand/tech words inside other text
    /// ("Wi-Fi роутер") do not flip the side. nil for same-script pairs and for text without such a letter.
    func detectSide(_ text: String) -> WordSide? {
        guard !isSameScript else { return nil }
        var latinSide: WordSide?
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            guard let script = Script.of(scalar) else { continue }
            let side: WordSide
            switch (term.scripts.contains(script), translation.scripts.contains(script)) {
            case (true, false): side = .term
            case (false, true): side = .translation
            default: continue
            }
            if script != .latin { return side }
            if latinSide == nil { latinSide = side }
        }
        return latinSide
    }
}

struct TranslationPair: Hashable, Sendable {
    let source: Language
    let target: Language
}
