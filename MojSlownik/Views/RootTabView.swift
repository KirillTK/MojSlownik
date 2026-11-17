import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            WordListView()
                .tabItem { Label("Словарь", systemImage: "character.book.closed") }

            TrainingView()
                .tabItem { Label("Практика", systemImage: "rectangle.stack") }
        }
        .tint(.appAccentStrong)
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
