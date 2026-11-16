import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            WordListView()
                .tabItem { Label("Словарь", systemImage: "book.closed.fill") }

            TrainingView()
                .tabItem { Label("Практика", systemImage: "rectangle.on.rectangle.angled") }

            NavigationStack { AchievementsView() }
                .tabItem { Label("Достижения", systemImage: "trophy.fill") }
        }
        .tint(.appAccent)
        .background { AchievementTracker() }
        .achievementBanner()
        .modifier(AppleTranslationHost())
    }
}

#Preview {
    let resources = AppResources.preview
    RootTabView()
        .modelContainer(resources.container)
        .environment(FolderLibraryStore())
        .environment(resources.dailyStudy)
        .environment(resources.achievements)
}
