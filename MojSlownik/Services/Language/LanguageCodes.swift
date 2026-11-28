import Foundation

/// The language codes this build can show (Latin and Cyrillic scripts). Sync validates workspaces
/// against it; `Language.all` must equal it. Narrower than this: the wizard's selectable lists
/// (`Language.studyOrder`, `Language.translationOrder`); never shrink this list, or legacy
/// workspaces stop loading. Widening the list bumps
/// `SyncEngine.capabilityVersion` so rows held by an older build are re-pulled.
enum LanguageCodes {
    static let supported: [String] = ["pl", "ru", "uk", "en", "de", "fr", "es", "it", "cs", "pt"]

    static func isSupported(_ code: String) -> Bool { supported.contains(code) }

    /// Only German keeps the case of the entered text (nouns are capitalised); the rest is lowercased.
    static func preservesCase(_ code: String) -> Bool { code == "de" }

    /// Stored text form of `text` on the side whose language is `code`.
    static func storedForm(_ text: String, language code: String) -> String {
        preservesCase(code) ? text : text.lowercased()
    }
}
