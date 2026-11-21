import Foundation
import Observation

/// The workspace list and the active workspace. The single write entry point for workspaces.
@MainActor
@Observable
final class WorkspaceStore {
    struct Option: Identifiable, Equatable, Hashable {
        let id: UUID
        let termCode: String
        let translationCode: String
        let sortOrder: Int
    }

    private(set) var options: [Option] = []
    private(set) var activeID: UUID?
    /// Called after the active workspace changed (and after `load()`), so scoped stores can follow.
    @ObservationIgnored var onActiveChange: ((WorkspaceContext?) -> Void)?

    @ObservationIgnored private let repository: any WorkspaceRepository
    @ObservationIgnored private let activeRepository: any ActiveWorkspaceRepository
    @ObservationIgnored private let logger: any AppLogging
    @ObservationIgnored private let changeSignal: LocalChangeSignal?

    init(repository: any WorkspaceRepository, activeRepository: any ActiveWorkspaceRepository,
         logger: (any AppLogging)? = nil, changeSignal: LocalChangeSignal? = nil) {
        let logger = logger ?? NoopAppLogger()
        self.repository = LoggingWorkspaceRepository(repository, logger: logger)
        self.activeRepository = activeRepository
        self.logger = logger
        self.changeSignal = changeSignal
    }

    var active: Option? { options.first { $0.id == activeID } }

    var context: WorkspaceContext? {
        active.map { WorkspaceContext(id: $0.id, termCode: $0.termCode, translationCode: $0.translationCode) }
    }

    /// Reads the options; the active one is the persisted id if still active, else the first option.
    func load() throws {
        options = try repository.workspaces().map {
            Option(id: $0.id, termCode: $0.termCode, translationCode: $0.translationCode, sortOrder: $0.sortOrder)
        }
        let persisted = activeRepository.load()
        let resolved = options.first { $0.id == persisted } ?? options.first
        activeID = resolved?.id
        if let resolved, resolved.id != persisted { activeRepository.save(resolved.id) }
        onActiveChange?(context)
    }

    func select(id: UUID) {
        guard id != activeID, let option = options.first(where: { $0.id == id }) else { return }
        activeID = id
        activeRepository.save(id)
        logger.log(.workspaceSwitched, [.termLanguage: .name(option.termCode),
                                        .targetLanguage: .name(option.translationCode)])
        onActiveChange?(context)
    }

    /// Adds the pair (or revives it after a delete) and makes it active.
    @discardableResult
    func create(term: String, translation: String) throws -> UUID {
        let isNew = !options.contains { $0.id == WorkspaceID.make(term: term, translation: translation) }
        let id = try repository.ensure(term: term, translation: translation)
        changeSignal?.notify()
        if isNew {
            logger.log(.workspaceCreated, [.termLanguage: .name(term), .targetLanguage: .name(translation)])
        }
        try load()
        select(id: id)
        return id
    }

    func delete(id: UUID) throws {
        let option = options.first { $0.id == id }
        try repository.delete(id: id)
        changeSignal?.notify()
        logger.log(.workspaceDeleted, [.termLanguage: .name(option?.termCode ?? "invalid"),
                                       .targetLanguage: .name(option?.translationCode ?? "invalid")])
        try load()
    }

    func reorder(ids: [UUID]) throws {
        try repository.reorder(ids: ids)
        changeSignal?.notify()
        try load()
    }
}
