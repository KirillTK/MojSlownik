import Foundation

/// The studied side (`term`, stored in `Word.polish`) or the translation side (`Word.russian`).
enum WordSide: String, Equatable, Sendable {
    case term, translation

    var other: WordSide { self == .term ? .translation : .term }
}

/// A word as entered by the user: both texts plus the side that was typed or scanned.
struct WordEntry: Equatable, Sendable {
    let term: String
    let translation: String
    let enteredSide: WordSide

    /// `input` was typed or scanned on `side`; `translation` is the text of the other side.
    static func make(input: String, translation: String, side: WordSide) -> WordEntry {
        side == .term
            ? WordEntry(term: input, translation: translation, enteredSide: .term)
            : WordEntry(term: translation, translation: input, enteredSide: .translation)
    }
}
