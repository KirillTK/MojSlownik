import SwiftUI

struct SessionProgress: View {
    let completed: Int
    let total: Int
    var spacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Answers")
                        .foregroundStyle(Color.subtleText)
                    Spacer(minLength: 12)
                    Text("\(completed) of \(total)")
                        .foregroundStyle(Color.appInk)
                        .monospacedDigit()
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Answers")
                        .foregroundStyle(Color.subtleText)
                    Text("\(completed) of \(total)")
                        .foregroundStyle(Color.appInk)
                        .monospacedDigit()
                }
            }
            .font(.subheadline.weight(.medium))
            MarkerProgressBar(value: Double(completed) / Double(max(total, 1)))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Practice progress")
        .accessibilityValue("Answers: \(completed) of \(total)")
        .accessibilityIdentifier("sessionProgress")
    }
}
