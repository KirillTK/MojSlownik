import Foundation
import Supabase

// Rows of public.words / public.folders (supabase/migrations) as they arrive from the server.
// Server data is untrusted: decode into these DTOs, then validate before anything touches
// SwiftData. SyncEngine (via SupabaseSyncRemote) is the caller; the Upsert DTOs below are the
// outgoing rows, which are validated with the same rules before they are sent.

/// Decodes with PostgREST's own decoder (the one `execute().value` uses), so the DTOs are
/// tested against the server's real timestamp format.
enum RemoteRecordDecoder {
    static func workspaces(from data: Data) throws -> [RemoteWorkspaceRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteWorkspaceRecord].self, from: data)
    }

    static func memberships(from data: Data) throws -> [RemoteMembershipRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteMembershipRecord].self, from: data)
    }

    static func words(from data: Data) throws -> [RemoteWordRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteWordRecord].self, from: data)
    }

    static func folders(from data: Data) throws -> [RemoteFolderRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteFolderRecord].self, from: data)
    }
}

/// A workspace (language pair). Its id is the uuid v5 of `term_language>translation_language`.
struct RemoteWorkspaceRecord: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let termLanguage: String
    let translationLanguage: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case termLanguage = "term_language"
        case translationLanguage = "translation_language"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

/// A word: `term` in the studied language of its workspace and its `translation`. `enteredSide` is
/// the side the user typed (`term` or `translation`); the languages live in the workspace.
struct RemoteWordRecord: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let workspaceID: UUID
    let term: String
    let translation: String
    let enteredSide: String
    /// Stable category id (`WordCategory.stableID`), not the localized title.
    let category: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let easeFactor: Double
    let intervalDays: Double
    let repetitions: Int
    let dueDate: Date
    let lastReviewGrade: String?
    let knowledgeTier: Int?
    let consecutiveSoftMisses: Int

    enum CodingKeys: String, CodingKey {
        case id, term, translation, category, repetitions
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case enteredSide = "entered_side"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case easeFactor = "ease_factor"
        case intervalDays = "interval_days"
        case dueDate = "due_date"
        case lastReviewGrade = "last_review_grade"
        case knowledgeTier = "knowledge_tier"
        case consecutiveSoftMisses = "consecutive_soft_misses"
    }
}

/// A word <-> folder membership (`word_folders`); keyed by `(word_id, folder_id)`.
struct RemoteMembershipRecord: Decodable, Equatable, Sendable {
    let userID: UUID
    let workspaceID: UUID
    let wordID: UUID
    let folderID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case wordID = "word_id"
        case folderID = "folder_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

struct RemoteFolderRecord: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let workspaceID: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

/// A workspace that passed validation.
struct ValidatedRemoteWorkspace: Equatable, Sendable {
    let id: UUID
    let termLanguage: String
    let translationLanguage: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

/// A word that passed validation; only this type may feed a merge into SwiftData.
struct ValidatedRemoteWord: Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let term: String
    let translation: String
    let enteredSide: WordSide
    let category: WordCategory
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let easeFactor: Double
    let intervalDays: Double
    let repetitions: Int
    let dueDate: Date
    let lastReviewGrade: ReviewGrade?
    let knowledgeTier: Int?
    let consecutiveSoftMisses: Int
}

struct ValidatedRemoteFolder: Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct ValidatedRemoteMembership: Equatable, Sendable {
    let workspaceID: UUID
    let wordID: UUID
    let folderID: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    /// The client-only identity (`MembershipID`): held ids, acks, de-duplication.
    var id: UUID { MembershipID.make(wordID: wordID, folderID: folderID) }
}

/// What the device knows when a pulled row is validated: ids of the local rows in any state with
/// the workspace each belongs to. Rows skipped (held) this cycle are not in the sets.
struct KnownRemoteIDs: Equatable, Sendable {
    var workspaceIDs: Set<UUID> = []
    /// word uuid -> workspace id
    var words: [UUID: UUID] = [:]
    /// folder id -> workspace id
    var folders: [UUID: UUID] = [:]
}

enum RemoteRecordError: Error, Equatable {
    case invalidID
    case foreignOwner
    case invalidText
    case invalidLanguage
    /// Well-formed pair this app version cannot show yet (a future language): skip, keep locally.
    case unsupportedLanguage
    /// Not the server's category id shape.
    case invalidCategory
    /// Well-formed category id added by a newer app version: skip, keep locally. Mapping it to
    /// `.other` would let this client write `other` back over the newer client's category.
    case unsupportedCategory
    /// The workspace is not known on this device (yet): held until it arrives.
    case unknownWorkspace
    /// `entered_side` is neither `term` nor `translation`.
    case invalidSide
    /// A membership whose word or folder is not known in that workspace.
    case unknownReference
    case invalidDate
    case invalidSchedule
}

/// Validates untrusted server rows. Mirrors the server CHECK constraints and adds the checks
/// only the client can do (owner, known folders, clock plausibility).
enum RemoteRecordValidator {
    static let maxTextLength = 500
    static let maxFolderNameLength = 200
    /// Tolerated device/server clock difference for "not in the future" checks. `updated_at` is
    /// often server time, so a slow device clock must not reject fresh rows; a day still stops
    /// far-future timestamps that would win last-write-wins forever (server time: Gap B).
    static let allowedClockSkew: TimeInterval = 24 * 60 * 60
    /// Earliest plausible timestamp (2020-01-01T00:00:00Z); the app did not exist before.
    static let earliestDate = Date(timeIntervalSince1970: 1_577_836_800)
    // Same bounds as SRSEngine, so every locally produced schedule passes.
    static let maxIntervalDays = SRSEngine.maxIntervalDays
    static let maxEaseFactor = SRSEngine.maxEaseFactor

