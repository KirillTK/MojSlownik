import XCTest
@testable import MojSlownik

final class ListeningQuestionTests: XCTestCase {
    func testLastReviewGradeSelectsAdaptiveMode() {
        let word = makeWord("dom", "dom")
        word.lastReviewGradeRawValue = ReviewGrade.again.rawValue
        XCTAssertEqual(ListeningQuestion.mode(for: word), .choices)

        word.lastReviewGradeRawValue = ReviewGrade.hard.rawValue
        XCTAssertEqual(ListeningQuestion.mode(for: word), .choices)

        word.lastReviewGradeRawValue = ReviewGrade.good.rawValue
        XCTAssertEqual(ListeningQuestion.mode(for: word), .translation)

        word.lastReviewGradeRawValue = ReviewGrade.easy.rawValue
        XCTAssertEqual(ListeningQuestion.mode(for: word), .dictation)
    }

    func testConfidenceTierSelectsListeningFormatAcrossAllLevels() {
        let word = makeWord("дом", "dom")
        for tier in 0...1 {
            word.knowledgeTier = tier
            XCTAssertEqual(ListeningQuestion.mode(for: word), .choices)
        }
        word.knowledgeTier = 2
        XCTAssertEqual(ListeningQuestion.mode(for: word), .translation)
        word.knowledgeTier = 3
        XCTAssertEqual(ListeningQuestion.mode(for: word), .dictation)
    }

    func testLegacyWordsUseTheirExistingSRSState() {
        let newWord = makeWord("дом", "dom")
        XCTAssertEqual(ListeningQuestion.mode(for: newWord), .choices)

        let hardWord = makeWord("дом", "dom")
        hardWord.repetitions = 1
        hardWord.easeFactor = 2.35
        XCTAssertEqual(ListeningQuestion.mode(for: hardWord), .choices)

        let goodWord = makeWord("дом", "dom")
        goodWord.repetitions = 2
        XCTAssertEqual(ListeningQuestion.mode(for: goodWord), .translation)

        let easyWord = makeWord("дом", "dom")
        easyWord.repetitions = 1
        easyWord.easeFactor = 2.65
        XCTAssertEqual(ListeningQuestion.mode(for: easyWord), .dictation)
    }

    func testChoiceQuestionHasFourDistinctPolishAnswers() {
        let words = ["dom", "kot", "pies", "woda"].map { makeWord("слово", $0) }
        let question = ListeningQuestion.question(for: words[0], among: words)

        XCTAssertEqual(question.mode, .choices)
        XCTAssertEqual(question.options.count, 4)
        XCTAssertEqual(Set(question.options.map { $0.lowercased() }).count, 4)
        XCTAssertTrue(question.options.contains("dom"))
        XCTAssertEqual(question.prompt, "dom")
    }

    func testDuplicateOrInsufficientSpellingsFallBackToTyping() {
        let duplicateWords = [makeWord("один", "dom"), makeWord("два", "dom"), makeWord("три", "kot")]
        let question = ListeningQuestion.question(for: duplicateWords[0], among: duplicateWords)

        XCTAssertEqual(question.mode, .translation)
        XCTAssertTrue(question.options.isEmpty)
        XCTAssertEqual(question.prompt, "один")
    }

    func testSpellingMatchesIgnoreCaseWhitespaceAndCanonicalCompositionButNotDiacritics() {
        XCTAssertTrue(ListeningQuestion.matches("  ŁÓDŹ\n", correctAnswer: "łódź"))
        XCTAssertTrue(ListeningQuestion.matches("z\u{0307}ółć", correctAnswer: "żółć"))
        XCTAssertFalse(ListeningQuestion.matches("lodz", correctAnswer: "łódź"))
    }

    func testSchedulerStoresTheLatestCardGrade() {
        let word = makeWord("дом", "dom")
        SRSEngine.apply(.easy, to: word)
        XCTAssertEqual(word.lastReviewGradeRawValue, ReviewGrade.easy.rawValue)

        SRSEngine.apply(.hard, to: word)
        XCTAssertEqual(word.lastReviewGradeRawValue, ReviewGrade.hard.rawValue)
    }

    private func makeWord(_ russian: String, _ polish: String) -> Word {
        Word(russian: russian, polish: polish, side: .term)
    }

    func testQuestionsUseTheStudiedSideForAnyPair() {
        let german = LanguagePair(term: .german, translation: .russian)
        let words = ["Haus": "дом", "Auto": "машина", "Brot": "хлеб", "Buch": "книга"].map { term, translation in
            Word(entry: WordEntry(term: term, translation: translation, enteredSide: .translation),
                 pair: german, workspaceID: nil)
        }
        let word = words[0]
        word.knowledgeTier = 2
        let translationQuestion = ListeningQuestion.question(for: word, among: words)
        XCTAssertEqual(translationQuestion.mode, .translation)
        XCTAssertEqual(translationQuestion.prompt, word.translation)
        XCTAssertEqual(translationQuestion.correctAnswer, word.term)

        word.knowledgeTier = 0
        let choices = ListeningQuestion.question(for: word, among: words)
        XCTAssertEqual(choices.mode, .choices)
        XCTAssertEqual(Set(choices.options), Set(words.map(\.term)))
    }
}
