# Backend abstraction prep (Supabase or another backend)

## Goal
Assess how ready the app is for a remote backend and prepare it. The work has three parts:
- (a) a data-access seam (repository protocols) for vocabulary, folders, achievements state and daily activity;
- (b) stable identity for words;
- (c) sync metadata: `updatedAt` plus soft-delete tombstones (`deletedAt`) on `Word` and `WordFolder`.

Add no networking, sync, auth or SDK. The only concrete implementations are SwiftData (vocabulary, folders) and UserDefaults (achievements, daily activity). User-visible behavior stays the same.

Target architecture: **offline-first** (D1). Local SwiftData is the source of truth and views read it (`@Query`, filtered in memory). All vocabulary and folder writes go through repository protocols that the stores own and the app root injects. A later sync engine pushes and pulls rows by `uuid`/`id`, `updatedAt` and `deletedAt`. The protocols stay synchronous and `@MainActor`.

## Decisions (2026-11-17, user)
- **D1 Offline-first**: local SwiftData is the truth. Repositories are synchronous and `@MainActor`. `@Query` reads stay.
- **D2 Add now**: optional `updatedAt: Date?` and `deletedAt: Date?` on `Word` and `WordFolder`, which makes every delete a soft delete. Every read excludes tombstones, and every repository write and every SRS review write bumps `updatedAt`.
- **D3 Abstract now**: protocols plus UserDefaults-backed implementations for achievements state (`achievements.v1`) and daily activity (`dailyStudyActivity.v1`). Keys and encoded format stay unchanged. They are injected at the app root and tested with in-memory fakes.
- **D4 `Word.uuid` with backfill.** `WordFolder` already has a stable identity. `var id: UUID = UUID()` has existed since the entity's first commit (4db7e79), so every row got a per-instance UUID at insert. There was no migration-time shared default, so it needs no backfill.
- **D5 Later**: SRS writes stay in `DailyStudyStore` and are not routed through the repository. They do set `updatedAt` (item 11).
- **O1 New row**: re-adding a pair whose only match is a soft-deleted word always **inserts a new row** with a new `uuid`, and the tombstone stays untouched. Duplicate detection (add, toggle, changeCategory) considers active rows only. Repeated scan-chip taps (add → remove → add …) leave one tombstone per removal. This is an accepted risk: there is no purge until the sync design (Gap C).
- **O2**: legacy `updatedAt` stays nil and is read as `createdAt` (`lastModifiedAt`).
- **O3**: soft-deleting a folder removes its id from every word's `folderIDs` (today's behavior).

Decisions derived in this plan (binding for the implementer):
- **Tombstone filtering is in memory, not `#Predicate`.** Use `words.filter(\.isActive)`, as AGENTS.md requires for due words. Reasons:
  1. It keeps one consistent filtering style.
  2. Optional-value comparisons in `#Predicate` have had iOS 17.x runtime issues, and this app has a history of SwiftData startup crashes (`daily-progress-startup-crash` plan). Avoid new predicate surface.
  3. Vocabulary is personal-scale, so the cost is negligible.
  4. Helpers (`FolderStore.words`, `AchievementMetrics.vocabulary`, `DailyStudyStore`) can filter too, which makes the exclusion unit-testable.
- **Legacy `updatedAt`**: no backfill. `nil` means "never modified since creation", and `lastModifiedAt = updatedAt ?? createdAt`. This avoids fabricating timestamps and avoids an extra write pass. New rows set `updatedAt = createdAt` at init.
- **Re-adding after delete** follows O1. The new row gets a fresh `uuid`, `createdAt = now`, default SRS and `updatedAt = createdAt`, exactly like today's insert. It also gets a new `persistentModelID`, so `DailyStudyStore` entries recorded for the deleted row (keyed by the old PersistentIdentifier) never attach to the new word, and the tombstone is excluded by the `isActive` filter. Daily progress for the re-added word therefore starts clean, as it did with hard deletes.
- **Folders follow the same rule.** Creating a folder whose name matches only a soft-deleted folder creates a new row with a new `id`. Its memberships were already removed at deletion (O3).
- **Folder soft delete** sets the folder's `deletedAt` and `updatedAt`. It still strips the folder id from every word's `folderIDs` and bumps those words' `updatedAt`, as today's behavior does. It never touches a word's `deletedAt`, so words are never deleted.
- **`updatedAt` bump rule**: set `updatedAt = now` on a row **if and only if a persisted field of that row changed** in the write. On save failure, restore the previous `updatedAt` together with the other restored fields. Paths that already use `context.rollback()` restore it automatically. Identity backfill (`uuid`) does **not** bump, because it is not a user change. **Deliberate exception:** `DailyStudyStore.review` and `recordPracticeAnswer` set `updatedAt = now` **unconditionally**. Every answer is a user change to SRS or knowledge state, the code does not compare fields there, and an unconditional bump keeps the rollback path simple.
- **Name clash**: `PersistentModel` already declares `isDeleted`. The new computed flag is named `isActive` (`deletedAt == nil`) on both models.

## Constraints (user instructions, verbatim)
- "Подготовить абстракции к supabase инфре или другому бекенду - готово ли приложение к этому - подмерж в ветку редизайн изменения с main"
- The merge of main into the redesign branch has already been done (d593a09). It is out of scope here.
- User decisions above (D1–D5), verbatim intent: D2 "ADD NOW — optional updatedAt/deletedAt on Word and WordFolder … Deletes in the repositories become soft deletes; every @Query and every in-memory read … must exclude deletedAt != nil … Removing folders must still never delete words." D3 "ABSTRACT NOW … keys and encoded format unchanged so existing progress is preserved; injected at app root."
- Orchestrator guidance: add no backend, sync, auth or SDK. Behavior stays identical. Schema changes are optional only, and no stored word is ever lost. Add unit tests with an in-memory ModelContainer plus fakes.
- AGENTS.md: persistence and business logic stay in Stores/ and Services/. FolderLibraryStore is injected once at the app root. Removing folders or memberships never deletes words. New persisted properties are optional or defaulted. Due words are filtered in memory. Never create or run UI tests.

