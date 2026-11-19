import SwiftData
import XCTest
@testable import MojSlownik

/// Shared builders for sync tests (in-memory container, local rows, remote records).
@MainActor
enum SyncTestKit {
    nonisolated static let owner = UUID(uuidString: "00000000-0000-4000-8000-0000000000e1")!
    nonisolated static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Word.self, WordFolder.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// A local word that is clean (synced at `serverTime`).
    @discardableResult
    static func insertWord(_ container: ModelContainer, russian: String = "кот", polish: String = "kot",
                           source: AppLanguage = .russian, id: UUID = UUID(), category: WordCategory = .other,
                           folders: [UUID] = [], createdAt: Date? = nil, syncedAt serverTime: Date? = nil,
                           deletedAt: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let word = Word(russian: russian, polish: polish, sourceLanguage: source,
                        createdAt: createdAt ?? t0.addingTimeInterval(-7_200), category: category)
        word.uuid = id
        word.folderIDs = folders
        if let serverTime {
            word.updatedAt = serverTime
            word.serverUpdatedAt = serverTime
        }
        if let deletedAt { word.deletedAt = deletedAt }
        context.insert(word)
        try context.save()
        return id
    }

    @discardableResult
    static func insertFolder(_ container: ModelContainer, name: String = "Урок", id: UUID = UUID(),
                             syncedAt serverTime: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let folder = WordFolder(name: name)
        folder.id = id
        folder.createdAt = t0.addingTimeInterval(-7_200)
        folder.updatedAt = folder.createdAt
        if let serverTime {
            folder.updatedAt = serverTime
            folder.serverUpdatedAt = serverTime
        }
        context.insert(folder)
        try context.save()
        return id
    }

    static func words(_ container: ModelContainer) throws -> [Word] {
        try ModelContext(container).fetch(FetchDescriptor<Word>())
    }

    static func word(_ container: ModelContainer, _ id: UUID) throws -> Word? {
        try words(container).first { $0.uuid == id }
    }

    static func folders(_ container: ModelContainer) throws -> [WordFolder] {
        try ModelContext(container).fetch(FetchDescriptor<WordFolder>())
    }

    static func edit(_ container: ModelContainer, _ id: UUID, at time: Date, _ change: (Word) -> Void) throws {
        let context = ModelContext(container)
        let word = try XCTUnwrap(context.fetch(FetchDescriptor<Word>()).first { $0.uuid == id })
        change(word)
        word.updatedAt = time
        try context.save()
    }

    static func remoteWord(id: UUID = UUID(), term: String = "kot", translation: String = "кот",
                           termLanguage: String = "pl", translationLanguage: String = "ru",
                           entered: String = "ru", category: String = "other", folders: [UUID] = [],
                           updatedAt: Date, deletedAt: Date? = nil, repetitions: Int = 1,
                           userID: UUID = owner) -> RemoteWordRecord {
        RemoteWordRecord(id: id, userID: userID, term: term, termLanguage: termLanguage,
                         translation: translation, translationLanguage: translationLanguage,
                         enteredLanguage: entered, category: category, folderIDs: folders,
                         createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt,
                         easeFactor: 2.5, intervalDays: 1, repetitions: repetitions,
                         dueDate: t0.addingTimeInterval(86_400), lastReviewGrade: "good", knowledgeTier: 1,
                         consecutiveSoftMisses: 0)
    }

    static func remoteFolder(id: UUID = UUID(), name: String = "Из облака", updatedAt: Date,
                             deletedAt: Date? = nil, userID: UUID = owner) -> RemoteFolderRecord {
        RemoteFolderRecord(id: id, userID: userID, name: name, sortOrder: 0,
                           createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func validated(_ record: RemoteWordRecord) throws -> ValidatedRemoteWord {
        try RemoteRecordValidator.validate(record, ownerID: owner, knownFolderIDs: [], now: t0)
    }

    static func validated(_ record: RemoteFolderRecord) throws -> ValidatedRemoteFolder {
        try RemoteRecordValidator.validate(record, ownerID: owner, now: t0)
    }
}
