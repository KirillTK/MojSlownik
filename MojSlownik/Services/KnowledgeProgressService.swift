import Foundation

enum KnowledgeAnswer {
    case choice(isCorrect: Bool)
    case typed(expected: String, submitted: String)
}

enum KnowledgeProgressService {
    static let minimumTier = 0
    static let maximumTier = 3
    static let softMatchThreshold = 0.7
    static let softMissesBeforeDrop = 2

    struct Assessment: Equatable {
        let isCorrect: Bool
        let similarity: Double?
        let tier: Int
        let tierChanged: Bool
    }

    static func tier(for word: Word) -> Int {
        if let tier = word.knowledgeTier { return clamped(tier) }
        if let rawValue = word.lastReviewGradeRawValue, let grade = ReviewGrade(rawValue: rawValue) {
            return tier(for: grade)
        }
        if word.repetitions == 0 || word.easeFactor < 2.5 { return 0 }
        return word.easeFactor > 2.5 ? 3 : 2
    }

    @discardableResult
    static func apply(_ answer: KnowledgeAnswer, to word: Word) -> Assessment {
        let previousTier = tier(for: word)
        word.knowledgeTier = previousTier

        switch answer {
        case .choice(let isCorrect):
            word.consecutiveSoftMisses = 0
            let newTier = bounded(previousTier + (isCorrect ? 1 : -1))
            word.knowledgeTier = newTier
            return Assessment(isCorrect: isCorrect, similarity: nil, tier: newTier,
                             tierChanged: newTier != previousTier)

        case .typed(let expected, let submitted):
            let score = similarity(expected: expected, submitted: submitted)
            if score == 1 {
                word.consecutiveSoftMisses = 0
                let newTier = bounded(previousTier + 1)
                word.knowledgeTier = newTier
                return Assessment(isCorrect: true, similarity: score, tier: newTier,
                                 tierChanged: newTier != previousTier)
            }

            var newTier = previousTier
            if score >= softMatchThreshold {
                word.consecutiveSoftMisses += 1
                if word.consecutiveSoftMisses >= softMissesBeforeDrop {
                    newTier = bounded(previousTier - 1)
                    word.consecutiveSoftMisses = 0
                }
            } else {
                newTier = bounded(previousTier - 1)
                word.consecutiveSoftMisses = 0
            }
            word.knowledgeTier = newTier
            return Assessment(isCorrect: false, similarity: score, tier: newTier,
                             tierChanged: newTier != previousTier)
        }
    }

    static func isCorrect(_ answer: KnowledgeAnswer) -> Bool {
        return switch answer {
        case .choice(let isCorrect): isCorrect
        case .typed(let expected, let submitted):
            similarity(expected: expected, submitted: submitted) == 1
        }
    }

    static func setTier(from grade: ReviewGrade, on word: Word) {
        word.knowledgeTier = tier(for: grade)
        word.consecutiveSoftMisses = 0
    }

    private static func tier(for grade: ReviewGrade) -> Int {
        return switch grade {
        case .again: 0
        case .hard: 1
        case .good: 2
        case .easy: 3
        }
    }

    static func similarity(expected: String, submitted: String) -> Double {
        let expectedCharacters = normalized(expected).map(String.init)
        let submittedCharacters = normalized(submitted).map(String.init)
        let denominator = max(expectedCharacters.count, submittedCharacters.count)
        guard !expectedCharacters.isEmpty, denominator > 0 else { return 0 }

        var previous = Array(0...submittedCharacters.count)
        for (expectedIndex, expectedCharacter) in expectedCharacters.enumerated() {
            var current = Array(repeating: 0, count: submittedCharacters.count + 1)
            current[0] = expectedIndex + 1
            for (submittedIndex, submittedCharacter) in submittedCharacters.enumerated() {
                let substitutionCost = expectedCharacter == submittedCharacter ? 0 : 1
                current[submittedIndex + 1] = min(
                    min(previous[submittedIndex + 1] + 1, current[submittedIndex] + 1),
                    previous[submittedIndex] + substitutionCost
                )
            }
            previous = current
        }
        return 1 - Double(previous[submittedCharacters.count]) / Double(denominator)
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    private static func clamped(_ tier: Int) -> Int {
        min(max(tier, minimumTier), maximumTier)
    }

    private static func bounded(_ tier: Int) -> Int {
        min(max(tier, minimumTier), maximumTier)
    }
}
