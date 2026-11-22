import Foundation

/// Russian names of workspaces for the title menu, the «Языки» sheet and the wizard.
enum WorkspaceLabels {
    /// Large title: «🇵🇱 Польский»; «🇩🇪 Немецкий ← 🇷🇺» when another active workspace studies the same language.
    static func title(of option: WorkspaceStore.Option, among options: [WorkspaceStore.Option]) -> String {
        let pair = option.pair
        let ambiguous = options.contains { $0.id != option.id && $0.termCode == option.termCode }
        let base = "\(pair.term.flag) \(pair.term.nameRU)"
        return ambiguous ? "\(base) ← \(pair.translation.flag)" : base
    }

    /// Menu option: «🇵🇱 Польский ← 🇷🇺».
    static func menuLabel(of option: WorkspaceStore.Option) -> String {
        let pair = option.pair
        return "\(pair.term.flag) \(pair.term.nameRU) ← \(pair.translation.flag)"
    }

    /// «Польский ← Русский» (no flags: «Языки» sheet row, delete confirmation).
    static func name(of option: WorkspaceStore.Option) -> String {
        "\(option.pair.term.nameRU) ← \(option.pair.translation.nameRU)"
    }

    /// Wizard row label: «Польский, Polski»; one name when the endonym is the same word.
    static func accessibilityName(of language: Language) -> String {
        language.endonym == language.nameRU ? language.nameRU : "\(language.nameRU), \(language.endonym)"
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
