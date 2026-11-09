import SwiftUI

struct SessionProgress: View {
    let completed: Int
    let total: Int
    var spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ответы")
                        .foregroundStyle(Color.subtleText)
                    Spacer(minLength: 12)
                    Text("\(completed) из \(total)")
                        .foregroundStyle(Color.appInk)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ответы")
                        .foregroundStyle(Color.subtleText)
                    Text("\(completed) из \(total)")
                        .foregroundStyle(Color.appInk)
                        .monospacedDigit()
                }
            }
            .font(.subheadline.weight(.medium))
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .tint(.appAccent)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Прогресс практики")
        .accessibilityValue("Ответов: \(completed) из \(total)")
    }
}
