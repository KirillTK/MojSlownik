import XCTest
@testable import MojSlownik

final class WorkspaceScopeTests: XCTestCase {
    private let german = WorkspaceID.make(term: "de", translation: "ru")

    private func word(_ polish: String, workspace: UUID?, deleted: Bool = false) -> Word {
        let word = Word(russian: "x", polish: polish, side: .term)
        word.workspaceID = workspace
        if deleted { word.markDeleted(now: .now) }
        return word
    }

    private func folder(_ name: String, workspace: UUID?, deleted: Bool = false) -> WordFolder {
        let folder = WordFolder(name: name)
        folder.workspaceID = workspace
        if deleted { folder.markDeleted(now: .now) }
        return folder
    }

    func testWordsAreFilteredByWorkspaceAndActivity() {
        let words = [word("a", workspace: WorkspaceID.legacy), word("b", workspace: german),
                     word("c", workspace: german, deleted: true)]
        XCTAssertEqual(WorkspaceScope.words(words, workspaceID: german).map(\.polish), ["b"])
        XCTAssertEqual(WorkspaceScope.words(words, workspaceID: WorkspaceID.legacy).map(\.polish), ["a"])
    }

    func testNilWorkspaceIDBelongsToTheLegacyWorkspace() {
        let words = [word("old", workspace: nil), word("de", workspace: german)]
        XCTAssertEqual(words[0].effectiveWorkspaceID, WorkspaceID.legacy)
        XCTAssertEqual(WorkspaceScope.words(words, workspaceID: WorkspaceID.legacy).map(\.polish), ["old"])
        XCTAssertTrue(WorkspaceScope.words(words, workspaceID: UUID()).isEmpty)
    }

    func testNilScopeIDGivesNothing() {
        XCTAssertTrue(WorkspaceScope.words([word("a", workspace: nil)], workspaceID: nil).isEmpty)
        XCTAssertTrue(WorkspaceScope.folders([folder("a", workspace: nil)], workspaceID: nil).isEmpty)
    }

    func testFoldersLikewise() {
        let folders = [folder("old", workspace: nil), folder("de", workspace: german),
                       folder("gone", workspace: german, deleted: true)]
        XCTAssertEqual(WorkspaceScope.folders(folders, workspaceID: german).map(\.name), ["de"])
        XCTAssertEqual(WorkspaceScope.folders(folders, workspaceID: WorkspaceID.legacy).map(\.name), ["old"])
    }
}
