import SwiftUI

struct SessionProgress: View {
    let completed: Int
    let total: Int
    var spacing: CGFloat = 20

    var body: some View {
        VStack(spacing: spacing) {
            ProgressView(value: Double(completed), total: Double(total))
                .tint(.appAccent)
            Text("\(completed + 1) из \(total)")
                .font(.caption)
                .foregroundStyle(Color.subtleText)
        }
    }
}
