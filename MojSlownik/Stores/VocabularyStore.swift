import Foundation
import Observation

/// Single write entry point for vocabulary from views.
@MainActor
@Observable
final class VocabularyStore {
    @ObservationIgnored private let repository: any VocabularyRepository

    init(repository: any VocabularyRepository) {
        self.repository = repository
    }

    func add(source: String, translation: String, category: WordCategory? = nil, folderID: UUID? = nil) throws {
        try repository.addWord(source: source, translation: translation, category: category, folderID: folderID)
    }

    @discardableResult
    func toggleScanned(source: String, translation: String, category: WordCategory,
                       folderID: UUID? = nil) throws -> Bool {
        try repository.toggleScannedWord(source: source, translation: translation,
                                         category: category, folderID: folderID)
    }

    func changeCategory(_ category: WordCategory, source: String, translation: String) throws {
        try repository.changeCategory(category, source: source, translation: translation)
    }

    func setCategory(_ category: WordCategory, for word: Word) throws {
        try repository.setCategory(category, wordID: identity(of: word))
    }

    func deleteWord(_ word: Word) throws {
        try repository.deleteWord(id: identity(of: word))
    }

    func setMembership(of word: Word, folderID: UUID, included: Bool) throws {
        try repository.setMembership(wordID: identity(of: word), folderID: folderID, included: included)
    }

    func removeFromAllFolders(_ word: Word) throws {
        try repository.removeFromAllFolders(wordID: identity(of: word))
    }

    /// Lazy retry: a word without a uuid gets one assigned before any write.
    private func identity(of word: Word) throws -> UUID {
        if let uuid = word.uuid { return uuid }
        return try repository.ensureIdentity(for: word)
    }
}
