import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case russian = "ru"
    case polish = "pl"

    var id: String { rawValue }

    var other: AppLanguage {
        self == .russian ? .polish : .russian
    }

    var displayName: String {
        self == .russian ? "Русский" : "Polski"
    }

    var flag: String {
        self == .russian ? "🇷🇺" : "🇵🇱"
    }

    var speechCode: String {
        self == .russian ? "ru-RU" : "pl-PL"
    }
}

enum LanguageDetector {
    /// Кириллица → русский, иначе → польский (латиница).
    static func detect(_ text: String) -> AppLanguage {
        for scalar in text.unicodeScalars {
            if (0x0400...0x04FF).contains(scalar.value) {
                return .russian
            }
        }
        return .polish
    }
}
