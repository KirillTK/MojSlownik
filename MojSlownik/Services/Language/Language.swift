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
    let endonym: String           // the language's own name, e.g. "Polski" (data, never localized)
    let flag: String
    let speechCode: String        // TTS and dictation locale
    let ocrCode: String           // Vision / DataScanner recognition language
    let googleCode: String        // gtx sl/tl
    let myMemoryCode: String      // langpair half
    let appleIdentifier: String?  // Locale.Language(identifier:); nil = Apple Translation unavailable
    let scripts: Set<Script>
    let preservesCase: Bool       // stored text keeps its case (German nouns)

    var id: String { code }

    private init(_ code: String, _ endonym: String, _ flag: String, speech: String, ocr: String, apple: String?,
                 script: Script) {
        self.code = code
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

    // l10n:data-begin language endonyms and flags
    static let polish = Language("pl", "Polski", "🇵🇱",
                                 speech: "pl-PL", ocr: "pl-PL", apple: "pl", script: .latin)
    static let russian = Language("ru", "Русский", "🇷🇺",
                                  speech: "ru-RU", ocr: "ru-RU", apple: "ru", script: .cyrillic)
    static let ukrainian = Language("uk", "Українська", "🇺🇦",
                                    speech: "uk-UA", ocr: "uk-UA", apple: "uk", script: .cyrillic)
    static let english = Language("en", "English", "🇬🇧",
                                  speech: "en-GB", ocr: "en-US", apple: "en", script: .latin)
    static let german = Language("de", "Deutsch", "🇩🇪",
                                 speech: "de-DE", ocr: "de-DE", apple: "de", script: .latin)
    static let french = Language("fr", "Français", "🇫🇷",
                                 speech: "fr-FR", ocr: "fr-FR", apple: "fr", script: .latin)
    static let spanish = Language("es", "Español", "🇪🇸",
                                  speech: "es-ES", ocr: "es-ES", apple: "es", script: .latin)
    static let italian = Language("it", "Italiano", "🇮🇹",
                                  speech: "it-IT", ocr: "it-IT", apple: "it", script: .latin)
    static let czech = Language("cs", "Čeština", "🇨🇿",
                                speech: "cs-CZ", ocr: "cs-CZ", apple: nil, script: .latin)
    static let portuguese = Language("pt", "Português", "🇵🇹",
                                     speech: "pt-PT", ocr: "pt-BR", apple: "pt", script: .latin)
    // l10n:data-end

    /// Every language a stored workspace may use; same order as `LanguageCodes.supported`.
    /// Legacy pairs outside the selectable lists below still load, sync and practice.
    static let all: [Language] = [.polish, .russian, .ukrainian, .english, .german,
                                  .french, .spanish, .italian, .czech, .portuguese]

    /// Selectable studied languages, wizard step 1 order (preselected: pl).
    static let studyOrder: [Language] = [.polish, .english, .german]
    /// Selectable translation languages, wizard step 2 order (preselected: ru).
    /// The studied language is disabled there, so no same-language pair can be created.
    static let translationOrder: [Language] = [.russian, .ukrainian, .english]

    init?(code: String) {
        guard let match = Self.all.first(where: { $0.code == code }) else { return nil }
        self = match
    }

    var names: LanguageNames { .of(code) }

    /// Localized language name for titles, rows and labels (English: "Polish").
    var localizedName: String { names.name }

    /// Stored text form: trimmed, lowercased unless the language keeps case.
    func storedForm(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return preservesCase ? trimmed : trimmed.lowercased()
    }
}

/// Localized UI forms of a language name (Localizable.xcstrings, `language.<code>.<form>`).
struct LanguageNames: Equatable {
    let name: String            // titles, rows, labels: "Polish"
    let inline: String          // nominative mid-sentence: "Polish"
    let inputOption: String     // segment after "I’m typing in": "Polish"
    let genitive: String        // same-alphabet note: "Polish"
    let adverb: String          // "in Polish"
    let wordPlaceholder: String // "Polish word"