## Readiness assessment

### Audit (HEAD d593a09) and status after this task
| Area | Current state | Backend impact | After this task |
| --- | --- | --- | --- |
| Reads (`@Query`) | `Word` in WordListView, TrainingView, AchievementsView, ScannerView (`ScanResultView.savedWords`), FlashcardsView, QuizView, ListeningPracticeView, AchievementTracker. `WordFolder` in AchievementsView, AchievementTracker. No `#Predicate`. | Fine for offline-first, because sync writes into the same container. | Kept. All of them read through an `isActive` filter. |
| Reads (folder catalog) | `FolderLibraryStore.options` is a manual cache, refreshed on `FolderPicker.onAppear` (FolderPicker.swift:47, :281-286) and after the store's own writes. | Changes applied by sync stay stale. | Excludes tombstones. **The change signal is still open (Gap A).** |
| Writes from views | Static `ScanWordStore`/`FolderStore` calls with context or container, plus a direct `word.category = $0` in `WordRow`. | There is no single change-tracking point. | **Closed**: VocabularyStore/FolderLibraryStore over repositories. |
| Writes from stores | `DailyStudyStore.review/recordPracticeAnswer` mutate SRS and save. | Centralized. | Not routed (D5), but they **bump `updatedAt`**. |
| Word identity | No stable ID. `persistentModelID` is persisted in UserDefaults by DailyStudyStore. | Blocker. | **Closed**: `Word.uuid` with backfill. DailyActivity keys stay PersistentIdentifier (Gap D). |
| Folder identity | `WordFolder.id: UUID` since the first commit. | Ready. | Ready. |
| Timestamps | `createdAt` only. | No incremental pull and no LWW. | **Closed (local side)**: `updatedAt` is bumped on every write. It uses the device clock (Gap B). |
| Deletion | Hard deletes everywhere. | Deletes cannot be propagated. | **Closed (local side)**: soft-delete tombstones. **There is no purge policy yet (Gap C).** |
| Memberships | `Word.folderIDs: [UUID]`. | Conflicts at whole-array granularity. | Unchanged. Membership changes bump the word's `updatedAt` (Gap E). |
| SRS state | Fields on `Word`. | Multi-device conflict. | Unchanged. Reviews bump `updatedAt` (Gap F). |
| Achievements | JSON `achievements.v1` in UserDefaults, read and written directly by the store. | No seam, and counters cannot be merged. | **Seam closed** (`AchievementStateRepository`). **Mergeability open (Gap G).** |
| Daily activity | JSON `dailyStudyActivity.v1`, keyed by PersistentIdentifier. | Device-local. No seam. | **Seam closed** (`DailyActivityRepository`). Keys stay as they are (Gap D). |
| Other local state | No `@AppStorage`/`@SceneStorage`. | None. | None. |
| Uniqueness | Pair and folder-name rules exist only on the client. | The server needs constraints. Merges can duplicate. | The folder rule becomes a pure function, and both rules ignore tombstones. The server side is open (Gap H). |
| Ownership | No `user_id`. | RLS needs it. | Open (auth task). |
| Category | Russian display string persisted. | Fragile column. | Open. |

### Remaining gaps, ranked
- **A.** No change signal for the folder catalog: sync-applied folder changes stay invisible until FolderPicker appears.
- **B.** `updatedAt` comes from the device clock. LWW across devices needs server timestamps or an HLC.
- **C.** Tombstones are never purged. The purge needs server acknowledgement, which belongs to the sync task.
- **D.** DailyActivity uses PersistentIdentifier keys. Move them to `Word.uuid` when daily state syncs, if ever.
- **E.** `folderIDs` array conflict granularity.
- **F.** SRS merge semantics.
- **G.** Achievement counters cannot be merged (they need an event log or per-device counters).
- **H.** Server-side uniqueness, `user_id`/RLS, category encoding.

Verdict: after this task the local data layer is **sync-shaped**. It has stable IDs, a modification timestamp, tombstones, and one write seam for everything except SRS reviews, which do bump `updatedAt`. It is still **not sync-ready**: gaps A–C must be solved before a first sync engine, and E–G before multi-device use.

### `@Query` tradeoff
Keep every `@Query`. Tombstone exclusion happens in memory at each consumer. Migrating reads behind protocols adds an observable cache and touches 8 views with no offline-first benefit.

## Acceptance criteria
- AC-1: Adding, scan toggle (with and without a folder), category change (scan results and dictionary row), word deletion, membership changes, and folder create/rename/reorder/delete look and behave exactly as before from the user's perspective. That covers error messages, ordering, counts and achievements, and words survive folder deletion.
- AC-2: `grep -rnE 'ScanWordStore\.|FolderStore\.(create|rename|reorder|delete|setMembership|removeFromAllFolders)|word\.category =' MojSlownik/Views` returns nothing. `FolderLibraryStore` methods take no `ModelContext`. `FolderStore.words(_:in:)` stays allowed.
- AC-3: `VocabularyRepository`, `FolderRepository`, `AchievementStateRepository` and `DailyActivityRepository` are protocols. The first two have no `ModelContext`/`ModelContainer`/`PersistentIdentifier` in their signatures. `AppResources` builds the SwiftData and UserDefaults implementations, and `MojSlownikApp` injects `FolderLibraryStore`, `VocabularyStore`, `DailyStudyStore` and `AchievementStore` once.
- AC-4: Every new `Word` has a unique `uuid`. A HEAD d593a09 store opens through `AppResources` with unchanged words, SRS and memberships. Every word gets a unique `uuid` (among duplicates, the earliest `createdAt` keeps its uuid), with `updatedAt == nil`, `deletedAt == nil` and `lastModifiedAt == createdAt`. A backfill failure is logged. A missing uuid gets a lazy retry, and only if that retry fails does the user see `missingIdentity`.
- AC-5: Deleting a word or folder through a repository sets `deletedAt`/`updatedAt` and keeps the row. No screen, count, practice pool, achievement metric, duplicate check, folder catalog or name check sees tombstoned rows.
- AC-6: Re-adding (add or toggle) a pair whose only match is a tombstone inserts a new active row with a new `uuid`, and the tombstone is unchanged. The re-added word's daily progress, review list and answer totals start clean.
- AC-7: Every repository write that changes a row sets its `updatedAt` to the injected `now`, and no-op writes don't. `DailyStudyStore.review` and `recordPracticeAnswer` set `word.updatedAt = now` unconditionally (deliberate exception). A failed save restores the previous value.
- AC-8: Existing `achievements.v1` and `dailyStudyActivity.v1` payloads are read back identically, and new writes use the same keys and JSON shape.
- AC-9: The in-memory fakes pass the same folder contract tests as SwiftData. `FolderLibraryStore`, `VocabularyStore`, `AchievementStore` and `DailyStudyStore` each work over a fake.
- AC-10: docs/architecture.md and AGENTS.md are updated. The build is clean with zero warnings, and `MojSlownikUnitTests` is green.

