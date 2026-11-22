import Foundation

enum AppLocale {
    /// The UI language iOS resolved for this app (en or ru) combined with the system region.
    static var current: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        // Only the language code changes; the region and other system settings stay.
        components.languageComponents.languageCode = Locale.LanguageCode(Bundle.main.preferredLocalizations.first ?? "en")
        return Locale(components: components)
    }
}
