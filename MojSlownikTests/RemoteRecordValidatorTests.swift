import XCTest
@testable import MojSlownik

final class RemoteRecordValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let owner = UUID()
    private let folderA = UUID()
    private let folderB = UUID()

    private func word(id: UUID = UUID(), userID: UUID? = nil, term: String = "kot", termLanguage: String = "pl",
                      translation: String = "кот", translationLanguage: String = "ru", entered: String = "ru",
                      category: String = "other", folderIDs: [UUID] = [],
                      createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil,
                      easeFactor: Double = 2.5, intervalDays: Double = 1, repetitions: Int = 1,
                      dueDate: Date? = nil, grade: String? = "good", tier: Int? = 2,
                      softMisses: Int = 0) -> RemoteWordRecord {
        RemoteWordRecord(id: id, userID: userID ?? owner, term: term, termLanguage: termLanguage,
                         translation: translation, translationLanguage: translationLanguage,
                         enteredLanguage: entered, category: category, folderIDs: folderIDs,
                         createdAt: createdAt ?? now.addingTimeInterval(-3_600),
                         updatedAt: updatedAt ?? now.addingTimeInterval(-60), deletedAt: deletedAt,
                         easeFactor: easeFactor, intervalDays: intervalDays, repetitions: repetitions,
                         dueDate: dueDate ?? now.addingTimeInterval(86_400), lastReviewGrade: grade,
                         knowledgeTier: tier, consecutiveSoftMisses: softMisses)
    }

    private func validate(_ record: RemoteWordRecord) throws -> ValidatedRemoteWord {
        try RemoteRecordValidator.validate(record, ownerID: owner, knownFolderIDs: [folderA, folderB], now: now)
    }

    private func assertRejects(_ record: RemoteWordRecord, _ expected: RemoteRecordError,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try validate(record), file: file, line: line) { error in
            XCTAssertEqual(error as? RemoteRecordError, expected, file: file, line: line)
        }
    }

    // MARK: Words

    func testAcceptsValidWordAndTrimsText() throws {
        let result = try validate(word(term: " kot", translation: "  кот \n"))
        XCTAssertEqual(result.term, "kot")
        XCTAssertEqual(result.termLanguage, .polish)
        XCTAssertEqual(result.translation, "кот")
        XCTAssertEqual(result.translationLanguage, .russian)
        XCTAssertEqual(result.enteredLanguage, .russian)
        XCTAssertEqual(result.lastReviewGrade, .good)
        XCTAssertEqual(result.knowledgeTier, 2)
    }

    func testRejectsNilUUID() {
        assertRejects(word(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), .invalidID)
    }

    func testRejectsRowOwnedByAnotherUser() {
        assertRejects(word(userID: UUID()), .foreignOwner)
    }

    func testRejectsEmptyOverlongOrControlCharacterText() {
        assertRejects(word(translation: "   "), .invalidText)
        assertRejects(word(term: String(repeating: "a", count: RemoteRecordValidator.maxTextLength + 1)), .invalidText)
        assertRejects(word(term: "ko\u{0}t"), .invalidText)
        assertRejects(word(translation: "к\u{1B}[31mот"), .invalidText)
    }

    /// Review finding: only Cc control characters are rejected; format characters are text.
    func testAcceptsFormatCharacters() throws {
        XCTAssertEqual(try validate(word(term: "przy\u{00AD}jaciel")).term, "przy\u{00AD}jaciel")
        XCTAssertNoThrow(try validate(word(translation: "семья 👨\u{200D}👩\u{200D}👧")))
        XCTAssertNoThrow(try validate(word(translation: "\u{200F}кот")))
        assertRejects(word(term: "ko\u{7}t"), .invalidText)
    }

    func testRejectsMalformedLanguagePair() {
        assertRejects(word(termLanguage: "Polish"), .invalidLanguage)
        assertRejects(word(translationLanguage: ""), .invalidLanguage)
        assertRejects(word(termLanguage: "ru", translationLanguage: "ru"), .invalidLanguage)
        assertRejects(word(entered: "en"), .invalidLanguage)
        // `$` would also match before a trailing newline; the pattern is anchored with `\z`.
        assertRejects(word(termLanguage: "pl\n"), .invalidLanguage)
    }

    /// A pair from a newer app version (e.g. German–English) is skipped, not treated as corrupt.
    func testWellFormedButUnsupportedPairIsSkipped() {
        assertRejects(word(term: "Haus", termLanguage: "de", translation: "house", translationLanguage: "en",
                           entered: "de"), .unsupportedLanguage)
        assertRejects(word(termLanguage: "pt-BR", entered: "ru"), .unsupportedLanguage)
    }

    func testEnteredLanguageMayBeEitherSide() throws {
        XCTAssertEqual(try validate(word(entered: "pl")).enteredLanguage, .polish)
    }

    func testCategoryUsesStableID() throws {
        XCTAssertEqual(try validate(word(category: "food")).category, .food)
        assertRejects(word(category: "Hacked"), .invalidCategory)
        assertRejects(word(category: WordCategory.food.rawValue), .invalidCategory)
        assertRejects(word(category: ""), .invalidCategory)
        assertRejects(word(category: "food\n"), .invalidCategory)
    }

    /// Review finding: the validator rejected schedules SRSEngine itself produces.
    func testEveryLocalScheduleIsAccepted() throws {
        let local = Word(russian: "кот", polish: "kot", sourceLanguage: .russian)
        for _ in 0..<80 { SRSEngine.apply(.easy, to: local, now: now) }
        let validated = try validate(word(easeFactor: local.easeFactor, intervalDays: local.intervalDays,
                                          repetitions: local.repetitions, dueDate: local.dueDate, grade: "easy"))
        XCTAssertEqual(validated.intervalDays, SRSEngine.maxIntervalDays)
    }

    /// Review finding: a category added by a newer version used to become `.other`, which this
    /// client would later write back over the newer client's value (last write wins).
    func testFutureCategoryIsSkippedNotMappedToOther() {
        assertRejects(word(category: "sport"), .unsupportedCategory)
    }

    /// Review finding: ids are persisted on the server and must never drift with case names.
    func testCategoryStableIDsArePinned() {
        XCTAssertEqual(WordCategory.allCases.map(\.stableID),
                       ["food", "home", "travel", "nature", "people", "work", "health", "other"])
    }

    func testCategoryStableIDsRoundTrip() {
        for category in WordCategory.allCases {
            XCTAssertEqual(WordCategory(stableID: category.stableID), category)
            XCTAssertNotNil(category.stableID.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression),
                            "matches the server CHECK on words.category")
        }
    }

    /// Review finding: folders may arrive after their words; membership must not be dropped.
    func testFolderIDsAreDedupedAndUnknownOnesKept() throws {
        let unknown = UUID()
        let result = try validate(word(folderIDs: [folderB, unknown, folderA, folderB]))
        XCTAssertEqual(result.folderIDs, [folderB, unknown, folderA])
        XCTAssertEqual(result.unknownFolderIDs, [unknown])
    }

    /// Review finding: server `updated_at` ahead of a slow device clock is still valid.
    func testServerTimestampAheadOfSlowDeviceClockIsAccepted() throws {
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(10 * 60))))
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(6 * 60 * 60))))
        assertRejects(word(updatedAt: now.addingTimeInterval(2 * 24 * 60 * 60)), .invalidDate)
    }

    func testRejectsTooManyFolderIDs() {
        let ids = (0...RemoteRecordValidator.maxFolderIDs).map { _ in UUID() }
        assertRejects(word(folderIDs: ids), .tooManyFolders)
    }

    func testRejectsImplausibleDates() {
        let future = now.addingTimeInterval(RemoteRecordValidator.allowedClockSkew + 1)
        assertRejects(word(createdAt: future, updatedAt: future), .invalidDate)
        assertRejects(word(updatedAt: future), .invalidDate)
        assertRejects(word(deletedAt: future), .invalidDate)
        assertRejects(word(createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 1)), .invalidDate)
    }

    /// Review finding: created_at (device clock) may be later than updated_at (server default).
    func testTimestampOrderIsNotRequired() throws {
        XCTAssertNoThrow(try validate(word(createdAt: now.addingTimeInterval(-60), updatedAt: now.addingTimeInterval(-120))))
        XCTAssertNoThrow(try validate(word(deletedAt: now.addingTimeInterval(-7_200))))
    }

    func testAcceptsTimestampsWithinClockSkew() throws {
        let slightlyAhead = now.addingTimeInterval(RemoteRecordValidator.allowedClockSkew - 1)
        XCTAssertNoThrow(try validate(word(createdAt: now.addingTimeInterval(-60), updatedAt: slightlyAhead,
                                           deletedAt: slightlyAhead)))
    }

    func testRejectsInvalidSchedule() {
        assertRejects(word(easeFactor: SRSEngine.maxEaseFactor + 0.01), .invalidSchedule)
        assertRejects(word(intervalDays: SRSEngine.maxIntervalDays + 1), .invalidSchedule)
        assertRejects(word(easeFactor: 1.2), .invalidSchedule)
        assertRejects(word(easeFactor: .nan), .invalidSchedule)
        assertRejects(word(easeFactor: .infinity), .invalidSchedule)
        assertRejects(word(intervalDays: -1), .invalidSchedule)
        assertRejects(word(intervalDays: .nan), .invalidSchedule)
        assertRejects(word(repetitions: -1), .invalidSchedule)
        assertRejects(word(dueDate: Date(timeIntervalSince1970: 0)), .invalidSchedule)
        assertRejects(word(dueDate: now.addingTimeInterval(200 * 365 * 86_400)), .invalidSchedule)
        assertRejects(word(grade: "perfect"), .invalidSchedule)
        assertRejects(word(tier: 4), .invalidSchedule)
        assertRejects(word(tier: -1), .invalidSchedule)
        assertRejects(word(softMisses: -1), .invalidSchedule)
    }

    func testAcceptsMissingOptionalScheduleFields() throws {
        let result = try validate(word(grade: nil, tier: nil))
        XCTAssertNil(result.lastReviewGrade)
        XCTAssertNil(result.knowledgeTier)
    }

    // MARK: Folders

    private func folder(id: UUID = UUID(), userID: UUID? = nil, name: String = "Еда",
                        createdAt: Date? = nil, updatedAt: Date? = nil,
                        deletedAt: Date? = nil) -> RemoteFolderRecord {
        RemoteFolderRecord(id: id, userID: userID ?? owner, name: name, sortOrder: 3,
                           createdAt: createdAt ?? now.addingTimeInterval(-3_600),
                           updatedAt: updatedAt ?? now.addingTimeInterval(-60), deletedAt: deletedAt)
    }

    func testAcceptsValidFolder() throws {
        let result = try RemoteRecordValidator.validate(folder(name: " Еда "), ownerID: owner, now: now)
        XCTAssertEqual(result.name, "Еда")
        XCTAssertEqual(result.sortOrder, 3)
    }

    func testRejectsInvalidFolders() {
        let cases: [(RemoteFolderRecord, RemoteRecordError)] = [
            (folder(userID: UUID()), .foreignOwner),
            (folder(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), .invalidID),
            (folder(name: ""), .invalidText),
            (folder(name: String(repeating: "x", count: RemoteRecordValidator.maxFolderNameLength + 1)), .invalidText),
            (folder(updatedAt: now.addingTimeInterval(2 * 24 * 3_600)), .invalidDate),
        ]
        for (record, expected) in cases {
            XCTAssertThrowsError(try RemoteRecordValidator.validate(record, ownerID: owner, now: now)) { error in
                XCTAssertEqual(error as? RemoteRecordError, expected)
            }
        }
    }

    // MARK: Decoding (PostgREST's decoder and wire format)

    func testDecodesPostgRESTWordRow() throws {
        let json = """
        [{"id":"8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69","user_id":"\(owner.uuidString.lowercased())",
          "term":"kot","term_language":"pl","translation":"кот","translation_language":"ru",
          "entered_language":"ru","category":"other",
          "folder_ids":["\(folderA.uuidString.lowercased())"],
          "created_at":"2026-11-17T22:49:18.123456+00:00","updated_at":"2026-11-17T22:50:00+00:00",
          "deleted_at":null,"ease_factor":2.5,"interval_days":1,"repetitions":1,
          "due_date":"2026-11-18T22:49:18.123456+00:00","last_review_grade":"good",
          "knowledge_tier":2,"consecutive_soft_misses":0}]
        """
        let rows = try RemoteRecordDecoder.words(from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].userID, owner)
        XCTAssertEqual(rows[0].folderIDs, [folderA])
        XCTAssertNil(rows[0].deletedAt)
        XCTAssertEqual(rows[0].createdAt.timeIntervalSince1970, 1_794_955_758.123, accuracy: 0.001)
    }

    func testDecodesPostgRESTFolderRow() throws {
        let json = """
        [{"id":"8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69","user_id":"\(owner.uuidString)","name":"Еда",
          "sort_order":2,"created_at":"2026-11-17T22:49:18+00:00","updated_at":"2026-11-17T22:49:18+00:00",
          "deleted_at":"2026-11-17T23:00:00+00:00"}]
        """
        let rows = try RemoteRecordDecoder.folders(from: Data(json.utf8))
        XCTAssertEqual(rows.first?.sortOrder, 2)
        XCTAssertNotNil(rows.first?.deletedAt)
    }

    func testRejectsRowWithMissingColumns() {
        XCTAssertThrowsError(try RemoteRecordDecoder.words(from: Data(#"[{"id":"x"}]"#.utf8)))
    }
}
