import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            WordListView()
                .tabItem { Label("Словарь", systemImage: "book.closed.fill") }

            TrainingView()
                .tabItem { Label("Тренировка", systemImage: "rectangle.on.rectangle.angled") }
        }
        .tint(.appAccent)
        .modifier(AppleTranslationHost())
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [Word.self, WordFolder.self], inMemory: true)
        .environment(FolderLibraryStore())
        .environment(DailyStudyStore())
}
