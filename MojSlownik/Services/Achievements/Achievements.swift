import Foundation

/// A named integer statistic; the only vocabulary achievements speak.
enum AchievementMetric: String, CaseIterable, Codable {
    case wordCount, folderCount, categoriesCovered, learnedWords, masteredWords, maxIntervalDays
    case totalAnswers, correctAnswers, listeningCorrect, perfectQuizzes
    case currentStreakDays, longestStreakDays
}

/// Declaration order is display order.
enum AchievementCategory: String, CaseIterable {
    case vocabulary, practice, streak, mastery, feats

    var title: String {
        switch self {
        case .vocabulary: String(localized: "Dictionary")
        case .practice: String(localized: "Practice")
        case .streak: String(localized: "Consistency")
        case .mastery: String(localized: "Mastery")
        case .feats: String(localized: "Feats")
        }
    }
}

enum AchievementCriterion: Equatable {
    case threshold(AchievementMetric, Int)
    /// Meta achievement: unlocked when every listed achievement is unlocked.
    case allOf([String])
}

struct AchievementDefinition: Identifiable, Equatable {
    let id: String
    let category: AchievementCategory
    let title: String
    let detail: String
    let symbol: String
    let points: Int
    var isSecret: Bool = false
    let criterion: AchievementCriterion
}

struct AchievementMetrics: Equatable {
    private(set) var values: [AchievementMetric: Int]

    init(_ values: [AchievementMetric: Int] = [:]) {
        self.values = values
    }

    subscript(metric: AchievementMetric) -> Int { values[metric] ?? 0 }

    func merging(_ other: AchievementMetrics) -> AchievementMetrics {
        AchievementMetrics(values.merging(other.values) { _, new in new })
    }

    /// Metrics derived from current SwiftData records; retroactive and storage-free.
    static func vocabulary(words: [Word], folderCount: Int) -> AchievementMetrics {
        var categories = Set<WordCategory>()
        var learned = 0
        var mastered = 0
        var maxInterval = 0.0
        let words = words.filter(\.isActive)
        for word in words {
            if word.category != .other { categories.insert(word.category) }
            if word.repetitions >= 3 { learned += 1 }
            if KnowledgeProgressService.tier(for: word) == KnowledgeProgressService.maximumTier { mastered += 1 }
            maxInterval = max(maxInterval, word.intervalDays)
        }
        return AchievementMetrics([
            .wordCount: words.count,
            .folderCount: folderCount,
            .categoriesCovered: categories.count,
            .learnedWords: learned,
            .masteredWords: mastered,
            .maxIntervalDays: Int(maxInterval)
        ])
    }
}

struct AchievementProgress: Equatable {
    let current: Int
    let target: Int
    let isUnlocked: Bool
    let unlockedAt: Date?

    var fraction: Double { target == 0 ? 0 : min(1, Double(current) / Double(target)) }
}