## Changes by file

### Models
1. **`Models/Word.swift`**
   - Add stored properties after `createdAt`:
     - `var uuid: UUID? = nil`, with the comment "stable cross-store identity; optional for additive migration; backfilled at launch";
     - `var updatedAt: Date? = nil`;
     - `var deletedAt: Date? = nil`.
   - Do not name the identity `id`, because `@Model` provides `Identifiable.id`. Add no `@Attribute(.unique)`.
   - `init`: `uuid = UUID()` and `updatedAt = createdAt`.
   - Extension:
     - `var isActive: Bool { deletedAt == nil }`
     - `var lastModifiedAt: Date { updatedAt ?? createdAt }`
     - `func markDeleted(now: Date) { deletedAt = now; updatedAt = now }`
   - Do not change `isDue`.
2. **`Models/WordFolder.swift`**
   - Add `var updatedAt: Date? = nil` and `var deletedAt: Date? = nil`.
   - `init` sets `updatedAt = createdAt`.
   - Add the same `isActive`, `lastModifiedAt` and `markDeleted(now:)`.

### Services
3. **New `Services/WordIdentityBackfill.swift`**: `@MainActor enum`, `import os`, with `logger = Logger(subsystem: "com.kirill.personal.mojslownik", category: "persistence")`.
   - `static func assignMissing(in context: ModelContext, rollbackOnFailure: Bool) throws -> Int`:
     - Fetch all words (tombstones included) and sort in memory by `(createdAt, polish, russian, sourceLanguageCode)`.
     - Walk the sorted list with a set of seen UUIDs, and assign `UUID()` when `uuid` is nil or already seen. "First" means the earliest `createdAt`. Remember `(word, previousUUID)` for each change.
     - If anything changed, save. On failure: if `rollbackOnFailure`, call `context.rollback()`; otherwise restore each changed word's previous `uuid`, which **never rolls back unrelated main-context edits**. Then rethrow.
     - Does not touch `updatedAt`.
   - `@discardableResult static func run(container:) -> Int`: uses an isolated context with `autosaveEnabled = false` and `rollbackOnFailure: true`. It catches errors, logs them with `logger.error(... privacy: .public)` and returns 0.
