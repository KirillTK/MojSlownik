import Foundation

// Repository decorators: every persistence failure is logged once, here, as `storage.failed`
// with a stable operation id, then rethrown. Stores wrap their repository in init, so a new
// repository method cannot be added without its failure being logged. Ids are
// "<repository>.<method>"; no arguments (user content) are logged.

@MainActor
final class LoggingVocabularyRepository: VocabularyRepository {
    private let base: any VocabularyRepository
    private let logger: any AppLogging

    init(_ base: any VocabularyRepository, logger: any AppLogging) {
        self.base = base
        self.logger = logger
    }

    func addWord(source: String, translation: String, category: WordCategory?, folderID: UUID?) throws {
        try logger.logged("vocabulary.add_word") {
            try base.addWord(source: source, translation: translation, category: category, folderID: folderID)
        }
    }

    func toggleScannedWord(source: String, translation: String, category: WordCategory, folderID: UUID?) throws -> Bool {
        try logger.logged("vocabulary.toggle_scanned_word") {
            try base.toggleScannedWord(source: source, translation: translation, category: category, folderID: folderID)
        }
    }

    func changeCategory(_ category: WordCategory, source: String, translation: String) throws {
        try logger.logged("vocabulary.change_category") {
            try base.changeCategory(category, source: source, translation: translation)
        }
    }

    func setCategory(_ category: WordCategory, wordID: UUID) throws {
        try logger.logged("vocabulary.set_category") { try base.setCategory(category, wordID: wordID) }
    }

    func deleteWord(id: UUID) throws {
        try logger.logged("vocabulary.delete_word") { try base.deleteWord(id: id) }
    }

    func setMembership(wordID: UUID, folderID: UUID, included: Bool) throws {
        try logger.logged("vocabulary.set_membership") {
            try base.setMembership(wordID: wordID, folderID: folderID, included: included)
        }
    }

    func removeFromAllFolders(wordID: UUID) throws {
        try logger.logged("vocabulary.remove_from_all_folders") { try base.removeFromAllFolders(wordID: wordID) }
    }

    func ensureIdentity(for word: Word) throws -> UUID {
        try logger.logged("vocabulary.ensure_identity") { try base.ensureIdentity(for: word) }
    }
}

@MainActor
final class LoggingFolderRepository: FolderRepository {
    private let base: any FolderRepository
    private let logger: any AppLogging

    init(_ base: any FolderRepository, logger: any AppLogging) {
        self.base = base
        self.logger = logger
    }

    func folders() throws -> [FolderRecord] {
        try logger.logged("folders.load") { try base.folders() }
    }

    func createFolder(name: String) throws -> UUID {
        try logger.logged("folders.create") { try base.createFolder(name: name) }
    }

    func renameFolder(id: UUID, name: String) throws {
        try logger.logged("folders.rename") { try base.renameFolder(id: id, name: name) }
    }

    func reorderFolders(ids: [UUID]) throws {
        try logger.logged("folders.reorder") { try base.reorderFolders(ids: ids) }
    }

    func deleteFolder(id: UUID) throws {
        try logger.logged("folders.delete") { try base.deleteFolder(id: id) }
    }
}

@MainActor
final class LoggingDailyActivityRepository: DailyActivityRepository {
    private let base: any DailyActivityRepository
    private let logger: any AppLogging

    init(_ base: any DailyActivityRepository, logger: any AppLogging) {
        self.base = base
        self.logger = logger
    }

    func load() -> DailyActivity? { base.load() }

    func prepareSave(_ activity: DailyActivity) throws -> () -> Void {
        try logger.logged("daily_activity.prepare_save") { try base.prepareSave(activity) }
    }

    func clear() { base.clear() }
}
