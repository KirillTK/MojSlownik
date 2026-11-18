import Foundation
import Observation

/// Single write entry point for vocabulary from views.
@MainActor
@Observable
final class VocabularyStore {
    @ObservationIgnored private let repository: any VocabularyRepository
    @ObservationIgnored private let logger: any AppLogging

    init(repository: any VocabularyRepository, logger: (any AppLogging)? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.repository = LoggingVocabularyRepository(repository, logger: logger)
        self.logger = logger
    }

    func add(source: String, translation: String, category: WordCategory? = nil, folderID: UUID? = nil) throws {
        try repository.addWord(source: source, translation: translation, category: category, folderID: folderID)
        logger.log(.wordAdded, addedProperties(source: source, category: category, folderID: folderID, via: "manual"))
    }

    @discardableResult
    func toggleScanned(source: String, translation: String, category: WordCategory,
                       folderID: UUID? = nil) throws -> Bool {
        let added = try repository.toggleScannedWord(source: source, translation: translation,
                                             category: category, folderID: folderID)
        if added {
            logger.log(.wordAdded, addedProperties(source: source, category: category, folderID: folderID, via: "scan"))
        } else {
            logger.log(.wordRemoved, [.source: .name("scan")])
        }
        return added
    }

    func changeCategory(_ category: WordCategory, source: String, translation: String) throws {
        try repository.changeCategory(category, source: source, translation: translation)
        logger.log(.wordCategoryChanged, [.category: .name(category.stableID)])
    }

    func setCategory(_ category: WordCategory, for word: Word) throws {
        try repository.setCategory(category, wordID: identity(of: word))
        logger.log(.wordCategoryChanged, [.category: .name(category.stableID)])
    }

    func deleteWord(_ word: Word) throws {
        try repository.deleteWord(id: identity(of: word))
        logger.log(.wordDeleted)
    }

    func setMembership(of word: Word, folderID: UUID, included: Bool) throws {
        try repository.setMembership(wordID: identity(of: word), folderID: folderID, included: included)
        logger.log(.wordFoldersChanged, [.included: .bool(included)])
    }

    func removeFromAllFolders(_ word: Word) throws {
        try repository.removeFromAllFolders(wordID: identity(of: word))
        logger.log(.wordFoldersChanged, [.included: .bool(false)])
    }

    /// Lazy retry: a word without a uuid gets one assigned before any write.
    private func identity(of word: Word) throws -> UUID {
        if let uuid = word.uuid { return uuid }
        return try repository.ensureIdentity(for: word)
    }

    /// Never logs the words themselves: only language, category id and folder presence.
    private func addedProperties(source: String, category: WordCategory?, folderID: UUID?,
                                 via channel: String) -> [LogKey: LogValue] {
        var properties: [LogKey: LogValue] = [
            .source: .name(channel),
            .language: .name(LanguageDetector.detect(source)),
            .inFolder: .bool(folderID != nil),
        ]
        if let category { properties[.category] = .name(category.stableID) }
        return properties
    }
}
