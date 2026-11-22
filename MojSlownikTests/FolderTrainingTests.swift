import XCTest
@testable import MojSlownik

final class FolderTrainingTests: XCTestCase {
    @MainActor
    func testQuizPromptsAndDistractorsStayInsideSelectedFolder() {
        let folderID = UUID()
        let pairs = [("вода", "woda"), ("хлеб", "chleb"), ("чай", "herbata"), ("кофе", "kawa")]
        let members = pairs.map { russian, polish in
            let word = Word(russian: russian, polish: polish, side: .term)
            return word
        }
        let outsider = Word(russian: "поезд", polish: "pociąg", side: .term)
        let index = MembershipIndex.linking(members, to: folderID)
        let scoped = FolderStore.words(members + [outsider], in: folderID, memberships: index)
        let questions = QuizQuestion.generate(from: scoped, count: 10)
        XCTAssertEqual(questions.count, 4)
        for question in questions {
            let sourceWord = members.first { $0.persistentModelID == question.wordID }
            XCTAssertNotNil(sourceWord)
            XCTAssertEqual(sourceWord?.text(on: question.promptSide), question.prompt)
            XCTAssertEqual(sourceWord?.text(on: question.promptSide.other), question.correctAnswer)
            XCTAssertTrue(members.map { $0.text(on: question.promptSide) }.contains(question.prompt))
            let allowedAnswers = Set(members.map { $0.text(on: question.promptSide.other) })
            XCTAssertTrue(Set(question.options).isSubset(of: allowedAnswers))
            XCTAssertTrue(question.options.contains(question.correctAnswer))
        }
        XCTAssertTrue(QuizQuestion.generate(from: FolderStore.words(members, in: UUID(), memberships: index), count: 10).isEmpty)
    }
}
