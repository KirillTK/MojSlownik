import SwiftUI

/// Icon tile for an achievement: yellow with a filled glyph when unlocked, neutral with a lock otherwise.
struct AchievementBadge: View {
    let symbol: String
    let isUnlocked: Bool
    var size: CGFloat = 40

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    private var side: CGFloat { size * scale }

    var body: some View {
        Image(systemName: symbol)
            .symbolVariant(isUnlocked ? .fill : .none)
            .font(.system(size: side * 0.45))
            .fontWeight(.medium)
            .foregroundStyle(isUnlocked ? Color.appOnAccent : Color.subtleText.opacity(0.8))
            .frame(width: side, height: side)
            .background(isUnlocked ? Color.appAccent : Color.appSecondarySurface,
                        in: RoundedRectangle(cornerRadius: side * 0.32, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock")
                        .font(.system(size: side * 0.25))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.subtleText)
                        .padding(4)
                }
            }
            .accessibilityHidden(true)
    }
}
