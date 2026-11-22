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

    func testJoiningLineBreakHyphenationJoinsPolishAndRussianLetters() {
        XCTAssertEqual(
            ScannedTextTokenizer.joiningLineBreakHyphenation(in: "przy-\nkład и пе-\nренос"),
            "przykład и перенос"
        )
    }

    func testJoiningLineBreakHyphenationSupportsSoftHyphenAndCRLF() {
        XCTAssertEqual(
            ScannedTextTokenizer.joiningLineBreakHyphenation(in: "sło\u{00AD}\r\nwo"),
            "słowo"
        )
    }

    func testJoiningLineBreakHyphenationPreservesCompoundsDashesAndNonmatchingText() {
        XCTAssertEqual(
            ScannedTextTokenizer.joiningLineBreakHyphenation(in: "biało-czerwony oraz pół–\nnoc i pół—\nnoc"),
            "biało-czerwony oraz pół–\nnoc i pół—\nnoc"
        )
        XCTAssertEqual(
            ScannedTextTokenizer.joiningLineBreakHyphenation(in: "koniec-\n  nowy\n-\nstart"),
            "koniec-\n  nowy\n-\nstart"
        )
    }

    func testNearbyLinesGroupWhileSeparateColumnsAndParagraphsStayApart() {
        let lines = [
            line("000000000001", "first line", CGRect(x: 10, y: 10, width: 70, height: 12)),
            line("000000000002", "second line", CGRect(x: 10, y: 25, width: 55, height: 12)),
            line("000000000003", "other column", CGRect(x: 180, y: 10, width: 70, height: 12)),
            line("000000000004", "next paragraph", CGRect(x: 10, y: 65, width: 80, height: 12))
        ]

        let blocks = ScannedTextBlockBuilder.build(from: lines)

        XCTAssertEqual(blocks.map(\.text), ["first line\nsecond line", "other column", "next paragraph"])
        XCTAssertEqual(blocks[0].lines.count, 2)
    }

    func testLongContinuousTextIsSplitIntoSelectableBlocks() {
        let lines = (0..<8).map { index in
            line(String(format: "%012d", index + 100), "line \(index)",
                 CGRect(x: 12, y: CGFloat(index) * 14, width: 90, height: 12))
        }

        let blocks = ScannedTextBlockBuilder.build(from: lines)

        XCTAssertEqual(blocks.map(\.lines.count), [3, 3, 2])
        XCTAssertTrue(blocks.allSatisfy { $0.lines.count <= 3 })
    }

    func testBlockIDsRemainStableWhenFrozenItemsReorder() {
        let first = line("000000000011", "first", CGRect(x: 10, y: 10, width: 60, height: 12))
        let second = line("000000000012", "second", CGRect(x: 10, y: 25, width: 60, height: 12))

        let initial = ScannedTextBlockBuilder.build(from: [first, second])
        let recomputed = ScannedTextBlockBuilder.build(from: [second, first])

        XCTAssertEqual(initial.map(\.id), recomputed.map(\.id))
        XCTAssertEqual(initial.first?.id, "00000000-0000-0000-0000-000000000011:00000000-0000-0000-0000-000000000012")
        let selected = Set([initial[0].id])
        XCTAssertEqual(ScannedTextBlockBuilder.selectedText(from: recomputed, IDs: selected), "first\nsecond")
    }

    func testTogglingBlocksBuildsReadingOrderAndPreservesRepeatedTranscripts() {
        let first = line("000000000021", "Same", CGRect(x: 10, y: 10, width: 40, height: 12))
        let far = line("000000000022", "Same", CGRect(x: 180, y: 10, width: 40, height: 12))
        let blocks = ScannedTextBlockBuilder.build(from: [far, first])
        XCTAssertEqual(blocks.count, 2)

        var selection = Set<String>()
        selection = ScannedTextBlockBuilder.toggled(blocks[0].id, in: selection)
        selection = ScannedTextBlockBuilder.toggled(blocks[1].id, in: selection)
        XCTAssertEqual(ScannedTextBlockBuilder.selectedText(from: blocks, IDs: selection), "Same\nSame")
        selection = ScannedTextBlockBuilder.toggled(blocks[0].id, in: selection)
        XCTAssertEqual(ScannedTextBlockBuilder.selectedText(from: blocks, IDs: selection), "Same")
    }

    func testVisionBoundsMapThroughAspectFillCropIntoViewportCoordinates() {
        let normalized = CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.25)
        let mapped = ScannedImageTextRecognizer.aspectFillRect(
            normalized, imageSize: CGSize(width: 400, height: 300), viewportSize: CGSize(width: 300, height: 600)
        )

        XCTAssertEqual(mapped.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(mapped.origin.y, 150, accuracy: 0.001)
        XCTAssertEqual(mapped.width, 150, accuracy: 0.001)
        XCTAssertEqual(mapped.height, 150, accuracy: 0.001)

        let croppedOut = ScannedImageTextRecognizer.aspectFillRect(
            CGRect(x: 0, y: 0.5, width: 0.1, height: 0.1),
            imageSize: CGSize(width: 400, height: 300), viewportSize: CGSize(width: 300, height: 600)
        )
        XCTAssertTrue(croppedOut.isNull)
    }

    private func line(_ suffix: String, _ text: String, _ bounds: CGRect) -> ScannedTextLine {
        ScannedTextLine(id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!, text: text, bounds: bounds)
    }

    func testOCRLanguagesFollowThePairWithoutRepeats() {
        XCTAssertEqual(ScannedImageTextRecognizer.ocrLanguages(for: .polishRussian), ["pl-PL", "ru-RU"])
        XCTAssertEqual(ScannedImageTextRecognizer.ocrLanguages(for: LanguagePair(term: .german, translation: .ukrainian)),
                       ["de-DE", "uk-UA"])
        let same = LanguagePair(term: Language.polish, translation: Language.polish)
        XCTAssertEqual(ScannedImageTextRecognizer.ocrLanguages(for: same), ["pl-PL"])
    }

    func testRecognitionLanguagesAreFilteredBySupportAndMayBeEmpty() {
        XCTAssertEqual(ScannedImageTextRecognizer.recognitionLanguages(wanted: ["pl-PL", "ru-RU"],
                                                                       supported: ["ru-RU", "en-US"]), ["ru-RU"])
        XCTAssertTrue(ScannedImageTextRecognizer.recognitionLanguages(wanted: ["cs-CZ"], supported: ["en-US"]).isEmpty)
        XCTAssertEqual(ScannedImageTextRecognizer.dataScannerLanguages(wanted: ["pt-BR", "uk-UA"],
                                                                       supported: ["pt-PT", "en-US"]), ["pt-BR"])
    }
}
