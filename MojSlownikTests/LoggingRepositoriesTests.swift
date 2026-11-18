import XCTest
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
            ("vocabulary.add_word", { try repository.addWord(source: "кот", translation: "kot", category: nil, folderID: nil) }),
            ("vocabulary.toggle_scanned_word", {
                _ = try repository.toggleScannedWord(source: "кот", translation: "kot", category: .food, folderID: nil)
            }),
            ("vocabulary.change_category", { try repository.changeCategory(.food, source: "кот", translation: "kot") }),
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
        XCTAssertThrowsError(try repository.ensureIdentity(for: Word(russian: "кот", polish: "kot", sourceLanguage: .russian)))
        assertLoggedFailure(spy, "vocabulary.ensure_identity")
        XCTAssertEqual(spy.entries.count, cases.count + 1, "exactly one entry per failure")
    }

    func testVocabularySuccessIsForwardedAndNotLogged() throws {
        let base = RecordingVocabularyRepository()
        base.toggleResult = false
        let spy = AppLogSpy()
        let repository = LoggingVocabularyRepository(base, logger: spy)
        XCTAssertFalse(try repository.toggleScannedWord(source: "a", translation: "b", category: .food, folderID: nil))
        XCTAssertEqual(base.calls, [.toggle("a", "b", .food, nil)])
        XCTAssertTrue(spy.entries.isEmpty)
    }

    func testEveryFolderMethodLogsItsFailure() throws {
        let base = InMemoryFolderRepository()
        let spy = AppLogSpy()
        let repository = LoggingFolderRepository(base, logger: spy)
        let id = try repository.createFolder(name: "Еда")
        XCTAssertTrue(spy.entries.isEmpty)
        let cases: [(String, () throws -> Void)] = [
            ("folders.load", { _ = try repository.folders() }),
            ("folders.create", { _ = try repository.createFolder(name: "Еда") }),
            ("folders.rename", { try repository.renameFolder(id: id, name: "Еда") }),
            ("folders.reorder", { try repository.reorderFolders(ids: [id]) }),
            ("folders.delete", { try repository.deleteFolder(id: id) }),
        ]
        for (operation, call) in cases {
            base.nextError = UserTextError(text: "Еда")
            XCTAssertThrowsError(try call(), operation)
            assertLoggedFailure(spy, operation)
        }
        XCTAssertEqual(try repository.folders().map(\.id), [id], "successful reads pass through")
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
