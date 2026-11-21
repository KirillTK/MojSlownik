#if DEBUG
import Foundation
import SwiftData

/// Named SwiftData fixtures for UI-test mode. Dates are relative to `now` (launch time).
enum UITestFixture: String, CaseIterable, Sendable {
    case empty, basicVocabulary, dueForReview, foldersOrdered
    /// `basicVocabulary` with fixed uuids and rows already synced (clean): pairs with the
    /// `syncedThenRemoteChanges` server state.
    case syncedVocabulary

    static let lesson1ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let lesson2ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let lesson3ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!

    /// Fixed ids of the `syncedVocabulary` words, in `basicVocabulary` order (kot = a1, dom = a2).
    static let syncedWordIDs: [UUID] = (1...5).map { UUID(uuidString: "00000000-0000-0000-0000-0000000000A\($0)")! }

    struct SyncedWord: Equatable, Sendable {
        let id: UUID
        let russian: String
        let polish: String
        let source: WordSide
        let createdAt: Date
        let dueDate: Date

        /// The server's (and the clean local row's) version time: createdAt cut to milliseconds.
        var syncedAt: Date { UITestFixture.truncatedToMillis(createdAt) }
    }

    static func syncedWords(now: Date) -> [SyncedWord] {
        let pairs: [(String, String, WordSide)] = [("кот", "kot", .translation), ("дом", "dom", .term),
                                                      ("вода", "woda", .term), ("хлеб", "chleb", .translation),
                                                      ("книга", "książka", .translation)]
        return pairs.enumerated().map { index, pair in
            SyncedWord(id: syncedWordIDs[index], russian: pair.0, polish: pair.1, source: pair.2,
                       createdAt: now.addingTimeInterval(-Double(index + 1) * 3600),
                       dueDate: now.addingTimeInterval(30 * 86_400))
        }
    }

    /// Version time of the clean pl ← ru workspace of `syncedVocabulary` (and of the server's copy).
    static func syncedWorkspaceStamp(now: Date) -> Date {
        truncatedToMillis(now.addingTimeInterval(-7_200))
    }

    static func truncatedToMillis(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }

    @MainActor
    func seed(into context: ModelContext, now: Date) throws {
        let workspace = try WorkspaceCatalog.ensure(term: "pl", translation: "ru", context: context, now: now)
        let workspaceID = workspace.id
        if self == .syncedVocabulary {
            // Clean, like the server's copy (the `syncedThenRemoteChanges` state mirrors it).
            let stamp = Self.syncedWorkspaceStamp(now: now)
            workspace.updatedAt = stamp
            workspace.serverUpdatedAt = stamp
        }
        var memberships: [(word: Word, folderID: UUID)] = []
        var index = 0
        func word(_ russian: String, _ polish: String, _ source: WordSide,
                  due: Bool = false, folders: [UUID] = []) -> Word {
            let word = Word(entry: WordEntry(term: polish, translation: russian, enteredSide: source),
                            pair: .polishRussian, workspaceID: workspaceID,
                            createdAt: now.addingTimeInterval(-Double(index + 1) * 3600))
            index += 1
            if due {
                word.repetitions = 1
                word.intervalDays = 1
                word.dueDate = now.addingTimeInterval(-86_400)
            } else {
                word.repetitions = 3
                word.intervalDays = 30
                word.easeFactor = 2.5
                word.dueDate = now.addingTimeInterval(30 * 86_400)
            }
            memberships += folders.map { (word, $0) }
            return word
        }

        var words: [Word] = []
        switch self {
        case .empty:
            break
        case .basicVocabulary:
            words = [word("кот", "kot", .translation), word("дом", "dom", .term),
                     word("вода", "woda", .term), word("хлеб", "chleb", .translation),
                     word("книга", "książka", .translation)]
        case .syncedVocabulary:
            words = Self.syncedWords(now: now).map { spec in
                let item = word(spec.russian, spec.polish, spec.source)
                item.uuid = spec.id
                item.updatedAt = spec.syncedAt
                item.serverUpdatedAt = spec.syncedAt
                return item
            }
        case .dueForReview:
            words = [word("кот", "kot", .translation), word("дом", "dom", .term),
                     word("вода", "woda", .term),
                     word("яблоко", "jabłko", .translation, due: true),
                     word("окно", "okno", .term, due: true)]
        case .foldersOrdered:
            let created = now.addingTimeInterval(-86_400)
            for (name, id, order) in [("Урок 3", Self.lesson3ID, 2), ("Урок 1", Self.lesson1ID, 0),
                                      ("Урок 2", Self.lesson2ID, 1)] {
                let folder = WordFolder(name: name)
                folder.id = id
                folder.sortOrder = order
                folder.createdAt = created
                folder.workspaceID = workspaceID
                context.insert(folder)
            }
            words = [word("кот", "kot", .translation, folders: [Self.lesson1ID]),
                     word("дом", "dom", .term, folders: [Self.lesson1ID]),
                     word("вода", "woda", .term, folders: [Self.lesson2ID]),
                     word("хлеб", "chleb", .translation)]
        }
        words.forEach(context.insert)
        for (word, folderID) in memberships {
            guard let uuid = word.uuid else { continue }
            context.insert(FolderMembership(wordID: uuid, folderID: folderID, workspaceID: workspaceID,
                                            createdAt: word.createdAt))
        }
        try context.save()
    }
}
#endif
