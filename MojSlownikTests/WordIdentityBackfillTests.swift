import XCTest
import SwiftData
@testable import MojSlownik

@MainActor
final class WordIdentityBackfillTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testNilUUIDsAreFilledDistinctAndOtherFieldsUnchanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let updated = t0.addingTimeInterval(5)
        for index in 0..<3 {
            let word = Word(russian: "в\(index)", polish: "w\(index)", sourceLanguage: .polish,
                            createdAt: t0.addingTimeInterval(Double(index)))
            word.uuid = nil
            word.updatedAt = index == 0 ? nil : updated
            word.repetitions = 4
            context.insert(word)
        }
        try context.save()

        XCTAssertEqual(WordIdentityBackfill.run(container: container), 3)

        let words = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(Set(words.compactMap(\.uuid)).count, 3)
        for word in words {
            XCTAssertEqual(word.repetitions, 4)
            XCTAssertNil(word.deletedAt)
            XCTAssertEqual(word.updatedAt, word.polish == "w0" ? nil : updated)
        }
    }

    func testExistingUUIDsAreKeptAndSecondRunReturnsZero() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let kept = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0)
        let keptID = try XCTUnwrap(kept.uuid)
        let missing = Word(russian: "к", polish: "k", sourceLanguage: .polish, createdAt: t0)
        missing.uuid = nil
        context.insert(kept)
        context.insert(missing)
        try context.save()

        XCTAssertEqual(WordIdentityBackfill.run(container: container), 1)
        XCTAssertEqual(WordIdentityBackfill.run(container: container), 0)
        let words = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(words.first { $0.polish == "w" }?.uuid, keptID)
        XCTAssertNotNil(words.first { $0.polish == "k" }?.uuid)
    }

    func testDuplicateUUIDsAreResolvedDeterministicallyEarliestKeeps() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shared = UUID()
        func word(_ polish: String, _ offset: Double) -> Word {
            let word = Word(russian: "в", polish: polish, sourceLanguage: .polish,
                            createdAt: t0.addingTimeInterval(offset))
            word.uuid = shared
            return word
        }
        [word("late", 20), word("early", 0), word("mid", 10), word("b", 30), word("a", 30)].forEach(context.insert)
        try context.save()

        XCTAssertEqual(WordIdentityBackfill.run(container: container), 4)

        let words = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(words.first { $0.polish == "early" }?.uuid, shared)
        XCTAssertEqual(Set(words.compactMap(\.uuid)).count, 5)
    }

    func testTieOnCreatedAtIsBrokenByPolishText() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let shared = UUID()
        for polish in ["b", "a"] {
            let word = Word(russian: "в", polish: polish, sourceLanguage: .polish, createdAt: t0)
            word.uuid = shared
            context.insert(word)
        }
        try context.save()
        _ = WordIdentityBackfill.run(container: container)
        let words = try ModelContext(container).fetch(FetchDescriptor<Word>())
        XCTAssertEqual(words.first { $0.polish == "a" }?.uuid, shared)
        XCTAssertNotEqual(words.first { $0.polish == "b" }?.uuid, shared)
    }

    func testRollbackFalseKeepsUnrelatedPendingEdits() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let legacy = Word(russian: "в", polish: "w", sourceLanguage: .polish, createdAt: t0)
        legacy.uuid = nil
        context.insert(legacy)
        try context.save()
        let pending = Word(russian: "к", polish: "k", sourceLanguage: .polish, createdAt: t0.addingTimeInterval(1))
        context.insert(pending)
        legacy.repetitions = 9

        XCTAssertEqual(try WordIdentityBackfill.assignMissing(in: context, rollbackOnFailure: false), 1)

        XCTAssertNotNil(legacy.uuid)
        XCTAssertEqual(legacy.repetitions, 9)
        XCTAssertEqual(pending.polish, "k")
        XCTAssertEqual(try ModelContext(container).fetch(FetchDescriptor<Word>()).count, 2)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Word.self, WordFolder.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
