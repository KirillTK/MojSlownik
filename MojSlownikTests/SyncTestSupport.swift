import SwiftData
import XCTest
@testable import MojSlownik

/// Shared builders for sync tests (in-memory container, local rows, remote records).
@MainActor
enum SyncTestKit {
    nonisolated static let owner = UUID(uuidString: "00000000-0000-4000-8000-0000000000e1")!
    nonisolated static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: AppSchema.schema,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// A local word that is clean (synced at `serverTime`).
    @discardableResult
    static func insertWord(_ container: ModelContainer, russian: String = "кот", polish: String = "kot",
                           source: WordSide = .translation, id: UUID = UUID(), category: WordCategory = .other,
                           folders: [UUID] = [], workspace: UUID = WorkspaceID.legacy, createdAt: Date? = nil,
                           syncedAt serverTime: Date? = nil, deletedAt: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let word = Word(russian: russian, polish: polish, side: source,
                        createdAt: createdAt ?? t0.addingTimeInterval(-7_200), category: category)
        word.uuid = id
        word.workspaceID = workspace
        if let serverTime {
            word.updatedAt = serverTime
            word.serverUpdatedAt = serverTime
        }
        if let deletedAt { word.deletedAt = deletedAt }
        context.insert(word)
        for folderID in folders {
            let membership = FolderMembership(wordID: id, folderID: folderID, workspaceID: workspace,
                                              createdAt: word.createdAt)
            if let serverTime {
                membership.updatedAt = serverTime
                membership.serverUpdatedAt = serverTime
            }
            context.insert(membership)
        }
        try context.save()
        return id
    }

    /// A local workspace row (clean when `syncedAt` is given).
    @discardableResult
    static func insertWorkspace(_ container: ModelContainer, term: String = "pl", translation: String = "ru",
                                syncedAt serverTime: Date? = nil, deletedAt: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let workspace = Workspace(termLanguageCode: term, translationLanguageCode: translation,
                                  createdAt: t0.addingTimeInterval(-7_200))
        if let serverTime {
            workspace.updatedAt = serverTime
            workspace.serverUpdatedAt = serverTime
        }
        workspace.deletedAt = deletedAt
        context.insert(workspace)
        try context.save()
        return workspace.id
    }

    /// A local membership row (clean when `syncedAt` is given).
    @discardableResult
    static func insertMembership(_ container: ModelContainer, wordID: UUID, folderID: UUID,
                                 workspace: UUID = WorkspaceID.legacy, syncedAt serverTime: Date? = nil,
                                 deletedAt: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let membership = FolderMembership(wordID: wordID, folderID: folderID, workspaceID: workspace,
                                          createdAt: t0.addingTimeInterval(-7_200))
        if let serverTime {
            membership.updatedAt = serverTime
            membership.serverUpdatedAt = serverTime
        }
        membership.deletedAt = deletedAt
        context.insert(membership)
        try context.save()
        return membership.id
    }

    static func memberships(_ container: ModelContainer) throws -> [FolderMembership] {
        try ModelContext(container).fetch(FetchDescriptor<FolderMembership>())
    }

    static func workspaces(_ container: ModelContainer) throws -> [Workspace] {
        try ModelContext(container).fetch(FetchDescriptor<Workspace>())
    }

    /// Active folder ids of a word (through memberships).
    static func folderIDs(_ container: ModelContainer, of wordID: UUID) throws -> Set<UUID> {
        MembershipIndex(try memberships(container)).folderIDs(of: wordID)
    }

    @discardableResult
    static func insertFolder(_ container: ModelContainer, name: String = "Урок", id: UUID = UUID(),
                             workspace: UUID = WorkspaceID.legacy, syncedAt serverTime: Date? = nil) throws -> UUID {
        let context = ModelContext(container)
        let folder = WordFolder(name: name)
        folder.id = id
        folder.workspaceID = workspace
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

    nonisolated static let legacyKnown = KnownRemoteIDs(workspaceIDs: [WorkspaceID.legacy])

    static func remoteWord(id: UUID = UUID(), term: String = "kot", translation: String = "кот",
                           workspace: UUID = WorkspaceID.legacy, entered: String = "translation",
                           category: String = "other", updatedAt: Date, deletedAt: Date? = nil,
                           repetitions: Int = 1, userID: UUID = owner, intervalDays: Double = 1,
                           dueDate: Date? = nil, lapseCount: Int? = nil) -> RemoteWordRecord {
        RemoteWordRecord(id: id, userID: userID, workspaceID: workspace, term: term, translation: translation,
                         enteredSide: entered, category: category,
                         createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt,
                         easeFactor: 2.5, intervalDays: intervalDays, repetitions: repetitions,
                         dueDate: dueDate ?? t0.addingTimeInterval(86_400), lastReviewGrade: "good", knowledgeTier: 1,
                         consecutiveSoftMisses: 0, lapseCount: lapseCount)
    }

    static func remoteFolder(id: UUID = UUID(), name: String = "Из облака", workspace: UUID = WorkspaceID.legacy,
                             updatedAt: Date, deletedAt: Date? = nil, userID: UUID = owner) -> RemoteFolderRecord {
        RemoteFolderRecord(id: id, userID: userID, workspaceID: workspace, name: name, sortOrder: 0,
                           createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func remoteWorkspace(term: String = "pl", translation: String = "ru", sortOrder: Int = 0,
                                updatedAt: Date, deletedAt: Date? = nil,
                                userID: UUID = owner) -> RemoteWorkspaceRecord {
        RemoteWorkspaceRecord(id: WorkspaceID.make(term: term, translation: translation), userID: userID,
                              termLanguage: term, translationLanguage: translation, sortOrder: sortOrder,
                              createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func remoteMembership(wordID: UUID, folderID: UUID, workspace: UUID = WorkspaceID.legacy,
                                 updatedAt: Date, deletedAt: Date? = nil,
                                 userID: UUID = owner) -> RemoteMembershipRecord {
        RemoteMembershipRecord(userID: userID, workspaceID: workspace, wordID: wordID, folderID: folderID,
                               createdAt: t0.addingTimeInterval(-7_200), updatedAt: updatedAt, deletedAt: deletedAt)
    }

    static func validated(_ record: RemoteWordRecord, known: KnownRemoteIDs = legacyKnown) throws -> ValidatedRemoteWord {
        try RemoteRecordValidator.validate(record, ownerID: owner, known: known, now: t0)
    }

    static func validated(_ record: RemoteFolderRecord, known: KnownRemoteIDs = legacyKnown) throws -> ValidatedRemoteFolder {
        try RemoteRecordValidator.validate(record, ownerID: owner, known: known, now: t0)
    }

    static func validated(_ record: RemoteWorkspaceRecord) throws -> ValidatedRemoteWorkspace {
        try RemoteRecordValidator.validate(record, ownerID: owner, now: t0)
    }

    static func validated(_ record: RemoteMembershipRecord, known: KnownRemoteIDs) throws -> ValidatedRemoteMembership {
        try RemoteRecordValidator.validate(record, ownerID: owner, known: known, now: t0)
    }
}
