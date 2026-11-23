#if DEBUG
import Foundation
import SwiftData

/// Named SwiftData fixtures for UI-test mode. Dates are relative to `now` (launch time).
enum UITestFixture: String, CaseIterable, Sendable {
    case empty, basicVocabulary, dueForReview, foldersOrdered
    /// Nothing at all, not even a workspace: the first-launch wizard (or the pull gate when signed in).
    case freshInstall
    /// pl ← ru (`basicVocabulary` words, folder "Lesson 1" with kot and dom) and de ← ru
    /// («das Haus», «lernen», folder «Lektion 1» with «das Haus»); pl sorts first and is active.
    case multiWorkspace
    /// en ← pl active and empty: both sides use Latin letters, so the "I’m typing in" control appears (ASCII typing works for both).
    case sameScriptWorkspace
    /// `basicVocabulary` with fixed uuids and rows already synced (clean): pairs with the
    /// `syncedThenRemoteChanges` server state.
    case syncedVocabulary
    /// pl ← ru, folders "Lesson 1" (kot, dom, chleb) and "Lesson 2" (4 new words): 3 learned, 3 learning
    /// (one hard word), 4 new; 5 due now, forecast tomorrow 1 / week 2.
    case studyProgress

    static let lesson1ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let lesson2ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let lesson3ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!
    static let lektion1ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F4")!

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
        let pairs: [(String, String, WordSide)] = [("кот", "kot", .translation), ("дом", "dom", .term), // l10n:data
                                                      ("вода", "woda", .term), ("хлеб", "chleb", .translation), // l10n:data
                                                      ("книга", "książka", .translation)] // l10n:data
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
        if self == .freshInstall { return }
        if self == .sameScriptWorkspace {
            try WorkspaceCatalog.ensure(term: "en", translation: "pl", context: context, now: now)
            return
        }
        let workspace = try WorkspaceCatalog.ensure(term: "pl", translation: "ru", context: context, now: now)
        let workspaceID = workspace.id
        if self == .syncedVocabulary {
            // Clean, like the server's copy (the `syncedThenRemoteChanges` state mirrors it).
            let stamp = Self.syncedWorkspaceStamp(now: now)
            workspace.updatedAt = stamp
            workspace.serverUpdatedAt = stamp
        }
        var memberships: [(word: Word, folderID: UUID, workspaceID: UUID)] = []
        var index = 0
        func word(_ russian: String, _ polish: String, _ source: WordSide,
                  due: Bool = false, folders: [UUID] = [],
                  pair: LanguagePair = .polishRussian, in owner: UUID? = nil) -> Word {
            let word = Word(entry: WordEntry(term: polish, translation: russian, enteredSide: source),
                            pair: pair, workspaceID: owner ?? workspaceID,
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
            memberships += folders.map { (word, $0, owner ?? workspaceID) }
            return word
        }

        var words: [Word] = []
        switch self {
        case .empty, .freshInstall, .sameScriptWorkspace:
            break
        case .multiWorkspace:
            let german = try WorkspaceCatalog.ensure(term: "de", translation: "ru", context: context, now: now)
            let germanPair = LanguagePair(term: .german, translation: .russian)
            let created = now.addingTimeInterval(-86_400)
            for (name, id, owner) in [("Урок 1", Self.lesson1ID, workspaceID), // l10n:data
                                      ("Lektion 1", Self.lektion1ID, german.id)] {
                let folder = WordFolder(name: name)
                folder.id = id
                folder.createdAt = created
                folder.workspaceID = owner
                context.insert(folder)
            }
            words = [word("кот", "kot", .translation, folders: [Self.lesson1ID]), // l10n:data
                     word("дом", "dom", .term, folders: [Self.lesson1ID]), // l10n:data
                     word("вода", "woda", .term), word("хлеб", "chleb", .translation), // l10n:data
                     word("книга", "książka", .translation), // l10n:data
                     word("дом", "das Haus", .translation, folders: [Self.lektion1ID], pair: germanPair, in: german.id), // l10n:data
                     word("учить", "lernen", .translation, pair: germanPair, in: german.id)] // l10n:data
        case .basicVocabulary:
            words = [word("кот", "kot", .translation), word("дом", "dom", .term), // l10n:data
                     word("вода", "woda", .term), word("хлеб", "chleb", .translation), // l10n:data
                     word("книга", "książka", .translation)] // l10n:data
        case .syncedVocabulary:
            words = Self.syncedWords(now: now).map { spec in
                let item = word(spec.russian, spec.polish, spec.source)
                item.uuid = spec.id
                item.updatedAt = spec.syncedAt
                item.serverUpdatedAt = spec.syncedAt
                return item
            }
        case .dueForReview:
            words = [word("кот", "kot", .translation), word("дом", "dom", .term), // l10n:data
                     word("вода", "woda", .term), // l10n:data
                     word("яблоко", "jabłko", .translation, due: true), // l10n:data
                     word("окно", "okno", .term, due: true)] // l10n:data
        case .studyProgress:
            let created = now.addingTimeInterval(-86_400)
            for (name, id, order) in [("Урок 1", Self.lesson1ID, 0), ("Урок 2", Self.lesson2ID, 1)] { // l10n:data
                let folder = WordFolder(name: name)
                folder.id = id
                folder.sortOrder = order
                folder.createdAt = created
                folder.workspaceID = workspaceID
                context.insert(folder)
            }
            let calendar = Calendar.autoupdatingCurrent
            func days(_ count: Int) -> Date { calendar.date(byAdding: .day, value: count, to: now) ?? now }
            func learning(_ item: Word, repetitions: Int, interval: Double, due: Date) -> Word {
                item.repetitions = repetitions
                item.intervalDays = interval
                item.lastReviewGradeRawValue = ReviewGrade.good.rawValue
                item.dueDate = due
                return item
            }
            func fresh(_ item: Word) -> Word {
                item.repetitions = 0
                item.intervalDays = 0
                item.dueDate = item.createdAt
                return item
            }
            // Learned: interval 30, due +30 days (the helper's defaults).
            let learned = [word("кот", "kot", .translation, folders: [Self.lesson1ID]), // l10n:data
                           word("дом", "dom", .term, folders: [Self.lesson1ID]), // l10n:data
                           word("вода", "woda", .term)] // l10n:data
            learned.forEach { $0.dueDate = days(30) }
            let hard = learning(word("привычка", "przyzwyczajenie", .translation), // l10n:data
                                repetitions: 1, interval: 1, due: days(-1))
            hard.easeFactor = 1.3
            hard.lapseCount = 7
            words = learned + [
                learning(word("хлеб", "chleb", .translation, folders: [Self.lesson1ID]), // l10n:data
                         repetitions: 2, interval: 3,
                         due: calendar.date(byAdding: .hour, value: 12, to: now) ?? now),
                learning(word("окно", "okno", .term), repetitions: 1, interval: 1, due: days(3)), // l10n:data
                hard,
                fresh(word("яблоко", "jabłko", .translation, folders: [Self.lesson2ID])), // l10n:data
                fresh(word("молоко", "mleko", .translation, folders: [Self.lesson2ID])), // l10n:data
                fresh(word("сыр", "ser", .translation, folders: [Self.lesson2ID])), // l10n:data
                fresh(word("рыба", "ryba", .translation, folders: [Self.lesson2ID]))] // l10n:data
        case .foldersOrdered:
            let created = now.addingTimeInterval(-86_400)
            for (name, id, order) in [("Урок 3", Self.lesson3ID, 2), ("Урок 1", Self.lesson1ID, 0), // l10n:data
                                      ("Урок 2", Self.lesson2ID, 1)] { // l10n:data
                let folder = WordFolder(name: name)
                folder.id = id
                folder.sortOrder = order
                folder.createdAt = created
                folder.workspaceID = workspaceID
                context.insert(folder)
            }
            words = [word("кот", "kot", .translation, folders: [Self.lesson1ID]), // l10n:data
                     word("дом", "dom", .term, folders: [Self.lesson1ID]), // l10n:data
                     word("вода", "woda", .term, folders: [Self.lesson2ID]), // l10n:data
                     word("хлеб", "chleb", .translation)] // l10n:data
        }
        words.forEach(context.insert)
        for (word, folderID, owner) in memberships {
            guard let uuid = word.uuid else { continue }
            context.insert(FolderMembership(wordID: uuid, folderID: folderID, workspaceID: owner,
                                            createdAt: word.createdAt))
        }
        try context.save()
    }
}
#endif
