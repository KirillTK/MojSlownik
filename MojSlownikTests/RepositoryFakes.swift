import Foundation
@testable import MojSlownik

enum RepositoryFakeError: Error, Equatable { case forced }

@MainActor
final class InMemoryFolderRepository: FolderRepository {
    struct Row {
        var id: UUID
        var name: String
        var sortOrder: Int
        var createdAt: Date
        var deletedAt: Date?
    }

    private(set) var rows: [Row] = []
    var nextError: Error?
    private var tick = 0

    private func failIfNeeded() throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    private var active: [Row] { rows.filter { $0.deletedAt == nil } }

    private func records() -> [FolderRecord] {
        active.sorted { ($0.sortOrder, $0.createdAt, $0.id.uuidString) < ($1.sortOrder, $1.createdAt, $1.id.uuidString) }
            .map { FolderRecord(id: $0.id, name: $0.name) }
    }

    func folders() throws -> [FolderRecord] {
        try failIfNeeded()
        return records()
    }

    func createFolder(name: String) throws -> UUID {
        try failIfNeeded()
        let clean = try FolderStore.validatedName(name, excluding: nil, existing: records())
        tick += 1
        let row = Row(id: UUID(), name: clean, sortOrder: (active.map(\.sortOrder).max() ?? -1) + 1,
                      createdAt: Date(timeIntervalSince1970: Double(tick)), deletedAt: nil)
        rows.append(row)
        return row.id
    }

    func renameFolder(id: UUID, name: String) throws {
        try failIfNeeded()
        guard let index = rows.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw FolderStore.StoreError.missingFolder
        }
        rows[index].name = try FolderStore.validatedName(name, excluding: id, existing: records())
    }

    func reorderFolders(ids: [UUID]) throws {
        try failIfNeeded()
        let current = active
        guard ids.count == current.count, Set(ids).count == ids.count, Set(ids) == Set(current.map(\.id)) else {
            throw FolderStore.StoreError.invalidOrder
        }
        for (index, id) in ids.enumerated() {
            if let row = rows.firstIndex(where: { $0.id == id }) { rows[row].sortOrder = index }
        }
    }

    func deleteFolder(id: UUID) throws {
        try failIfNeeded()
        for index in rows.indices where rows[index].id == id && rows[index].deletedAt == nil {
            rows[index].deletedAt = Date(timeIntervalSince1970: 1)
        }
    }
}

@MainActor
final class RecordingVocabularyRepository: VocabularyRepository {
    enum Call: Equatable {
        case addWord(String, String, WordCategory?, UUID?)
        case toggle(String, String, WordCategory, UUID?)
        case changeCategory(WordCategory, String, String)
        case setCategory(WordCategory, UUID)
        case deleteWord(UUID)
        case setMembership(UUID, UUID, Bool)
        case removeFromAllFolders(UUID)
        case ensureIdentity
    }

    private(set) var calls: [Call] = []
    var toggleResult = true
    var nextError: Error?
    var identityResult: Result<UUID, Error> = .success(UUID())

    private func record(_ call: Call) throws {
        calls.append(call)
        if let error = nextError {
            nextError = nil
            throw error
        }
    }

    func addWord(source: String, translation: String, category: WordCategory?, folderID: UUID?) throws {
        try record(.addWord(source, translation, category, folderID))
    }

    func toggleScannedWord(source: String, translation: String, category: WordCategory,
                           folderID: UUID?) throws -> Bool {
        try record(.toggle(source, translation, category, folderID))
        return toggleResult
    }

    func changeCategory(_ category: WordCategory, source: String, translation: String) throws {
        try record(.changeCategory(category, source, translation))
    }

    func setCategory(_ category: WordCategory, wordID: UUID) throws { try record(.setCategory(category, wordID)) }
    func deleteWord(id: UUID) throws { try record(.deleteWord(id)) }

    func setMembership(wordID: UUID, folderID: UUID, included: Bool) throws {
        try record(.setMembership(wordID, folderID, included))
    }

    func removeFromAllFolders(wordID: UUID) throws { try record(.removeFromAllFolders(wordID)) }

    func ensureIdentity(for word: Word) throws -> UUID {
        calls.append(.ensureIdentity)
        let uuid = try identityResult.get()
        word.uuid = uuid
        return uuid
    }
}

@MainActor
final class InMemoryAchievementStateRepository: AchievementStateRepository {
    var state = AchievementState()
    private(set) var saveCount = 0
    var nextError: Error?

    func load() -> AchievementState { state }

    func save(_ state: AchievementState) throws {
        if let error = nextError {
            nextError = nil
            throw error
        }
        saveCount += 1
        self.state = state
    }
}

@MainActor
final class InMemoryDailyActivityRepository: DailyActivityRepository {
    var stored: DailyActivity?
    var prepareError: Error?
    private(set) var clearCount = 0

    func load() -> DailyActivity? { stored }

    func prepareSave(_ activity: DailyActivity) throws -> () -> Void {
        if let error = prepareError { throw error }
        return { [weak self] in self?.stored = activity }
    }

    func clear() {
        clearCount += 1
        stored = nil
    }
}
