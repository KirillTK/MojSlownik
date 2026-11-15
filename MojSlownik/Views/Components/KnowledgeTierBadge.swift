import SwiftUI

struct KnowledgeTierBadge: View {
    let word: Word
    let level: Int
    var hidesWordInAccessibilityLabel = false

    private var presentation: Presentation { Self.presentation(for: level) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { mark in
                Capsule()
                    .fill(mark < presentation.filledMarks ? presentation.color.color : Color.appBorder)
                    .frame(width: 4, height: 8)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(Color.cardBackground, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.appBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        Self.accessibilityDescription(for: word, level: level,
                                      hidesWord: hidesWordInAccessibilityLabel)
    }

    static func presentation(for level: Int) -> Presentation {
        switch min(max(level, 0), 3) {
        case 0: Presentation(filledMarks: 1, levelName: "Не помню", color: .error)
        case 1: Presentation(filledMarks: 2, levelName: "Трудно", color: .warning)
        case 2: Presentation(filledMarks: 3, levelName: "Хорошо", color: .accent)
        default: Presentation(filledMarks: 4, levelName: "Легко", color: .mastery)
        }
    }

    static func accessibilityDescription(for word: Word, level: Int, hidesWord: Bool = false) -> String {
        let levelName = presentation(for: level).levelName
        return hidesWord ? "Уровень знания: \(levelName)" : "Уровень знания слова \(word.polish): \(levelName)"
    }

    struct Presentation: Equatable {
        let filledMarks: Int
        let levelName: String
        let color: IndicatorColor
    }

    enum IndicatorColor: Equatable {
        case error, warning, accent, mastery

        var color: Color {
            switch self {
            case .error: .appError
            case .warning: .appWarning
            case .accent: .appAccent
            case .mastery: .appMastery
            }
        }
    }
}