    static func of(_ code: String) -> LanguageNames {
        switch code {
        case "pl":
            return LanguageNames(
                name: String(localized: "language.pl.name", defaultValue: "Polish", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.pl.inline", defaultValue: "Polish", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.pl.inputOption", defaultValue: "Polish", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.pl.genitive", defaultValue: "Polish", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.pl.adverb", defaultValue: "in Polish", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.pl.wordPlaceholder", defaultValue: "Polish word", comment: "Placeholder of the answer field: '<language> word'"))
        case "ru":
            return LanguageNames(
                name: String(localized: "language.ru.name", defaultValue: "Russian", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.ru.inline", defaultValue: "Russian", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.ru.inputOption", defaultValue: "Russian", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.ru.genitive", defaultValue: "Russian", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.ru.adverb", defaultValue: "in Russian", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.ru.wordPlaceholder", defaultValue: "Russian word", comment: "Placeholder of the answer field: '<language> word'"))
        case "uk":
            return LanguageNames(
                name: String(localized: "language.uk.name", defaultValue: "Ukrainian", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.uk.inline", defaultValue: "Ukrainian", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.uk.inputOption", defaultValue: "Ukrainian", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.uk.genitive", defaultValue: "Ukrainian", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.uk.adverb", defaultValue: "in Ukrainian", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.uk.wordPlaceholder", defaultValue: "Ukrainian word", comment: "Placeholder of the answer field: '<language> word'"))
        case "en":
            return LanguageNames(
                name: String(localized: "language.en.name", defaultValue: "English", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.en.inline", defaultValue: "English", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.en.inputOption", defaultValue: "English", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.en.genitive", defaultValue: "English", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.en.adverb", defaultValue: "in English", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.en.wordPlaceholder", defaultValue: "English word", comment: "Placeholder of the answer field: '<language> word'"))
        case "de":
            return LanguageNames(
                name: String(localized: "language.de.name", defaultValue: "German", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.de.inline", defaultValue: "German", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.de.inputOption", defaultValue: "German", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.de.genitive", defaultValue: "German", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.de.adverb", defaultValue: "in German", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.de.wordPlaceholder", defaultValue: "German word", comment: "Placeholder of the answer field: '<language> word'"))
        case "fr":
            return LanguageNames(
                name: String(localized: "language.fr.name", defaultValue: "French", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.fr.inline", defaultValue: "French", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.fr.inputOption", defaultValue: "French", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.fr.genitive", defaultValue: "French", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.fr.adverb", defaultValue: "in French", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.fr.wordPlaceholder", defaultValue: "French word", comment: "Placeholder of the answer field: '<language> word'"))
        case "es":
            return LanguageNames(
                name: String(localized: "language.es.name", defaultValue: "Spanish", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.es.inline", defaultValue: "Spanish", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.es.inputOption", defaultValue: "Spanish", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.es.genitive", defaultValue: "Spanish", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.es.adverb", defaultValue: "in Spanish", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.es.wordPlaceholder", defaultValue: "Spanish word", comment: "Placeholder of the answer field: '<language> word'"))
        case "it":
            return LanguageNames(
                name: String(localized: "language.it.name", defaultValue: "Italian", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.it.inline", defaultValue: "Italian", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.it.inputOption", defaultValue: "Italian", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.it.genitive", defaultValue: "Italian", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.it.adverb", defaultValue: "in Italian", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.it.wordPlaceholder", defaultValue: "Italian word", comment: "Placeholder of the answer field: '<language> word'"))
        case "cs":
            return LanguageNames(
                name: String(localized: "language.cs.name", defaultValue: "Czech", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.cs.inline", defaultValue: "Czech", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.cs.inputOption", defaultValue: "Czech", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.cs.genitive", defaultValue: "Czech", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.cs.adverb", defaultValue: "in Czech", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.cs.wordPlaceholder", defaultValue: "Czech word", comment: "Placeholder of the answer field: '<language> word'"))
        case "pt":
            return LanguageNames(
                name: String(localized: "language.pt.name", defaultValue: "Portuguese", comment: "Language name used in titles, rows and labels"),
                inline: String(localized: "language.pt.inline", defaultValue: "Portuguese", comment: "Language name in the middle of a sentence (nominative)"),
                inputOption: String(localized: "language.pt.inputOption", defaultValue: "Portuguese", comment: "Language name in the segment after 'I'm typing in'"),
                genitive: String(localized: "language.pt.genitive", defaultValue: "Portuguese", comment: "Language name in the same-alphabet note"),
                adverb: String(localized: "language.pt.adverb", defaultValue: "in Portuguese", comment: "Adverb form: 'in <language>'"),
                wordPlaceholder: String(localized: "language.pt.wordPlaceholder", defaultValue: "Portuguese word", comment: "Placeholder of the answer field: '<language> word'"))
        default:
            return LanguageNames(name: code, inline: code, inputOption: code, genitive: code,
                                 adverb: code, wordPlaceholder: code)
        }
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
    /// (a Latin brand name inside Cyrillic text) do not flip the side. nil for same-script pairs and for text without such a letter.
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
