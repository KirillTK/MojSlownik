import SwiftUI

struct KnowledgeTierBadge: View {
    let word: Word
    let level: Int
    var hidesWordInAccessibilityLabel = false

    private var presentation: Presentation { Self.presentation(for: level) }

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lineWidth = size * 0.2
        ZStack {
            Circle().stroke(Color.appRingTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: presentation.fillFraction)
                .stroke(presentation.color.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .snappy, value: presentation.fillFraction)
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

        /// Share of the ring that is filled: a quarter per tier step.
        var fillFraction: Double { Double(filledMarks) / 4 }
    }

    enum IndicatorColor: Equatable {
        case error, warning, accent, mastery

        var color: Color {
            switch self {
            case .error: .appError
            case .warning: .appCaution
            case .accent: .appAccentText
            case .mastery: .appMastery
            }
        }
    }
}
