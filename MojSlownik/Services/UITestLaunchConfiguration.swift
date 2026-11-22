#if DEBUG
import Foundation

/// DEBUG-only UI-test mode, activated by launch environment variables.
/// Production (Release) builds contain none of this code.
struct UITestLaunchConfiguration: Equatable, Sendable {
    static let fixtureKey = "UITEST_FIXTURE"
    static let prefillKey = "UITEST_PREFILL"
    static let authKey = "UITEST_AUTH"
    static let syncKey = "UITEST_SYNC"
    static let defaultsSuite = "MojSlownik.UITest"

    let fixture: UITestFixture
    let prefill: String?
    var auth: UITestAuthState = .signedOut
    var sync: UITestSyncState = .empty

    enum ParseError: LocalizedError, Equatable {
        case unknownFixture(String)
        case unknownAuthState(String)
        case unknownSyncState(String)

        var errorDescription: String? {
            switch self {
            case .unknownAuthState(let name):
                let known = UITestAuthState.allCases.map(\.rawValue).joined(separator: ", ")
                return "Unknown UITEST_AUTH '\(name)'. Known: \(known)"
            case .unknownSyncState(let name):
                let known = UITestSyncState.allCases.map(\.rawValue).joined(separator: ", ")
                return "Unknown UITEST_SYNC '\(name)'. Known: \(known)"
            case .unknownFixture(let name):
                let known = UITestFixture.allCases.map(\.rawValue).joined(separator: ", ")
                return "Unknown UITEST_FIXTURE '\(name)'. Known: \(known)"
            }
        }
    }

    /// nil when no key is set (empty strings count as unset).
    /// Prefill, auth or sync without a fixture implies fixture `.empty`. Unknown names throw.
    static func parse(_ environment: [String: String]) throws -> UITestLaunchConfiguration? {
        let fixtureName = environment[fixtureKey].flatMap { $0.isEmpty ? nil : $0 }
        let prefill = environment[prefillKey].flatMap { $0.isEmpty ? nil : $0 }
        let authName = environment[authKey].flatMap { $0.isEmpty ? nil : $0 }
        let syncName = environment[syncKey].flatMap { $0.isEmpty ? nil : $0 }
        guard fixtureName != nil || prefill != nil || authName != nil || syncName != nil else { return nil }
        var auth = UITestAuthState.signedOut
        if let authName {
            guard let known = UITestAuthState(rawValue: authName) else {
                throw ParseError.unknownAuthState(authName)
            }
            auth = known
        }
        var sync = UITestSyncState.empty
        if let syncName {
            guard let known = UITestSyncState(rawValue: syncName) else {
                throw ParseError.unknownSyncState(syncName)
            }
            sync = known
        }
        let fixture: UITestFixture
        if let fixtureName {
            guard let known = UITestFixture(rawValue: fixtureName) else {
                throw ParseError.unknownFixture(fixtureName)
            }
            fixture = known
        } else {
            fixture = .empty
        }
        return UITestLaunchConfiguration(fixture: fixture, prefill: prefill, auth: auth, sync: sync)
    }

    /// Cached for non-throwing call sites (Translator, WordListView). App launch calls
    /// parse(ProcessInfo.processInfo.environment) itself so errors surface.
    static let current: UITestLaunchConfiguration? =
        try? parse(ProcessInfo.processInfo.environment)
}

/// Account state for UI tests; always a network-free StaticAuthBackend.
enum UITestAuthState: String, CaseIterable, Sendable {
    case signedOut, signedIn
    /// Signed out, and every sign-in attempt fails (error message path).
    case failing

    @MainActor
    func makeBackend() -> StaticAuthBackend {
        switch self {
        case .signedOut: StaticAuthBackend()
        case .signedIn: StaticAuthBackend(account: StaticAuthBackend.testAccount)
        case .failing: StaticAuthBackend(failsSignIn: true)
        }
    }
}

/// Deterministic, network-free translation used in UI-test mode.
enum UITestTranslationStub {
    private static let toPolish: [String: String] = [
        "привет": "cześć", "мир": "świat", "привет мир": "cześć świecie", // l10n:data
        "собака": "pies", "кот": "kot", "дом": "dom", "house": "dom", // l10n:data
    ]
    private static let toGerman: [String: String] = ["дом": "das Haus", "учить": "lernen"] // l10n:data
    private static let toEnglish: [String: String] = ["dom": "house"]
    private static let toRussian: [String: String] = [
        "dom": "дом", "kot": "кот", "woda": "вода", "dziękuję": "спасибо", // l10n:data
        "bardzo": "очень", "dziękuję bardzo": "спасибо большое", // l10n:data
    ]

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func translate(_ text: String, from source: Language, to target: Language) -> String {
        let key = key(text)
        switch target.code {
        case "pl": return toPolish[key] ?? "słowo"
        case "ru": return toRussian[key] ?? "слово" // l10n:data
        case "de": return toGerman[key] ?? "Wort"
        case "en": return toEnglish[key] ?? "word"
        default: return "word"
        }
    }

    /// Raw groups `[google, myMemory]` so the real merge/validation still runs.
    static func alternatives(_ text: String, pair: TranslationPair) -> [[TranslationAlternative]] {
        switch key(text) {
        case "dom":
            return [[TranslationAlternative(text: "дом", partOfSpeech: "существительное"), // l10n:data
                     TranslationAlternative(text: "жилище", partOfSpeech: nil)], []] // l10n:data
        case "собака": // l10n:data
            return [[TranslationAlternative(text: "pies", partOfSpeech: "rzeczownik"),
                     TranslationAlternative(text: "psina", partOfSpeech: nil)], []]
        default:
            return [[], []]
        }
    }
}
#endif
