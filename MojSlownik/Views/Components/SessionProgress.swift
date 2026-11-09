import SwiftUI

struct SessionProgress: View {
    let completed: Int
    let total: Int
    var spacing: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text("Ответов: \(completed) из \(total)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.subtleText)
                .monospacedDigit()
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .tint(.appAccent)
                .accessibilityLabel("Прогресс тренировки")
                .accessibilityValue("Ответов: \(completed) из \(total)")
        }
    }
}
