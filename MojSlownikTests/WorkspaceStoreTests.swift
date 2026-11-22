import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var spy: AppLogSpy!
    private var signal: LocalChangeSignal!
    private var notified = 0
    private let de = WorkspaceID.make(term: "de", translation: "ru")

    override func setUpWithError() throws {
        container = try ModelContainer(for: AppSchema.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        defaults = UserDefaults(suiteName: "WorkspaceStoreTests.\(UUID().uuidString)")!
        spy = AppLogSpy()
        signal = LocalChangeSignal()
        notified = 0
        signal.handler = { [unowned self] in notified += 1 }
        try WorkspaceCatalog.ensure(term: "pl", translation: "ru", container: container)
        try WorkspaceCatalog.ensure(term: "de", translation: "ru", container: container)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(repository: SwiftDataWorkspaceRepository(container: container),
                       activeRepository: UserDefaultsActiveWorkspaceRepository(defaults: defaults),
                       logger: spy, changeSignal: signal)
    }

    func testInputSideIsPerWorkspaceAndPersists() throws {
        let sides = UserDefaultsInputSideRepository(defaults: defaults)
        let store = WorkspaceStore(repository: SwiftDataWorkspaceRepository(container: container),
                                   activeRepository: UserDefaultsActiveWorkspaceRepository(defaults: defaults),
                                   inputSides: sides, logger: spy, changeSignal: signal)
        try store.load()
        XCTAssertEqual(store.inputSide(for: de), .term)
        store.setInputSide(.translation, for: de)
        XCTAssertEqual(store.inputSide(for: de), .translation)
        XCTAssertEqual(store.inputSide(for: WorkspaceID.legacy), .term)
        let reloaded = WorkspaceStore(repository: SwiftDataWorkspaceRepository(container: container),
                                      activeRepository: UserDefaultsActiveWorkspaceRepository(defaults: defaults),
                                      inputSides: UserDefaultsInputSideRepository(defaults: defaults),
                                      logger: spy, changeSignal: signal)
        XCTAssertEqual(reloaded.inputSide(for: de), .translation)
        XCTAssertNotNil(defaults.dictionary(forKey: "workspace.inputSide.v1"))
    }

    func testActiveInputSideAppliesToSameScriptPairsOnly() throws {
        let enPl = try WorkspaceCatalog.ensure(term: "en", translation: "pl", container: container)
        let store = makeStore()
        try store.load()
        XCTAssertEqual(store.pair, .polishRussian)
        XCTAssertNil(store.activeInputSide, "pl ← ru detects the side by script")
        store.select(id: enPl)
        XCTAssertEqual(store.pair, LanguagePair(term: .english, translation: .polish))
        XCTAssertEqual(store.activeInputSide, .term)
        store.setInputSide(.translation, for: enPl)
        XCTAssertEqual(store.activeInputSide, .translation)
    }

    func testLoadFallsBackToTheFirstOptionAndPersistsIt() throws {
        let store = makeStore()
        try store.load()
        XCTAssertEqual(store.options.map(\.termCode), ["pl", "de"])
        XCTAssertEqual(store.activeID, WorkspaceID.legacy)
        XCTAssertEqual(store.context, WorkspaceContext(id: WorkspaceID.legacy, termCode: "pl", translationCode: "ru"))
        XCTAssertEqual(defaults.string(forKey: "workspace.active.v1"), WorkspaceID.legacy.uuidString)
    }

    func testLoadPicksThePersistedActiveWorkspace() throws {
        defaults.set(de.uuidString, forKey: "workspace.active.v1")
        let store = makeStore()
        try store.load()
        XCTAssertEqual(store.activeID, de)
        XCTAssertEqual(store.active?.termCode, "de")
    }

    func testLoadIgnoresAPersistedIDThatIsNoLongerActive() throws {
        defaults.set(UUID().uuidString, forKey: "workspace.active.v1")
        let store = makeStore()
        try store.load()
        XCTAssertEqual(store.activeID, WorkspaceID.legacy)
        XCTAssertEqual(defaults.string(forKey: "workspace.active.v1"), WorkspaceID.legacy.uuidString)
    }

    func testSelectPersistsLogsCodesAndNotifiesOnActiveChange() throws {
        let store = makeStore()
        var contexts: [WorkspaceContext?] = []
        store.onActiveChange = { contexts.append($0) }
        try store.load()
        store.select(id: de)
        store.select(id: de)
        store.select(id: UUID())

        XCTAssertEqual(store.activeID, de)
        XCTAssertEqual(defaults.string(forKey: "workspace.active.v1"), de.uuidString)
        XCTAssertEqual(spy.events, [.workspaceSwitched])
        XCTAssertEqual(spy.entries[0].properties, [.termLanguage: .name("de"), .targetLanguage: .name("ru")])
        XCTAssertEqual(contexts.map { $0?.termCode }, ["pl", "de"], "load and one real switch")
    }

    func testCreateAddsSelectsAndLogs() throws {
        let store = makeStore()
        try store.load()
        let id = try store.create(term: "en", translation: "pl")
        XCTAssertEqual(id, WorkspaceID.make(term: "en", translation: "pl"))
        XCTAssertEqual(store.activeID, id)
        XCTAssertEqual(store.options.map(\.termCode), ["pl", "de", "en"])
        XCTAssertEqual(spy.events, [.workspaceCreated, .workspaceSwitched])
        XCTAssertGreaterThan(notified, 0)
    }

    func testCreatingAnExistingPairSelectsItWithoutDuplicating() throws {
        let store = makeStore()
        try store.load()
        try store.create(term: "de", translation: "ru")
        XCTAssertEqual(store.activeID, de)
        XCTAssertEqual(store.options.count, 2)
        XCTAssertFalse(spy.events.contains(.workspaceCreated))
    }

    func testReAddingADeletedPairLogsRestoredNotCreated() throws {
        let store = makeStore()
        try store.load()
        try store.delete(id: de)
        let before = spy.entries.count
        try store.create(term: "de", translation: "ru")
        XCTAssertEqual(store.activeID, de)
        let entries = Array(spy.entries.dropFirst(before))
        XCTAssertEqual(entries.map(\.event), [.workspaceRestored, .workspaceSwitched])
        XCTAssertEqual(entries[0].properties, [.termLanguage: .name("de"), .targetLanguage: .name("ru")])
    }

    func testEnsureReportsCreatedExistingAndRestored() throws {
        let repository = SwiftDataWorkspaceRepository(container: container)
        XCTAssertEqual(try repository.ensure(term: "en", translation: "pl").outcome, .created)
        XCTAssertEqual(try repository.ensure(term: "en", translation: "pl").outcome, .existing)
        try repository.delete(id: WorkspaceID.make(term: "en", translation: "pl"))
        let restored = try repository.ensure(term: "en", translation: "pl")
        XCTAssertEqual(restored.outcome, .restored)
        XCTAssertEqual(restored.id, WorkspaceID.make(term: "en", translation: "pl"))
    }

    func testDeletingTheActiveWorkspaceSelectsAnother() throws {
        let store = makeStore()
        try store.load()
        store.select(id: de)
        try store.delete(id: de)
        XCTAssertEqual(store.activeID, WorkspaceID.legacy)
        XCTAssertEqual(store.options.map(\.termCode), ["pl"])
        XCTAssertTrue(spy.events.contains(.workspaceDeleted))
        XCTAssertThrowsError(try store.delete(id: WorkspaceID.legacy))
        XCTAssertEqual(store.options.count, 1)
    }

    func testReorderReloadsOptions() throws {
        let store = makeStore()
        try store.load()
        try store.reorder(ids: [de, WorkspaceID.legacy])
        XCTAssertEqual(store.options.map(\.termCode), ["de", "pl"])
        XCTAssertEqual(store.activeID, WorkspaceID.legacy, "reordering keeps the active workspace")
    }

    func testLogsNeverCarryAnythingButCodes() throws {
        let store = makeStore()
        try store.load()
        store.select(id: de)
        XCTAssertFalse(spy.loggedNames.contains("invalid"))
    }
}
