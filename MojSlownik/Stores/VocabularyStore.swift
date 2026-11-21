import Foundation
import Observation

/// Single write entry point for vocabulary from views.
@MainActor
@Observable
final class VocabularyStore {
    @ObservationIgnored private let repository: any VocabularyRepository
    @ObservationIgnored private let logger: any AppLogging

    @ObservationIgnored private let changeSignal: LocalChangeSignal?
    /// The active workspace (set by the app wiring); writes that create or match words need it.
    @ObservationIgnored var workspace: WorkspaceContext?

    init(repository: any VocabularyRepository, logger: (any AppLogging)? = nil,
         changeSignal: LocalChangeSignal? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.changeSignal = changeSignal
        self.repository = LoggingVocabularyRepository(repository, logger: logger)
        self.logger = logger
    }

    func add(_ entry: WordEntry, category: WordCategory? = nil, folderID: UUID? = nil) throws {
        let workspace = try requireWorkspace()
        try repository.addWord(entry, category: category, folderID: folderID, workspace: workspace)
        changeSignal?.notify()
        logger.log(.wordAdded, addedProperties(entry, workspace: workspace, category: category,
                                               folderID: folderID, via: "manual"))
    }

    @discardableResult
    func toggleScanned(_ entry: WordEntry, category: WordCategory, folderID: UUID? = nil) throws -> Bool {
        let workspace = try requireWorkspace()
        let added = try repository.toggleScannedWord(entry, category: category, folderID: folderID,
                                                     workspace: workspace)
        changeSignal?.notify()
        if added {
            logger.log(.wordAdded, addedProperties(entry, workspace: workspace, category: category,
                                                   folderID: folderID, via: "scan"))
        } else {
            logger.log(.wordRemoved, [.source: .name("scan")])
        }
        return added
    }

    func changeCategory(_ category: WordCategory, entry: WordEntry) throws {
        try repository.changeCategory(category, entry: entry, workspace: try requireWorkspace())
        changeSignal?.notify()
        logger.log(.wordCategoryChanged, [.category: .name(category.stableID)])
    }

    func setCategory(_ category: WordCategory, for word: Word) throws {
        try repository.setCategory(category, wordID: identity(of: word))
        changeSignal?.notify()
        logger.log(.wordCategoryChanged, [.category: .name(category.stableID)])
    }

    func deleteWord(_ word: Word) throws {
        try repository.deleteWord(id: identity(of: word))
        changeSignal?.notify()
        logger.log(.wordDeleted)
    }

    func setMembership(of word: Word, folderID: UUID, included: Bool) throws {
        try repository.setMembership(wordID: identity(of: word), folderID: folderID, included: included)
        changeSignal?.notify()
        logger.log(.wordFoldersChanged, [.included: .bool(included)])
    }

    func removeFromAllFolders(_ word: Word) throws {
        try repository.removeFromAllFolders(wordID: identity(of: word))
        changeSignal?.notify()
        logger.log(.wordFoldersChanged, [.included: .bool(false)])
    }

    /// Lazy retry: a word without a uuid gets one assigned before any write.
    private func identity(of word: Word) throws -> UUID {
        if let uuid = word.uuid { return uuid }
        return try repository.ensureIdentity(for: word)
    }

    private func requireWorkspace() throws -> WorkspaceContext {
        guard let workspace else { throw RepositoryError.noWorkspace }
        return workspace
    }

    /// Never logs the words themselves: only language, category id and folder presence.
    private func addedProperties(_ entry: WordEntry, workspace: WorkspaceContext, category: WordCategory?,
                                 folderID: UUID?, via channel: String) -> [LogKey: LogValue] {
        var properties: [LogKey: LogValue] = [
            .source: .name(channel),
            .language: .name(workspace.code(of: entry.enteredSide)),
            .inFolder: .bool(folderID != nil),
        ]
        if let category { properties[.category] = .name(category.stableID) }
        return properties
    }
}
