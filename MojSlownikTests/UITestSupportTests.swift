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
                       ["empty", "basicVocabulary", "dueForReview", "foldersOrdered", "freshInstall",
                        "multiWorkspace", "sameScriptWorkspace", "syncedVocabulary", "studyProgress"])
        XCTAssertEqual(UITestSyncState.allCases.map(\.rawValue),
                       ["empty", "remoteVocabulary", "failsOnce", "linkedToOtherAccount", "syncedThenRemoteChanges",
                        "remoteWorkspaces"])
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

    func testStudyProgressBucketsForecastAndHardWordsPerScope() throws {
        let container = try seeded(.studyProgress)
        let all = try words(container)
        let memberships = MembershipIndex(try container.mainContext.fetch(FetchDescriptor<FolderMembership>()))
        let calendar = Calendar.autoupdatingCurrent

        XCTAssertEqual(all.count, 10)
        XCTAssertEqual(StudyProgress.breakdown(all), .init(new: 4, learning: 3, learned: 3))
        XCTAssertEqual(StudyProgress.forecast(all, now: now, calendar: calendar), .init(tomorrow: 1, week: 2))
        XCTAssertEqual(StudyProgress.hardWords(all).map(\.polish), ["przyzwyczajenie"])
        let hard = try XCTUnwrap(all.first { $0.polish == "przyzwyczajenie" })
        XCTAssertEqual(hard.dueDate, now.addingTimeInterval(-86_400), "exactly one day overdue")
        XCTAssertEqual(SRSEngine.preview(.hard, for: hard, now: now), .days(2))
        XCTAssertEqual(SRSEngine.preview(.good, for: hard, now: now), .days(3))
        XCTAssertEqual(SRSEngine.preview(.easy, for: hard, now: now), .days(4))
        XCTAssertEqual(all.filter { $0.dueDate <= now }.count, 5)

        let lesson1 = FolderStore.words(all, in: UITestFixture.lesson1ID, memberships: memberships)
        XCTAssertEqual(Set(lesson1.map(\.polish)), ["kot", "dom", "chleb"])
        XCTAssertEqual(StudyProgress.breakdown(lesson1), .init(new: 0, learning: 1, learned: 2))
        XCTAssertTrue(StudyProgress.hardWords(lesson1).isEmpty)
        let lesson2 = FolderStore.words(all, in: UITestFixture.lesson2ID, memberships: memberships)
        XCTAssertEqual(Set(lesson2.map(\.polish)), ["jabłko", "mleko", "ser", "ryba"])
        XCTAssertEqual(StudyProgress.breakdown(lesson2), .init(new: 4, learning: 0, learned: 0))
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<WordFolder>()).map(\.name).sorted(),
                       ["Урок 1", "Урок 2"])
    }

    func testFoldersOrderedSortsByOrderAndAssignsMemberships() throws {
        let container = try seeded(.foldersOrdered)
        XCTAssertEqual(try FolderStore.folders(in: container.mainContext).map(\.name),
                       ["Урок 1", "Урок 2", "Урок 3"])
        let index = MembershipIndex(try container.mainContext.fetch(FetchDescriptor<FolderMembership>()))
        let byPolish = Dictionary(uniqueKeysWithValues: try words(container).map {
            ($0.polish, $0.uuid.map { index.folderIDs(of: $0) } ?? []) })
        XCTAssertEqual(byPolish["kot"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byPolish["dom"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byPolish["woda"], [UITestFixture.lesson2ID])
        XCTAssertEqual(byPolish["chleb"], [])
        XCTAssertTrue(try words(container).allSatisfy { $0.folderIDs.isEmpty }, "the legacy array stays frozen")
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<FolderMembership>())
            .allSatisfy { $0.workspaceID == WorkspaceID.legacy })
    }

    func testEveryPlainFixtureSeedsExactlyOneLegacyWorkspaceAndAssignsIt() throws {
        for fixture in UITestFixture.allCases where ![.freshInstall, .multiWorkspace, .sameScriptWorkspace].contains(fixture) {
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

    func testFreshInstallSeedsNothingNotEvenAWorkspace() throws {
        let container = try seeded(.freshInstall)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Workspace>()).count, 0)
        XCTAssertEqual(try words(container).count, 0)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<WordFolder>()).count, 0)
    }

    func testSameScriptWorkspaceIsAnEmptyEnglishPolishPair() throws {
        let container = try seeded(.sameScriptWorkspace)
        let workspaces = try WorkspaceCatalog.workspaces(in: container.mainContext)
        XCTAssertEqual(workspaces.map(\.id), [WorkspaceID.make(term: "en", translation: "pl")])
        XCTAssertEqual(try words(container).count, 0)
        let pair = try XCTUnwrap(LanguagePair(termCode: "en", translationCode: "pl"))
        XCTAssertTrue(pair.isSameScript, "the direction control appears")
    }

    func testMultiWorkspaceHasPolishFirstAndScopedWordsAndFolders() throws {
        let container = try seeded(.multiWorkspace)
        let context = container.mainContext
        let german = WorkspaceID.make(term: "de", translation: "ru")
        let workspaces = try WorkspaceCatalog.workspaces(in: context)
        XCTAssertEqual(workspaces.map(\.id), [WorkspaceID.legacy, german])
        XCTAssertEqual(workspaces.map(\.sortOrder), [0, 1])
        let all = try words(container)
        XCTAssertEqual(Set(WorkspaceScope.words(all, workspaceID: WorkspaceID.legacy).map(\.term)),
                       ["kot", "dom", "woda", "chleb", "książka"])
        XCTAssertEqual(Set(WorkspaceScope.words(all, workspaceID: german).map(\.term)), ["das Haus", "lernen"],
                       "German keeps its case")
        let folders = try context.fetch(FetchDescriptor<WordFolder>())
        XCTAssertEqual(WorkspaceScope.folders(folders, workspaceID: WorkspaceID.legacy).map(\.name), ["Урок 1"])
        XCTAssertEqual(WorkspaceScope.folders(folders, workspaceID: german).map(\.name), ["Lektion 1"])
        let index = MembershipIndex(try context.fetch(FetchDescriptor<FolderMembership>()))
        let byTerm = Dictionary(uniqueKeysWithValues: all.map { ($0.term, $0.uuid.map { index.folderIDs(of: $0) } ?? []) })
        XCTAssertEqual(byTerm["kot"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byTerm["dom"], [UITestFixture.lesson1ID])
        XCTAssertEqual(byTerm["das Haus"], [UITestFixture.lektion1ID])
        XCTAssertEqual(byTerm["lernen"], [])
        let memberships = try context.fetch(FetchDescriptor<FolderMembership>())
        XCTAssertTrue(memberships.filter { $0.folderID == UITestFixture.lektion1ID }.allSatisfy { $0.workspaceID == german })
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

    func testParseQuickAction() throws {
        let configuration = try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_QUICK_ACTION": "scan-text"]))
        XCTAssertEqual(configuration.quickAction, .scanText)
        XCTAssertEqual(configuration.fixture, .empty, "a quick action without a fixture implies .empty")
        XCTAssertNil(try XCTUnwrap(UITestLaunchConfiguration.parse(["UITEST_FIXTURE": "empty"])).quickAction)
    }

    func testUnknownQuickActionThrowsNamingTheValue() {
        XCTAssertThrowsError(try UITestLaunchConfiguration.parse(["UITEST_QUICK_ACTION": "nope"])) { error in
            XCTAssertEqual(error as? UITestLaunchConfiguration.ParseError, .unknownQuickAction("nope"))
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
            XCTAssertEqual(row.enteredSide, word.sourceLanguageCode == "ru" ? "translation" : "term")
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

    func testSyncedVocabularyWorkspaceIsCleanAndMirrorsTheServerCopy() throws {
        let container = try seeded(.syncedVocabulary)
        let workspace = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Workspace>()).first)
        XCTAssertFalse(workspace.isSyncDirty)
        let remote = UITestSyncState.syncedThenRemoteChanges.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        let server = try XCTUnwrap(remote.workspace(id: WorkspaceID.legacy, userID: owner))
        XCTAssertEqual(server.updatedAt, workspace.serverUpdatedAt)
        XCTAssertEqual([server.termLanguage, server.translationLanguage], ["pl", "ru"])
        let defaults = UserDefaults(suiteName: "UITestSupportTests.workspaceCursor")!
        defaults.removePersistentDomain(forName: "UITestSupportTests.workspaceCursor")
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        UITestSyncState.syncedThenRemoteChanges.seedState(into: repository, now: now)
        XCTAssertEqual(repository.load().workspacesCursor, SyncCursor(updatedAt: server.updatedAt, id: server.id))
    }

    func testRemoteVocabularyServerHoldsTheWorkspaceFolderAndMembership() throws {
        let remote = UITestSyncState.remoteVocabulary.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        XCTAssertEqual(remote.server.workspaces.count, 1)
        XCTAssertEqual(remote.server.memberships.count, 1)
        XCTAssertTrue(remote.server.folders.values.allSatisfy { $0.workspaceID == WorkspaceID.legacy })
        XCTAssertTrue(remote.server.workspaces.values.allSatisfy { $0.userID == owner })
    }

    func testRemoteWorkspacesServerHoldsGermanFirstAndPolishSecond() throws {
        let remote = UITestSyncState.remoteWorkspaces.makeRemote(now: now)
        let owner = StaticAuthBackend.testAccount.userID
        let german = WorkspaceID.make(term: "de", translation: "ru")
        let rows = remote.server.workspaces.values.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(rows.map(\.id), [german, WorkspaceID.legacy])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1])
        XCTAssertEqual(Set(remote.server.words.values.filter { $0.workspaceID == german }.map(\.term)), ["das Haus"])
        XCTAssertEqual(Set(remote.server.words.values.filter { $0.workspaceID == WorkspaceID.legacy }.map(\.term)),
                       ["most", "ser"])
        var known = KnownRemoteIDs(workspaceIDs: [german, WorkspaceID.legacy])
        for row in remote.server.words.values {
            known.words[row.id] = row.workspaceID
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, known: known, now: now))
        }
        for row in rows {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, now: now))
        }
    }

    func testRemoteWorkspacesSeedsNoLocalLinkState() {
        let defaults = UserDefaults(suiteName: "UITestSupportTests.remoteWorkspaces")!
        defaults.removePersistentDomain(forName: "UITestSupportTests.remoteWorkspaces")
        let repository = UserDefaultsSyncStateRepository(defaults: defaults)
        UITestSyncState.remoteWorkspaces.seedState(into: repository, now: now)
        XCTAssertNil(repository.load().linkedAccountID)
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
        XCTAssertNotNil(remote.membership(wordID: most.id, folderID: UITestSyncState.cloudFolderID, userID: owner),
                        "the cloud word sits in the cloud folder through a membership row")
        // Every seeded row passes the validator that real pulls use.
        var known = KnownRemoteIDs(workspaceIDs: [WorkspaceID.legacy])
        for row in remote.server.words.values { known.words[row.id] = row.workspaceID }
        known.folders[UITestSyncState.cloudFolderID] = WorkspaceID.legacy
        for row in remote.server.words.values {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, known: known, now: now))
        }
        for row in remote.server.workspaces.values {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, now: now))
        }
        for row in remote.server.memberships.values {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(row, ownerID: owner, known: known, now: now))
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

    func testStubIsKeyedByTheTargetLanguage() {
        XCTAssertEqual(UITestTranslationStub.translate("дом", from: .russian, to: .german), "das Haus")
        XCTAssertEqual(UITestTranslationStub.translate("учить", from: .russian, to: .german), "lernen")
        XCTAssertEqual(UITestTranslationStub.translate("dom", from: .polish, to: .english), "house")
        XCTAssertEqual(UITestTranslationStub.translate("house", from: .english, to: .polish), "dom")
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
                       "the fixture seeds its single workspace")
        XCTAssertEqual(resources.workspaces.activeID, WorkspaceID.legacy)
        XCTAssertEqual(resources.vocabulary.workspace?.id, WorkspaceID.legacy)
        XCTAssertEqual(resources.folders.workspaceID, WorkspaceID.legacy)
    }

    func testFreshInstallResourcesHaveNoWorkspaceSoTheGateShowsTheWizard() throws {
        let resources = try AppResources.uiTest(
            UITestLaunchConfiguration(fixture: .freshInstall, prefill: nil), now: now)
        XCTAssertTrue(resources.workspaces.options.isEmpty)
        XCTAssertNil(resources.workspaces.activeID)
        XCTAssertEqual(try resources.container.mainContext.fetch(FetchDescriptor<Workspace>()).count, 0)
    }

    func testMultiWorkspaceResourcesStartOnPolish() throws {
        let resources = try AppResources.uiTest(
            UITestLaunchConfiguration(fixture: .multiWorkspace, prefill: nil), now: now)
        XCTAssertEqual(resources.workspaces.options.map(\.termCode), ["pl", "de"])
        XCTAssertEqual(resources.workspaces.activeID, WorkspaceID.legacy)
    }
}
#endif
