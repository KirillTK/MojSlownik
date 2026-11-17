import SwiftUI

/// Thin capsule progress bar. Callers keep their own accessibility label and value.
struct MarkerProgressBar: View {
    let value: Double
    var track: Color = .appSecondarySurface
    var fill: Color = .appAccentStrong
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: clamped)
        .accessibilityHidden(true)
    }
}
