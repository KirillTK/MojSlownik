import Foundation

/// Writing system used to sanity-check provider candidates.
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

/// Central descriptor: codes of every provider plus the expected scripts.
struct TranslationLanguage: Hashable, Sendable {
    let id: String               // stable app code, e.g. "pl"
    let googleCode: String       // gtx sl/tl
    let myMemoryCode: String     // langpair half
    let appleIdentifier: String  // Locale.Language(identifier:)
    let scripts: Set<Script>

    static let polish = TranslationLanguage(id: "pl", googleCode: "pl", myMemoryCode: "pl", appleIdentifier: "pl", scripts: [.latin])
    static let russian = TranslationLanguage(id: "ru", googleCode: "ru", myMemoryCode: "ru", appleIdentifier: "ru", scripts: [.cyrillic])

    /// Supported languages: a language with an existing Script = one entry here;
    /// a new script also needs a Script case (+ AppLanguage/Word work).
    static let all: [TranslationLanguage] = [.polish, .russian]
}

struct TranslationPair: Hashable, Sendable {
    let source: TranslationLanguage
    let target: TranslationLanguage
}

extension AppLanguage {
    var translationLanguage: TranslationLanguage {
        TranslationLanguage.all.first { $0.id == rawValue }!
    }

    /// Pair for translating text in this language into `other`.
    var translationPair: TranslationPair {
        TranslationPair(source: translationLanguage, target: other.translationLanguage)
    }
}
