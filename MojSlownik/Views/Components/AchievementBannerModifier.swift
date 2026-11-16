import SwiftUI

extension View {
    /// Shows the store's current achievement banner. Timers and announcements live in the
    /// store, so hosting this at several presentation levels is safe.
    func achievementBanner() -> some View {
        modifier(AchievementBannerModifier())
    }
}

private struct AchievementBannerModifier: ViewModifier {
    @Environment(AchievementStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let achievement = store.currentAnnouncement {
                    AchievementBanner(achievement: achievement)
                        .id(achievement.id)
                        .padding(.top, 56)
                        .padding(.horizontal, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .onTapGesture { store.dismissAnnouncement() }
                        .gesture(DragGesture().onEnded { value in
                            if value.translation.height < -24 { store.dismissAnnouncement() }
                        })
                        .accessibilityAction(named: "Скрыть") { store.dismissAnnouncement() }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.currentAnnouncement?.id)
    }
}
