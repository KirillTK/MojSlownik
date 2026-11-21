import Foundation

/// The studied side (`term`, stored in `Word.polish`) or the translation side (`Word.russian`).
enum WordSide: String, Equatable, Sendable {
    case term, translation
}

/// A word as entered by the user: both texts plus the side that was typed or scanned.
struct WordEntry: Equatable, Sendable {
    let term: String
    let translation: String
    let enteredSide: WordSide

    /// Phase-1 adapter for the fixed pl ← ru pair: a Cyrillic source is the translation side.
    static func legacy(source: String, translation: String) -> WordEntry {
        if LanguageDetector.detect(source) == .russian {
            return WordEntry(term: translation, translation: source, enteredSide: .translation)
        }
        return WordEntry(term: source, translation: translation, enteredSide: .term)
    }
}
