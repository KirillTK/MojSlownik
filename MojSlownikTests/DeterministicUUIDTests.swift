import XCTest
@testable import MojSlownik

final class DeterministicUUIDTests: XCTestCase {
    func testWorkspaceIDsMatchPinnedValues() {
        // The server derives the same ids with uuid_generate_v5 (R3); these values must never change.
        XCTAssertEqual(WorkspaceID.make(term: "pl", translation: "ru").uuidString.lowercased(),
                       "0db61f29-e285-5e06-84f5-d85acfa1b5cc")
        XCTAssertEqual(WorkspaceID.make(term: "de", translation: "ru").uuidString.lowercased(),
                       "f03536f4-02a8-515b-924f-f39a95de6a18")
        XCTAssertEqual(WorkspaceID.make(term: "uk", translation: "ru").uuidString.lowercased(),
                       "be15f3c7-76f8-503d-82ac-31a7b330772a")
        XCTAssertEqual(WorkspaceID.make(term: "en", translation: "pl").uuidString.lowercased(),
                       "ffaa32bf-2636-5dbd-8e6a-ff2987c0cf6f")
    }

    func testLegacyIsPolishRussian() {
        XCTAssertEqual(WorkspaceID.legacy, WorkspaceID.make(term: "pl", translation: "ru"))
        XCTAssertEqual(WorkspaceID.legacy.uuidString.lowercased(), "0db61f29-e285-5e06-84f5-d85acfa1b5cc")
    }

    func testDirectionMatters() {
        XCTAssertNotEqual(WorkspaceID.make(term: "pl", translation: "ru"),
                          WorkspaceID.make(term: "ru", translation: "pl"))
    }

    func testVersionAndVariantBits() {
        for name in ["pl>ru", "de>ru", "", "ключ"] {
            let id = UUID.v5(namespace: WorkspaceID.namespace, name: name)
            let text = id.uuidString
            let parts = text.split(separator: "-")
            XCTAssertEqual(parts[2].first, "5", "version 5 for \(name)")
            XCTAssertTrue(["8", "9", "A", "B"].contains(String(parts[3].first!)), "RFC 4122 variant for \(name)")
        }
    }

    func testSameInputGivesSameOutputAndRFCReferenceValue() {
        // RFC 4122 DNS namespace + "www.example.com" (reference value from the RFC family of tools).
        let dns = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
        XCTAssertEqual(UUID.v5(namespace: dns, name: "www.example.com").uuidString.lowercased(),
                       "2ed6657d-e927-568b-95e1-2665a8aea6a2")
        XCTAssertEqual(UUID.v5(namespace: dns, name: "a"), UUID.v5(namespace: dns, name: "a"))
    }
}
