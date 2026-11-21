import SwiftUI
import SwiftData

@main
@MainActor
struct MojSlownikApp: App {
    @State private var workspaces: WorkspaceStore
    @State private var folders: FolderLibraryStore
    @State private var vocabulary: VocabularyStore
    @State private var dailyStudy: DailyStudyStore
    @State private var achievements: AchievementStore
    @State private var auth: AuthStore
    @State private var sync: SyncStore
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer
    private let logger: any AppLogging

    init() {
        do {
            #if DEBUG
            let resources: AppResources
            if let configuration = try UITestLaunchConfiguration.parse(ProcessInfo.processInfo.environment) {
                resources = try AppResources.uiTest(configuration)
            } else if AppResources.isUnitTestHost {
                resources = try AppResources.unitTestHost()
            } else {
                resources = try AppResources.production()
            }
            #else
            let resources = try AppResources.production()
            #endif
            container = resources.container
            _workspaces = State(initialValue: resources.workspaces)
            _folders = State(initialValue: resources.folders)
            _vocabulary = State(initialValue: resources.vocabulary)
            _dailyStudy = State(initialValue: resources.dailyStudy)
            _achievements = State(initialValue: resources.achievements)
            _auth = State(initialValue: resources.auth)
            _sync = State(initialValue: resources.sync)
            logger = resources.logger
            AppLog.shared = resources.logger
            // Once per process (here, not in a view's .task that runs per scene).
            resources.logger.log(.appLaunched)
        } catch {
            fatalError("Unable to open the dictionary: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(workspaces)
                .environment(folders)
                .environment(vocabulary)
                .environment(dailyStudy)
                .environment(achievements)
                .environment(auth)
                .environment(sync)
                .task { auth.start() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                BackgroundLogFlush.start(logger: logger)
                let sync = sync
                BackgroundLogFlush.run(name: "sync") { await sync.syncBeforeLeaving() }
            case .active:
                sync.sceneDidBecomeActive()
            default:
                break
            }
        }
    }
}

@MainActor
struct AppResources {
    let container: ModelContainer
    let workspaces: WorkspaceStore
    let folders: FolderLibraryStore
    let vocabulary: VocabularyStore
    let dailyStudy: DailyStudyStore
    let achievements: AchievementStore
    let auth: AuthStore
    let sync: SyncStore
    let logger: any AppLogging
    /// Not placed in the environment; creates its client lazily (first auth/log use).
    let supabase: SupabaseClientProvider

