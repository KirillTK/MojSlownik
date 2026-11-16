import SwiftUI

/// Icon tile for an achievement: accent when unlocked, dimmed with a lock otherwise.
struct AchievementBadge: View {
    let symbol: String
    let isUnlocked: Bool
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45))
            .foregroundStyle(isUnlocked ? Color.appAccent : Color.subtleText.opacity(0.5))
            .frame(width: size, height: size)
            .background(Color.appSecondarySurface, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: size * 0.25))
                        .foregroundStyle(Color.subtleText)
                        .padding(4)
                }
            }
            .accessibilityHidden(true)
    }
}