4. **New `Services/DataRepositories.swift`** (`import Foundation`; it references the app's own `Word` and `WordCategory`. AC-3 bans only `ModelContext`/`ModelContainer`/`PersistentIdentifier` in signatures). The file comment says the protocols are synchronous on purpose (offline-first local writes, sync elsewhere).
   - `struct FolderRecord: Equatable, Hashable, Sendable { let id: UUID; let name: String }`
   - `enum RepositoryError: LocalizedError, Equatable { case missingIdentity }`, with the message "Не удалось определить слово. Перезапустите приложение."
   - `@MainActor protocol FolderRepository: AnyObject`:
     - `folders() throws -> [FolderRecord]`, active folders in display order;
     - `createFolder(name:) throws -> UUID`;
     - `renameFolder(id:name:)`;
     - `reorderFolders(ids:)`;
     - `deleteFolder(id:)`, a soft delete that never deletes words.
   - `@MainActor protocol VocabularyRepository: AnyObject`:
     - `addWord(source:translation:category: WordCategory?, folderID: UUID?)`
     - `toggleScannedWord(source:translation:category:folderID:) -> Bool`
     - `changeCategory(_:source:translation:)`
     - `setCategory(_:wordID: UUID)`
     - `deleteWord(id: UUID)` (soft)
     - `setMembership(wordID:folderID:included:)`
     - `removeFromAllFolders(wordID:)`
     - `ensureIdentity(for word: Word) throws -> UUID`

     All of them are `throws`.
5. **New `Services/ProgressRepositories.swift`** (D3):
   - `struct AchievementState: Codable, Equatable`: the former private `AchievementStore.Stored`, moved as-is. It keeps the same property names (`unlocked`, `ledger`, `didInitialSync`) and the same `decodeIfPresent` custom `init(from:)`, so the JSON shape is identical.
   - `struct DailyActivity: Codable, Equatable` and `struct DailyActivityAnswer: Codable, Equatable`: the former private `Activity`/`Answer`, moved as-is. They keep the property names `day`, `completedIDs`, `pendingIDs`, `quizCompletedIDs`, `answers`, `wordID` and `isCorrect`, plus the existing comments about array equality and optional additions. They use synthesized coding with no custom keys, exactly as today.
   - `@MainActor protocol AchievementStateRepository: AnyObject`:
     - `load() -> AchievementState`: missing or corrupt data gives `AchievementState()`;
     - `save(_ state: AchievementState) throws`.
   - `@MainActor protocol DailyActivityRepository: AnyObject`:
     - `load() -> DailyActivity?`: missing or corrupt data gives nil;
     - `prepareSave(_ activity: DailyActivity) throws -> () -> Void`: encodes or validates now and returns a non-throwing commit. This keeps DailyStudyStore's "encode before mutating, commit after context save" atomicity;
     - `clear()`.
   - `final class UserDefaultsAchievementStateRepository` (`init(defaults: UserDefaults, key: String = "achievements.v1")`): uses plain `JSONEncoder()`/`JSONDecoder()`, as today.
   - `final class UserDefaultsDailyActivityRepository` (`init(defaults:key: String = "dailyStudyActivity.v1")`): `prepareSave` encodes with `JSONEncoder()` and returns `{ defaults.set(data, forKey: key) }`, and `clear()` calls `removeObject`.
6. **`Services/FolderStore.swift`** (all user-visible messages unchanged):
   - Add a `now: Date = .now` parameter to every mutating function.
   - Add a pure `static func validatedName(_:excluding:existing: [FolderRecord]) throws -> String`. The private context version passes **active** folders only.
   - `folders(in:)` returns active folders only. `create` computes `sortOrder` from the max over active folders.
   - `rename`: finds an **active** folder (otherwise `.missingFolder`). Sets `name` and `updatedAt = now` if the name changed. On failure restores both.
   - `reorder`: validates against active folders, bumps `updatedAt` only on folders whose `sortOrder` changed, and on failure restores `sortOrder` and `updatedAt`.
   - `delete(id:container:now:)`: `markDeleted(now)` on the matching active folder. For every word (tombstones included) whose `folderIDs` contains the id: remove it and set `updatedAt = now`. Never touch a word's `deletedAt`. Saves with rollback on failure.
   - `requireFolder` throws `.missingFolder` for tombstoned folders.
   - `setMembership` / `removeFromAllFolders`: resolve only **active** words (otherwise `.missingWord`). Bump `updatedAt` only if `folderIDs` changed, and restore `folderIDs` and `updatedAt` on failure.
   - `words(_:in:)` first filters `\.isActive`, then by folder.
7. **`Services/ScanWordStore.swift`**: add `now: Date = .now` to all functions. Matching uses **active words only**: `existing = words.filter(\.isActive).filter { matches }`. Tombstones are never matched, reused or modified.
   - `toggle`, folder mode:
     - With active matches: same as today, plus `updatedAt = now` on each word whose `folderIDs` changed.
     - Otherwise: insert a new word as today.
   - `toggle`, no-folder mode:
     - With active matches: `markDeleted(now)` on each (replaces `context.delete`).
     - Otherwise: insert as today.
   - `add`:
     - An active match is reused as today, with an `updatedAt` bump if the category or folder changed.
     - Otherwise: insert.
   - `changeCategory`: active match only, with a bump if the category changed.
   - `delete(wordID:container:now:)`: the word must be active (otherwise `.missingWord`); call `markDeleted(now)`.
   - Rollback-on-failure stays as is.
8. **New `Services/SwiftDataRepositories.swift`**: `@MainActor final class SwiftDataFolderRepository` and `SwiftDataVocabularyRepository`, each `init(container: ModelContainer, now: @escaping () -> Date = { .now })`.
   - Folder repository:
     - `folders()` maps `FolderStore.folders(in: container.mainContext)`;
     - create and rename use `container.mainContext`;
     - reorder and delete use the `container:` variants;
     - every call passes `now()`.
   - Vocabulary repository:
     - add, toggle and changeCategory forward to `ScanWordStore`.
     - `deleteWord(id:)` resolves the active word by `uuid` in a fresh context, then calls `ScanWordStore.delete`.
     - `setMembership` / `removeFromAllFolders` resolve the word in `container.mainContext` and call `FolderStore` with `mainContext`.
     - `setCategory(_:wordID:)` works on the active word in `mainContext`: if the category changed, set it, set `updatedAt = now()` and save, restoring both on failure.
     - `ensureIdentity(for:)` returns `word.uuid` if it is non-nil. Otherwise it calls `WordIdentityBackfill.assignMissing(in: container.mainContext, rollbackOnFailure: false)`, logs and rethrows on error, and re-reads `word.uuid`. If it is still nil it throws `RepositoryError.missingIdentity`.
     - Private helper `activeWord(uuid:in:)` throws `FolderStore.StoreError.missingWord`.
9. **`Services/Achievements.swift`**: `AchievementMetrics.vocabulary(words:folderCount:)` filters `words.filter(\.isActive)` internally. The signature is unchanged, and callers pass an active folder count.

### Stores
10. **`Stores/FolderLibraryStore.swift`**
    - `init(repository: any FolderRepository)`.
    - Methods: `load()`, `@discardableResult create(name:) -> UUID`, `delete(id:)`, `rename(id:name:)`, `reorder(ids:)`. Each calls the repository, then `load()`.
    - Drop the SwiftData import.
11. **`Stores/DailyStudyStore.swift`**
    - Designated init: `init(repository: any DailyActivityRepository, calendar:now:)`. It loads through `repository.load()` and applies the same same-day check.
    - Add `convenience init(defaults: UserDefaults = .standard, calendar:now:)` that wraps `UserDefaultsDailyActivityRepository(defaults:)`, so the existing tests and call sites compile unchanged.
    - Replace private `Activity`/`Answer` with `DailyActivity`/`DailyActivityAnswer`.
    - Every former `JSONEncoder().encode(next)` + `defaults.set` pair becomes `let commit = try repository.prepareSave(next)` (at the same point) … `activity = next; commit()`.
    - `refresh` calls `repository.clear()`.
    - `progress`, `reviewWords` and `answerTotals` first apply `let words = words.filter(\.isActive)`.
    - `review` and `recordPracticeAnswer`: capture `previousUpdatedAt = word.updatedAt` and set `word.updatedAt = now` before `context.save()`. On failure restore it together with the existing restored fields. This is the D5 bump without routing.
    - `recordPracticeAnswer` gains no new parameter (it already has `now`).
12. **`Stores/AchievementStore.swift`**
    - Designated init: `init(repository: any AchievementStateRepository, calendar:catalog:displayDuration:)`, which loads `repository.load()`.
    - Add `convenience init(defaults: UserDefaults = .standard, calendar:catalog:displayDuration:)` that wraps the UserDefaults repository.
    - `persist()` calls `try repository.save(AchievementState(...))` inside the existing `do/catch` + `assertionFailure`.
    - Remove the private `Stored` and the `storageKey`.
13. **New `Stores/VocabularyStore.swift`**: `@MainActor @Observable final class VocabularyStore(repository:)`.
    - Methods: `add(source:translation:category:folderID:)`, `@discardableResult toggleScanned(source:translation:category:folderID:) -> Bool`, `changeCategory(_:source:translation:)`, `setCategory(_:for: Word)`, `deleteWord(_: Word)`, `setMembership(of: Word, folderID:included:)`, `removeFromAllFolders(_: Word)`.
    - Word-targeted methods use `identity(of:)`, which returns `word.uuid` or else `try repository.ensureIdentity(for: word)` (the lazy retry). If identity fails, no write call is made.
14. **`MojSlownikApp.swift`**
    - `AppResources` gains `folders` and `vocabulary`.
    - Init order:
      1. the container;
      2. `WordIdentityBackfill.run(container:)`;
      3. `dailyStudy = DailyStudyStore(repository: UserDefaultsDailyActivityRepository(defaults: defaults), calendar:now:)`;
      4. `achievements = AchievementStore(repository: UserDefaultsAchievementStateRepository(defaults: defaults), calendar:)`;
      5. `folders = FolderLibraryStore(repository: SwiftDataFolderRepository(container:))`;
      6. `vocabulary = VocabularyStore(repository: SwiftDataVocabularyRepository(container:))`.
    - `MojSlownikApp` holds all four as `@State` from `resources` and injects each with `.environment`.

### Views (no layout or visual change)
Rule for every `@Query` of `Word`/`WordFolder`: rename the stored query to `stored…` and add a computed property with the **original name** that returns `stored….filter(\.isActive)`. All existing usages then read active rows with no further edits.
15. **`WordListView.swift`**
    - `@Query(sort: \Word.createdAt, order: .reverse) private var storedWords` and `words`, as per the rule above.
    - Add `@Environment(VocabularyStore.self)` to `WordListView` and `WordRow`.
    - Swipe action calls `deleteWord(word)`, which calls `vocabulary.deleteWord(word)`.
    - Folder delete: `folderLibrary.delete(id:)`.
    - Category binding setter: `try vocabulary.setCategory($0, for: word)`, with a new row-level `@State categoryError` and `.errorAlert(title: "Не удалось изменить категорию", ...)`. This mirrors the existing row-level `folderError` alert (see Risks).
    - Folder menu: `vocabulary.removeFromAllFolders(word)` / `vocabulary.setMembership(of: word, folderID:included:)`.
    - Remove an unused `modelContext`.
    - Preview: `AppResources.preview` container plus all four stores.
16. **`AddWordView.swift`**: `save()` calls `vocabulary.add(...)`. Remove an unused `modelContext`. Same preview fix.
17. **`ScannerView.swift`** (`ScanResultView`): `savedWords` follows the rule above. Use `vocabulary.changeCategory` / `vocabulary.toggleScanned`.
18. **`Components/FolderPicker.swift`**: library calls without `context:`.
19. **`TrainingView`, `FlashcardsView`, `QuizView`, `ListeningPracticeView`**: `allWords` follows the rule above. They already route through `FolderStore.words`, which filters too.
20. **`AchievementsView`, `Components/AchievementTracker`**: `words` and `folders` follow the rule above, so `folders.count` is active-only.
21. **Previews (all of the above plus `RootTabView`)**: use `AppResources.preview` (container, folders, vocabulary, dailyStudy, achievements). Replace every `FolderLibraryStore()` and every `.modelContainer(for: ..., inMemory: true)`.

### Docs
22. **`docs/architecture.md`**
    - Application Map gets a "Data access" row (the four repository protocols and their implementations, VocabularyStore, backfill).
    - Startup mentions the backfill.
    - In Adding, replace "without a repository layer" with the store → repository path.
    - Deletion becomes soft delete with tombstones excluded in memory; re-adding inserts a new row.
    - Study Folders: FolderLibraryStore over FolderRepository, folder soft delete.
    - Non-obvious Constraints: `isActive` filtering everywhere, no `#Predicate`, the `updatedAt` rule, `lastModifiedAt` for legacy rows.
    - New section "Backend Readiness" with gaps A–H.
23. **`AGENTS.md`**, two invariant bullets:
    - "Vocabulary/folder writes from views go through VocabularyStore/FolderLibraryStore (Services/DataRepositories.swift); views never mutate Word or call ScanWordStore/FolderStore writers."
    - "Words and folders are soft-deleted (`deletedAt`); every read filters `\.isActive` in memory; every write that changes a row sets `updatedAt`."

## Implementation phases
The phases run strictly in order. **Each phase ends with:** `xcodegen generate` (if it added files), a clean build with zero warnings, and a green `MojSlownikUnitTests`. Do not start the next phase on a red gate. Item numbers refer to "Changes by file".

### Phase 1: Data layer (models, soft delete, filtering, timestamps, identity)
Scope: items 1–3, 6 (except the pure `validatedName(…existing: [FolderRecord])` overload, which belongs to Phase 2), 7, 9, the filtering and `updatedAt` parts of 11, and the `@Query` rename rule in items 15, 17, 19 and 20. The only change to `MojSlownikApp.swift` is the `WordIdentityBackfill.run(container:)` call in `AppResources.init`. Views keep calling `ScanWordStore`/`FolderStore` directly for now.

Files owned:
- **Models**: `MojSlownik/Models/Word.swift`, `MojSlownik/Models/WordFolder.swift`
- **Services**: new `MojSlownik/Services/WordIdentityBackfill.swift`, `MojSlownik/Services/FolderStore.swift`, `MojSlownik/Services/ScanWordStore.swift`, `MojSlownik/Services/Achievements.swift`
- **Store**: `MojSlownik/Stores/DailyStudyStore.swift` (`isActive` filter in `progress`/`reviewWords`/`answerTotals`; unconditional `updatedAt` bump plus restore in `review`/`recordPracticeAnswer`; persistence untouched)
- **App root**: `MojSlownik/MojSlownikApp.swift` (backfill call only)
- **Views** (`stored…` + computed active property only): `WordListView.swift`, `TrainingView.swift`, `ScannerView.swift`, `FlashcardsView.swift`, `QuizView.swift`, `ListeningPracticeView.swift`, `AchievementsView.swift`, `Components/AchievementTracker.swift`
- **Tests**:
  - new: `WordIdentityBackfillTests.swift`, `LegacySchemaMigrationTests.swift`, `SoftDeleteExclusionTests.swift`, `ReAddAfterDeleteTests.swift` (here written against `ScanWordStore.add/toggle/delete(wordID: persistentModelID, container:)`);
  - updated: `WordTests.swift`, `DailyStudyStoreTests.swift` (updatedAt bump), `ScanWordStoreTests.swift`, `FolderStoreTests.swift` (active helpers, tombstone assertions, folder soft-delete, reorder bump), `FolderPersistenceTests.swift`, `FolderTrainingTests.swift` (active helpers).

Gate extras: `grep -rn '@Query' MojSlownik/Views` shows only `stored…` property names.

### Phase 2: Repositories and stores for vocabulary and folders
Scope: items 4, 6 (pure `validatedName` overload), 8, 10, 13, 14 (`folders`/`vocabulary` in `AppResources` plus injection), 15–18 and 21 (call-site and preview rewiring). `FolderLibraryStore`'s API change, `FolderPicker`, `WordListView` and `FolderLibraryStoreTests` change **in the same step**, so the build never breaks midway.

Files owned:
- **Services**: new `MojSlownik/Services/DataRepositories.swift`, new `MojSlownik/Services/SwiftDataRepositories.swift`, `MojSlownik/Services/FolderStore.swift` (pure `validatedName` overload)
- **Stores**: `MojSlownik/Stores/FolderLibraryStore.swift`, new `MojSlownik/Stores/VocabularyStore.swift`
- **App root**: `MojSlownik/MojSlownikApp.swift`
- **Views**: `WordListView.swift`, `AddWordView.swift`, `ScannerView.swift`, `Components/FolderPicker.swift`, plus preview-only edits in `RootTabView.swift`, `TrainingView.swift`, `FlashcardsView.swift`, `QuizView.swift`, `ListeningPracticeView.swift`
- **Tests**:
  - new: `RepositoryFakes.swift` (folder and vocabulary fakes), `FolderRepositoryContractTests.swift`, `SwiftDataVocabularyRepositoryTests.swift`, `VocabularyStoreTests.swift`;
  - updated: `FolderLibraryStoreTests.swift`, `FolderPersistenceTests.swift` (constructor). Add the `AppResources` shared-container test to `WordIdentityBackfillTests.swift`.

Gate extras: the AC-2 grep returns nothing.

### Phase 3: Progress repositories and docs
Scope: items 5, the repository parts of 11 and 12, the progress-repository construction in item 14, and items 22–23.

Files owned:
- **Services**: new `MojSlownik/Services/ProgressRepositories.swift`
- **Stores**: `MojSlownik/Stores/DailyStudyStore.swift` (repository init plus convenience `defaults:` init, `DailyActivity` types, `prepareSave`/`clear`), `MojSlownik/Stores/AchievementStore.swift`
- **App root**: `MojSlownik/MojSlownikApp.swift`
- **Tests**:
  - new: `ProgressRepositoryTests.swift`;
  - updated: `RepositoryFakes.swift` (progress fakes), `AchievementStoreTests.swift` and `DailyStudyStoreTests.swift` (store-over-fake and prepare-failure tests; existing tests unchanged via the convenience inits).
- **Docs**: `docs/architecture.md`, `AGENTS.md`

Gate extras: grep that `"achievements.v1"` and `"dailyStudyActivity.v1"` appear only in `ProgressRepositories.swift` (and tests).

## Reuse
- The `ScanWordStore` and `FolderStore` statics stay as the SwiftData core. `FolderStore.StoreError` messages are reused. `errorAlert` is reused.
- The `AppResources` pattern is extended.
- The convenience `defaults:` inits keep all 25 existing `DailyStudyStore(`/`AchievementStore(` test constructions unchanged.
- No Theme or visual changes.

## Data compatibility
- Schema additions, all optional and nil by default (lightweight migration): `Word.uuid`, `Word.updatedAt`, `Word.deletedAt`, `WordFolder.updatedAt`, `WordFolder.deletedAt`. Nothing is renamed or removed.
- Legacy rows load with nil in every new field, which means active, never modified, and no identity yet. The backfill assigns the uuids. `updatedAt` stays nil and is read as `createdAt`.
- No row is ever hard-deleted from now on. Previously deleted words are gone already. Tombstones persist and are invisible.
- `achievements.v1` and `dailyStudyActivity.v1` keep the same keys, types, property names and encoder settings, so today's progress, streaks and unlocks survive.
- Folder deletion still strips memberships and never deletes words.

## Verification
Run `xcodegen generate`, the build (zero warnings), and `MojSlownikUnitTests`. All tests are `@MainActor` and use an in-memory `ModelConfiguration(isStoredInMemoryOnly: true)` for `Word` + `WordFolder` unless they say on-disk. Persistence assertions read through a **fresh `ModelContext(container)`**, so a dropped `save()` fails.

**Fakes — new `MojSlownikTests/RepositoryFakes.swift`**
- `InMemoryFolderRepository`: rows `(id, name, sortOrder, createdAt, deletedAt)`. It uses `FolderStore.validatedName(_:excluding:existing:)` over active rows, applies the same invalid-order rule, soft-deletes, and supports `nextError`.
- `RecordingVocabularyRepository`: a call-log enum including `.ensureIdentity`, plus `toggleResult`, `nextError`, and `identityResult: Result<UUID, Error>`. On success it sets `word.uuid`.
- `InMemoryAchievementStateRepository`: `var state`, `saveCount`, `nextError`.
- `InMemoryDailyActivityRepository`: `var stored: DailyActivity?`, `prepareError`. The commit closure writes `stored`.

**Contract and store tests**
- **`FolderRepositoryContractTests`**: `runContract(make:persistedNames:)` runs for SwiftData (with a fresh-context `persistedNames`) and for the in-memory fake (`persistedNames` nil). It covers:
  - trim and whitespace collapse;
  - append order;
  - `.emptyName`;
  - a case/Unicode duplicate gives `.duplicateName` with no change;
  - rename, and rename to an existing name throws;
  - reorder, and an invalid reorder gives `.invalidOrder`;
  - delete removes the folder from `folders()`;
  - **re-creating a deleted folder's name succeeds with a new id**.
- **SwiftData-only folder tests**:
  - delete leaves a row with `deletedAt` set (fresh context, `fetch` includes it);
  - member words keep SRS and `deletedAt == nil`, lose only that folder id, and get `updatedAt == now`;
  - `requireFolder` / `setMembership` on a deleted folder give `.missingFolder`;
  - reorder bumps only the folders whose order changed.
- **`SwiftDataVocabularyRepositoryTests`** (fixed `now` clock):
  - add sets a uuid and `updatedAt == createdAt`, and re-adding the same active pair reuses it;
  - `deleteWord` soft-deletes: the row remains with `deletedAt == updatedAt == now`, and an unknown or tombstoned uuid gives `.missingWord`;
  - `setMembership` / `removeFromAllFolders` / `setCategory` persist and bump `updatedAt`, and a no-op change does **not** bump it;
  - `toggleScannedWord` returns true, then false (soft delete), then true. That leaves two rows: one tombstone with its original uuid and `deletedAt` unchanged, and one new active row with a different uuid;
  - `ensureIdentity` assigns a uuid on a nil-uuid `mainContext` word (same instance, visible in a fresh context) and returns an existing uuid unchanged.
- **`SoftDeleteExclusionTests`**:
  - `FolderStore.words(_:in:)` with nil and with a folder;
  - `AchievementMetrics.vocabulary` (word count, categories, learned);
  - `DailyStudyStore.progress/reviewWords/answerTotals` (a due tombstone is excluded);
  - `FolderStore.folders` and the name check ignore deleted folders;
  - `ScanWordStore.changeCategory` does not modify a tombstone;
  - `toggle` with a folder on a pair whose only match is a tombstone inserts a new row with `folderIDs == [folder]` and leaves the tombstone's fields unchanged.
- **`ReAddAfterDeleteTests`**:
  - `add` → `deleteWord` → `add` of the same pair (a different source direction and category on the second add): there are two rows. The tombstone keeps `uuid`, `deletedAt`, `updatedAt` and all fields byte-for-byte as they were at deletion. The new active row has a different `uuid`, `createdAt == now2`, default SRS, `updatedAt == createdAt`, the new category, and `folderIDs` from the second call.
  - Deleting twice and re-adding leaves two tombstones and one active row. Every lookup (`changeCategory`, `toggle`) affects only the active row.
  - **Daily activity is clean**, using `DailyStudyStore(defaults: <suite>)` with a fixed `now`:
    1. Add word W and `review(.again, to: W)` (now pending, with one incorrect answer).
    2. Soft-delete W, then re-add the same pair as W2.
    3. Pass the active words from a fresh fetch. Assert that `reviewWords` contains W2 only (not the tombstone W), and `progress == Summary(completed: 0, remaining: 1)`.
    4. Assert `answerTotals == (0, 0)`.
    5. Run the same check with `recordPracticeAnswer(..., isQuiz: true)` on W before deleting.
- **`WordIdentityBackfillTests`**:
  - nil uuids get filled and distinct, and other fields **including `updatedAt`** stay unchanged;
  - existing uuids are kept;
  - the duplicate order is deterministic: createdAt t0+20, t0, t0+10 share X, and only t0 keeps it; on a tie, polish "a" beats "b";
  - a second run returns 0;
  - **`rollbackOnFailure: false` never calls rollback**. Insert an unrelated unsaved edit into the context, run `assignMissing(rollbackOnFailure: false)` successfully, and assert the unrelated edit is still pending (`context.hasChanges` before save / value intact). Failure-path rollback cannot be forced and is covered by code review.
- **`LegacySchemaMigrationTests`** (on-disk):
  - `LegacySchemaV1: VersionedSchema` (1.0.0) has nested `@Model Word`/`WordFolder` copying HEAD d593a09 field-for-field. That means no `uuid`, `updatedAt` or `deletedAt`, and `WordFolder` has `id = UUID()`, `name`, `createdAt`, `sortOrder = 0`.
  - **First assert** that `Schema(versionedSchema: LegacySchemaV1.self).entities.map(\.name).sorted() == ["Word", "WordFolder"]` and that the current `Schema([Word.self, WordFolder.self])` has the same names. This rules out an entity-name mismatch before anything is attributed to migration.
  - Write 1 folder and 3 words (non-default SRS, categories, `folderIDs`), then release the container.
  - Reopen through `AppResources(configuration: ModelConfiguration(url:cloudKitDatabase: .none), defaults: <unique suite>)`.
  - Assert:
    - the count is 3;
    - the uuids are unique and non-nil;
    - all legacy fields are unchanged;
    - `updatedAt == nil`, `deletedAt == nil`, `isActive`, `lastModifiedAt == createdAt`;
    - the words appear in `FolderStore.words(_, in: folder.id)`;
    - the folder is active with `updatedAt == nil`, and `resources.folders.load()` lists it.
  - Clean up in `tearDown`.
- **`ProgressRepositoryTests`** (D3):
  - `UserDefaultsAchievementStateRepository`:
    - a **golden JSON** literal in the current shape (`{"unlocked":{"first-word":<Double>},"ledger":{...all fields...},"didInitialSync":true}`, with dates as `JSONEncoder` default reference-date doubles) under `achievements.v1` loads into the expected `AchievementState`;
    - `save` and then `JSONSerialization` of the stored data give the same keys and values;
    - partial JSON without `didInitialSync` loads as false;
    - corrupt data loads as the default.
  - `UserDefaultsDailyActivityRepository`:
    - a test-local `LegacyDailyActivityV1` mirror copies HEAD's private `Activity`/`Answer` exactly. Encoded with `JSONEncoder` into `dailyStudyActivity.v1` (with real PersistentIdentifiers from an in-memory container), it `load()`s equal; the reverse direction decodes with the mirror;
    - `prepareSave` does not write until the commit runs;
    - `clear` removes the key.
- **Store-over-fake tests**:
  - `AchievementStore(repository: InMemory…)`: `record` saves to the fake, and a new store over the same fake restores `ledger`/`unlocked`.
  - `DailyStudyStore(repository: InMemory…)`: `review` commits to the fake, and a new store restores today's progress. With `prepareError` set, `review` throws and the word's SRS and `updatedAt` are unchanged.
  - `DailyStudyStoreTests` adds that `review` and `recordPracticeAnswer` set `word.updatedAt == now` (fresh context).
  - `VocabularyStoreTests`:
    - forwarding;
    - a word with a uuid skips `ensureIdentity`;
    - a nil uuid with success records `[.ensureIdentity, .deleteWord(U)]` (and the same for setCategory, setMembership and removeFromAllFolders);
    - a nil uuid with failure throws `missingIdentity`, and only `.ensureIdentity` is recorded.
  - `FolderLibraryStoreTests`: new constructor; the reload assertion goes through `FolderStore.folders(in: ModelContext(container))`; add a store-over-fake test.
- **Updated existing tests**:
  - The `words(in:)` / folder-fetch helpers in `ScanWordStoreTests`, `FolderStoreTests`, `FolderPersistenceTests` and `FolderTrainingTests` (where they fetch raw rows) filter `\.isActive`, so "removed" assertions keep their meaning.
  - Add one explicit tombstone assertion per deletion test (the row exists with `deletedAt` set).
  - Hard-delete expectations such as `fetch(...).count == 0` become active-count checks.
  - `WordTests`: new words have distinct uuids and `updatedAt == createdAt`.

**Manual checks**
- Upgrade-install over a d593a09 build that has words, folders, memberships, reviews, unlocked achievements and today's progress. Everything must be intact: progress ring, streak, unlocks.
- Delete a word and re-add it, which shows it at the top with fresh progress.
- Toggle a scan chip repeatedly.
- Delete a folder: its words remain, and the name can be reused.
- Category change in a row.
- OCR and camera paths need a physical device.

## Risks
- **A missed read site leaks tombstones.** Mitigation: the stored/computed `@Query` rename rule (compile-time coverage of all usages), filtering in helpers too, and a grep step: `grep -rn '@Query' MojSlownik/Views` must show only `stored…` names.
- **Legacy schema fidelity.** The migration test only counts if `LegacySchemaV1` matches d593a09 exactly. Check the entity-name assertion first. If migration still fails with the names matching, stop and escalate: production upgrades would fail the same way.
- **Tombstone pile-up (accepted, O1).** Every delete leaves a row. Repeated scan-chip toggling (add/remove/add …) adds one tombstone per removal, and folder delete/re-create cycles do the same. There is no purge until the sync design defines server-acknowledged purging (Gap C). Every read path pays an in-memory `isActive` filter over a slowly growing table. That is negligible at personal scale (thousands of rows), but it should be revisited if row counts grow by orders of magnitude.
- **Device-clock `updatedAt`** is not reliable for cross-device LWW (Gap B).
- **Row-level error alerts.** The new `categoryError` alert is per `WordRow`, mirroring the existing per-row `folderError`. Two `.errorAlert`s per list row are consistent with today's pattern and not hoisted. If list-row alert presentation misbehaves in manual checks, hoist both into `WordListView` via an `onError` callback, in a follow-up.
- **The lazy identity retry saves `mainContext`**, which flushes pending autosave edits earlier. The outcome is the same and no rollback happens.
- **Explicit category save** replaces autosave. A failure now shows an alert.
- **The `DailyStudyStore` refactor** touches the atomic review path. The existing DailyStudyStoreTests plus the new prepare-failure test guard it.
- **Duplicate pairs across devices.** Under O1, a delete on one device plus a re-add on another yields two rows for the same pair (one tombstone, one active). The sync design must accept this as intended.

## Open decisions
None. D1–D5 and O1–O3 are decided (see Decisions).

## Revision log
- Round 1 (critic): folder-catalog staleness gap, fresh-context reload assertions, `LegacySchemaV1` migration test, deterministic duplicate backfill, logged failure plus lazy `ensureIdentity` retry. All were accepted and are kept above.
- Round 2 (user decisions plus plan-reviewer lows): D2 and D3 are now in scope (sync metadata, soft delete, progress repositories), and D4 records the WordFolder identity status. Reviewer lows:
  1. `assignMissing(rollbackOnFailure:)`: only the isolated `run` rolls back, and `ensureIdentity` restores just the changed uuids.
  2. The row-level alert is kept, consistent with `folderError`, and noted in Risks with the hoist fallback.
  3. The migration test asserts entity names first.
  4. The AC-2 grep uses `grep -rnE`.
- Round 3 (user answers plus reviewer): O1 is a new row, so all resurrection logic and tests are removed and replaced by ReAddAfterDeleteTests (including clean daily activity). The tombstone pile-up is an accepted risk. O2 and O3 are defaults. The "Foundation only" claim is corrected. The unconditional SRS `updatedAt` bump is stated as a deliberate exception. Implementation is split into three phases.

## Approval

- 2026-11-17 — approved by user (full mode, 3 phases).
