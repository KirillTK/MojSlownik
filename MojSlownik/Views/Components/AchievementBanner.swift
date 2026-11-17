import SwiftUI

struct AchievementBanner: View {
    let achievement: AchievementDefinition

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 20, style: .continuous) }

    var body: some View {
        HStack(spacing: 12) {
            AchievementBadge(symbol: achievement.symbol, isUnlocked: true, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Достижение получено")
                    .font(.caption)
                    .foregroundStyle(Color.appOnInverse.opacity(0.7))
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(Color.appOnInverse)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("+\(achievement.points)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.appOnAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appAccent, in: Capsule())
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.appInverseSurface, in: shape)
        .overlay { shape.strokeBorder(Color.appInverseEdge, lineWidth: 1) }
        .shadow(color: .black.opacity(0.25), radius: 15, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Достижение получено: \(achievement.title), плюс \(achievement.points) очков")
        .accessibilityHint("Дважды коснитесь, чтобы скрыть")
        .accessibilityAddTraits(.isButton)
    }
}
