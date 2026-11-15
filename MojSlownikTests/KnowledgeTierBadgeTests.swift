import XCTest
@testable import MojSlownik

final class KnowledgeTierBadgeTests: XCTestCase {
    func testEachTierHasDistinctVisualMarksColorAndAccessibleName() {
        let presentations = (0...3).map(KnowledgeTierBadge.presentation(for:))

        XCTAssertEqual(presentations.map(\.filledMarks), [1, 2, 3, 4])
        XCTAssertEqual(presentations.map(\.levelName), ["Не помню", "Трудно", "Хорошо", "Легко"])
        XCTAssertEqual(presentations.map(\.color), [.error, .warning, .accent, .mastery])
    }

    func testPresentationClampsOutOfRangeLevels() {
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: -1), KnowledgeTierBadge.presentation(for: 0))
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: 4), KnowledgeTierBadge.presentation(for: 3))
    }

    func testAccessibleDescriptionNamesWordAndTierUnlessItWouldRevealListeningAnswer() {
        let word = Word(russian: "город", polish: "miasto", sourceLanguage: .polish)

        XCTAssertEqual(KnowledgeTierBadge.accessibilityDescription(for: word, level: 2),
                       "Уровень знания слова miasto: Хорошо")
        XCTAssertEqual(KnowledgeTierBadge.accessibilityDescription(for: word, level: 2, hidesWord: true),
                       "Уровень знания: Хорошо")
    }

    func testLegacyWordTierUsesSharedKnowledgeResolver() {
        let word = Word(russian: "вода", polish: "woda", sourceLanguage: .polish)
        word.lastReviewGradeRawValue = ReviewGrade.easy.rawValue

        XCTAssertEqual(KnowledgeProgressService.tier(for: word), 3)
        XCTAssertEqual(KnowledgeTierBadge.presentation(for: KnowledgeProgressService.tier(for: word)).levelName,
                       "Легко")
    }
}
