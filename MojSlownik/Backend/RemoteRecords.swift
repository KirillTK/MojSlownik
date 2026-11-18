import Foundation
import Supabase

// Rows of public.words / public.folders (supabase/migrations) as they arrive from the server.
// Server data is untrusted: decode into these DTOs, then validate before anything touches
// SwiftData. Nothing downloads them yet; the future sync engine is the only intended caller.

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

        // A due date is set at review time, which is at or before `now` (+ allowed clock skew).
        let latestDueDate = now.addingTimeInterval(maxIntervalDays * 86_400 + allowedClockSkew)
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
        guard !trimmed.isEmpty, trimmed.count <= maxLength,
              // Cc only: format characters (soft hyphen, ZWJ, RLM) are legitimate text.
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw RemoteRecordError.invalidText
        }
        return trimmed
    }

    private static func validateTimestamps(createdAt: Date, updatedAt: Date, deletedAt: Date?,
                                           now: Date) throws {
        // Each timestamp is only bounds-checked: created_at comes from a device clock while
        // updated_at may be the server default, so their order is not meaningful (Gap B).
        let latest = now.addingTimeInterval(allowedClockSkew)
        let plausible = { (date: Date) in date >= earliestDate && date <= latest }
        guard plausible(createdAt), plausible(updatedAt), deletedAt.map(plausible) ?? true else {
            throw RemoteRecordError.invalidDate
        }
    }
}
