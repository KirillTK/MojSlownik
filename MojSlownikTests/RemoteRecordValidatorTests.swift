import XCTest
@testable import MojSlownik

final class RemoteRecordValidatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let owner = UUID()
    private let folderA = UUID()
    private let folderB = UUID()

    private let workspace = WorkspaceID.legacy
    private var known: KnownRemoteIDs { KnownRemoteIDs(workspaceIDs: [workspace, WorkspaceID.make(term: "de", translation: "ru")]) }

    private func word(id: UUID = UUID(), userID: UUID? = nil, workspaceID: UUID? = nil, term: String = "kot",
                      translation: String = "кот", entered: String = "translation",
                      category: String = "other",
                      createdAt: Date? = nil, updatedAt: Date? = nil, deletedAt: Date? = nil,
                      easeFactor: Double = 2.5, intervalDays: Double = 1, repetitions: Int = 1,
                      dueDate: Date? = nil, grade: String? = "good", tier: Int? = 2,
                      softMisses: Int = 0) -> RemoteWordRecord {
        RemoteWordRecord(id: id, userID: userID ?? owner, workspaceID: workspaceID ?? workspace, term: term,
                         translation: translation, enteredSide: entered, category: category,
                         createdAt: createdAt ?? now.addingTimeInterval(-3_600),
                         updatedAt: updatedAt ?? now.addingTimeInterval(-60), deletedAt: deletedAt,
                         easeFactor: easeFactor, intervalDays: intervalDays, repetitions: repetitions,
                         dueDate: dueDate ?? now.addingTimeInterval(86_400), lastReviewGrade: grade,
                         knowledgeTier: tier, consecutiveSoftMisses: softMisses)
    }

    private func validate(_ record: RemoteWordRecord) throws -> ValidatedRemoteWord {
        try RemoteRecordValidator.validate(record, ownerID: owner, known: known, now: now)
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
        XCTAssertEqual(result.translation, "кот")
        XCTAssertEqual(result.workspaceID, workspace)
        XCTAssertEqual(result.enteredSide, .translation)
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

    func testUnknownWorkspaceIsHeld() {
        assertRejects(word(workspaceID: UUID()), .unknownWorkspace)
    }

    func testEnteredSideMustBeTermOrTranslation() throws {
        XCTAssertEqual(try validate(word(entered: "term")).enteredSide, .term)
        assertRejects(word(entered: "pl"), .invalidSide)
        assertRejects(word(entered: ""), .invalidSide)
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

    /// Review finding: server `updated_at` ahead of a slow device clock is still valid.
    func testServerTimestampAheadOfSlowDeviceClockIsAccepted() throws {
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(10 * 60))))
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(6 * 60 * 60))))
        // `updated_at` is server time: no device-clock upper bound at all.
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(2 * 24 * 60 * 60))))
        XCTAssertNoThrow(try validate(word(updatedAt: now.addingTimeInterval(400 * 24 * 60 * 60))))
    }

    /// Interior tab/newline/CR are text (the add-word fields are multiline); other controls are not.
    func testInteriorWhitespaceControlsAreAccepted() throws {
        XCTAssertEqual(try validate(word(term: "ko\nt\tx\r\ny")).term, "ko\nt\tx\r\ny")
        XCTAssertEqual(try validate(word(translation: " \n кот\nдом \n")).translation, "кот\nдом")
        assertRejects(word(term: "ko\u{0}t"), .invalidText)
        assertRejects(word(term: "ko\u{1B}t"), .invalidText)
        assertRejects(word(term: "ko\u{85}t"), .invalidText)
    }

    /// The server counts char_length in Unicode scalars; graphemes would let this through.
    func testTextLengthCountsUnicodeScalars() throws {
        let max = RemoteRecordValidator.maxTextLength
        XCTAssertNoThrow(try validate(word(term: String(repeating: "a", count: max))))
        assertRejects(word(term: String(repeating: "a", count: max + 1)), .invalidText)
        // "e" + combining acute = 1 grapheme, 2 scalars: 300 graphemes are 600 scalars.
        let combining = String(repeating: "e\u{301}", count: 300)
        XCTAssertEqual(combining.count, 300)
        assertRejects(word(translation: combining), .invalidText)
        XCTAssertNoThrow(try validate(word(translation: String(repeating: "e\u{301}", count: 250))))
        assertRejects(word(translation: String(repeating: "e\u{301}", count: 251)), .invalidText)
    }

    func testCreatedAtAheadOfNowIsBoundedByUpdatedAt() throws {
        let updated = now.addingTimeInterval(3 * 24 * 3_600)
        let skew = RemoteRecordValidator.allowedClockSkew
        XCTAssertNoThrow(try validate(word(createdAt: now.addingTimeInterval(3_600), updatedAt: now.addingTimeInterval(60))))
        XCTAssertNoThrow(try validate(word(createdAt: updated.addingTimeInterval(skew), updatedAt: updated)))
        assertRejects(word(createdAt: updated.addingTimeInterval(skew + 1), updatedAt: updated), .invalidDate)
        assertRejects(word(updatedAt: updated, deletedAt: updated.addingTimeInterval(skew + 1)), .invalidDate)
        // A slow device clock: a row updated "in the future" may carry a due date relative to it.
        let due = updated.addingTimeInterval(SRSEngine.maxIntervalDays * 86_400)
        XCTAssertNoThrow(try validate(word(updatedAt: updated, dueDate: due)))
    }

    func testUpdatedAtBeforeEarliestDateIsRejected() {
        assertRejects(word(createdAt: now.addingTimeInterval(-3_600),
                           updatedAt: RemoteRecordValidator.earliestDate.addingTimeInterval(-1)), .invalidDate)
    }

    func testRejectsImplausibleDates() {
        let future = now.addingTimeInterval(RemoteRecordValidator.allowedClockSkew + 1)
        // created_at/deleted_at are bounded by max(now, updatedAt) + skew; updated_at has no upper bound.
        assertRejects(word(createdAt: future), .invalidDate)
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

    private func folder(id: UUID = UUID(), userID: UUID? = nil, workspaceID: UUID? = nil, name: String = "Еда",
                        createdAt: Date? = nil, updatedAt: Date? = nil,
                        deletedAt: Date? = nil) -> RemoteFolderRecord {
        RemoteFolderRecord(id: id, userID: userID ?? owner, workspaceID: workspaceID ?? workspace, name: name, sortOrder: 3,
                           createdAt: createdAt ?? now.addingTimeInterval(-3_600),
                           updatedAt: updatedAt ?? now.addingTimeInterval(-60), deletedAt: deletedAt)
    }

    func testAcceptsValidFolder() throws {
        let result = try RemoteRecordValidator.validate(folder(name: " Еда "), ownerID: owner, known: known, now: now)
        XCTAssertEqual(result.name, "Еда")
        XCTAssertEqual(result.sortOrder, 3)
    }

    func testRejectsInvalidFolders() {
        let cases: [(RemoteFolderRecord, RemoteRecordError)] = [
            (folder(userID: UUID()), .foreignOwner),
            (folder(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), .invalidID),
            (folder(name: ""), .invalidText),
            (folder(name: String(repeating: "x", count: RemoteRecordValidator.maxFolderNameLength + 1)), .invalidText),
            (folder(createdAt: now.addingTimeInterval(2 * 24 * 3_600)), .invalidDate),
            (folder(updatedAt: Date(timeIntervalSince1970: 1)), .invalidDate),
            (folder(workspaceID: UUID()), .unknownWorkspace),
        ]
        for (record, expected) in cases {
            XCTAssertThrowsError(try RemoteRecordValidator.validate(record, ownerID: owner, known: known, now: now)) { error in
                XCTAssertEqual(error as? RemoteRecordError, expected)
            }
        }
    }

    // MARK: Decoding (PostgREST's decoder and wire format)

    func testDecodesPostgRESTWordRow() throws {
        let json = """
        [{"id":"8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69","user_id":"\(owner.uuidString.lowercased())",
          "workspace_id":"\(workspace.uuidString.lowercased())",
          "term":"kot","translation":"кот","entered_side":"translation","category":"other",
          "created_at":"2026-11-17T22:49:18.123456+00:00","updated_at":"2026-11-17T22:50:00+00:00",
          "deleted_at":null,"ease_factor":2.5,"interval_days":1,"repetitions":1,
          "due_date":"2026-11-18T22:49:18.123456+00:00","last_review_grade":"good",
          "knowledge_tier":2,"consecutive_soft_misses":0}]
        """
        let rows = try RemoteRecordDecoder.words(from: Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].userID, owner)
        XCTAssertEqual(rows[0].workspaceID, workspace)
        XCTAssertEqual(rows[0].enteredSide, "translation")
        XCTAssertNil(rows[0].deletedAt)
        XCTAssertEqual(rows[0].createdAt.timeIntervalSince1970, 1_794_955_758.123, accuracy: 0.001)
    }

    func testDecodesPostgRESTFolderRow() throws {
        let json = """
        [{"id":"8C1D3A57-2E1B-4F0B-9B7A-1E2D3C4B5A69","user_id":"\(owner.uuidString)","workspace_id":"\(workspace.uuidString)","name":"Еда",
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

    // MARK: Workspaces

    private func workspaceRecord(term: String = "pl", translation: String = "ru", id: UUID? = nil,
                                 userID: UUID? = nil, deletedAt: Date? = nil) -> RemoteWorkspaceRecord {
        RemoteWorkspaceRecord(id: id ?? WorkspaceID.make(term: term, translation: translation),
                              userID: userID ?? owner, termLanguage: term, translationLanguage: translation,
                              sortOrder: 1, createdAt: now.addingTimeInterval(-3_600),
                              updatedAt: now.addingTimeInterval(-60), deletedAt: deletedAt)
    }

    private func assertRejects(_ record: RemoteWorkspaceRecord, _ expected: RemoteRecordError,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try RemoteRecordValidator.validate(record, ownerID: owner, now: now),
                             file: file, line: line) { error in
            XCTAssertEqual(error as? RemoteRecordError, expected, file: file, line: line)
        }
    }

    func testAcceptsWorkspaceWithDeterministicID() throws {
        let result = try RemoteRecordValidator.validate(workspaceRecord(term: "de", translation: "ru"),
                                                        ownerID: owner, now: now)
        XCTAssertEqual(result.id, UUID(uuidString: "f03536f4-02a8-515b-924f-f39a95de6a18"))
        XCTAssertEqual(result.termLanguage, "de")
        XCTAssertEqual(result.sortOrder, 1)
    }

    func testRejectsWorkspaceWithWrongIDOrOwnerOrLanguages() {
        assertRejects(workspaceRecord(id: UUID()), .invalidID)
        assertRejects(workspaceRecord(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!), .invalidID)
        assertRejects(workspaceRecord(userID: UUID()), .foreignOwner)
        assertRejects(workspaceRecord(term: "Polish"), .invalidLanguage)
        assertRejects(workspaceRecord(term: "ru", translation: "ru"), .invalidLanguage)
        assertRejects(workspaceRecord(term: "pl\n"), .invalidLanguage)
    }

    /// Well-formed codes outside the supported list are skipped (held), not treated as corrupt.
    func testWellFormedUnsupportedWorkspaceLanguageIsUnsupported() {
        assertRejects(workspaceRecord(term: "ja", translation: "ru"), .unsupportedLanguage)
        assertRejects(workspaceRecord(term: "pl", translation: "pt-BR"), .unsupportedLanguage)
    }

    func testAllSupportedLanguagesAreAcceptedInWorkspaces() throws {
        XCTAssertEqual(LanguageCodes.supported, ["pl", "ru", "uk", "en", "de", "fr", "es", "it", "cs", "pt"])
        for code in LanguageCodes.supported where code != "ru" {
            XCTAssertNoThrow(try RemoteRecordValidator.validate(workspaceRecord(term: code, translation: "ru"),
                                                                ownerID: owner, now: now))
        }
    }

    // MARK: Memberships

    private func membership(wordID: UUID, folderID: UUID, workspaceID: UUID? = nil, userID: UUID? = nil,
                            deletedAt: Date? = nil) -> RemoteMembershipRecord {
        RemoteMembershipRecord(userID: userID ?? owner, workspaceID: workspaceID ?? workspace, wordID: wordID,
                               folderID: folderID, createdAt: now.addingTimeInterval(-3_600),
                               updatedAt: now.addingTimeInterval(-60), deletedAt: deletedAt)
    }

    func testMembershipReferencesMustBeKnownInTheSameWorkspace() throws {
        let wordID = UUID()
        var ids = known
        ids.words[wordID] = workspace
        ids.folders[folderA] = workspace
        let valid = try RemoteRecordValidator.validate(membership(wordID: wordID, folderID: folderA),
                                                       ownerID: owner, known: ids, now: now)
        XCTAssertEqual(valid.id, MembershipID.make(wordID: wordID, folderID: folderA))

        func assertReference(_ record: RemoteMembershipRecord, _ expected: RemoteRecordError,
                             file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try RemoteRecordValidator.validate(record, ownerID: owner, known: ids, now: now),
                                 file: file, line: line) {
                XCTAssertEqual($0 as? RemoteRecordError, expected, file: file, line: line)
            }
        }
        assertReference(membership(wordID: UUID(), folderID: folderA), .unknownReference)
        assertReference(membership(wordID: wordID, folderID: folderB), .unknownReference)
        // Both known, but in another workspace than the membership claims.
        let deRu = WorkspaceID.make(term: "de", translation: "ru")
        assertReference(membership(wordID: wordID, folderID: folderA, workspaceID: deRu), .unknownReference)
        assertReference(membership(wordID: wordID, folderID: folderA, userID: UUID()), .foreignOwner)
        assertReference(membership(wordID: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                                   folderID: folderA), .invalidID)
    }
}
