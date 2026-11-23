import SwiftUI

/// Segmented capsule bar (learned / learning / new). Callers keep their own accessibility label
/// and value: the bar is hidden from VoiceOver, the state is carried by text.
struct ProgressSegmentsBar: View {
    struct Segment: Identifiable, Equatable {
        let id: String
        let value: Int
        let color: Color
    }

    let segments: [Segment]
    var track: Color = .appSecondarySurface
    var height: CGFloat = 12
    var spacing: CGFloat = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: [Segment] { segments.filter { $0.value > 0 } }
    private var total: Int { visible.reduce(0) { $0 + $1.value } }

    var body: some View {
        GeometryReader { proxy in
            let items = visible
            let gaps = spacing * CGFloat(max(0, items.count - 1))
            let available = max(0, proxy.size.width - gaps)
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                HStack(spacing: spacing) {
                    ForEach(items) { segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: available * CGFloat(segment.value) / CGFloat(max(total, 1)))
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: segments)
        .accessibilityHidden(true)
    }
}
