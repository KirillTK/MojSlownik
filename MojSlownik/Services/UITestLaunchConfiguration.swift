#if DEBUG
import Foundation

/// DEBUG-only UI-test mode, activated by launch environment variables.
/// Production (Release) builds contain none of this code.
struct UITestLaunchConfiguration: Equatable, Sendable {
    static let fixtureKey = "UITEST_FIXTURE"
    static let prefillKey = "UITEST_PREFILL"
    static let defaultsSuite = "MojSlownik.UITest"

    let fixture: UITestFixture
    let prefill: String?

    enum ParseError: LocalizedError, Equatable {
        case unknownFixture(String)

        var errorDescription: String? {
            switch self {
            case .unknownFixture(let name):
                let known = UITestFixture.allCases.map(\.rawValue).joined(separator: ", ")
                return "Unknown UITEST_FIXTURE '\(name)'. Known: \(known)"
            }
        }
    }

    /// nil when neither key is set (empty strings count as unset).
    /// Prefill without a fixture implies fixture `.empty`. An unknown fixture name throws.
    static func parse(_ environment: [String: String]) throws -> UITestLaunchConfiguration? {
        let fixtureName = environment[fixtureKey].flatMap { $0.isEmpty ? nil : $0 }
        let prefill = environment[prefillKey].flatMap { $0.isEmpty ? nil : $0 }
        guard fixtureName != nil || prefill != nil else { return nil }
        let fixture: UITestFixture
        if let fixtureName {
            guard let known = UITestFixture(rawValue: fixtureName) else {
                throw ParseError.unknownFixture(fixtureName)
            }
            fixture = known
        } else {
            fixture = .empty
        }
        return UITestLaunchConfiguration(fixture: fixture, prefill: prefill)
    }

    /// Cached for non-throwing call sites (Translator, WordListView). App launch calls
    /// parse(ProcessInfo.processInfo.environment) itself so errors surface.
    static let current: UITestLaunchConfiguration? =
        try? parse(ProcessInfo.processInfo.environment)
}

/// Deterministic, network-free translation used in UI-test mode.
enum UITestTranslationStub {
    private static let toPolish: [String: String] = [
        "привет": "cześć", "мир": "świat", "привет мир": "cześć świecie",
        "собака": "pies", "кот": "kot", "дом": "dom",
    ]
    private static let toRussian: [String: String] = [
        "dom": "дом", "kot": "кот", "woda": "вода", "dziękuję": "спасибо",
        "bardzo": "очень", "dziękuję bardzo": "спасибо большое",
    ]

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) -> String {
        let key = key(text)
        switch target {
        case .polish: return toPolish[key] ?? "słowo"
        case .russian: return toRussian[key] ?? "слово"
        }
    }

    /// Raw groups `[google, myMemory]` so the real merge/validation still runs.
    static func alternatives(_ text: String, pair: TranslationPair) -> [[TranslationAlternative]] {
        switch key(text) {
        case "dom":
            return [[TranslationAlternative(text: "дом", partOfSpeech: "существительное"),
                     TranslationAlternative(text: "жилище", partOfSpeech: nil)], []]
        case "собака":
            return [[TranslationAlternative(text: "pies", partOfSpeech: "rzeczownik"),
                     TranslationAlternative(text: "psina", partOfSpeech: nil)], []]
        default:
            return [[], []]
        }
    }
}
#endif
