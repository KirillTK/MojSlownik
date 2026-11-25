import SwiftData
import XCTest
@testable import MojSlownik

@MainActor
final class ScheduleNormalizerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86_400

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(for: AppSchema.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return (container, container.mainContext)
    }

    @discardableResult
    private func insert(_ context: ModelContext, interval: Double, due: Date, uuid: UUID? = nil,
                        reps: Int = 5) -> Word {
        let word = Word(russian: "кот", polish: "kot", side: .translation, createdAt: now.addingTimeInterval(-9 * day))
        word.repetitions = reps
        word.intervalDays = interval
        word.dueDate = due
        if let uuid { word.uuid = uuid }
        context.insert(word)
        return word
    }

    func testLongIntervalAndFarDueAreClampedToTheLastReviewPlusTheLibraryCap() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        // Reviewed 10 days ago with a 400-day interval: due in 390 days.
        let word = insert(context, interval: 400, due: now.addingTimeInterval(390 * day))
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 1)
        XCTAssertEqual(word.intervalDays, SRSEngine.maxLibraryIntervalDays)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(-10 * day + 32 * day))
    }

    func testAlreadyOverdueWordKeepsItsDueDate() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let due = now.addingTimeInterval(-5 * day)
        let word = insert(context, interval: 400, due: due)
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 1)
        XCTAssertEqual(word.intervalDays, 32)
        XCTAssertEqual(word.dueDate, due)
    }

    func testFutureDueMovedIntoThePastIsSpreadByTheUUIDOffset() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        // Reviewed 400 days ago with a 800-day interval: review + 30 d is long past.
        let id = UUID(uuid: (3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let word = insert(context, interval: 800, due: now.addingTimeInterval(400 * day), uuid: id)
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 1)
        XCTAssertEqual(word.dueDate, now.addingTimeInterval(3 * day))
        let offsets = (0...255).map { value -> TimeInterval in
            let uuid = UUID(uuid: (UInt8(value), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            let state = SRSState(easeFactor: 2.5, intervalDays: 800, repetitions: 5,
                                 dueDate: now.addingTimeInterval(400 * day), lastReviewGradeRawValue: nil, lapseCount: 0)
            return ScheduleNormalizer.normalized(state, uuid: uuid, now: now)!.dueDate.timeIntervalSince(now) / day
        }
        XCTAssertTrue(offsets.allSatisfy { (0...6).contains($0) })
    }

    func testSecondRunChangesNothing() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        insert(context, interval: 400, due: now.addingTimeInterval(390 * day))
        insert(context, interval: 800, due: now.addingTimeInterval(400 * day))
        insert(context, interval: 400, due: now.addingTimeInterval(-5 * day))
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 3)
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 0)
    }

    func testNormalizingNeverTouchesUpdatedAtOrServerStamp() throws {
        let (container, context) = try makeContext()
        let word = insert(context, interval: 400, due: now.addingTimeInterval(390 * day))
        let stamp = now.addingTimeInterval(-3_000)
        word.updatedAt = stamp
        word.serverUpdatedAt = stamp
        try context.save()
        XCTAssertFalse(word.isSyncDirty)

        XCTAssertEqual(ScheduleNormalizer.run(container: container, now: now), 1)

        let fresh = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Word>()).first)
        XCTAssertEqual(fresh.intervalDays, 32)
        XCTAssertEqual(fresh.updatedAt, stamp)
        XCTAssertEqual(fresh.serverUpdatedAt, stamp)
        XCTAssertFalse(fresh.isSyncDirty)
    }

    func testDeletedAndShortScheduleRowsAreUntouched() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let deleted = insert(context, interval: 400, due: now.addingTimeInterval(390 * day))
        deleted.markDeleted(now: now)
        let short = insert(context, interval: 30, due: now.addingTimeInterval(30 * day))
        let fresh = insert(context, interval: 0, due: now, reps: 0)
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 0)
        XCTAssertEqual(deleted.intervalDays, 400)
        XCTAssertEqual(short.intervalDays, 30)
        XCTAssertEqual(fresh.dueDate, now)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Word>()).count, 3, "no word is deleted")
    }

    func testNonFiniteScheduleFallsBackToTheCap() {
        let state = SRSState(easeFactor: 2.5, intervalDays: .infinity, repetitions: 5,
                             dueDate: now.addingTimeInterval(10 * day), lastReviewGradeRawValue: nil, lapseCount: 0)
        let fixed = ScheduleNormalizer.normalized(state, uuid: nil, now: now)
        XCTAssertEqual(fixed?.intervalDays, 32)
    }

    /// What FSRS produces with the 30-day setting (Good 31 d, Easy 32 d) is never shortened.
    func testPackageProducedThirtyOneAndThirtyTwoDaySchedulesAreLeftUntouched() throws {
        let (container, context) = try makeContext()
        defer { _ = container }
        let good = insert(context, interval: 31, due: now.addingTimeInterval(31 * day))
        let easy = insert(context, interval: 32, due: now.addingTimeInterval(32 * day))
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 0)
        XCTAssertEqual(good.intervalDays, 31)
        XCTAssertEqual(easy.intervalDays, 32)
        XCTAssertEqual(easy.dueDate, now.addingTimeInterval(32 * day))
        // One day past the library bound is clamped.
        let over = insert(context, interval: 33, due: now.addingTimeInterval(33 * day))
        XCTAssertEqual(try ScheduleNormalizer.normalize(in: context, now: now), 1)
        XCTAssertEqual(over.intervalDays, 32)
    }
}
