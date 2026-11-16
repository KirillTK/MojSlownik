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
        case .vocabulary: "Словарь"
        case .practice: "Практика"
        case .streak: "Постоянство"
        case .mastery: "Мастерство"
        case .feats: "Подвиги"
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
        .init(id: "vocabulary.words.1", category: .vocabulary, title: "Первое слово", detail: "Добавьте первое слово",
              symbol: "text.badge.plus", points: 5, criterion: .threshold(.wordCount, 1)),
        .init(id: "vocabulary.words.50", category: .vocabulary, title: "Полсотни", detail: "Соберите 50 слов",
              symbol: "books.vertical", points: 10, criterion: .threshold(.wordCount, 50)),
        .init(id: "vocabulary.words.200", category: .vocabulary, title: "Библиотекарь", detail: "Соберите 200 слов",
              symbol: "books.vertical.fill", points: 25, criterion: .threshold(.wordCount, 200)),
        .init(id: "vocabulary.folders.3", category: .vocabulary, title: "Организатор", detail: "Создайте 3 папки",
              symbol: "folder.fill", points: 10, criterion: .threshold(.folderCount, 3)),
        .init(id: "vocabulary.categories.all", category: .vocabulary, title: "Эрудит",
              detail: "Слова во всех темах, кроме «Другое»", symbol: "square.grid.3x3.fill", points: 15,
              criterion: .threshold(.categoriesCovered, WordCategory.allCases.count - 1)),
        .init(id: "practice.answers.100", category: .practice, title: "Сотня ответов",
              detail: "Дайте 100 ответов в практике", symbol: "checkmark.circle", points: 10,
              criterion: .threshold(.totalAnswers, 100)),
        .init(id: "practice.answers.500", category: .practice, title: "Упорство",
              detail: "Дайте 500 ответов в практике", symbol: "checkmark.seal.fill", points: 25,
              criterion: .threshold(.totalAnswers, 500)),
        .init(id: "practice.quiz.perfect", category: .practice, title: "Без ошибок",
              detail: "Пройдите викторину без единой ошибки", symbol: "trophy.fill", points: 10,
              criterion: .threshold(.perfectQuizzes, 1)),
        .init(id: "practice.listening.50", category: .practice, title: "Острый слух",
              detail: "50 верных ответов «На слух»", symbol: "ear.fill", points: 15,
              criterion: .threshold(.listeningCorrect, 50)),
        .init(id: "streak.days.3", category: .streak, title: "Три дня подряд",
              detail: "Занимайтесь 3 дня подряд", symbol: "flame", points: 10,
              criterion: .threshold(.longestStreakDays, 3)),
        .init(id: "streak.days.7", category: .streak, title: "Неделя практики",
              detail: "Занимайтесь 7 дней подряд", symbol: "flame.fill", points: 25,
              criterion: .threshold(.longestStreakDays, 7)),
        .init(id: "mastery.learned.10", category: .mastery, title: "Закреплено",
              detail: "10 слов повторены 3 раза подряд", symbol: "brain", points: 10,
              criterion: .threshold(.learnedWords, 10)),
        .init(id: "mastery.tier.25", category: .mastery, title: "Знаток",
              detail: "25 слов на высшем уровне знания", symbol: "star.fill", points: 25,
              criterion: .threshold(.masteredWords, 25)),
        .init(id: "mastery.interval.30", category: .mastery, title: "Долгая память",
              detail: "Слово с интервалом повторения от 30 дней", symbol: "calendar.badge.clock", points: 20,
              criterion: .threshold(.maxIntervalDays, 30)),
        .init(id: "meta.polyglot", category: .feats, title: "Полиглот",
              detail: "Получите «Библиотекарь», «Неделя практики», «Знаток» и «Без ошибок»",
              symbol: "crown.fill", points: 25,
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
