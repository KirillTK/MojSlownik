import XCTest
@testable import MojSlownik

final class FolderTrainingTests: XCTestCase {
    @MainActor
    func testQuizPromptsAndDistractorsStayInsideSelectedFolder() {
        let folderID = UUID()
        let pairs = [("вода", "woda"), ("хлеб", "chleb"), ("чай", "herbata"), ("кофе", "kawa")]
        let members = pairs.map { russian, polish in
            let word = Word(russian: russian, polish: polish, sourceLanguage: .polish)
            word.folderIDs = [folderID]
            return word
        }
        let outsider = Word(russian: "поезд", polish: "pociąg", sourceLanguage: .polish)
        let scoped = FolderStore.words(members + [outsider], in: folderID)
        let questions = QuizQuestion.generate(from: scoped, count: 10)
        XCTAssertEqual(questions.count, 4)
        for question in questions {
            XCTAssertTrue(members.map { $0.text(in: question.promptLanguage) }.contains(question.prompt))
            let allowedAnswers = Set(members.map { $0.text(in: question.promptLanguage.other) })
            XCTAssertTrue(Set(question.options).isSubset(of: allowedAnswers))
            XCTAssertTrue(question.options.contains(question.correctAnswer))
        }
        XCTAssertTrue(QuizQuestion.generate(from: FolderStore.words(members, in: UUID()), count: 10).isEmpty)
    }
}
