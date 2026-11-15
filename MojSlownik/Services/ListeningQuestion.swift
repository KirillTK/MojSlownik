import Foundation
import SwiftData

enum ListeningAnswerMode: Equatable {
    case choices
    case translation
    case dictation
}

struct ListeningQuestion {
    let wordID: PersistentIdentifier
    let mode: ListeningAnswerMode
    let prompt: String
    let correctAnswer: String
    let options: [String]

    static func generate(from words: [Word], count: Int) -> [ListeningQuestion] {
        words.shuffled().prefix(count).map { question(for: $0, among: words) }
    }

    static func question(for word: Word, among words: [Word]) -> ListeningQuestion {
        var mode = mode(for: word)
        var options: [String] = []
        if mode == .choices {
            options = ([word.polish] + distractors(for: word, among: words)).shuffled()
            if options.count < 4 { mode = .translation }
        }

        return ListeningQuestion(
            wordID: word.persistentModelID,
            mode: mode,
            prompt: mode == .translation ? word.russian : word.polish,
            correctAnswer: word.polish,
            options: mode == .choices ? options : []
        )
    }

    static func mode(for word: Word) -> ListeningAnswerMode {
        if let rawValue = word.lastReviewGradeRawValue,
           let grade = ReviewGrade(rawValue: rawValue) {
            switch grade {
            case .again, .hard: return .choices
            case .good: return .translation
            case .easy: return .dictation
            }
        }

        if word.repetitions == 0 || word.easeFactor < 2.5 { return .choices }
        return word.easeFactor > 2.5 ? .dictation : .translation
    }

    static func matches(_ answer: String, correctAnswer: String) -> Bool {
        normalize(answer) == normalize(correctAnswer)
    }

    private static func distractors(for word: Word, among words: [Word]) -> [String] {
        let correct = normalize(word.polish)
        var seen: Set<String> = [correct]
        return words.shuffled().compactMap { candidate in
            let answer = candidate.polish
            guard candidate.persistentModelID != word.persistentModelID,
                  seen.insert(normalize(answer)).inserted else { return nil }
            return answer
        }.prefix(3).map { $0 }
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}
