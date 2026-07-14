import Foundation
import SwiftData

@Model
final class Word {
    var russian: String
    var polish: String
    var sourceLanguageCode: String
    var createdAt: Date

    // Интервальное повторение (упрощённый SM-2)
    var easeFactor: Double
    var intervalDays: Double
    var repetitions: Int
    var dueDate: Date

    init(russian: String, polish: String, sourceLanguage: AppLanguage, createdAt: Date = .now) {
        self.russian = russian
        self.polish = polish
        self.sourceLanguageCode = sourceLanguage.rawValue
        self.createdAt = createdAt
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = createdAt
    }
}

extension Word {
    var isDue: Bool { dueDate <= .now }

    func text(in language: AppLanguage) -> String {
        language == .russian ? russian : polish
    }
}