enum AchievementCatalog {
    static let all: [AchievementDefinition] = [
        .init(id: "vocabulary.words.1", category: .vocabulary, title: String(localized: "First word"), detail: String(localized: "Add your first word"),
              symbol: "text.badge.plus", points: 5, criterion: .threshold(.wordCount, 1)),
        .init(id: "vocabulary.words.50", category: .vocabulary, title: String(localized: "Fifty"), detail: String(localized: "Collect 50 words"),
              symbol: "book", points: 10, criterion: .threshold(.wordCount, 50)),
        .init(id: "vocabulary.words.200", category: .vocabulary, title: String(localized: "Librarian"), detail: String(localized: "Collect 200 words"),
              symbol: "books.vertical", points: 25, criterion: .threshold(.wordCount, 200)),
        .init(id: "vocabulary.folders.3", category: .vocabulary, title: String(localized: "Organizer"), detail: String(localized: "Create 3 folders"),
              symbol: "folder", points: 10, criterion: .threshold(.folderCount, 3)),
        .init(id: "vocabulary.categories.all", category: .vocabulary, title: String(localized: "Scholar"),
              detail: String(localized: "Words in every topic except “Other”"), symbol: "square.grid.3x3", points: 15,
              criterion: .threshold(.categoriesCovered, WordCategory.allCases.count - 1)),
        .init(id: "practice.answers.100", category: .practice, title: String(localized: "A hundred answers"),
              detail: String(localized: "Give 100 answers in practice"), symbol: "checkmark.circle", points: 10,
              criterion: .threshold(.totalAnswers, 100)),
        .init(id: "practice.answers.500", category: .practice, title: String(localized: "Persistence"),
              detail: String(localized: "Give 500 answers in practice"), symbol: "checkmark.seal", points: 25,
              criterion: .threshold(.totalAnswers, 500)),
        .init(id: "practice.quiz.perfect", category: .practice, title: String(localized: "Flawless"),
              detail: String(localized: "Finish a quiz without a single mistake"), symbol: "trophy", points: 10,
              criterion: .threshold(.perfectQuizzes, 1)),
        .init(id: "practice.listening.50", category: .practice, title: String(localized: "Sharp ear"),
              detail: String(localized: "50 correct answers in “Listening”"), symbol: "ear", points: 15,
              criterion: .threshold(.listeningCorrect, 50)),
        .init(id: "streak.days.3", category: .streak, title: String(localized: "Three days in a row"),
              detail: String(localized: "Practice 3 days in a row"), symbol: "flame", points: 10,
              criterion: .threshold(.longestStreakDays, 3)),
        .init(id: "streak.days.7", category: .streak, title: String(localized: "Practice week"),
              detail: String(localized: "Practice 7 days in a row"), symbol: "medal", points: 25,
              criterion: .threshold(.longestStreakDays, 7)),
        .init(id: "mastery.learned.10", category: .mastery, title: String(localized: "Locked in"),
              detail: String(localized: "10 words repeated correctly 3 times in a row"), symbol: "brain", points: 10,
              criterion: .threshold(.learnedWords, 10)),
        .init(id: "mastery.tier.25", category: .mastery, title: String(localized: "Connoisseur"),
              detail: String(localized: "25 words at the highest knowledge level"), symbol: "star", points: 25,
              criterion: .threshold(.masteredWords, 25)),
        .init(id: "mastery.interval.30", category: .mastery, title: String(localized: "Long memory"),
              detail: String(localized: "A word with a review interval of 30 days or more"), symbol: "calendar.badge.clock", points: 20,
              criterion: .threshold(.maxIntervalDays, 30)),
        .init(id: "meta.polyglot", category: .feats, title: String(localized: "Polyglot"),
              detail: String(localized: "Earn “Librarian”, “Practice week”, “Connoisseur” and “Flawless”"),
              symbol: "crown", points: 25,
              criterion: .allOf(["vocabulary.words.200", "streak.days.7", "mastery.tier.25", "practice.quiz.perfect"]))
    ]

    static func definition(id: String) -> AchievementDefinition? {
        all.first { $0.id == id }
    }
}

enum AchievementEvaluator {
    static func newlyUnlocked(catalog: [AchievementDefinition], metrics: AchievementMetrics,
                              unlocked: Set<String>) -> [String] {
        var result: [String] = []
        var done = unlocked
        for definition in catalog where !done.contains(definition.id) {
            if case .threshold(let metric, let target) = definition.criterion, metrics[metric] >= target {
                result.append(definition.id)
                done.insert(definition.id)
            }
        }
        var changed = true
        while changed {
            changed = false
            for definition in catalog where !done.contains(definition.id) {
                guard case .allOf(let ids) = definition.criterion, !ids.isEmpty,
                      !ids.contains(definition.id),
                      ids.allSatisfy({ id in catalog.contains { $0.id == id } && done.contains(id) })
                else { continue }
                result.append(definition.id)
                done.insert(definition.id)
                changed = true
            }
        }
        return result
    }

    static func progress(for definition: AchievementDefinition, metrics: AchievementMetrics,
                         unlocked: [String: Date]) -> AchievementProgress {
        let unlockedAt = unlocked[definition.id]
        let isUnlocked = unlockedAt != nil
        switch definition.criterion {
        case .threshold(let metric, let target):
            return AchievementProgress(current: isUnlocked ? target : min(metrics[metric], target),
                                       target: target, isUnlocked: isUnlocked, unlockedAt: unlockedAt)
        case .allOf(let ids):
            let count = ids.filter { unlocked[$0] != nil }.count
            return AchievementProgress(current: isUnlocked ? ids.count : count, target: ids.count,
                                       isUnlocked: isUnlocked, unlockedAt: unlockedAt)
        }
    }
}
