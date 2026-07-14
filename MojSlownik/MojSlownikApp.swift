import SwiftUI
import SwiftData

@main
struct MojSlownikApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(for: Word.self)
    }
}
