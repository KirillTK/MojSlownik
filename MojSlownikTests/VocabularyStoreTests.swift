import XCTest
@testable import MojSlownik

@MainActor
final class VocabularyStoreTests: XCTestCase {
    private func word(uuid: UUID?) -> Word {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.uuid = uuid
        return word
    }

    func testForwardsWritesToRepository() throws {
        let repo = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repo)
        store.workspace = .legacy
        let folder = UUID()
        let entry = WordEntry(term: "woda", translation: "вода", enteredSide: .term)
        try store.add(WordEntry.legacy(source: "woda", translation: "вода"), category: .food, folderID: folder)
        repo.toggleResult = false
        XCTAssertFalse(try store.toggleScanned(WordEntry.legacy(source: "woda", translation: "вода"), category: .food))
        try store.changeCategory(.home, entry: WordEntry.legacy(source: "woda", translation: "вода"))
        XCTAssertEqual(repo.calls, [
            .addWord(entry, .food, folder, .legacy),
            .toggle(entry, .food, nil, .legacy),
            .changeCategory(.home, entry, .legacy)
        ])
    }

    func testWordWithUUIDSkipsEnsureIdentity() throws {
        let repo = RecordingVocabularyRepository()
        let store = VocabularyStore(repository: repo)
        store.workspace = .legacy
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
            store.workspace = .legacy
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
            store.workspace = .legacy
            XCTAssertThrowsError(try operation(store, word(uuid: nil))) { error in
                XCTAssertEqual(error as? RepositoryError, .missingIdentity)
            }
            XCTAssertEqual(repo.calls, [.ensureIdentity])
        }
    }

    func testChangeSignalFiresAfterSuccessfulWritesOnly() throws {
        let repo = RecordingVocabularyRepository()
        let signal = LocalChangeSignal()
        var fired = 0
        signal.handler = { fired += 1 }
        let store = VocabularyStore(repository: repo, changeSignal: signal)
        store.workspace = .legacy
        let target = word(uuid: UUID())
        let folder = UUID()

        try store.add(WordEntry.legacy(source: "woda", translation: "вода"))
        try store.toggleScanned(WordEntry.legacy(source: "woda", translation: "вода"), category: .food)
        try store.changeCategory(.home, entry: WordEntry.legacy(source: "woda", translation: "вода"))
        try store.setCategory(.travel, for: target)
        try store.deleteWord(target)
        try store.setMembership(of: target, folderID: folder, included: true)
        try store.removeFromAllFolders(target)
        XCTAssertEqual(fired, 7)

        repo.nextError = RepositoryFakeError.forced
        XCTAssertThrowsError(try store.add(WordEntry.legacy(source: "kot", translation: "кот")))
        repo.nextError = RepositoryFakeError.forced
        XCTAssertThrowsError(try store.deleteWord(target))
        XCTAssertEqual(fired, 7, "failed writes never notify")
    }
}
