import Foundation

enum LanguageDetector {
    /// Side of `text` in a different-script pair (see `LanguagePair.detectSide`); nil if undecidable.
    static func side(of text: String, in pair: LanguagePair) -> WordSide? {
        pair.detectSide(text)
    }
}