    static func validate(_ record: RemoteWorkspaceRecord, ownerID: UUID, now: Date) throws -> ValidatedRemoteWorkspace {
        try validateIdentity(id: record.id, userID: record.userID, ownerID: ownerID)
        guard isLanguageCode(record.termLanguage), isLanguageCode(record.translationLanguage),
              record.termLanguage != record.translationLanguage else {
            throw RemoteRecordError.invalidLanguage
        }
        guard record.id == WorkspaceID.make(term: record.termLanguage, translation: record.translationLanguage) else {
            throw RemoteRecordError.invalidID
        }
        guard LanguageCodes.isSupported(record.termLanguage), LanguageCodes.isSupported(record.translationLanguage) else {
            throw RemoteRecordError.unsupportedLanguage
        }
        try validateTimestamps(createdAt: record.createdAt, updatedAt: record.updatedAt,
                               deletedAt: record.deletedAt, now: now)
        return ValidatedRemoteWorkspace(id: record.id, termLanguage: record.termLanguage,
                                        translationLanguage: record.translationLanguage,
                                        sortOrder: record.sortOrder, createdAt: record.createdAt,
                                        updatedAt: record.updatedAt, deletedAt: record.deletedAt)
    }

    static func validate(_ record: RemoteWordRecord, ownerID: UUID, known: KnownRemoteIDs,
                         now: Date) throws -> ValidatedRemoteWord {
        try validateIdentity(id: record.id, userID: record.userID, ownerID: ownerID)
        let term = try validText(record.term, maxLength: maxTextLength)
        let translation = try validText(record.translation, maxLength: maxTextLength)
        guard known.workspaceIDs.contains(record.workspaceID) else { throw RemoteRecordError.unknownWorkspace }
        guard let enteredSide = WordSide(rawValue: record.enteredSide) else { throw RemoteRecordError.invalidSide }
        try validateTimestamps(createdAt: record.createdAt, updatedAt: record.updatedAt,
                               deletedAt: record.deletedAt, now: now)

        // A due date is set at review time, which is at or before `max(now, updatedAt)`
        // (+ allowed clock skew): `updated_at` is server time, so a slow device clock must not
        // reject fresh rows from other devices.
        let latestDueDate = max(now, record.updatedAt)
            .addingTimeInterval(maxIntervalDays * 86_400 + allowedClockSkew)
        guard record.easeFactor.isFinite, (SRSEngine.minEaseFactor...maxEaseFactor).contains(record.easeFactor),
              record.intervalDays.isFinite, (0...maxIntervalDays).contains(record.intervalDays),
              record.repetitions >= 0, record.consecutiveSoftMisses >= 0,
              record.dueDate >= earliestDate, record.dueDate <= latestDueDate else {
            throw RemoteRecordError.invalidSchedule
        }
        let tierRange = KnowledgeProgressService.minimumTier...KnowledgeProgressService.maximumTier
        if let tier = record.knowledgeTier, !tierRange.contains(tier) {
            throw RemoteRecordError.invalidSchedule
        }
        var grade: ReviewGrade?
        if let rawGrade = record.lastReviewGrade {
            guard let parsed = ReviewGrade(rawValue: rawGrade) else { throw RemoteRecordError.invalidSchedule }
            grade = parsed
        }

        guard isCategoryID(record.category) else { throw RemoteRecordError.invalidCategory }
        guard let category = WordCategory(stableID: record.category) else {
            throw RemoteRecordError.unsupportedCategory
        }

        return ValidatedRemoteWord(
            id: record.id, workspaceID: record.workspaceID, term: term, translation: translation,
            enteredSide: enteredSide, category: category,
            createdAt: record.createdAt, updatedAt: record.updatedAt, deletedAt: record.deletedAt,
            easeFactor: record.easeFactor, intervalDays: record.intervalDays,
            repetitions: record.repetitions, dueDate: record.dueDate, lastReviewGrade: grade,
            knowledgeTier: record.knowledgeTier, consecutiveSoftMisses: record.consecutiveSoftMisses)
    }