    init(configuration: ModelConfiguration? = nil, defaults: UserDefaults = .standard,
         calendar: Calendar = .autoupdatingCurrent, now: Date = .now,
         supabase: SupabaseClientProvider? = nil, logger: (any AppLogging)? = nil,
         authBackend: (any AuthBackend)? = nil, syncRemote: (any SyncRemote)? = nil) throws {
        let supabase = supabase ?? SupabaseClientProvider()
        let logger = logger ?? NoopAppLogger()
        if let configuration {
            container = try ModelContainer(for: AppSchema.schema, configurations: configuration)
        } else {
            container = try ModelContainer(for: AppSchema.schema)
        }
        WordIdentityBackfill.run(container: container)
        WorkspaceBackfill.run(container: container, defaults: defaults, now: now)
        // PersistentIdentifier decoding requires Word's schema to be registered first.
        let changeSignal = LocalChangeSignal()
        dailyStudy = DailyStudyStore(repository: UserDefaultsDailyActivityRepository(defaults: defaults),
                                     calendar: calendar, now: now, logger: logger, changeSignal: changeSignal)
        achievements = AchievementStore(repository: UserDefaultsAchievementStateRepository(defaults: defaults),
                                        calendar: calendar, logger: logger)
        folders = FolderLibraryStore(repository: SwiftDataFolderRepository(container: container), logger: logger,
                                     changeSignal: changeSignal)
        vocabulary = VocabularyStore(repository: SwiftDataVocabularyRepository(container: container), logger: logger,
                                     changeSignal: changeSignal)
        let workspaces = WorkspaceStore(repository: SwiftDataWorkspaceRepository(container: container),
                                        activeRepository: UserDefaultsActiveWorkspaceRepository(defaults: defaults),
                                        logger: logger, changeSignal: changeSignal)
        self.workspaces = workspaces
        workspaces.onActiveChange = { [folders, vocabulary] context in
            folders.workspaceID = context?.id
            vocabulary.workspace = context
            try? folders.load()
        }
        try? workspaces.load()
        auth = AuthStore(backend: authBackend ?? SupabaseAuthBackend(provider: supabase), logger: logger)
        let stateRepository = UserDefaultsSyncStateRepository(defaults: defaults)
        let syncStore = SwiftDataSyncStore(container: container)
        let engine = syncRemote.map { SyncEngine(remote: $0, local: syncStore, state: stateRepository) }
        let sync = SyncStore(engine: engine, state: stateRepository, folders: folders,
                             achievements: achievements, logger: logger)
        self.sync = sync
        changeSignal.handler = { [weak sync] in sync?.localDataChanged() }
        auth.onAccountChange = { [weak sync] account in sync?.accountDidChange(account) }
        auth.beforeSignOut = { [weak sync] in await sync?.syncBeforeLeaving() }
        self.logger = logger
        self.supabase = supabase
    }

    /// The app's real wiring: on-disk log queue uploading to Supabase while signed in.
    static func production() throws -> AppResources {
        let supabase = SupabaseClientProvider()
        let queue = AppLogQueue(fileURL: AppLogQueue.defaultFileURL())
        queue.uploader = SupabaseLogUploader(provider: supabase)
        let resources = try AppResources(supabase: supabase, logger: queue,
                                         syncRemote: SupabaseSyncRemote(provider: supabase))
        queue.currentAccountID = { [weak auth = resources.auth] in auth?.account?.userID }
        return resources
    }

    #if DEBUG
    /// Unit tests run inside the app; the host must not touch the network, Keychain or disk logs.
    static var isUnitTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func unitTestHost() throws -> AppResources {
        // Fresh every run, like uiTest(): no state leaks between test runs.
        UserDefaults().removePersistentDomain(forName: "MojSlownik.UnitTestHost")
        return try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                         defaults: UserDefaults(suiteName: "MojSlownik.UnitTestHost")!,
                         authBackend: StaticAuthBackend())
    }

    static func uiTest(_ configuration: UITestLaunchConfiguration, now: Date = .now) throws -> AppResources {
        UserDefaults().removePersistentDomain(forName: UITestLaunchConfiguration.defaultsSuite)
        let defaults = UserDefaults(suiteName: UITestLaunchConfiguration.defaultsSuite)!
        configuration.sync.seedState(into: UserDefaultsSyncStateRepository(defaults: defaults), now: now)
        let remote = configuration.sync.makeRemote(now: now)
        let resources = try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                         defaults: defaults, now: now,
                                         authBackend: configuration.auth.makeBackend(), syncRemote: remote)
        resources.sync.onCycleSucceeded = { remote.armScriptedChanges() }
        try configuration.fixture.seed(into: resources.container.mainContext, now: now)
        try resources.workspaces.load()
        return resources
    }
    #endif

    static let preview: AppResources = {
        do {
            let resources = try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                             defaults: UserDefaults(suiteName: "MojSlownik.Previews")!,
                                             authBackend: StaticAuthBackend())
            try WorkspaceCatalog.ensure(term: "pl", translation: "ru", context: resources.container.mainContext)
            try resources.workspaces.load()
            resources.auth.start()  // previews have no App .task; leave the `.unknown` spinner
            return resources
        } catch {
            fatalError("Unable to create preview storage: \(error)")
        }
    }()
}
