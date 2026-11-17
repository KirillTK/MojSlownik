import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class FolderRepositoryContractTests: XCTestCase {
    func testSwiftDataRepositoryHonoursContract() throws {
        let container = try ModelContainer(for: Word.self, WordFolder.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try runContract(make: { SwiftDataFolderRepository(container: container) },
                        persistedNames: { try FolderStore.folders(in: ModelContext(container)).map(\.name) })
    }

    func testInMemoryFakeHonoursContract() throws {
        try runContract(make: { InMemoryFolderRepository() }, persistedNames: nil)
    }

    private func runContract(make: () -> any FolderRepository,
                             persistedNames: (() throws -> [String])?) throws {
        let repo = make()
        let a = try repo.createFolder(name: "  Урок \n 1 ")
        let b = try repo.createFolder(name: "GÓRA")
        XCTAssertEqual(try repo.folders(), [FolderRecord(id: a, name: "Урок 1"), FolderRecord(id: b, name: "GÓRA")])
        if let persistedNames { XCTAssertEqual(try persistedNames(), ["Урок 1", "GÓRA"]) }

        assertStoreError(.emptyName) { _ = try repo.createFolder(name: " \n ") }
        assertStoreError(.duplicateName) { _ = try repo.createFolder(name: "урок 1") }
        assertStoreError(.duplicateName) { _ = try repo.createFolder(name: "góra".decomposedStringWithCanonicalMapping) }
        XCTAssertEqual(try repo.folders().count, 2)

        try repo.renameFolder(id: a, name: "Первый")
        assertStoreError(.duplicateName) { try repo.renameFolder(id: a, name: "gÓra") }
        XCTAssertEqual(try repo.folders().map(\.name), ["Первый", "GÓRA"])

        try repo.reorderFolders(ids: [b, a])
        XCTAssertEqual(try repo.folders().map(\.id), [b, a])
        assertStoreError(.invalidOrder) { try repo.reorderFolders(ids: [a]) }
        assertStoreError(.invalidOrder) { try repo.reorderFolders(ids: [a, a]) }
        XCTAssertEqual(try repo.folders().map(\.id), [b, a])
        if let persistedNames { XCTAssertEqual(try persistedNames(), ["GÓRA", "Первый"]) }

        try repo.deleteFolder(id: a)
        XCTAssertEqual(try repo.folders().map(\.id), [b])
        assertStoreError(.missingFolder) { try repo.renameFolder(id: a, name: "Нет") }
        let recreated = try repo.createFolder(name: "Первый")
        XCTAssertNotEqual(recreated, a)
        XCTAssertEqual(try repo.folders().map(\.name), ["GÓRA", "Первый"])
        if let persistedNames { XCTAssertEqual(try persistedNames(), ["GÓRA", "Первый"]) }
    }

    private func assertStoreError(_ expected: FolderStore.StoreError, file: StaticString = #filePath,
                                  line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription, file: file, line: line)
        }
    }
}
