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
}
