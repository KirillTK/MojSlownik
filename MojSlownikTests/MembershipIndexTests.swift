import XCTest
@testable import MojSlownik

final class MembershipIndexTests: XCTestCase {
    private func membership(_ word: UUID, _ folder: UUID, deleted: Bool = false) -> FolderMembership {
        let row = FolderMembership(wordID: word, folderID: folder, workspaceID: WorkspaceID.legacy)
        if deleted { row.markDeleted(now: .now) }
        return row
    }

    func testBothDirectionsAndTombstonesAreExcluded() {
        let word1 = UUID(), word2 = UUID(), folderA = UUID(), folderB = UUID()
        let index = MembershipIndex([membership(word1, folderA), membership(word1, folderB, deleted: true),
                                     membership(word2, folderA)])
        XCTAssertEqual(index.folderIDs(of: word1), [folderA], "the tombstone is excluded")
        XCTAssertEqual(index.wordIDs(in: folderA), [word1, word2])
        XCTAssertTrue(index.wordIDs(in: folderB).isEmpty)
        XCTAssertTrue(index.contains(wordID: word2, folderID: folderA))
        XCTAssertFalse(index.contains(wordID: word2, folderID: folderB))
        XCTAssertFalse(index.contains(wordID: nil, folderID: folderA))
    }

    func testEmptyInput() {
        let index = MembershipIndex([])
        XCTAssertTrue(index.folderIDs(of: UUID()).isEmpty)
        XCTAssertTrue(index.wordIDs(in: UUID()).isEmpty)
    }
}
