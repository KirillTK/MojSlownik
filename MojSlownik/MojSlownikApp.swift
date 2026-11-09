import SwiftUI
import SwiftData

@main
@MainActor
struct MojSlownikApp: App {
    @State private var folders = FolderLibraryStore()
    @State private var dailyStudy: DailyStudyStore
    private let container: ModelContainer

    init() {
        do {
            let resources = try AppResources()
            container = resources.container
            _dailyStudy = State(initialValue: resources.dailyStudy)
        } catch {
            fatalError("Unable to open the dictionary: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(folders)
                .environment(dailyStudy)
        }
        .modelContainer(container)
    }
}

@MainActor
struct AppResources {
    let container: ModelContainer
    let dailyStudy: DailyStudyStore

    init(configuration: ModelConfiguration? = nil, defaults: UserDefaults = .standard,
         calendar: Calendar = .autoupdatingCurrent, now: Date = .now) throws {
        if let configuration {
            container = try ModelContainer(for: Word.self, WordFolder.self, configurations: configuration)
        } else {
            container = try ModelContainer(for: Word.self, WordFolder.self)
        }
        // PersistentIdentifier decoding requires Word's schema to be registered first.
        dailyStudy = DailyStudyStore(defaults: defaults, calendar: calendar, now: now)
    }

    static let preview: AppResources = {
        do {
            return try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                    defaults: UserDefaults(suiteName: "MojSlownik.Previews")!)
        } catch {
            fatalError("Unable to create preview storage: \(error)")
        }
    }()
}
