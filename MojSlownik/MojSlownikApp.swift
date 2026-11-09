import SwiftUI
import SwiftData

@main
struct MojSlownikApp: App {
    @State private var folders = FolderLibraryStore()
    @State private var dailyStudy = DailyStudyStore()
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(folders)
                .environment(dailyStudy)
        }
        .modelContainer(for: [Word.self, WordFolder.self])
    }
}
