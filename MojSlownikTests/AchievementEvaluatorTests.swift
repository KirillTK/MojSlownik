import XCTest
import SwiftData
@testable import MojSlownik

final class AchievementEvaluatorTests: XCTestCase {
    private func def(_ id: String, _ criterion: AchievementCriterion) -> AchievementDefinition {
        AchievementDefinition(id: id, category: .vocabulary, title: id, detail: id, symbol: "star",
                              points: 1, criterion: criterion)
    }

    func testCatalogIsValid() {
        let all = AchievementCatalog.all
        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(all.count, 15)
        XCTAssertEqual(all.reduce(0) { $0 + $1.points }, 240)
        for item in all {
            XCTAssertGreaterThan(item.points, 0)
            XCTAssertFalse(item.category.title.isEmpty)
            switch item.criterion {
            case .threshold(_, let target): XCTAssertGreaterThan(target, 0)
            case .allOf(let required):
                XCTAssertFalse(required.isEmpty)
                XCTAssertFalse(required.contains(item.id))
                for id in required { XCTAssertNotNil(AchievementCatalog.definition(id: id)) }
            }
        }
    }

    func testThresholdUnlocksAtExactlyTarget() {
        let catalog = [def("a", .threshold(.wordCount, 5))]
        let below = AchievementMetrics([.wordCount: 4])
        let exact = AchievementMetrics([.wordCount: 5])
        XCTAssertEqual(AchievementEvaluator.newlyUnlocked(catalog: catalog, metrics: below, unlocked: []), [])
        XCTAssertEqual(AchievementEvaluator.newlyUnlocked(catalog: catalog, metrics: exact, unlocked: []), ["a"])
        XCTAssertEqual(AchievementEvaluator.newlyUnlocked(catalog: catalog, metrics: exact, unlocked: ["a"]), [])
    }

    func testMetaUnlocksWithLastRequirementInSameCall() {
        let catalog = [def("a", .threshold(.wordCount, 1)), def("b", .threshold(.folderCount, 1)),
                       def("m", .allOf(["a", "b"]))]
        let partial = AchievementEvaluator.newlyUnlocked(
            catalog: catalog, metrics: AchievementMetrics([.wordCount: 1]), unlocked: [])
        XCTAssertEqual(partial, ["a"])
        let last = AchievementEvaluator.newlyUnlocked(
            catalog: catalog, metrics: AchievementMetrics([.wordCount: 1, .folderCount: 1]), unlocked: ["a"])
        XCTAssertEqual(last, ["b", "m"])
    }

    func testMetaWithUnknownOrSelfIDNeverUnlocks() {
        let catalog = [def("a", .threshold(.wordCount, 1)), def("m", .allOf(["a", "missing"])),
                       def("s", .allOf(["s"]))]
        let result = AchievementEvaluator.newlyUnlocked(
            catalog: catalog, metrics: AchievementMetrics([.wordCount: 1]), unlocked: [])
        XCTAssertEqual(result, ["a"])
    }

    func testChainedMetaResolvesInOneCall() {
        let catalog = [def("outer", .allOf(["inner"])), def("inner", .allOf(["a"])),
                       def("a", .threshold(.wordCount, 1))]
        let result = AchievementEvaluator.newlyUnlocked(
            catalog: catalog, metrics: AchievementMetrics([.wordCount: 1]), unlocked: [])
        XCTAssertEqual(Set(result), ["a", "inner", "outer"])
        XCTAssertEqual(result.count, 3)
    }

    func testProgress() {
        let threshold = def("a", .threshold(.wordCount, 10))
        let meta = def("m", .allOf(["a", "b", "c"]))
        let date = Date(timeIntervalSince1970: 1)
        var progress = AchievementEvaluator.progress(for: threshold, metrics: AchievementMetrics([.wordCount: 99]),
                                                     unlocked: [:])
        XCTAssertEqual(progress.current, 10)
        XCTAssertEqual(progress.fraction, 1)
        progress = AchievementEvaluator.progress(for: threshold, metrics: AchievementMetrics([.wordCount: 3]),
                                                 unlocked: [:])
        XCTAssertEqual(progress.current, 3)
        XCTAssertEqual(progress.fraction, 0.3, accuracy: 0.0001)
        progress = AchievementEvaluator.progress(for: threshold, metrics: AchievementMetrics(), unlocked: ["a": date])
        XCTAssertEqual(progress, AchievementProgress(current: 10, target: 10, isUnlocked: true, unlockedAt: date))
        progress = AchievementEvaluator.progress(for: meta, metrics: AchievementMetrics(), unlocked: ["a": date, "b": date])
        XCTAssertEqual(progress.current, 2)
        XCTAssertEqual(progress.target, 3)
        XCTAssertFalse(progress.isUnlocked)
        XCTAssertEqual(AchievementProgress(current: 0, target: 0, isUnlocked: false, unlockedAt: nil).fraction, 0)
    }

    @MainActor
    func testVocabularyMetrics() throws {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        _ = container
        let empty = AchievementMetrics.vocabulary(words: [], folderCount: 0)
        for metric in AchievementMetric.allCases { XCTAssertEqual(empty[metric], 0) }

        let a = Word(russian: "a", polish: "a", side: .translation, category: .food)
        let b = Word(russian: "b", polish: "b", side: .translation, category: .food)
        let c = Word(russian: "c", polish: "c", side: .translation, category: .home)
        let d = Word(russian: "d", polish: "d", side: .translation, category: .other)
        a.repetitions = 2
        b.repetitions = 3
        c.knowledgeTier = KnowledgeProgressService.maximumTier
        c.intervalDays = 31.5
        d.lastReviewGradeRawValue = ReviewGrade.easy.rawValue
        a.knowledgeTier = 1
        b.knowledgeTier = 1
        let metrics = AchievementMetrics.vocabulary(words: [a, b, c, d], folderCount: 2)
        XCTAssertEqual(metrics[.wordCount], 4)
        XCTAssertEqual(metrics[.folderCount], 2)
        XCTAssertEqual(metrics[.categoriesCovered], 2)
        XCTAssertEqual(metrics[.learnedWords], 1)
        XCTAssertEqual(metrics[.masteredWords], 2)
        XCTAssertEqual(metrics[.maxIntervalDays], 31)
    }
}
