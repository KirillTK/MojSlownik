import Foundation

/// Localized names of workspaces for the title menu, the Languages sheet and the wizard.
enum WorkspaceLabels {
    /// Large title: "🇵🇱 Polish"; "🇩🇪 German ← 🇷🇺" when another active workspace studies the same language.
    static func title(of option: WorkspaceStore.Option, among options: [WorkspaceStore.Option]) -> String {
        let pair = option.pair
        let ambiguous = options.contains { $0.id != option.id && $0.termCode == option.termCode }
        let base = "\(pair.term.flag) \(pair.term.localizedName)"
        return ambiguous ? "\(base) ← \(pair.translation.flag)" : base
    }

    /// Menu option: "🇵🇱 Polish ← 🇷🇺".
    static func menuLabel(of option: WorkspaceStore.Option) -> String {
        let pair = option.pair
        return "\(pair.term.flag) \(pair.term.localizedName) ← \(pair.translation.flag)"
    }

    /// "Polish ← Russian" (no flags: Languages sheet row, delete confirmation).
    static func name(of option: WorkspaceStore.Option) -> String {
        "\(option.pair.term.localizedName) ← \(option.pair.translation.localizedName)"
    }

    /// Localized count such as "5 words" (plural rules come from the catalog).
    static func wordCount(_ n: Int) -> String { String(localized: "\(n) words") }

    /// Localized count such as "1 folder" (plural rules come from the catalog).
    static func folderCount(_ n: Int) -> String { String(localized: "\(n) folders") }

    /// Wizard row label: "Polish, Polski"; one name when the endonym is the same word.
    static func accessibilityName(of language: Language) -> String {
        language.endonym == language.localizedName ? language.localizedName : "\(language.localizedName), \(language.endonym)"
    }
}

/// Wizard rules: which pairs already exist and what is preselected.
struct WorkspaceWizardChoices: Equatable {
    enum PairStatus: Equatable {
        case available
        /// The translation language equals the studied one.
        case sameAsStudied
        /// An active workspace: choosing it opens it.
        case existing
        /// A soft-deleted workspace: choosing it brings the words back.
        case restorable
    }

    var activeIDs: Set<UUID> = []
    var deletedIDs: Set<UUID> = []

    func status(term: Language, translation: Language) -> PairStatus {
        if term == translation { return .sameAsStudied }
        let id = WorkspaceID.make(term: term.code, translation: translation.code)
        if activeIDs.contains(id) { return .existing }
        if deletedIDs.contains(id) { return .restorable }
        return .available
    }

    /// Russian, unless it is the studied language (then nothing is preselected).
    static func defaultTranslation(for term: Language) -> Language? {
        term == .russian ? nil : .russian
    }

    /// The translation after the studied language changed: kept unless it equals the new studied
    /// language; an empty choice gets the default.
    static func translation(afterStudying term: Language, current: Language?) -> Language? {
        guard let current, current != term else { return defaultTranslation(for: term) }
        return current
    }
}
