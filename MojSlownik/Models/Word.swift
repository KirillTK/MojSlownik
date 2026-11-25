import Foundation
import SwiftData

@Model
final class Word {
    // Storage names predate workspaces and stay (no migration): `polish` is the studied side
    // (term), `russian` the translation side, `sourceLanguageCode` the language of the entered
    // side. Read and write them through `term`/`translation`.
    var russian: String
    var polish: String
    var sourceLanguageCode: String
    var categoryRawValue: String = "Другое" // l10n:data
    // Frozen legacy storage: memberships live in FolderMembership. Never written after the
    // memberships migration (`legacyFolderIDsMigrated`); read only by WorkspaceBackfill.
    var folderIDs: [UUID] = []
    var legacyFolderIDsMigrated: Bool = false
    var createdAt: Date
    // stable cross-store identity; optional for additive migration; backfilled at launch
    var uuid: UUID? = nil
    var updatedAt: Date? = nil
    var deletedAt: Date? = nil
    // server updated_at of the last synced version; nil = never synced to the linked account;
    // .distantPast = re-link sentinel
    var serverUpdatedAt: Date? = nil
    // nil = a row from before workspaces; reads treat it as the legacy pl ← ru workspace
    var workspaceID: UUID? = nil

    // FSRS state + fields the app still reads (see SRSEngine)
    /// Legacy SM-2, no longer written; read by the FSRS conversion and the KnowledgeProgressService
    /// tier fallback.
    var easeFactor: Double
    var intervalDays: Double
    var repetitions: Int
    var dueDate: Date
    var lastReviewGradeRawValue: String? = nil
    var knowledgeTier: Int? = nil
    var consecutiveSoftMisses: Int = 0
    /// Failures after a success; see the SRSEngine lapse rule.
    var lapseCount: Int = 0
    /// FSRS card state (0 new, 1 learning, 2 review, 3 relearning); nil until derived or reviewed.
    var fsrsStateRawValue: Int? = nil
    var fsrsStability: Double? = nil
    var fsrsDifficulty: Double? = nil
    var fsrsLearningStep: Int = 0
    var fsrsLastReviewedAt: Date? = nil

    /// A word entered on `entry.enteredSide` of `pair`; texts are stored in each side's stored form.
    init(entry: WordEntry, pair: LanguagePair, workspaceID: UUID?, createdAt: Date = .now,
         category: WordCategory? = nil) {
        self.russian = pair.translation.storedForm(entry.translation)
        self.polish = pair.term.storedForm(entry.term)
        self.sourceLanguageCode = pair.language(of: entry.enteredSide).code
        self.workspaceID = workspaceID
        self.categoryRawValue = (category ?? WordCategory.detect(term: entry.term, translation: entry.translation)).rawValue
        self.createdAt = createdAt
        self.uuid = UUID()
        self.updatedAt = createdAt
        self.easeFactor = 2.5
        self.intervalDays = 0
        self.repetitions = 0
        self.dueDate = createdAt
    }
}

extension Word {
    var category: WordCategory {
        get { WordCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    /// Trim, NFC, lowercase: the comparison form shared by duplicate checks and sync adoption.
    static func normalizedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping.lowercased()
    }

    func matches(_ entry: WordEntry) -> Bool {
        Word.normalizedText(term) == Word.normalizedText(entry.term)
            && Word.normalizedText(translation) == Word.normalizedText(entry.translation)
    }

    /// Studied side (stored in `polish`).
    var term: String {
        get { polish }
        set { polish = newValue }
    }

    /// Translation side (stored in `russian`).
    var translation: String {
        get { russian }
        set { russian = newValue }
    }

    func text(on side: WordSide) -> String {
        side == .term ? term : translation
    }

    var effectiveWorkspaceID: UUID { workspaceID ?? WorkspaceID.legacy }

    /// The side the word was entered on, from the stored language code.
    func enteredSide(in workspace: WorkspaceContext) -> WordSide {
        sourceLanguageCode == workspace.translationCode && sourceLanguageCode != workspace.termCode
            ? .translation : .term
    }

    /// Normalized (polish, russian) pair, used to adopt a server duplicate during sync.
    var syncPairKey: String { Word.normalizedText(polish) + "\u{1F}" + Word.normalizedText(russian) }

    var isActive: Bool { deletedAt == nil }
    var lastModifiedAt: Date { updatedAt ?? createdAt }
    /// Changed since the last sync: equality, never ordering (the device clock may move back).
    var isSyncDirty: Bool { serverUpdatedAt != lastModifiedAt }

    func markDeleted(now: Date) {
        deletedAt = now
        updatedAt = now
    }

    var isDue: Bool { dueDate <= .now }
}
