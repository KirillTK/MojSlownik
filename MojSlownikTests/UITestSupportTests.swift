#if DEBUG
import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class UITestSupportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: UITestLaunchConfiguration.defaultsSuite)
        super.tearDown()
    }

    /// Returns the container too: the context must not outlive it.
    private func seeded(_ fixture: UITestFixture) throws -> ModelContainer {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        try fixture.seed(into: container.mainContext, now: now)
        return container
    }

    private func words(_ container: ModelContainer) throws -> [Word] {
        try container.mainContext.fetch(FetchDescriptor<Word>())
    }

    // MARK: Fixtures

    func testFixtureNamesArePinned() {
        // The UI-test E2ETestCase.Fixture enum mirrors these raw values.
        XCTAssertEqual(UITestFixture.allCases.map(\.rawValue),
                       ["empty", "basicVocabulary", "dueForReview", "foldersOrdered", "syncedVocabulary"])
        XCTAssertEqual(UITestSyncState.allCases.map(\.rawValue),
                       ["empty", "remoteVocabulary", "failsOnce", "linkedToOtherAccount", "syncedThenRemoteChanges"])
    }

    func testEmptyFixtureHasNoData() throws {
        let container = try seeded(.empty)
        XCTAssertEqual(try words(container).count, 0)
        XCTAssertEqual(try FolderStore.folders(in: container.mainContext).count, 0)
    }

    func testBasicVocabularyHasFiveLearnedWords() throws {
        let container = try seeded(.basicVocabulary)
        let all = try words(container)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.filter { $0.dueDate <= now }.count, 0)
        XCTAssertEqual(Set(all.map(\.polish)), ["kot", "dom", "woda", "chleb", "książka"])
    }

    func testDueForReviewHasExactlyTwoDueWords() throws {
        let container = try seeded(.dueForReview)
        let all = try words(container)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(Set(all.filter { $0.dueDate <= now }.map(\.polish)), ["jabłko", "okno"])
    }

    func testFoldersOrderedSortsByOrderAndAssignsMemberships() throws {
        let container = try seeded(.foldersOrdered)
        XCTAssertEqual(try FolderStore.folders(in: container.mainContext).map(\.name),
                       ["Урок 1", "Урок 2", "Урок 3"])
        let byPolish = Dictionary(uniqueKeysWithValues: try words(container).map { ($0.polish, $0.folderIDs) })
        XCTAssertEqual(byPolish["kot"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byPolish["dom"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byPolish["woda"], [UITestFixture.lesson2ID])
        XCTAssertEqual(byPolish["chleb"], [])
    }

    func testEveryFixtureSeedsExactlyOneLegacyWorkspaceAndAssignsIt() throws {
        for fixture in UITestFixture.allCases {
            let container = try seeded(fixture)
            let workspaces = try container.mainContext.fetch(FetchDescriptor<Workspace>())
            XCTAssertEqual(workspaces.map(\.id), [WorkspaceID.legacy], "\(fixture)")
            XCTAssertEqual(workspaces.map(\.termLanguageCode), ["pl"], "\(fixture)")
            XCTAssertEqual(workspaces.map(\.translationLanguageCode), ["ru"], "\(fixture)")
            XCTAssertTrue(try words(container).allSatisfy { $0.workspaceID == WorkspaceID.legacy }, "\(fixture)")
            let folders = try container.mainContext.fetch(FetchDescriptor<WordFolder>())
            XCTAssertTrue(folders.allSatisfy { $0.workspaceID == WorkspaceID.legacy }, "\(fixture)")
        }
    }

    // MARK: Launch configuration

    func testParseWithoutKeysIsNil() throws {
        XCTAssertNil(try UITestLaunchConfiguration.parse([:]))
        XCTAssertNil(try UITestLaunchConfiguration.parse(["UITEST_PREFILL": ""]))
    }

    func testPrefillImpliesEmptyFixture() throws {
        let configuration = try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_PREFILL": "x"]))
        XCTAssertEqual(configuration.fixture, .empty)
        XCTAssertEqual(configuration.prefill, "x")
    }

    func testParseFixtureWithoutPrefill() throws {
        let configuration = try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_FIXTURE": "dueForReview"]))
        XCTAssertEqual(configuration.fixture, .dueForReview)
        XCTAssertNil(configuration.prefill)
    }

    func testUnknownFixtureThrowsNamingTheValue() {
        XCTAssertThrowsError(try UITestLaunchConfiguration.parse(["UITEST_FIXTURE": "nope"])) { error in
            XCTAssertEqual(error as? UITestLaunchConfiguration.ParseError, .unknownFixture("nope"))
            XCTAssertTrue(error.localizedDescription.contains("nope"))
        }
    }

    func testParseSyncState() throws {
        let configuration = try XCTUnwrap(UITestLaunchConfiguration.parse(
            ["UITEST_FIXTURE": "syncedVocabulary", "UITEST_SYNC": "syncedThenRemoteChanges"]))
        XCTAssertEqual(configuration.fixture, .syncedVocabulary)
        XCTAssertEqual(configuration.sync, .syncedThenRemoteChanges)
        XCTAssertEqual(try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_FIXTURE": "empty"])).sync, .empty)
        let syncOnly = try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_SYNC": "failsOnce"]))
        XCTAssertEqual(syncOnly.fixture, .empty, "a sync value without a fixture implies .empty")
        XCTAssertEqual(syncOnly.sync, .failsOnce)
    }

    func testUnknownSyncStateThrowsNamingTheValue() {
        XCTAssertThrowsError(try UITestLaunchConfiguration.parse(["UITEST_SYNC": "nope"])) { error in
            XCTAssertEqual(error as? UITestLaunchConfiguration.ParseError, .unknownSyncState("nope"))
            XCTAssertTrue(error.localizedDescription.contains("nope"))
        }
    }

    // MARK: Sync fixtures

    func testSyncedVocabularyHasFixedIDsAndCleanRows() throws {
        let container = try seeded(.syncedVocabulary)
        let all = try words(container)
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(Set(all.compactMap(\.uuid)), Set(UITestFixture.syncedWordIDs))
        let kot = try XCTUnwrap(all.first { $0.polish == "kot" })
        let dom = try XCTUnwrap(all.first { $0.polish == "dom" })
        XCTAssertEqual(kot.uuid, UITestFixture.syncedWordIDs[0])
        XCTAssertEqual(dom.uuid, UITestFixture.syncedWordIDs[1])
        for word in all {
            XCTAssertFalse(word.isSyncDirty, word.polish)
            XCTAssertEqual(word.serverUpdatedAt, UITestFixture.truncatedToMillis(word.createdAt))
        }
        XCTAssertEqual(Set(all.map(\.polish)), ["kot", "dom", "woda", "chleb", "książka"])
    }

    func testSyncedThenRemoteChangesMirrorsTheSyncedFixtureExactly() throws {
        let container = try seeded(.syncedVocabulary)
        let remote = UITestSyncState.syncedThenRemoteChanges.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        XCTAssertEqual(remote.currentUserID, owner)
        XCTAssertEqual(remote.server.words.count, 5)
        for word in try words(container) {
            let row = try XCTUnwrap(remote.word(id: try XCTUnwrap(word.uuid), userID: owner), word.polish)
            XCTAssertEqual(row.term, word.polish)
            XCTAssertEqual(row.translation, word.russian)
            XCTAssertEqual(row.updatedAt, word.serverUpdatedAt)
            XCTAssertEqual(row.createdAt, word.createdAt)
            XCTAssertEqual(row.dueDate, word.dueDate)
            XCTAssertEqual(row.category, word.category.stableID)
            XCTAssertEqual(row.enteredLanguage, word.sourceLanguageCode)
            XCTAssertEqual(row.repetitions, word.repetitions)
            XCTAssertEqual(row.intervalDays, word.intervalDays)
            XCTAssertNil(row.deletedAt)
        }
        let defaults = UserDefaults(suiteName: "UITestSupportTests.sync")!
        defaults.removePersistentDomain(forName: "UITestSupportTests.sync")
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        UITestSyncState.syncedThenRemoteChanges.seedState(into: repository, now: now)
        let state = repository.load()
        XCTAssertEqual(state.linkedAccountID, owner)
        let newest = try XCTUnwrap(remote.server.words.values.max { $0.updatedAt < $1.updatedAt })
        XCTAssertEqual(state.wordsCursor, SyncCursor(updatedAt: newest.updatedAt, id: newest.id))
    }

    func testScriptedChangesAreArmedOnceAndAreNewer() throws {
        let remote = UITestSyncState.syncedThenRemoteChanges.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        let ids = UITestFixture.syncedWordIDs
        let before = try XCTUnwrap(remote.word(id: ids[1], userID: owner)).updatedAt
        remote.armScriptedChanges()
        let dom = try XCTUnwrap(remote.word(id: ids[1], userID: owner))
        let kot = try XCTUnwrap(remote.word(id: ids[0], userID: owner))
        XCTAssertNotNil(dom.deletedAt)
        XCTAssertGreaterThan(dom.updatedAt, before)
        XCTAssertEqual(kot.translation, "котик")
        let stamp = kot.updatedAt
        remote.armScriptedChanges()
        XCTAssertEqual(remote.word(id: ids[0], userID: owner)?.updatedAt, stamp, "arming applies only once")
    }

    func testRemoteVocabularySeedContentsAndOwner() throws {
        let remote = UITestSyncState.remoteVocabulary.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        XCTAssertEqual(Set(remote.server.words.values.map(\.term)), ["most", "ser", "kot"])
        XCTAssertTrue(remote.server.words.values.allSatisfy { $0.userID == owner })
        let folder = try XCTUnwrap(remote.folder(id: UITestSyncState.cloudFolderID, userID: owner))
        XCTAssertEqual(folder.name, "Из облака")
        let most = try XCTUnwrap(remote.server.words.values.first { $0.term == "most" })
        XCTAssertEqual(most.folderIDs, [UITestSyncState.cloudFolderID])
        // Every seeded row passes the validator that real pulls use.
        for row in remote.server.words.values {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, knownFolderIDs: [], now: now))
        }
    }

    func testLinkedToOtherAccountSeedsAMismatchingLink() {
        let defaults = UserDefaults(suiteName: "UITestSupportTests.mismatch")!
        defaults.removePersistentDomain(forName: "UITestSupportTests.mismatch")
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        UITestSyncState.linkedToOtherAccount.seedState(into: repository, now: now)
        let linked = repository.load().linkedAccountID
        XCTAssertEqual(linked, UITestSyncState.otherAccountID)
        XCTAssertNotEqual(linked, StaticAuthBackend.testAccount.userID)
        UITestSyncState.empty.seedState(into: repository, now: now)
        XCTAssertEqual(repository.load().linkedAccountID, linked, "empty seeds nothing")
    }

    func testFailsOnceFailsTheFirstCallOnly() async throws {
        let remote = UITestSyncState.failsOnce.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        do {
            _ = try await remote.fetchWords(ownerID: owner, after: nil, limit: 10)
            XCTFail("the first call must fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        let rows = try await remote.fetchWords(ownerID: owner, after: nil, limit: 10)
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: Translation stub

    func testStubTranslatesRussianToPolishWithoutCyrillic() {
        let hello = UITestTranslationStub.translate("Привет ", from: .russian, to: .polish)
        let dog = UITestTranslationStub.translate("собака", from: .russian, to: .polish)
        XCTAssertEqual(hello, "cześć")
        XCTAssertEqual(dog, "pies")
        for value in [hello, dog] {
            XCTAssertNil(value.range(of: "[а-яА-ЯёЁ]", options: .regularExpression))
        }
    }

    func testStubTranslatesPolishToRussianAndFallsBack() {
        XCTAssertEqual(UITestTranslationStub.translate("dom", from: .polish, to: .russian), "дом")
        XCTAssertEqual(UITestTranslationStub.translate("zzz", from: .russian, to: .polish), "słowo")
        XCTAssertEqual(UITestTranslationStub.translate("zzz", from: .polish, to: .russian), "слово")
    }

    func testStubAlternativesFlowThroughRealMerge() {
        let pair = TranslationPair(source: .polish, target: .russian)
        let groups = UITestTranslationStub.alternatives("dom", pair: pair)
        XCTAssertEqual(groups.count, 2)
        let merged = TranslationAlternatives.merge(primary: "дом", groups: groups, sourceText: "dom", pair: pair)
        XCTAssertTrue(merged.map(\.text).contains("жилище"))
        XCTAssertEqual(UITestTranslationStub.alternatives("unknown", pair: pair), [[], []])
    }

    // MARK: AppResources

    func testUITestResourcesWipeDefaultsAndSeedFixture() throws {
        let suite = UITestLaunchConfiguration.defaultsSuite
        UserDefaults(suiteName: suite)!.set("sentinel", forKey: "sentinel")
        let resources = try AppResources.uiTest(
            UITestLaunchConfiguration(fixture: .dueForReview, prefill: nil), now: now)
        XCTAssertNil(UserDefaults(suiteName: suite)!.object(forKey: "sentinel"))
        XCTAssertEqual(try resources.container.mainContext.fetch(FetchDescriptor<Word>()).count, 5)
        XCTAssertEqual(try resources.container.mainContext.fetch(FetchDescriptor<Workspace>()).count, 1,
                       "the backfill fallback and the fixture share one workspace")
        XCTAssertEqual(resources.workspaces.activeID, WorkspaceID.legacy)
        XCTAssertEqual(resources.vocabulary.workspace?.id, WorkspaceID.legacy)
        XCTAssertEqual(resources.folders.workspaceID, WorkspaceID.legacy)
    }
}
#endif
