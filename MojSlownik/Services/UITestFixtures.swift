#if DEBUG
import Foundation
import SwiftData

/// Named SwiftData fixtures for UI-test mode. Dates are relative to `now` (launch time).
enum UITestFixture: String, CaseIterable, Sendable {
    case empty, basicVocabulary, dueForReview, foldersOrdered

    static let lesson1ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let lesson2ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let lesson3ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!

    @MainActor
    func seed(into context: ModelContext, now: Date) throws {
        var index = 0
        func word(_ russian: String, _ polish: String, _ source: AppLanguage,
                  due: Bool = false, folders: [UUID] = []) -> Word {
            let word = Word(russian: russian, polish: polish, sourceLanguage: source,
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
            word.folderIDs = folders
            return word
        }

        var words: [Word] = []
        switch self {
        case .empty:
            break
        case .basicVocabulary:
            words = [word("кот", "kot", .russian), word("дом", "dom", .polish),
                     word("вода", "woda", .polish), word("хлеб", "chleb", .russian),
                     word("книга", "książka", .russian)]
        case .dueForReview:
            words = [word("кот", "kot", .russian), word("дом", "dom", .polish),
                     word("вода", "woda", .polish),
                     word("яблоко", "jabłko", .russian, due: true),
                     word("окно", "okno", .polish, due: true)]
        case .foldersOrdered:
            let created = now.addingTimeInterval(-86_400)
            for (name, id, order) in [("Урок 3", Self.lesson3ID, 2), ("Урок 1", Self.lesson1ID, 0),
                                      ("Урок 2", Self.lesson2ID, 1)] {
                let folder = WordFolder(name: name)
                folder.id = id
                folder.sortOrder = order
                folder.createdAt = created
                context.insert(folder)
            }
            words = [word("кот", "kot", .russian, folders: [Self.lesson1ID]),
                     word("дом", "dom", .polish, folders: [Self.lesson1ID]),
                     word("вода", "woda", .polish, folders: [Self.lesson2ID]),
                     word("хлеб", "chleb", .russian)]
        }
        words.forEach(context.insert)
        try context.save()
    }
}
#endif