    static func validate(_ record: RemoteFolderRecord, ownerID: UUID, known: KnownRemoteIDs,
                         now: Date) throws -> ValidatedRemoteFolder {
        try validateIdentity(id: record.id, userID: record.userID, ownerID: ownerID)
        let name = try validText(record.name, maxLength: maxFolderNameLength)
        guard known.workspaceIDs.contains(record.workspaceID) else { throw RemoteRecordError.unknownWorkspace }
        try validateTimestamps(createdAt: record.createdAt, updatedAt: record.updatedAt,
                               deletedAt: record.deletedAt, now: now)
        return ValidatedRemoteFolder(id: record.id, workspaceID: record.workspaceID, name: name,
                                     sortOrder: record.sortOrder, createdAt: record.createdAt,
                                     updatedAt: record.updatedAt, deletedAt: record.deletedAt)
    }

    /// The word and the folder must be known on this device, both in the membership's workspace.
    static func validate(_ record: RemoteMembershipRecord, ownerID: UUID, known: KnownRemoteIDs,
                         now: Date) throws -> ValidatedRemoteMembership {
        guard record.userID == ownerID else { throw RemoteRecordError.foreignOwner }
        guard record.wordID != nilUUID, record.folderID != nilUUID, record.workspaceID != nilUUID else {
            throw RemoteRecordError.invalidID
        }
        try validateTimestamps(createdAt: record.createdAt, updatedAt: record.updatedAt,
                               deletedAt: record.deletedAt, now: now)
        guard known.words[record.wordID] == record.workspaceID,
              known.folders[record.folderID] == record.workspaceID else {
            throw RemoteRecordError.unknownReference
        }
        return ValidatedRemoteMembership(workspaceID: record.workspaceID, wordID: record.wordID,
                                         folderID: record.folderID, createdAt: record.createdAt,
                                         updatedAt: record.updatedAt, deletedAt: record.deletedAt)
    }

    /// Same shape as the server CHECK: BCP 47 language with up to three subtags.
    static func isLanguageCode(_ code: String) -> Bool {
        matches(languageCodePattern, code)
    }

    /// Same shape as the server CHECK on words.category.
    static func isCategoryID(_ id: String) -> Bool {
        matches(categoryIDPattern, id)
    }

    // Compiled once: a sync validates three codes per row.
    private static let languageCodePattern = try! NSRegularExpression(pattern: #"^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}\z"#)
    private static let categoryIDPattern = try! NSRegularExpression(pattern: #"^[a-z][a-z0-9_]{0,31}\z"#)

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }

    private static let nilUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private static func validateIdentity(id: UUID, userID: UUID, ownerID: UUID) throws {
        guard id != nilUUID else { throw RemoteRecordError.invalidID }
        // RLS should make this impossible; a mismatch means the response is not trustworthy.
        guard userID == ownerID else { throw RemoteRecordError.foreignOwner }
    }

    private static func validText(_ text: String, maxLength: Int) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unicode scalars, like the server's char_length on a UTF-8 database (graphemes would
        // let combining-mark text through that the server CHECK rejects).
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= maxLength,
              // Cc only: format characters (soft hyphen, ZWJ, RLM) are legitimate text, and
              // interior tab/newline are allowed because the add-word fields are multiline.
              !trimmed.unicodeScalars.contains(where: isDisallowedControl) else {
            throw RemoteRecordError.invalidText
        }
        return trimmed
    }

