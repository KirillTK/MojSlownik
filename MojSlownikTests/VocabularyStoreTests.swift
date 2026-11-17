import XCTest
@testable import MojSlownik

@MainActor
final class VocabularyStoreTests: XCTestCase {
    private func word(uuid: UUID?) -> Word {
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.uuid = uuid
        return word
    }

    func testForwardsWritesToRepository() throws {
        let repo = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repo)
        let folder = UUID()
        try store.add(source: "woda", translation: "вода", category: .food, folderID: folder)
        repo.toggleResult = false
        XCTAssertFalse(try store.toggleScanned(source: "woda", translation: "вода", category: .food))
        try store.changeCategory(.home, source: "woda", translation: "вода")
        XCTAssertEqual(repo.calls, [
            .addWord("woda", "вода", .food, folder),
            .toggle("woda", "вода", .food, nil),
            .changeCategory(.home, "woda", "вода")
        ])
    }

    func testWordWithUUIDSkipsEnsureIdentity() throws {
        let repo = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repo)
        let id = UUID()
        let target = word(uuid: id)
        let folder = UUID()
        try store.deleteWord(target)
        try store.setCategory(.travel, for: target)
        try store.setMembership(of: target, folderID: folder, included: true)
        try store.removeFromAllFolders(target)
        XCTAssertEqual(repo.calls, [.deleteWord(id), .setCategory(.travel, id),
                                    .setMembership(id, folder, true), .removeFromAllFolders(id)])
    }

    func testNilUUIDTriggersLazyIdentityThenWrite() throws {
        let folder = UUID()
        let operations: [(VocabularyStore, Word) throws -> Void] = [
            { try $0.deleteWord($1) },
            { try $0.setCategory(.travel, for: $1) },
            { try $0.setMembership(of: $1, folderID: folder, included: false) },
            { try $0.removeFromAllFolders($1) }
        ]
        for operation in operations {
            let repo = RecordingVocabularyRepository()
            let assigned = UUID()
            repo.identityResult = .success(assigned)
            let store = VocabularyStore(repository: repo)
            try operation(store, word(uuid: nil))
            XCTAssertEqual(repo.calls.count, 2)
            XCTAssertEqual(repo.calls.first, .ensureIdentity)
        }
        let repo = RecordingVocabularyRepository()
        let assigned = UUID()
        repo.identityResult = .success(assigned)
        try VocabularyStore(repository: repo).deleteWord(word(uuid: nil))
        XCTAssertEqual(repo.calls, [.ensureIdentity, .deleteWord(assigned)])
    }

    func testIdentityFailureThrowsAndMakesNoWrite() {
        let operations: [(VocabularyStore, Word) throws -> Void] = [
            { try $0.deleteWord($1) },
            { try $0.setCategory(.travel, for: $1) },
            { try $0.setMembership(of: $1, folderID: UUID(), included: true) },
            { try $0.removeFromAllFolders($1) }
        ]
        for operation in operations {
            let repo = RecordingVocabularyRepository()
            repo.identityResult = .failure(RepositoryError.missingIdentity)
            let store = VocabularyStore(repository: repo)
            XCTAssertThrowsError(try operation(store, word(uuid: nil))) { error in
                XCTAssertEqual(error as? RepositoryError, .missingIdentity)
            }
            XCTAssertEqual(repo.calls, [.ensureIdentity])
        }
    }
}
