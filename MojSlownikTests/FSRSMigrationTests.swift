import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class FSRSMigrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func state(ease: Double = 2.5, interval: Double, repetitions: Int, due: Date? = nil,
                       grade: String? = "good", lapses: Int = 0) -> SRSState {
        SRSState(easeFactor: ease, intervalDays: interval, repetitions: repetitions, dueDate: due ?? now,
                 lastReviewGradeRawValue: grade, lapseCount: lapses)
    }

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    // MARK: derive

    func testNeverReviewedWordIsNew() {
        let memory = FSRSMigration.derive(from: state(interval: 0, repetitions: 0, grade: nil), now: now)
        XCTAssertEqual(memory, .new)
    }

    func testAgainResetWordIsLearningOrRelearningWithZeroMemory() {
        let reset = state(interval: 0, repetitions: 0, due: now.addingTimeInterval(300), grade: "again")
        let learning = FSRSMigration.derive(from: reset, now: now)
        XCTAssertEqual(learning.state, 1)
        XCTAssertEqual(learning.stability, 0)
        XCTAssertEqual(learning.difficulty, 0)
        XCTAssertEqual(learning.lastReviewedAt, now.addingTimeInterval(300 - 600))
        let lapsed = FSRSMigration.derive(from: state(interval: 0, repetitions: 0, grade: "again", lapses: 2), now: now)
        XCTAssertEqual(lapsed.state, 3)
        XCTAssertEqual(lapsed.lastReviewedAt, now.addingTimeInterval(-600), "never after now")
    }

    func testReviewWordGetsStabilityFromTheIntervalAndDifficultyFromTheEase() {
        let memory = FSRSMigration.derive(from: state(interval: 10, repetitions: 4, due: now), now: now)
        XCTAssertEqual(memory.state, 2)
        XCTAssertEqual(memory.stability, 10)
        XCTAssertEqual(memory.difficulty, 6.914, accuracy: 0.001)
        XCTAssertEqual(memory.lastReviewedAt, now.addingTimeInterval(-10 * day))
        let hardest = FSRSMigration.derive(from: state(ease: 1.3, interval: 1, repetitions: 1), now: now)
        XCTAssertEqual(hardest.difficulty, 10)
        let easiest = FSRSMigration.derive(from: state(ease: 10, interval: 30, repetitions: 4), now: now)
        XCTAssertEqual(easiest.difficulty, 1)
        // A future review date is never used: the last review is capped at now.
        let early = FSRSMigration.derive(from: state(interval: 3, repetitions: 2, due: now.addingTimeInterval(day)),
                                         now: now)
        XCTAssertEqual(early.lastReviewedAt, now.addingTimeInterval(day - 3 * day))
        let overdue = FSRSMigration.derive(from: state(interval: 3, repetitions: 2, due: now.addingTimeInterval(-day)),
                                           now: now)
        XCTAssertEqual(overdue.lastReviewedAt, now.addingTimeInterval(-4 * day))
    }

    func testDerivationCapsTheIntervalAndSurvivesNonFiniteValues() {
        XCTAssertEqual(FSRSMigration.derive(from: state(interval: 400, repetitions: 4), now: now).stability,
                       SRSEngine.maxLibraryIntervalDays)
        let weird = FSRSMigration.derive(from: state(ease: .nan, interval: .infinity, repetitions: 3), now: now)
        XCTAssertTrue(FSRSMigration.isValid(weird), "\(weird)")
        XCTAssertEqual(weird.stability, 1)
    }

    func testEveryDerivedMemoryIsValidAndDeterministic() {
        for interval in [0.0, 0.5, 1, 7, 30, 32, 400] {
            for ease in [1.3, 2.5, 4, 10] {
                for repetitions in [0, 1, 6] {
                    for grade in [nil, "again", "good"] as [String?] {
                        let input = state(ease: ease, interval: interval, repetitions: repetitions, grade: grade,
                                          lapses: repetitions)
                        let memory = FSRSMigration.derive(from: input, now: now)
                        XCTAssertTrue(FSRSMigration.isValid(memory), "\(input) -> \(memory)")
                        XCTAssertEqual(memory, FSRSMigration.derive(from: input, now: now))
                    }
                }
            }
        }
    }

    // MARK: isValid / effective / migrated

    func testIsValidBounds() {
        func memory(_ state: Int, _ stability: Double, _ difficulty: Double, step: Int = 0,
                    last: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> FSRSMemory {
            FSRSMemory(state: state, stability: stability, difficulty: difficulty, learningStep: step,
                       lastReviewedAt: last)
        }
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, 5, last: nil)), "review needs a last review")
        XCTAssertFalse(FSRSMigration.isValid(memory(1, 0, 0, last: nil)))
        XCTAssertFalse(FSRSMigration.isValid(memory(3, 2, 5, last: nil)))
        XCTAssertTrue(FSRSMigration.isValid(memory(0, 0, 0, last: nil)))
        XCTAssertTrue(FSRSMigration.isValid(.new))
        XCTAssertFalse(FSRSMigration.isValid(memory(0, 1, 5)))
        XCTAssertTrue(FSRSMigration.isValid(memory(1, 0, 0)))
        XCTAssertTrue(FSRSMigration.isValid(memory(3, 0, 0)))
        XCTAssertTrue(FSRSMigration.isValid(memory(3, 0.001, 1)))
        XCTAssertFalse(FSRSMigration.isValid(memory(1, 0.0001, 5)))
        XCTAssertTrue(FSRSMigration.isValid(memory(2, 0.001, 1)))
        XCTAssertTrue(FSRSMigration.isValid(memory(2, 36_500, 10)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 36_501, 5)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, 0.9)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, 10.1)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 0, 0)))
        XCTAssertFalse(FSRSMigration.isValid(memory(4, 5, 5)))
        XCTAssertFalse(FSRSMigration.isValid(memory(-1, 5, 5)))
        XCTAssertTrue(FSRSMigration.isValid(memory(2, 5, 5, step: 100)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, 5, step: 101)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, 5, step: -1)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, .nan, 5)))
        XCTAssertFalse(FSRSMigration.isValid(memory(2, 5, .infinity)))
    }

    func testMigratedFillsOnlyMissingOrInvalidBlocksAndIsIdempotent() throws {
        var input = state(interval: 5, repetitions: 2)
        let filled = try XCTUnwrap(FSRSMigration.migrated(input, now: now))
        XCTAssertEqual(filled.memory, FSRSMigration.derive(from: input, now: now))
        XCTAssertNil(FSRSMigration.migrated(filled, now: now))
        input = filled
        input.fsrsStability = -1
        XCTAssertNotNil(FSRSMigration.migrated(input, now: now), "an invalid block is re-derived")
        XCTAssertEqual(FSRSMigration.effective(input, now: now), FSRSMigration.derive(from: input, now: now))
        XCTAssertEqual(FSRSMigration.effective(filled, now: now), filled.memory)
    }

    // MARK: migrate(in:)

    private func insert(_ context: ModelContext, interval: Double, repetitions: Int, ease: Double = 2.5,
                        due: Date, grade: String? = "good", lapses: Int = 0) -> Word {
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: now.addingTimeInterval(-30 * day))
        word.intervalDays = interval
        word.repetitions = repetitions
        word.easeFactor = ease
        word.dueDate = due
        word.lastReviewGradeRawValue = grade
        word.lapseCount = lapses
        context.insert(word)
        return word
    }

    func testMigrateFillsActiveWordsWithoutChangingSM2FieldsOrDirtyingRows() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let stamp = now.addingTimeInterval(-3_000)
        let reviewed = insert(context, interval: 10, repetitions: 4, ease: 2.1, due: now.addingTimeInterval(2 * day),
                              lapses: 3)
        let fresh = insert(context, interval: 0, repetitions: 0, due: now, grade: nil)
        let deleted = insert(context, interval: 5, repetitions: 2, due: now)
        deleted.markDeleted(now: now)
        for word in [reviewed, fresh] {
            word.updatedAt = stamp
            word.serverUpdatedAt = stamp
        }
        try context.save()
        let before = [reviewed, fresh].map { SRSState(word: $0) }

        XCTAssertEqual(try FSRSMigration.migrate(in: context, now: now), 2)

        for (word, original) in zip([reviewed, fresh], before) {
            let after = SRSState(word: word)
            XCTAssertEqual(after.easeFactor, original.easeFactor)
            XCTAssertEqual(after.intervalDays, original.intervalDays)
            XCTAssertEqual(after.repetitions, original.repetitions)
            XCTAssertEqual(after.dueDate, original.dueDate, "no due date moves")
            XCTAssertEqual(after.lapseCount, original.lapseCount)
            XCTAssertEqual(after.lastReviewGradeRawValue, original.lastReviewGradeRawValue)
            XCTAssertTrue(try XCTUnwrap(after.memory.map(FSRSMigration.isValid)))
            XCTAssertEqual(word.updatedAt, stamp)
            XCTAssertEqual(word.serverUpdatedAt, stamp)
            XCTAssertFalse(word.isSyncDirty)
        }
        XCTAssertEqual(reviewed.fsrsStateRawValue, 2)
        XCTAssertEqual(fresh.fsrsStateRawValue, 0)
        XCTAssertNil(deleted.fsrsStateRawValue, "deleted words are untouched")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Word>()).count, 3, "no word is deleted")
        XCTAssertEqual(try FSRSMigration.migrate(in: context, now: now), 0, "a second run changes nothing")
    }

    func testRunReturnsTheChangedCountAndTwoDevicesDeriveTheSameMemory() throws {
        let (container, context) = try makeContext()
        let word = insert(context, interval: 8, repetitions: 3, due: now.addingTimeInterval(day))
        try context.save()
        XCTAssertEqual(FSRSMigration.run(container: container, now: now), 1)
        let fresh = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(SRSState(word: fresh).memory,
                       FSRSMigration.derive(from: SRSState(word: word), now: now))
        XCTAssertEqual(FSRSMigration.run(container: container, now: now), 0)
    }

    func testNormalizerThenConversionKeepsAShortenedScheduleConsistent() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let word = insert(context, interval: 400, repetitions: 5, due: now.addingTimeInterval(390 * day))
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 1)
        XCTAssertEqual(try FSRSMigration.migrate(in: context, now: now), 1)
        XCTAssertEqual(word.intervalDays, SRSEngine.maxLibraryIntervalDays)
        XCTAssertEqual(word.fsrsStability, SRSEngine.maxLibraryIntervalDays)
        XCTAssertLessThanOrEqual(try XCTUnwrap(word.fsrsLastReviewedAt), now)
    }
}
