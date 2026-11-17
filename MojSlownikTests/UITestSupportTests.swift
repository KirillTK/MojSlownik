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
        let container = try ModelContainer(for: Word.self, WordFolder.self,
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
                       ["empty", "basicVocabulary", "dueForReview", "foldersOrdered"])
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
    }
}
#endif
