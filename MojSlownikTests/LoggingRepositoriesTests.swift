import XCTest
import SwiftData
@testable import MojSlownik

/// Review finding: every repository failure is logged once by a decorator (not by hand in each
/// store method), with a stable "<repository>.<method>" id and no user content.
@MainActor
final class LoggingRepositoriesTests: XCTestCase {
    private func assertLoggedFailure(_ spy: AppLogSpy, _ operation: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(spy.events.last, .storageFailed, operation, file: file, line: line)
        XCTAssertEqual(spy.entries.last?.level, .error, file: file, line: line)
        XCTAssertEqual(spy.entries.last?.properties[.operation], .name(operation), file: file, line: line)
        XCTAssertFalse(spy.loggedNames.contains { $0.contains("кот") || $0.contains("Еда") }, file: file, line: line)
    }

    func testEveryVocabularyMethodLogsItsFailure() {
        let base = RecordingVocabularyRepository()
        let spy = AppLogSpy()
        let repository = LoggingVocabularyRepository(base, logger: spy)
        let id = UUID()
        let cases: [(String, () throws -> Void)] = [
            ("vocabulary.add_word", { try repository.addWord(WordEntry.legacy(source: "кот", translation: "kot"), category: nil, folderID: nil, workspace: .legacy) }),
            ("vocabulary.toggle_scanned_word", {
                _ = try repository.toggleScannedWord(WordEntry.legacy(source: "кот", translation: "kot"), category: .food, folderID: nil, workspace: .legacy)
            }),
            ("vocabulary.change_category", { try repository.changeCategory(.food, entry: WordEntry.legacy(source: "кот", translation: "kot"), workspace: .legacy) }),
            ("vocabulary.set_category", { try repository.setCategory(.home, wordID: id) }),
            ("vocabulary.delete_word", { try repository.deleteWord(id: id) }),
            ("vocabulary.set_membership", { try repository.setMembership(wordID: id, folderID: id, included: true) }),
            ("vocabulary.remove_from_all_folders", { try repository.removeFromAllFolders(wordID: id) }),
        ]
        for (operation, call) in cases {
            base.nextError = UserTextError(text: "кот")
            XCTAssertThrowsError(try call(), operation)
            assertLoggedFailure(spy, operation)
        }
        base.identityResult = .failure(UserTextError(text: "кот"))
        XCTAssertThrowsError(try repository.ensureIdentity(for: Word(russian: "кот", polish: "kot", side: .translation)))
        assertLoggedFailure(spy, "vocabulary.ensure_identity")
        XCTAssertEqual(spy.entries.count, cases.count + 1, "exactly one entry per failure")
    }

    func testVocabularySuccessIsForwardedAndNotLogged() throws {
        let base = RecordingVocabularyRepository()
        base.toggleResult = false
        let spy = AppLogSpy()
        let repository = LoggingVocabularyRepository(base, logger: spy)
        XCTAssertFalse(try repository.toggleScannedWord(WordEntry.legacy(source: "a", translation: "b"), category: .food, folderID: nil, workspace: .legacy))
        XCTAssertEqual(base.calls, [.toggle(WordEntry.legacy(source: "a", translation: "b"), .food, nil, .legacy)])
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testEveryWorkspaceMethodLogsItsFailure() throws {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let base = SwiftDataWorkspaceRepository(container: container)
        let spy = AppLogSpy()
        let repository = LoggingWorkspaceRepository(base, logger: spy)
        let id = try repository.ensure(term: "pl", translation: "ru").id
        XCTAssertEqual(try repository.workspaces().map(\.id), [id], "successful calls pass through unlogged")
        XCTAssertTrue(spy.entries.isEmpty)
        let cases: [(String, () throws -> Void)] = [
            ("workspaces.delete", { try repository.delete(id: id) }),
            ("workspaces.reorder", { try repository.reorder(ids: [id, id]) }),
        ]
        for (operation, call) in cases {
            XCTAssertThrowsError(try call(), operation)
            assertLoggedFailure(spy, operation)
        }
        XCTAssertEqual(spy.entries.count, cases.count)
    }

    func testEveryFolderMethodLogsItsFailure() throws {
        let base = InMemoryFolderRepository()
        let spy = AppLogSpy()
        let repository = LoggingFolderRepository(base, logger: spy)
        let ws = WorkspaceID.legacy
        let id = try repository.createFolder(name: "Еда", workspaceID: ws)
        XCTAssertTrue(spy.entries.isEmpty)
        let cases: [(String, () throws -> Void)] = [
            ("folders.load", { _ = try repository.folders(in: ws) }),
            ("folders.create", { _ = try repository.createFolder(name: "Еда", workspaceID: ws) }),
            ("folders.rename", { try repository.renameFolder(id: id, name: "Еда") }),
            ("folders.reorder", { try repository.reorderFolders(ids: [id], workspaceID: ws) }),
            ("folders.delete", { try repository.deleteFolder(id: id) }),
        ]
        for (operation, call) in cases {
            base.nextError = UserTextError(text: "Еда")
            XCTAssertThrowsError(try call(), operation)
            assertLoggedFailure(spy, operation)
        }
        XCTAssertEqual(try repository.folders(in: ws).map(\.id), [id], "successful reads pass through")
    }

    func testDailyActivityPrepareSaveFailureIsLogged() throws {
        let base = InMemoryDailyActivityRepository()
        let spy = AppLogSpy()
        let repository = LoggingDailyActivityRepository(base, logger: spy)
        let commit = try repository.prepareSave(DailyActivity(day: Date(timeIntervalSince1970: 0)))
        commit()
        XCTAssertNotNil(repository.load())
        repository.clear()
        XCTAssertEqual(base.clearCount, 1)
        XCTAssertTrue(spy.entries.isEmpty)

        base.prepareError = UserTextError(text: "кот")
        XCTAssertThrowsError(try repository.prepareSave(DailyActivity(day: Date(timeIntervalSince1970: 0))))
        assertLoggedFailure(spy, "daily_activity.prepare_save")
    }
}
