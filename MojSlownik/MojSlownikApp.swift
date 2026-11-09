import SwiftUI
import SwiftData

@main
struct MojSlownikApp: App {
    @State private var folders = FolderLibraryStore()
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(folders)
        }
        .modelContainer(for: [Word.self, WordFolder.self])
    }
}
