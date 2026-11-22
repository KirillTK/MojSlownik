import XCTest
@testable import MojSlownik

@MainActor
final class SyncStateRepositoryTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "SyncStateRepositoryTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testRoundTrip() throws {
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        let state = SyncState(linkedAccountID: UUID(), capabilityVersion: 1,
                              foldersCursor: SyncCursor(updatedAtMillis: 1_794_955_800_123, id: UUID()),
                              wordsCursor: SyncCursor(updatedAtMillis: 1_794_955_900_456, id: UUID()),
                              lastSyncedAt: Date(timeIntervalSince1970: 1_800_000_000), heldIDs: [UUID(), UUID()])
        try repository.save(state)
        XCTAssertEqual(repository.load(), state)
        XCTAssertEqual(UserDefaultsSyncStateRepository(defaults: defaults).load(), state, "a new instance reads it")
    }

    func testMissingDataGivesDefaultState() {
        XCTAssertEqual(UserDefaultsSyncStateRepository(defaults: defaults).load(), SyncState())
        XCTAssertNil(SyncState().linkedAccountID)
        XCTAssertEqual(SyncState().capabilityVersion, 0)
        XCTAssertTrue(SyncState().heldIDs.isEmpty)
    }

    func testCorruptDataGivesDefaultState() {
        defaults.set(Data("not json".utf8), forKey: UserDefaultsSyncStateRepository.defaultKey)
        XCTAssertEqual(UserDefaultsSyncStateRepository(defaults: defaults).load(), SyncState())
        defaults.set("a string", forKey: UserDefaultsSyncStateRepository.defaultKey)
        XCTAssertEqual(UserDefaultsSyncStateRepository(defaults: defaults).load(), SyncState())
    }

    func testPartialJSONDecodesWithDefaults() throws {
        let id = UUID()
        let state = try JSONDecoder().decode(SyncState.self, from: Data(#"{"linkedAccountID":"\#(id.uuidString)"}"#.utf8))
        XCTAssertEqual(state, SyncState(linkedAccountID: id))
        XCTAssertEqual(try JSONDecoder().decode(SyncState.self, from: Data("{}".utf8)), SyncState())
    }

    func testStoredUnderTheDocumentedKey() throws {
        try UserDefaultsSyncStateRepository(defaults: defaults).save(SyncState(capabilityVersion: 1))
        XCTAssertNotNil(defaults.data(forKey: "sync.v1"))
    }

    /// An old `sync.v1` (two cursors, no `secondaryID`) decodes with the new cursors nil.
    func testOldStateJSONDecodesWithNilNewCursors() throws {
        let id = UUID()
        let json = """
        {"linkedAccountID":"\(id.uuidString)","capabilityVersion":1,
         "foldersCursor":{"updatedAtMillis":1794955800123,"id":"\(id.uuidString)"},
         "wordsCursor":{"updatedAtMillis":1794955800124,"id":"\(id.uuidString)"}}
        """
        let state = try JSONDecoder().decode(SyncState.self, from: Data(json.utf8))
        XCTAssertNil(state.workspacesCursor)
        XCTAssertNil(state.membershipsCursor)
        XCTAssertEqual(state.foldersCursor, SyncCursor(updatedAtMillis: 1_794_955_800_123, id: id))
        XCTAssertNil(state.foldersCursor?.secondaryID)
    }

    func testSecondaryIDAndNewCursorsRoundTrip() throws {
        let cursor = SyncCursor(updatedAtMillis: 1_794_955_800_123, id: UUID(), secondaryID: UUID())
        let state = SyncState(linkedAccountID: UUID(), capabilityVersion: 2,
                              workspacesCursor: SyncCursor(updatedAtMillis: 5, id: UUID()),
                              membershipsCursor: cursor)
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        try repository.save(state)
        XCTAssertEqual(repository.load(), state)
        XCTAssertEqual(repository.load().membershipsCursor?.secondaryID, cursor.secondaryID)
    }

    func testOverlappingResetsBothIDsAndKeepsAMissingSecondaryNil() {
        let membership = SyncCursor(updatedAtMillis: 100_000, id: UUID(), secondaryID: UUID())
        let overlapped = membership.overlapping(by: 60_000)
        XCTAssertEqual(overlapped.updatedAtMillis, 40_000)
        XCTAssertEqual(overlapped.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertEqual(overlapped.secondaryID, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertNil(SyncCursor(updatedAtMillis: 100_000, id: UUID()).overlapping(by: 1).secondaryID)
    }
}
