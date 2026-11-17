import Foundation
import SwiftData

@Model
final class Word {
    var russian: String
    var polish: String
    var sourceLanguageCode: String
    var categoryRawValue: String = "Другое"
    var folderIDs: [UUID] = []
    var createdAt: Date
    // stable cross-store identity; optional for additive migration; backfilled at launch
    var uuid: UUID? = nil
    var updatedAt: Date? = nil
    var deletedAt: Date? = nil

    // Интервальное повторение (упрощённый SM-2)
    var easeFactor: Double
    var intervalDays: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewGradeRawValue: String? = nil
    var knowledgeTier: Int? = nil
    var consecutiveSoftMisses: Int = 0

    init(russian: String, polish: String, sourceLanguage: AppLanguage, createdAt: Date = .now, category: WordCategory? = nil) {
        self.russian = russian.lowercased()
        self.polish = polish.lowercased()
        self.sourceLanguageCode = sourceLanguage.rawValue
        self.categoryRawValue = (category ?? WordCategory.detect(russian: russian, polish: polish)).rawValue
        self.createdAt = createdAt
        self.uuid = UUID()
        self.updatedAt = createdAt
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = createdAt
    }
}

extension Word {
    var category: WordCategory {
        get { WordCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    func matches(source: String, translation: String, language: AppLanguage) -> Bool {
        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCanonicalMapping.lowercased()
        }
        return normalized(text(in: language)) == normalized(source)
            && normalized(text(in: language.other)) == normalized(translation)
    }

    var isActive: Bool { deletedAt == nil }
    var lastModifiedAt: Date { updatedAt ?? createdAt }

    func markDeleted(now: Date) {
        deletedAt = now
        updatedAt = now
    }

    var isDue: Bool { dueDate <= .now }

    func text(in language: AppLanguage) -> String {
        language == .russian ? russian : polish
    }
}
