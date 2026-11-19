import Foundation
import Supabase

// Rows of public.words / public.folders (supabase/migrations) as they arrive from the server.
// Server data is untrusted: decode into these DTOs, then validate before anything touches
// SwiftData. SyncEngine (via SupabaseSyncRemote) is the caller; the Upsert DTOs below are the
// outgoing rows, which are validated with the same rules before they are sent.

/// Decodes with PostgREST's own decoder (the one `execute().value` uses), so the DTOs are
/// tested against the server's real timestamp format.
enum RemoteRecordDecoder {
    static func words(from data: Data) throws -> [RemoteWordRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteWordRecord].self, from: data)
    }

    static func folders(from data: Data) throws -> [RemoteFolderRecord] {
        try PostgrestClient.Configuration.jsonDecoder.decode([RemoteFolderRecord].self, from: data)
    }
}

/// A word is a language-neutral pair: `term` in the studied language and its `translation`,
/// each with a BCP 47 code. `enteredLanguage` is the side the user typed (one of the pair).
struct RemoteWordRecord: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let term: String
    let termLanguage: String
    let translation: String
    let translationLanguage: String
    let enteredLanguage: String
    /// Stable category id (`WordCategory.stableID`), not the localized title.
    let category: String
    let folderIDs: [UUID]
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
        case termLanguage = "term_language"
        case translationLanguage = "translation_language"
        case enteredLanguage = "entered_language"
        case folderIDs = "folder_ids"
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

struct RemoteFolderRecord: Decodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }
}

/// A word that passed validation; only this type may feed a merge into SwiftData.
struct ValidatedRemoteWord: Equatable, Sendable {
    let id: UUID
    let term: String
    let termLanguage: AppLanguage
    let translation: String
    let translationLanguage: AppLanguage
    let enteredLanguage: AppLanguage
    let category: WordCategory
    /// Deduplicated; may include folders that have not reached this device yet.
    let folderIDs: [UUID]
    /// Members of `folderIDs` the device does not know yet (folders may arrive later). The merge
    /// keeps them; dropping them would erase membership on the next push.
    let unknownFolderIDs: Set<UUID>
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
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
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
    case tooManyFolders
    case invalidDate
    case invalidSchedule
}

/// Validates untrusted server rows. Mirrors the server CHECK constraints and adds the checks
/// only the client can do (owner, known folders, clock plausibility).
enum RemoteRecordValidator {
    static let maxTextLength = 500
    static let maxFolderNameLength = 200
    static let maxFolderIDs = 500
    /// Tolerated device/server clock difference for "not in the future" checks. `updated_at` is
    /// often server time, so a slow device clock must not reject fresh rows; a day still stops
    /// far-future timestamps that would win last-write-wins forever (server time: Gap B).
    static let allowedClockSkew: TimeInterval = 24 * 60 * 60
    /// Earliest plausible timestamp (2020-01-01T00:00:00Z); the app did not exist before.
    static let earliestDate = Date(timeIntervalSince1970: 1_577_836_800)
    // Same bounds as SRSEngine, so every locally produced schedule passes.
    static let maxIntervalDays = SRSEngine.maxIntervalDays
    static let maxEaseFactor = SRSEngine.maxEaseFactor