    private static func isDisallowedControl(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.generalCategory == .control else { return false }
        return scalar != "\t" && scalar != "\n" && scalar != "\r"
    }

    private static func validateTimestamps(createdAt: Date, updatedAt: Date, deletedAt: Date?,
                                           now: Date) throws {
        // `updated_at` is server-assigned: only a lower bound, no device-clock upper bound (a
        // slow device clock would otherwise skip other devices' fresh rows forever). The
        // device-written timestamps are bounded relative to `max(now, updatedAt)`.
        let latest = max(now, updatedAt).addingTimeInterval(allowedClockSkew)
        let plausible = { (date: Date) in date >= earliestDate && date <= latest }
        guard updatedAt >= earliestDate, plausible(createdAt), deletedAt.map(plausible) ?? true else {
            throw RemoteRecordError.invalidDate
        }
    }
}

/// Outgoing `public.workspaces` row. Never contains `updated_at` (the server assigns it). Every key
/// is encoded, with an explicit `null` where empty: supabase-swift sends `columns=` as the union
/// of the rows' keys, and an omitted `deleted_at` would never clear a server tombstone.
struct RemoteWorkspaceUpsert: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let termLanguage: String
    let translationLanguage: String
    let sortOrder: Int
    let createdAt: Date
    let deletedAt: Date?

    static let selectColumns = "id,user_id,term_language,translation_language,sort_order,created_at,"
        + "updated_at,deleted_at"

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case termLanguage = "term_language"
        case translationLanguage = "translation_language"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(termLanguage, forKey: .termLanguage)
        try container.encode(translationLanguage, forKey: .translationLanguage)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

/// Outgoing `public.words` row; same every-key rule as `RemoteWorkspaceUpsert`. No legacy columns.
struct RemoteWordUpsert: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let workspaceID: UUID
    let term: String
    let translation: String
    let enteredSide: String
    let category: String
    let createdAt: Date
    let deletedAt: Date?
    let easeFactor: Double
    let intervalDays: Double
    let repetitions: Int
    let dueDate: Date
    let lastReviewGrade: String?
    let knowledgeTier: Int?
    let consecutiveSoftMisses: Int

    static let selectColumns = "id,user_id,workspace_id,term,translation,entered_side,category,created_at,"
        + "updated_at,deleted_at,ease_factor,interval_days,repetitions,due_date,last_review_grade,"
        + "knowledge_tier,consecutive_soft_misses"

    enum CodingKeys: String, CodingKey {
        case id, term, translation, category, repetitions
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case enteredSide = "entered_side"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
        case easeFactor = "ease_factor"
        case intervalDays = "interval_days"
        case dueDate = "due_date"
        case lastReviewGrade = "last_review_grade"
        case knowledgeTier = "knowledge_tier"
        case consecutiveSoftMisses = "consecutive_soft_misses"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(term, forKey: .term)
        try container.encode(translation, forKey: .translation)
        try container.encode(enteredSide, forKey: .enteredSide)
        try container.encode(category, forKey: .category)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(easeFactor, forKey: .easeFactor)
        try container.encode(intervalDays, forKey: .intervalDays)
        try container.encode(repetitions, forKey: .repetitions)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(lastReviewGrade, forKey: .lastReviewGrade)
        try container.encode(knowledgeTier, forKey: .knowledgeTier)
        try container.encode(consecutiveSoftMisses, forKey: .consecutiveSoftMisses)
    }
}

/// Outgoing `public.folders` row; same every-key rule as `RemoteWorkspaceUpsert`.
struct RemoteFolderUpsert: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let workspaceID: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let deletedAt: Date?

    static let selectColumns = "id,user_id,workspace_id,name,sort_order,created_at,updated_at,deleted_at"

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(name, forKey: .name)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}

/// Outgoing `public.word_folders` row; same every-key rule as `RemoteWorkspaceUpsert`.
struct RemoteMembershipUpsert: Encodable, Equatable, Sendable {
    let userID: UUID
    let workspaceID: UUID
    let wordID: UUID
    let folderID: UUID
    let createdAt: Date
    let deletedAt: Date?

    static let selectColumns = "user_id,workspace_id,word_id,folder_id,created_at,updated_at,deleted_at"

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case workspaceID = "workspace_id"
        case wordID = "word_id"
        case folderID = "folder_id"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(wordID, forKey: .wordID)
        try container.encode(folderID, forKey: .folderID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}
