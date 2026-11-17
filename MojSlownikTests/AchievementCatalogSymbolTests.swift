import XCTest
@testable import MojSlownik

final class AchievementCatalogSymbolTests: XCTestCase {
    func testCatalogSymbolsAreOutlineNames() {
        for definition in AchievementCatalog.all {
            XCTAssertFalse(definition.symbol.hasSuffix(".fill"), "\(definition.id) uses \(definition.symbol)")
        }
    }

    func testCatalogSymbolsAreUnique() {
        let symbols = AchievementCatalog.all.map(\.symbol)
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }
}
