import XCTest
@testable import MojSlownik

final class KnowledgeTierBadgeTests: XCTestCase {
    func testEachTierHasDistinctVisualMarksColorAndAccessibleName() {
        let presentations = (0...3).map(KnowledgeTierBadge.presentation(for:))

        XCTAssertEqual(presentations.map(\.filledMarks), [1, 2, 3, 4])
        XCTAssertEqual(presentations.map(\.levelName), ["Again", "Hard", "Good", "Easy"])
        XCTAssertEqual(presentations.map(\.color), [.error, .warning, .accent, .mastery])
    }

    func testRingFillFractionGrowsWithTier() {
        XCTAssertEqual((0...3).map { KnowledgeTierBadge.presentation(for: $0).fillFraction }, [0.25, 0.5, 0.75, 1.0])
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: -1).fillFraction, 0.25)
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: 9).fillFraction, 1.0)
    }

    func testPresentationClampsOutOfRangeLevels() {
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: -1), KnowledgeTierBadge.presentation(for: 0))
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: 4), KnowledgeTierBadge.presentation(for: 3))
    }

    func testAccessibleDescriptionNamesWordAndTierUnlessItWouldRevealListeningAnswer() {
        let word = Word(russian: "город", polish: "miasto", side: .term)

        XCTAssertEqual(KnowledgeTierBadge.accessibilityDescription(for: word, level: 2),
                       "Knowledge level of the word miasto: Good")
        XCTAssertEqual(KnowledgeTierBadge.accessibilityDescription(for: word, level: 2, hidesWord: true),
                       "Knowledge level: Good")
    }

    func testLegacyWordTierUsesSharedKnowledgeResolver() {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.lastReviewGradeRawValue = ReviewGrade.easy.rawValue

        XCTAssertEqual(KnowledgeProgressService.tier(for: word), 3)
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: KnowledgeProgressService.tier(for: word)).levelName,
                       "Easy")
    }
}
