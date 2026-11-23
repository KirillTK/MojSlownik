import SwiftData
import XCTest
@testable import MojSlownik

/// Stores log product events and storage failures, never user content.
@MainActor
final class StoreLoggingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Vocabulary

    func testAddLogsLanguageCategoryAndFolderPresenceOnly() throws {
        let spy = AppLogSpy()
        let store = VocabularyStore(repository: RecordingVocabularyRepository(), logger: spy)
        store.workspace = .legacy
        try store.add(WordEntry.legacy(source: "кот", translation: "kot"), category: .food, folderID: UUID())
        XCTAssertEqual(spy.events, [.wordAdded])
        XCTAssertEqual(spy.entries[0].properties, [.source: .name("manual"), .language: .name("ru"),
                                                   .category: .name("food"), .inFolder: .bool(true)])
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("кот") || $0.contains("kot") })
    }

    func testScanToggleLogsAddOrRemove() throws {
        let spy = AppLogSpy()
        let repository = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repository, logger: spy)
        store.workspace = .legacy
        repository.toggleResult = true
        try store.toggleScanned(WordEntry.legacy(source: "dom", translation: "дом"), category: .home)
        repository.toggleResult = false
        try store.toggleScanned(WordEntry.legacy(source: "dom", translation: "дом"), category: .home)
        XCTAssertEqual(spy.events, [.wordAdded, .wordRemoved])
        XCTAssertEqual(spy.entries[0].properties[.source], .name("scan"))
        XCTAssertEqual(spy.entries[0].properties[.language], .name("pl"))
    }

    func testEveryVocabularyMutationLogsAnEvent() throws {
        let spy = AppLogSpy()
        let store = VocabularyStore(repository: RecordingVocabularyRepository(), logger: spy)
        store.workspace = .legacy
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: now)
        try store.changeCategory(.food, entry: WordEntry.legacy(source: "кот", translation: "kot"))
        try store.setCategory(.home, for: word)
        try store.setMembership(of: word, folderID: UUID(), included: true)
        try store.removeFromAllFolders(word)
        try store.deleteWord(word)
        XCTAssertEqual(spy.events, [.wordCategoryChanged, .wordCategoryChanged, .wordFoldersChanged,
                                    .wordFoldersChanged, .wordDeleted])
    }

    func testVocabularyFailureLogsCodeOnlyAndRethrows() {
        let spy = AppLogSpy()
        let repository = RecordingVocabularyRepository()
        repository.nextError = UserTextError(text: "кот")
        let store = VocabularyStore(repository: repository, logger: spy)
        store.workspace = .legacy
        XCTAssertThrowsError(try store.add(WordEntry.legacy(source: "кот", translation: "kot")))
        XCTAssertEqual(spy.events, [.storageFailed])
        XCTAssertEqual(spy.entries[0].level, .error)
        XCTAssertEqual(spy.entries[0].properties[.operation], .name("vocabulary.add_word"))
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("кот") })
    }

    // MARK: Folders

    func testFolderEventsNeverIncludeNames() throws {
        let spy = AppLogSpy()
        let store = FolderLibraryStore.inLegacyWorkspace(repository: InMemoryFolderRepository(), logger: spy)
        let first = try store.create(name: "Секретная папка")
        let second = try store.create(name: "Еда")
        try store.rename(id: first, name: "Работа")
        try store.reorder(ids: [second, first])
        try store.delete(id: second)
        XCTAssertEqual(spy.events, [.folderCreated, .folderCreated, .folderRenamed, .foldersReordered, .folderDeleted])
        XCTAssertEqual(spy.entries[3].properties[.count], .int(2))
        XCTAssertTrue(spy.loggedNames.isEmpty)
    }

    func testFolderFailureLogsOperation() {
        let spy = AppLogSpy()
        let repository = InMemoryFolderRepository()
        repository.nextError = UserTextError(text: "Еда")
        let store = FolderLibraryStore.inLegacyWorkspace(repository: repository, logger: spy)
        XCTAssertThrowsError(try store.create(name: "Еда"))
        XCTAssertEqual(spy.events, [.storageFailed])
        XCTAssertEqual(spy.entries[0].properties[.operation], .name("folders.create"))
    }

    // MARK: Achievements and practice

    func testAnnouncedUnlocksAreLoggedByCatalogID() {
        let spy = AppLogSpy()
        let store = AchievementStore(repository: InMemoryAchievementStateRepository(), logger: spy)
        store.sync(vocabulary: AchievementMetrics([.wordCount: 1]), now: now)
        XCTAssertTrue(spy.entries.isEmpty, "the silent first sync logs nothing")
        store.sync(vocabulary: AchievementMetrics([.wordCount: 50]), now: now)
        XCTAssertEqual(spy.events, [.achievementUnlocked])
        XCTAssertEqual(spy.entries[0].properties[.achievement], .name("vocabulary.words.50"))
    }

    func testPracticeAnswersAreLoggedWithModeAndResult() throws {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: now)
        context.insert(word)
        try context.save()
        let spy = AppLogSpy()
        let store = DailyStudyStore(repository: InMemoryDailyActivityRepository(), now: now, logger: spy)

        try store.review(.again, to: word, context: context, now: now)
        try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: true), context: context,
                                       mode: .quiz, now: now)
        // Review finding: listening counts toward quiz completion (isQuiz) but logs its own mode.
        try store.recordPracticeAnswer(word: word, answer: .typed(expected: "kot", submitted: "kot"),
                                       context: context, mode: .listening, now: now)
        XCTAssertEqual(spy.events, [.practiceAnswered, .practiceAnswered, .practiceAnswered])
        XCTAssertEqual(spy.entries[0].properties, [.mode: .name("flashcards"), .grade: .name("again"), .correct: .bool(false)])
        XCTAssertEqual(spy.entries[1].properties, [.mode: .name("quiz"), .correct: .bool(true)])
        XCTAssertEqual(spy.entries[2].properties, [.mode: .name("listening"), .correct: .bool(true)])
        XCTAssertFalse(spy.loggedNames.contains("kot"))
    }

    /// Review finding: every practice path logs, including activity-encoding failures.
    func testPracticeRecordFailuresAndLowLevelPathsAreLogged() throws {
        let repository = InMemoryDailyActivityRepository()
        let spy = AppLogSpy()
        let store = DailyStudyStore(repository: repository, now: now, logger: spy)
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: now)
        container.mainContext.insert(word)
        try container.mainContext.save()

        try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: false),
                                       context: container.mainContext, mode: .quiz, now: now)
        try store.record(wordID: word.persistentModelID, grade: .easy, now: now)
        XCTAssertEqual(spy.entries.map(\.properties[.mode]), [.name("quiz"), .name("flashcards")])

        repository.prepareError = UserTextError(text: "кот")
        XCTAssertThrowsError(try store.review(.good, to: word, context: container.mainContext, now: now))
        let beforeSRS = SRSState(word: word)
        let beforeTier = word.knowledgeTier
        XCTAssertThrowsError(try store.recordPracticeAnswer(word: word, answer: .choice(isCorrect: true),
                                                            context: container.mainContext, mode: .quiz, now: now))
        XCTAssertEqual(SRSState(word: word), beforeSRS, "a failed activity encode must not touch the schedule")
        XCTAssertEqual(word.knowledgeTier, beforeTier)
        XCTAssertEqual(spy.events.suffix(2), [.storageFailed, .storageFailed])
        XCTAssertEqual(spy.entries.last?.properties[.operation], .name("daily_activity.prepare_save"))
    }
}
