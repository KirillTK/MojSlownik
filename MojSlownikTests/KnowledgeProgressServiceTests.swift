import XCTest
@testable import MojSlownik

final class KnowledgeProgressServiceTests: XCTestCase {
    func testTypedExactAnswerRaisesTierAndClearsSoftMisses() {
        let word = makeWord(tier: 2, softMisses: 1)

        let result = KnowledgeProgressService.apply(.typed(expected: "łódź", submitted: " ŁÓDŹ "), to: word)

        XCTAssertTrue(result.isCorrect)
        XCTAssertEqual(result.tier, 3)
        XCTAssertEqual(word.consecutiveSoftMisses, 0)
    }

    func testSeventyPercentNearMissDropsTierOnlyAfterTwoConsecutiveMisses() {
        let word = makeWord(tier: 3)
        let expected = "abcdefghij"
        let seventyPercentMatch = "abcdeXgXYj"

        let first = KnowledgeProgressService.apply(.typed(expected: expected, submitted: seventyPercentMatch), to: word)
        XCTAssertEqual(first.similarity ?? -1, 0.7, accuracy: 0.0001)
        XCTAssertEqual(first.tier, 3)
        XCTAssertEqual(word.consecutiveSoftMisses, 1)

        let second = KnowledgeProgressService.apply(.typed(expected: expected, submitted: seventyPercentMatch), to: word)
        XCTAssertEqual(second.tier, 2)
        XCTAssertEqual(word.consecutiveSoftMisses, 0)
    }

    func testBelowSeventyPercentDropsTierImmediately() {
        let word = makeWord(tier: 3)

        let result = KnowledgeProgressService.apply(.typed(expected: "abcdefghij", submitted: "abcdXXXXXX"), to: word)

        XCTAssertEqual(result.similarity ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(result.tier, 2)
        XCTAssertEqual(word.consecutiveSoftMisses, 0)
    }

    func testCorrectTypedAnswerClearsSoftMissStreak() {
        let word = makeWord(tier: 3, softMisses: 1)

        _ = KnowledgeProgressService.apply(.typed(expected: "woda", submitted: "woda"), to: word)

        XCTAssertEqual(word.consecutiveSoftMisses, 0)
        XCTAssertEqual(word.knowledgeTier, 3)
    }

    func testChoiceAnswersMoveOneTierAndStayWithinBounds() {
        let word = makeWord(tier: 0)
        XCTAssertEqual(KnowledgeProgressService.apply(.choice(isCorrect: false), to: word).tier, 0)
        XCTAssertEqual(KnowledgeProgressService.apply(.choice(isCorrect: true), to: word).tier, 1)
        word.knowledgeTier = 3
        XCTAssertEqual(KnowledgeProgressService.apply(.choice(isCorrect: true), to: word).tier, 3)
        XCTAssertEqual(KnowledgeProgressService.apply(.choice(isCorrect: false), to: word).tier, 2)
    }

    func testFlashcardGradeSetsTierDirectlyAndResetsSoftMisses() {
        let word = makeWord(tier: 3, softMisses: 1)

        KnowledgeProgressService.setTier(from: .hard, on: word)

        XCTAssertEqual(word.knowledgeTier, 1)
        XCTAssertEqual(word.consecutiveSoftMisses, 0)
    }

    func testLegacyWordsDeriveTierFromSavedGradeOrExistingSRS() {
        let easyWord = makeWord(tier: nil)
        easyWord.lastReviewGradeRawValue = ReviewGrade.easy.rawValue
        XCTAssertEqual(KnowledgeProgressService.tier(for: easyWord), 3)

        let reviewedWord = makeWord(tier: nil)
        reviewedWord.repetitions = 2
        XCTAssertEqual(KnowledgeProgressService.tier(for: reviewedWord), 2)

        XCTAssertEqual(KnowledgeProgressService.tier(for: makeWord(tier: nil)), 0)
    }

    func testSimilarityNormalizesCaseWhitespaceAndUnicodeButKeepsDiacriticsMeaningful() {
        XCTAssertEqual(KnowledgeProgressService.similarity(expected: " ŁÓDŹ ", submitted: "łódź"), 1)
        XCTAssertEqual(KnowledgeProgressService.similarity(expected: "żółć", submitted: "z\u{0307}ółć"), 1)
        XCTAssertLessThan(KnowledgeProgressService.similarity(expected: "łódź", submitted: "lodz"), 0.7)
        XCTAssertEqual(KnowledgeProgressService.similarity(expected: "", submitted: ""), 0)
        XCTAssertEqual(KnowledgeProgressService.similarity(expected: "woda", submitted: ""), 0)
    }

    private func makeWord(tier: Int?, softMisses: Int = 0) -> Word {
        let word = Word(russian: "вода", polish: "woda", side: .term)
        word.knowledgeTier = tier
        word.consecutiveSoftMisses = softMisses
        return word
    }
}
