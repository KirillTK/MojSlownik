import XCTest
@testable import MojSlownik

final class ScannedTextTokenizerTests: XCTestCase {
    func testTokensPreservePunctuationAndOriginalSpacing() {
        XCTAssertEqual(ScannedTextTokenizer.tokens(in: "Gdzie woda?\nTu, tak."), [
            .word("Gdzie"), .text(" "), .word("woda"), .text("?\n"),
            .word("Tu"), .text(", "), .word("tak"), .text(".")
        ])
    }

    func testSelectableWordsKeepRepeatedWordsAndDiacriticsButExcludeSingleCharacters() {
        XCTAssertEqual(ScannedTextTokenizer.words(in: "i woda, woda — dziękuję!"), ["woda", "woda", "dziękuję"])
    }

    func testHyphenAndApostropheStayInsideWords() {
        XCTAssertEqual(ScannedTextTokenizer.words(in: "biało-czerwony O'Brien"), ["biało-czerwony", "O'Brien"])
        XCTAssertTrue(ScannedTextTokenizer.words(in: "").isEmpty)
    }
}
