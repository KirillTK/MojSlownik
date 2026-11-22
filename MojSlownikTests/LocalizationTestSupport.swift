import Foundation

/// Lookups in the Russian localization from a test host that runs in English.
enum LocalizationTestSupport {
    static let ruLocale = Locale(identifier: "ru_RU")

    /// The app's `ru.lproj` bundle (the unit-test host is the app, so `Bundle.main` is the app bundle).
    static let ruBundle: Bundle = {
        guard let path = Bundle.main.path(forResource: "ru", ofType: "lproj"), let bundle = Bundle(path: path) else {
            fatalError("ru.lproj is missing from the app bundle")
        }
        return bundle
    }()

    /// Plain (non-plural) lookup by catalog key; returns the key when nothing matches.
    static func ru(_ key: String) -> String {
        ruBundle.localizedString(forKey: key, value: "\u{0}missing", table: nil)
    }

    /// Plural lookups need the ru locale as well as the ru bundle: the locale picks the plural category.
    static func ruWords(_ n: Int) -> String {
        String(localized: "\(n) words", bundle: ruBundle, locale: ruLocale)
    }

    static func ruFolders(_ n: Int) -> String {
        String(localized: "\(n) folders", bundle: ruBundle, locale: ruLocale)
    }

    static let ruLanguageNames: [(code: String, forms: [String])] = [
        ("pl", ["Польский", "польский", "Польском", "польского", "по-польски", "Польское слово"]),
        ("ru", ["Русский", "русский", "Русском", "русского", "по-русски", "Русское слово"]),
        ("uk", ["Украинский", "украинский", "Украинском", "украинского", "по-украински", "Украинское слово"]),
        ("en", ["Английский", "английский", "Английском", "английского", "по-английски", "Английское слово"]),
        ("de", ["Немецкий", "немецкий", "Немецком", "немецкого", "по-немецки", "Немецкое слово"]),
        ("fr", ["Французский", "французский", "Французском", "французского", "по-французски", "Французское слово"]),
        ("es", ["Испанский", "испанский", "Испанском", "испанского", "по-испански", "Испанское слово"]),
        ("it", ["Итальянский", "итальянский", "Итальянском", "итальянского", "по-итальянски", "Итальянское слово"]),
        ("cs", ["Чешский", "чешский", "Чешском", "чешского", "по-чешски", "Чешское слово"]),
        ("pt", ["Португальский", "португальский", "Португальском", "португальского", "по-португальски",
                "Португальское слово"]),
    ]

    static let nameForms = ["name", "inline", "inputOption", "genitive", "adverb", "wordPlaceholder"]
}