    static func validate(_ record: RemoteWordRecord, ownerID: UUID, knownFolderIDs: Set<UUID>,
                         now: Date) throws -> ValidatedRemoteWord {
        try validateIdentity(id: record.id, userID: record.userID, ownerID: ownerID)
        let term = try validText(record.term, maxLength: maxTextLength)
        let translation = try validText(record.translation, maxLength: maxTextLength)
        guard isLanguageCode(record.termLanguage), isLanguageCode(record.translationLanguage),
              record.termLanguage != record.translationLanguage,
              [record.termLanguage, record.translationLanguage].contains(record.enteredLanguage) else {
            throw RemoteRecordError.invalidLanguage
        }
        guard let termLanguage = AppLanguage(rawValue: record.termLanguage),
              let translationLanguage = AppLanguage(rawValue: record.translationLanguage),
              let enteredLanguage = AppLanguage(rawValue: record.enteredLanguage) else {
            throw RemoteRecordError.unsupportedLanguage
        }
        guard record.folderIDs.count <= maxFolderIDs else { throw RemoteRecordError.tooManyFolders }
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

        var seen = Set<UUID>()
        let folderIDs = record.folderIDs.filter { seen.insert($0).inserted }

        return ValidatedRemoteWord(
            id: record.id, term: term, termLanguage: termLanguage, translation: translation,
            translationLanguage: translationLanguage, enteredLanguage: enteredLanguage,
            category: category, folderIDs: folderIDs,
            unknownFolderIDs: seen.subtracting(knownFolderIDs),
            createdAt: record.createdAt, updatedAt: record.updatedAt, deletedAt: record.deletedAt,
            easeFactor: record.easeFactor, intervalDays: record.intervalDays,
            repetitions: record.repetitions, dueDate: record.dueDate, lastReviewGrade: grade,
            knowledgeTier: record.knowledgeTier, consecutiveSoftMisses: record.consecutiveSoftMisses)
    }

    static func validate(_ record: RemoteFolderRecord, ownerID: UUID, now: Date) throws -> ValidatedRemoteFolder {
        try validateIdentity(id: record.id, userID: record.userID, ownerID: ownerID)
        let name = try validText(record.name, maxLength: maxFolderNameLength)
        try validateTimestamps(createdAt: record.createdAt, updatedAt: record.updatedAt,
                               deletedAt: record.deletedAt, now: now)
        return ValidatedRemoteFolder(id: record.id, name: name, sortOrder: record.sortOrder,
                                     createdAt: record.createdAt, updatedAt: record.updatedAt,
                                     deletedAt: record.deletedAt)
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

/// Outgoing `public.words` row. Never contains `updated_at` (the server assigns it). Every key
/// is encoded, with an explicit `null` where empty: supabase-swift sends `columns=` as the union
/// of the rows' keys, and an omitted `deleted_at` would never clear a server tombstone.
struct RemoteWordUpsert: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let term: String
    let termLanguage: String
    let translation: String
    let translationLanguage: String
    let enteredLanguage: String
    let category: String
    let folderIDs: [UUID]
    let createdAt: Date
    let deletedAt: Date?
    let easeFactor: Double
    let intervalDays: Double
    let repetitions: Int
    let dueDate: Date
    let lastReviewGrade: String?
    let knowledgeTier: Int?
    let consecutiveSoftMisses: Int

    static let selectColumns = "id,user_id,term,term_language,translation,translation_language,"
        + "entered_language,category,folder_ids,created_at,updated_at,deleted_at,ease_factor,"
        + "interval_days,repetitions,due_date,last_review_grade,knowledge_tier,consecutive_soft_misses"

    enum CodingKeys: String, CodingKey {
        case id, term, translation, category, repetitions
        case userID = "user_id"
        case termLanguage = "term_language"
        case translationLanguage = "translation_language"
        case enteredLanguage = "entered_language"
        case folderIDs = "folder_ids"
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
        try container.encode(term, forKey: .term)
        try container.encode(termLanguage, forKey: .termLanguage)
        try container.encode(translation, forKey: .translation)
        try container.encode(translationLanguage, forKey: .translationLanguage)
        try container.encode(enteredLanguage, forKey: .enteredLanguage)
        try container.encode(category, forKey: .category)
        try container.encode(folderIDs, forKey: .folderIDs)
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

/// Outgoing `public.folders` row; same every-key rule as `RemoteWordUpsert`.
struct RemoteFolderUpsert: Encodable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let name: String
    let sortOrder: Int
    let createdAt: Date
    let deletedAt: Date?

    static let selectColumns = "id,user_id,name,sort_order,created_at,updated_at,deleted_at"

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case deletedAt = "deleted_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(name, forKey: .name)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }
}
