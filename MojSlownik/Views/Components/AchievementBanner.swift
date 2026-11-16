import SwiftUI

struct AchievementBanner: View {
    let achievement: AchievementDefinition

    var body: some View {
        HStack(spacing: 12) {
            AchievementBadge(symbol: achievement.symbol, isUnlocked: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Достижение получено")
                    .font(.caption)
                    .foregroundStyle(Color.subtleText)
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(Color.appInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("+\(achievement.points)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.appAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSecondarySurface, in: Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Достижение получено: \(achievement.title), плюс \(achievement.points) очков")
        .accessibilityHint("Дважды коснитесь, чтобы скрыть")
        .accessibilityAddTraits(.isButton)
    }
}
