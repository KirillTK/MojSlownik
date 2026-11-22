# Mój Słownik Architecture

Personal ru ↔ pl dictionary for iPhone, using SwiftUI and SwiftData on iOS 17+.
Optional Supabase account (Apple/Google); words and folders sync with the account
(offline-first, see Sync). Signed-in users upload
content-free diagnostics. Vocabulary is stored locally; web
translation sends entered or recognized text to an external service.

## Application Map

Paths below are relative to `MojSlownik/` unless stated otherwise.

### Source layout

Layers stay at the top of `MojSlownik/`; domain sub-folders sit inside them.

- `Models/` SwiftData models; `Stores/` observable stores views write through; `Theme/`;
  `Backend/` Supabase adapters (the only Supabase import).
- `Services/Data/` repository seams and implementations, SwiftData writers, word identity and
  value types; `Services/Workspaces/`, `Services/Language/`, `Services/Translation/`,
  `Services/Speech/`, `Services/Scanning/` (OCR), `Services/Practice/` (SRS, confidence,
  listening), `Services/Achievements/`, `Services/Sync/`, `Services/Account/`,
  `Services/Logging/`, `Services/UITestSupport/` (DEBUG UI-test mode).
- `Views/RootTabView.swift` plus `Views/Dictionary/`, `Views/Practice/`, `Views/Workspaces/`,
  `Views/Account/`; shared views in `Views/Components/`.
- Tests stay flat in `MojSlownikTests/` and `MojSlownikUITests/` (several tests locate the repo
  root relative to their own file).

| Area | Files and responsibilities |
| --- | --- |
| Startup | `MojSlownikApp.swift` creates a model container for `Word` and `WordFolder`, injects the shared folder, daily-study and achievement stores, and presents `RootTabView`. |
| Navigation | `Views/RootTabView.swift`: Dictionary and Training tabs (Achievements is pushed from Training), root `AppleTranslationHost`, `AchievementTracker` and `achievementBanner()`. |
| Data access | Protocols `VocabularyRepository`/`FolderRepository` (`Services/Data/DataRepositories.swift`) and `AchievementStateRepository`/`DailyActivityRepository` (`Services/Data/ProgressRepositories.swift`). SwiftData implementations (`Services/Data/SwiftDataRepositories.swift`, over `ScanWordStore`/`FolderStore`) and UserDefaults implementations are built in `AppResources`. Views write through `Stores/VocabularyStore.swift` and `Stores/FolderLibraryStore.swift`; `Services/Data/WordIdentityBackfill.swift` assigns `Word.uuid`. |
| Persistence | `Models/Word.swift`: Russian/Polish pair, source language, persisted category, creation date, last card grade, adaptive knowledge tier and SRS state; alongside the `WordFolder` model for custom study packs. |
| Dictionary | `Views/Dictionary/WordListView.swift`: creation-date `@Query`, search in both languages, deletion, add and camera presentation; `Views/Components/KnowledgeTierBadge.swift`: compact confidence indicator reused by dictionary, scanner chips and practice prompts. |
| Adding words | `Views/Dictionary/AddWordView.swift` and `Stores/AddWordDraft.swift`: source/translation draft, 600 ms debounce, editable translation and category/folder selection; saving through `ScanWordStore.add`. |
| Translation | `Services/Translation/TranslationService.swift`: `Translator` facade; implementations in `AppleTranslator.swift`, `GoogleWebTranslator.swift`, `MyMemoryTranslator.swift`. `Services/Language/Language.swift` is the central descriptor table (10 languages: names, speech/OCR/provider codes, Apple identifier, script, case rule) and `LanguagePair`; `TranslationAlternatives.swift` parses, filters and merges extra translation candidates. |
| Camera and results | `Views/Dictionary/ScannerView.swift`: permission, VisionKit live line tap, transient frame capture/freeze, full-screen still-image OCR, tappable OCR text blocks with multi-select, and translation of all recognized text; compact bilingual quick-add cards and an explicit correction menu opening nested `AddWordView`. Captured images stay in memory only and can be retaken. `Services/Scanning/ScannedTextTokenizer.swift` recognizes text in the captured image, maps Vision bounds through aspect-fill, and groups/orders recognized items into stable blocks. |
| Practice | `Views/Practice/TrainingView.swift`: daily progress and entry points to flashcards, quiz and adaptive listening practice; `Services/Practice/KnowledgeProgressService.swift`: shared per-word confidence and typed-answer scoring; `Views/Practice/ListeningPracticeView.swift`/`Services/Practice/ListeningQuestion.swift`: audio recognition choices, translation input and audio dictation selected by confidence; `Stores/DailyStudyStore.swift`: atomic word-confidence and local daily activity updates; `Services/Practice/SRSEngine.swift`: card scheduling and last card grade. |
| Achievements | `Services/Achievements/Achievements.swift`: metrics, definitions, catalog and pure evaluator; `Services/Achievements/AchievementLedger.swift`: lifetime practice counters and events; `Stores/AchievementStore.swift`: unlocks, banner queue (`recordNextUnlocksSilently` skips banners for unlocks caused by just-pulled vocabulary); `Views/Practice/AchievementsView.swift` plus `Views/Components/Achievement*.swift`. |
| Speech and styling | `Services/Speech/SpeechService.swift`, `Views/Components/PronounceButton.swift`: system speech; `Theme/Theme.swift`: dynamic colors and cards. |
| Backend | `Backend/`: remote backend code, kept apart from `Services/`; the only place that imports `Supabase`. `SupabaseConfiguration.swift` (URL, publishable key, OAuth redirect), `SupabaseClientProvider.swift` (lazy client, no SDK logger), `SupabaseAuthBackend.swift` (native SDK OAuth), `SupabaseLogUploader.swift` (app_logs inserts), `SupabaseSyncRemote.swift` (PostgREST transport of the sync engine), `RemoteRecords.swift`/`RemoteMergePolicy.swift` (DTOs, validator, merge rule). Schema: `supabase/migrations`, tests: `supabase/tests`. |
| Account and logs | `Stores/AuthStore.swift` over `Services/Account/Auth.swift` (`AuthBackend`; `StaticAuthBackend` for previews/UI tests); `Views/Account/AccountView.swift` from the Словарь toolbar. `Services/Logging/AppLog.swift` (typed events) and `Services/Logging/AppLogQueue.swift` (on-disk queue, uploads while signed in, flush on threshold/sign-in/sign-out/background). Stores take an `AppLogging`; static services use `AppLog.shared`. `Stores/SyncStore.swift` owns sync triggers, status and linking (see Sync). |
| Build | Root `project.yml`: XcodeGen, application, `MojSlownikTests` and `MojSlownikUITests`, iOS 17.0, Swift 5.9. Schemes: `MojSlownik` (app), `MojSlownikUnitTests` and `MojSlownikE2E` (UI tests, parallel classes). CI: `.github/workflows/ci.yml`. Swift package `supabase-swift` (product `Supabase`, exact 2.55.7; needs Xcode 16.3+). |

## Data Flows

**Startup:** `AppResources` constructs and retains the `Word`/`WordFolder`
`ModelContainer` before constructing `DailyStudyStore`. Restoring Codable
`PersistentIdentifier` values requires those entity types to be registered first;
SwiftData can terminate the process rather than throw when that precondition fails.
The app injects that same container into its scene. Previews use ordered in-memory
resources with separate defaults, never the user's daily activity. After the
container opens, `WordIdentityBackfill.run` assigns a unique `Word.uuid` to rows that
lack one (earliest `createdAt` keeps a duplicated uuid); failures are logged and
`VocabularyStore` retries lazily through `ensureIdentity` before a word-targeted write.

**Deletion:** dictionary rows expose a red «Удалить» swipe action, which soft-deletes
the exact word globally (`VocabularyStore` → repository → `ScanWordStore.delete`,
setting `deletedAt`/`updatedAt` in an isolated, explicitly saved context). Tombstones
stay in the store and are excluded in memory by `isActive`; re-adding the same pair
inserts a new row with a new `uuid` and clean progress. Errors remain at screen level. Custom folder rows in
the shared picker expose the same action followed by a named confirmation;
`FolderLibraryStore.delete` refreshes the catalog and clears invalid selections.
Removing a folder soft-deletes it, strips its id from every word and preserves
vocabulary, SRS and other folder memberships.

**Adding:** input → `LanguageDetector` → `Translator` → editable translation →
`Word` → SwiftData → dictionary/training `@Query` updates. Pair fields always
follow their languages regardless of input direction. After the debounce, gated input
(one line, at most 4 words and 60 characters) also fetches alternatives in parallel
(Google `dt=bd/at`, MyMemory `matches`); they appear as «Варианты» chips, never delay or
replace the primary translation and are not persisted. These screens use the
views through `VocabularyStore` → `VocabularyRepository` → `ScanWordStore`, which saves explicitly
in an isolated context.

**Voice input:** Add Word starts `SpeechRecognitionService` only from its
microphone button. Native Speech/AVAudioEngine recognition uses Polish (`pl-PL`)
and requests microphone/speech permissions at first use. Partial transcripts stay
in an ephemeral draft; final or explicitly stopped recognition commits once to
the editable source. `AddWordDraft` owns debounced translation and revision guards;
identical dictated text also restarts a cancelled translation. Cancellation and
failure preserve the typed pair and resume a missing translation when appropriate.
Dismissal/background cancels capture; permission-dialog inactivity does not.
Capture resources and stale callbacks are invalidated at every terminal state;
Stop has a bounded finalization wait. Pronunciation reapplies playback audio
configuration after capture. Audio may be processed by Apple; committed text
uses the existing translation providers. No audio or transcript history is stored.

**Scanning:** tap a recognized line while live or freeze the current frame with VisionKit `capturePhoto()`. The scanner then stops and is removed from the view hierarchy; Vision `VNRecognizeTextRequest` analyzes the captured UIImage itself. The still fills the screen while tappable OCR text-block bubbles let users select/deselect several blocks, or translate all still-image OCR text. Selected blocks stay accented and a compact count/translate action lets users revise their selection before translation. Vision's normalized bottom-left bounds are converted to top-left image coordinates and mapped through the image's aspect-fill scale/crop into the full-screen viewport; observations cropped entirely outside the displayed image are omitted. Text blocks group nearby OCR lines with a three-line cap so dense pages remain selectable; each ID derives from sorted member observation UUIDs, so state recomputation keeps selection stable. The still and OCR results remain in screen memory; retake clears both and resumes the live camera. No image is saved to Photos or disk. Verify image orientation/crop alignment on a physical device because the captured still and live preview may frame slightly differently. Selected blocks and lines are ordered top-to-bottom/left-to-right and joined with newlines; repeated OCR observations remain separate. The scan dismisses the camera and presents `ScanResultView` after 0.4 seconds, translating the text and each unique word sequentially.
Chips show original, translation and category. With no destination folder, tapping a ready card toggles its pair in the dictionary: add, remove, then add again.
The saved state shows a checkmark and an explicit removal hint. Removing a word also
removes its SRS progress; re-adding starts a new record. `Services/Data/ScanWordStore.swift`
uses a fresh context for each operation, normalizes pair lookup with `Word.matches`,
and rolls back only that operation on failure. It does not save or roll back unrelated
pending edits in the screen context.
The source is an editable multiline field preserving punctuation. On first display,
OCR line-wrap hyphenation is joined only for an ASCII or soft hyphen directly between
letters across LF/CRLF; compound hyphens and dash punctuation remain untouched.
Edits debounce a new sequential translation and invalidate older requests by revision,
so late results cannot replace the current text or loading state. An explicit
word-correction menu opens `AddWordView(initialText:)`; scan translation pauses while
that sheet is open and resumes on dismissal. Closing either screen cancels its
translation work. Translation failures can be retried.

**Categories:** `Services/Data/WordCategory.swift` assigns one of seven topics using
exact normalized Russian/Polish keyword matches, falling back to Other. This is a
small local vocabulary, not semantic classification; inflections may be unrecognized.
`Word.categoryRawValue` has a declaration-level Other default for existing stores;
new words are classified automatically unless a manual override is supplied.
Categories can be changed through a chevron menu inside each scan card (including
saved words), in the add form, or through the dictionary row's category menu.
A horizontal category/count strip filters the dictionary alongside text search.

**Practice:** scoped session snapshot → reveal answer → rating → apply SRS and
explicitly save the same `Word` → record daily activity. The saved card grade
selects the listening practice format from the shared confidence tier: tiers 0–1
play a Polish word for four-choice recognition, tier 2 asks for Polish spelling
from a Russian prompt, and tier 3 plays the Polish word for dictation. Exact typed
answers raise one tier; normalized Levenshtein similarity of at least 70% counts
as a soft miss and lowers a tier after two consecutive misses, while lower scores
lower a tier immediately. Choice answers move one tier up or down; flashcard
self-ratings set the tier directly. Existing records derive an initial tier from
their saved card grade or SRS state. `DailyStudyStore.review`
restores only that word's prior SRS fields if saving fails; the screen reports the
failure and does not advance. Each quiz question carries its source word's stable
identifier. Quiz/listening answers update confidence and daily activity together,
without changing SM-2 scheduling. A failed save restores the word's prior
confidence state. Selecting an answer persists activity before local feedback;
Back retains accepted answers even in an unfinished quiz.
The 0.9-second transition is cancellable when leaving the screen. Quiz questions,
position and score remain session state; quiz answers do not change SRS fields.

**Daily progress:** the app-scoped observable `DailyStudyStore` stores the local day
and unique completed/pending `PersistentIdentifier` collections, today's quiz successes,
and answer events as Codable data in UserDefaults. Successful flashcard and quiz
answers add unique daily completion. A quiz success exempts that word from today's
remaining practice without altering its SRS due date; the exemption ends at local
midnight. A later wrong quiz answer or "Не помню" removes all completion/exemption
and keeps the word pending. A later success clears pending; a flashcard success
returns the word to ordinary SRS-based due handling. The flashcard session also
appends "Не помню" words for another attempt during its ten-minute SRS delay.
The training ring counts existing words in the selected folder: completed today
versus currently due (unless successfully quizzed today) or pending. Pending always
wins; due status still overrides flashcard-only completion. Daily answer/correct/error
statistics count every answer from either mode, independently of unique-word completion.
Both counters use the current existing folder scope. New optional fields decode
existing v1 completion and pending state without inventing historical answer counts.
Persisted ID collections use equality-based arrays, retaining the old Set JSON
format: decoded SwiftData IDs can compare equal to live model IDs while producing
different hashes, so hashed membership is unsuitable for matching restored activity.
New due words can increase the total; this is current review workload, not a fixed
daily goal or a percentage of language knowledge. Deleting vocabulary or changing
folder memberships changes the live scope without changing stored vocabulary.
An empty workload has zero progress, while a nonempty completed workload is full.
Daily activity resets on the local calendar day; progress reads are pure and
ignore stale days, while appearance/foreground/review events refresh persisted
state. Training recomputes time-based status periodically. Free practice of up to
ten random scoped words remains available when none are due or pending.
Session progress counts answers (including retry attempts); the completion screen
separately reports unique words and total answers.

## Achievements

Data flows one way: sources -> `AchievementMetrics` -> `AchievementEvaluator` ->
`AchievementStore` (unlocks) -> UI. Metrics are named integers (`AchievementMetric`).
Derived metrics (`AchievementMetrics.vocabulary`) are recomputed from Word/WordFolder
records and are retroactive; recorded metrics come from `AchievementLedger`
(lifetime answers, listening, perfect quizzes, streaks), updated by
`AchievementStore.record` after each accepted flashcard, quiz or listening answer.
Both persist nothing but `achievements.v1` in UserDefaults (unlock dates, ledger,
`didInitialSync`). Unlocks are permanent: falling metrics or deleted words never
revoke them, and removed catalog entries are ignored, not deleted. IDs are never reused.
The first sync after install/upgrade unlocks satisfied derived achievements silently;
later unlocks queue banners. `AchievementTracker` (root) syncs from `@Query` data and
scene phase. The store owns banner state (queue, one dismiss timer, announce-once), so
`.achievementBanner()` can be applied on the root, `AddWordView` and `ScanResultView`;
any new sheet that can save words needs the modifier too.
`recordNextUnlocksSilently` (set by `SyncStore` after a pull that changed vocabulary) is a
one-shot, in-memory, 10 s flag: the next `sync` that unlocks something records it without banner
or log.

To add: an achievement on an existing metric is one `AchievementDefinition` line in
`AchievementCatalog.all`; a derived metric is a new `AchievementMetric` case plus its
computation in `AchievementMetrics.vocabulary`; a recorded metric also needs a ledger
field (decoded with a default), an `AchievementEvent` and a call site; a new criterion
kind needs an `AchievementCriterion` case, an evaluator branch and a test.

## Workspaces

A workspace is a language pair (studied `term` ← `translation`); its id is the uuid v5 of the pair
(`WorkspaceID`), so one pair is one workspace on every device. Words, folders, memberships, the daily ring
and practice are scoped to the active workspace (`WorkspaceScope`, in memory, `effectiveWorkspaceID`).
Achievements stay global.

- **Store.** `WorkspaceStore` is the single write entry point (create/restore, select, reorder, soft delete,
  input side of same-script pairs). `create` logs `workspace.created`, or `workspace.restored` when the pair
  revives a tombstone (`WorkspaceEnsureResult.outcome`). Changing the active workspace re-points
  `VocabularyStore`/`FolderLibraryStore` (`onActiveChange`). Deleting is soft: words and folders stay hidden
  and return when the pair is added again; the last active workspace cannot be deleted.
- **Gate (`RootTabView`, `Services/Workspaces/WorkspaceGate.swift`).** No active workspace: `loading` while the session
  is restored (`AuthStore.unknown`), `waitingForAccount` while a signed-in, linked account's first workspace
  pull is running (`SyncStore.workspacePullFinished`, set after the pulled workspaces are loaded), else
  `needsSetup` = the first-launch wizard as a full-screen cover. One 10 s timer covers loading and waiting.
  A fresh install gets no workspace from `WorkspaceBackfill`; an existing install gets pl ← ru silently.
- **UI.** `WorkspaceWizardView` (two steps, also a sheet from «Новый язык…»), `.workspaceTitleMenu(words:)`
  on Словарь and Практика (inline title with the system `toolbarTitleMenu` chevron; the large-title menu has
  no chevron on iOS 26), `WorkspaceManagerView` («Языки»: select, reorder, delete with confirmation, add).
  A workspace switch dismisses sheets built with the old pair and resets folder/category/search filters.
  Same-script pairs show the «Ввожу на» control in `AddWordView` (remembered per workspace).
- **Fixtures.** `freshInstall`, `multiWorkspace`, `sameScriptWorkspace`; sync state `remoteWorkspaces`.

## Sync

Workspaces, folders, words and memberships (with SRS state) sync with `public.workspaces`, `public.folders`,
`public.words` and `public.word_folders`;
achievements and daily activity stay per device. Local SwiftData is the source of truth and the
app works offline. Pieces: `Services/Sync/SyncEngine.swift` (one cycle), `Services/Sync/SwiftDataSyncStore.swift`
(the SwiftData side), `Services/Sync/SyncRemote.swift` (transport protocol, cursor), `Services/Sync/SyncState.swift`
(`sync.v1` in UserDefaults), `Backend/SupabaseSyncRemote.swift` (the only Supabase import),
`Stores/SyncStore.swift` (triggers, status). `InMemorySyncRemote` (DEBUG) serves unit and UI tests.

- **Cycle.** Every cycle pulls workspaces, folders, words and memberships (the foreign-key order), then
  pushes them in the same order, so a remote tombstone is seen before any push. A membership is pushed
  only when its word and folder are known synced (not held, not session-rejected). One cycle runs at a time; a trigger
  during a run schedules one follow-up. Triggers: sign-in/launch with a restored session, foreground
  (throttled to 30 s), 5 s after the last local edit (`LocalChangeSignal` from the three stores),
  background (inside a background task) and before sign-out (inside the 3 s bound), and the
  manual button in the account sheet.
- **Wire mapping (v2).** `workspace_id` (= `WorkspaceID`, the uuid v5 of `term>translation`; the server
  enforces it), `term` = `polish`, `translation` = `russian` (storage names), `entered_side` (`term` |
  `translation`) = `sourceLanguageCode` against the workspace's codes (an unknown code pushes `term`),
  `category` = `WordCategory.stableID`. Pulled text is stored with the per-language case rule
  (`Services/Language/LanguageCodes.swift`: only German keeps case). Workspace languages are validated against
  the supported list (`pl ru uk en de fr es it cs pt`); a word/folder whose workspace is unknown is
  held until it arrives. Text length counts Unicode scalars; interior tab/newline are allowed. Every
  upsert row encodes every key (explicit `null`s); the legacy columns no longer exist.
- **Memberships.** `FolderMembership` (id = `MembershipID`, a client-only uuid v5 of word and folder)
  mirrors `word_folders`; conflicts are per (word, folder). Removing one is a tombstone, adding it
  again revives it. A local or pulled word/folder tombstone tombstones its active memberships. A
  membership tombstone whose word or folder is unknown is skipped (`orphan_tombstone`), an active one
  is held. `Word.folderIDs` is frozen legacy storage, migrated once into memberships
  (`WorkspaceBackfill`, flag `legacyFolderIDsMigrated`).
- **Workspaces.** Ids are deterministic, so there is no workspace adoption. `RemoteMergePolicy` has one
  documented exception to «a remote tombstone with no local row creates nothing»: workspace tombstones
  are stored (clean), so words and folders of a workspace deleted elsewhere are stored hidden and come
  back when the pair is re-added.
- **Dirty tracking.** `serverUpdatedAt` on `Word`/`WordFolder` holds only a server `updated_at`, nil
  (never synced) or the re-link sentinel `Date.distantPast`; device time is never written to it.
  `isSyncDirty = serverUpdatedAt != lastModifiedAt` (equality, never ordering). After a push ack or an
  applied pull both `updatedAt` and `serverUpdatedAt` take the server time; an ack applies only if the
  row did not change during the request.
- **Server time.** A trigger (`private.set_server_updated_at`, `clock_timestamp()` truncated to ms, at
  least previous + 1 ms) assigns `updated_at`; clients never send it. Server hard deletes are revoked:
  soft delete (`deleted_at`) is the only deletion, tombstones are always pushed.
- **Cursor.** One cursor per table (four): `(updated_at millis, id)`; memberships use
  `(updated_at, word_id, folder_id)` (`SyncCursor.secondaryID`). A pull starts 60 s before it
  (out-of-order commits), filters `user_id`, orders by `(updated_at, id)` and pages by 500 with the
  keyset filter; the cursor is saved after each applied page. Content-invalid rows are skipped and
  counted and the cursor moves past them; their ids are held (`SyncState.heldIDs`, max 5 000) so the
  local copies are not pushed over a newer client's version. A foreign-owner row aborts the cycle.
  `capabilityVersion` bumps (now 2) clear all cursors and held ids; widening the supported languages or a
  validator later bumps it again.
- **Conflict rule** (`RemoteMergePolicy`): no local row inserts (or adopts a duplicate pair/folder name
  that was never synced); the re-link sentinel lets the server win unless the row was edited after the
  link (`SyncState.linkedAt`, device clock vs the row's own `updatedAt`); an echo or stale row keeps
  local; a clean local row follows the server; a dirty local row is kept and pushed (last device to sync
  wins), except that a remote tombstone beats an active local edit. Nothing hard-deletes a local word.
- **Linking.** The first signed-in account is linked automatically. Linking resets per-row state
  (clean synced rows get the sentinel, others nil). A different account pauses sync
  (`accountMismatch`); «Объединить» in the account sheet re-links after confirmation. Sign-out keeps
  local data and the link.
- **After a pull.** Changed workspaces reload `WorkspaceStore`, changed folders or memberships refresh
  `FolderLibraryStore.options`; `SyncStore.workspacePullFinished` is set after the workspace pull; changed vocabulary makes
  `AchievementStore.recordNextUnlocksSilently` skip banners for the next unlock (10 s, one-shot).
- **Logging.** `sync.completed/failed/rows_skipped/linked/account_mismatch` with counts, trigger and
  reason names, error domain/code; never text, ids or emails.

## Localization

- **Catalogs:** `MojSlownik/Localizable.xcstrings` (UI copy) and `InfoPlist.xcstrings` (camera,
  microphone and speech usage descriptions). Source language `en`, translation `ru`; iOS picks the
  system language and falls back to English. Code gets strings through `Text("…")` /
  `String(localized:)`; key style is the English sentence (`language.<code>.<form>` for language
  names).
- **`LanguageNames`** (`Services/Language/Language.swift`): localized forms of a language name (name,
  inline, input option, genitive, adverb, placeholder) read from the catalog; `Language` keeps
  only codes, flags and endonyms.
- **`AppLocale.current`:** the language iOS resolved (`Bundle.main.preferredLocalizations`) with
  the system region; use it for dates and numbers instead of a fixed locale.
- **Plurals:** one numeric argument per key (`%lld words`, `%lld folders`, `%lld points`,
  `%lld days`) with en one/other and ru one/few/many/other variations; no `%#@` or
  substitutions. `WorkspaceLabels` has the helpers.
- **Data regions:** domain data that contains Cyrillic (`WordCategory` raw values, fixtures,
  language endonyms) is never localized and sits in `// l10n:data-begin` / `// l10n:data-end`
  blocks or on lines ending `// l10n:data`.
- **Checks:** `scripts/check-localization.sh <DerivedData>` compares the `.stringsdata` the
  compiler emits (`SWIFT_EMIT_LOC_STRINGS`) with the catalog (missing and dead keys; CI runs it
  after the build). `LocalizationCatalogTests` validates both languages and format specifiers;
  `SourceHygieneTests` rejects Cyrillic in comments everywhere and in app string literals outside
  data regions.
- **Test language:** the `MojSlownikUnitTests` scheme pins `language: en`, `region: US`. E2E
  launches in Russian by default; `E2ETestCase.launch(language:)` takes `.russian`, `.english`,
  `.german` (falls back to English) or `.germanThenRussian` and passes `-AppleLanguages` /
  `-AppleLocale`.

## Study Folders

`Models/WordFolder.swift` stores a UUID, display name, creation date and persisted
display order. Existing folders whose additive ordering value is equal retain a
deterministic legacy order by creation date and UUID; the first explicit reorder
replaces that fallback with contiguous saved positions. New folders append after
the current order, and deletion keeps the relative order of the remaining folders.
Memberships are `FolderMembership` rows (`Models/FolderMembership.swift`; `Services/Data/MembershipIndex.swift`
reads them): one vocabulary entry can belong to multiple folders, sharing its SRS progress.
`Word.folderIDs` is frozen legacy storage, migrated into memberships once. Categories remain independent.
`Services/Data/FolderStore.swift` validates folder names, prevents case-equivalent duplicates,
changes memberships and soft-deletes folders (`FolderLibraryStore` over `FolderRepository`)
without deleting vocabulary or SRS.
`Stores/FolderLibraryStore.swift` is the single app-scoped observable catalog, injected through
SwiftUI's environment at MojSlownikApp. All selectors and dictionary folder menus
read its options; creation and deletion actions refresh the same catalog. SwiftData
remains persistent storage. Membership/deletion operations use isolated contexts;
creation uses the observed context. Names collapse whitespace and compare using
canonical Unicode and lowercase to reject duplicates.

Folder selection uses a dedicated sheet with a direct list and checkmarks.
Creation opens a SwiftUI Form destination (not a native alert TextField); failures
remain visible next to the entered name, and success selects the folder and closes the sheet. The
catalog is loaded explicitly when opening a selector; it does not rely on a nested
native Menu/Picker or on a per-view Query snapshot. Only the destination selection
and presentation state stay local to each screen, preserving the no-folder default
for a new scan. Removing a folder clears invalid local selections through the shared
catalog update.

The same self-contained `FolderPicker` sheet exposes `Править`: users can drag
folders into a new order, rename one in a prefilled form, or request deletion with
the existing named confirmation. Selection remains a one-tap checkmark action
outside edit mode; persistence and shared-catalog refresh remain in
`FolderStore`/`FolderLibraryStore`, not in individual screens.

`FolderPicker` is reused in dictionary, add, scan and training screens. It can create
and select a folder. AddWordView initializes its destination once through SwiftUI State, preserving
a newly created/selected folder across subsequent appearances. Scanner/add default to no destination; dictionary/training nil
means all words. The dictionary row folder menu adds/removes existing membership;
the selected folder can be deleted with confirmation. New manual words use idempotent
`ScanWordStore.add`: an existing exact pair is reused, retaining its SRS and category
unless category was explicitly changed.

In a selected scan folder, a card tap toggles membership only. Existing global words
are reused; removing from a folder never deletes the global word. Flashcards and quiz
filter through `FolderStore.words` before session/question generation, including all
quiz distractors. Empty folders never fall back to global vocabulary.

## Reusable Views

`Views/Components/` contains FolderPicker, CategoryMenu, PronounceButton,
SessionProgress, PrimaryButtonStyle, chipStyle, MarkerProgressBar, KnowledgeTierBadge
(ring), AchievementBadge, AchievementBanner, the achievementBanner() modifier and the
errorAlert modifier. CategoryMenu shares available choices
and selected-state behavior while callers supply their label and persistence action.
SessionProgress shares practice-session progress rendering. errorAlert shares optional
error presentation and dismissal. Screens retain navigation, session state and content;
Theme.cardStyle handles shared surfaces instead of a universal card component.

## Presentation

The «Маркер» language: warm paper, ink type and highlighter-yellow fills. Practice is
hero-led with one primary action, and flashcards flip on tap. Tokens, components, icons,
motion and haptics are defined in [DESIGN.md](../DESIGN.md).

## Non-obvious Constraints

- Language detection checks Unicode `U+0400…U+04FF`: any Cyrillic means Russian;
  everything else means Polish. This is an alphabet heuristic, not full detection.
- New input cancels the previous translation task and clears the translation so
  an old value cannot be saved with a new word. Translation remains editable;
  insertion does not enforce pair uniqueness.
- On physical iOS 18+ devices: Apple with a 4-second timeout → Google → MyMemory.
  Apple is skipped on iOS 17 and in the simulator. Cancellation propagates to the
  caller rather than triggering fallback.
- Apple provides `TranslationSession` only through a view's `.translationTask`.
  `AppleTranslationModel.shared` connects the facade to the root modifier using
  a continuation. It holds one pending request; a new request cancels the previous
  one. Cancellation handling prevents session waiting from blocking the timeout.
- Google uses an unofficial endpoint without a key. MyMemory rejects empty,
  unchanged and script-incompatible candidates (target script required, source-only
  script letters rejected, driven by `Language` descriptors); it tries the
  main response, then `matches` in descending score order. A non-200 `responseStatus`
  and `MYMEMORY WARNING` texts are never used as translations. This filters candidates
  but does not guarantee quality. Requests include the implementation's default contact email.
- Alternatives (`TranslationAlternativesService`) are fetched from Google and MyMemory
  even when Apple translates, so entered text leaves the device. Each source fails
  silently (5 s resource timeout, ephemeral session), results are deduplicated
  case-insensitively, capped at 6 and never stored. `AddWordDraft` keeps its task until
  alternatives finish; dictation keeps visible chips and clears them only when the text changes.
- The camera requires permission and positive `DataScannerViewController.isSupported`
  and `isAvailable` checks. OCR languages are selected from supported ru/pl languages;
  if neither is supported, an empty list allows automatic selection. Polish
  diacritics are not guaranteed.
- Tokenization preserves punctuation. Alphanumeric characters, apostrophes and
  hyphens belong to words. Only tokens longer than one character are selectable
  in text and chips; repeated words are preserved.
- Words and folders are soft-deleted (`deletedAt`). Every read filters `isActive` in memory
  (`@Query` is stored as `stored…` plus a filtered computed property); no `#Predicate`.
  A write sets `updatedAt` only when a persisted field changed; `DailyStudyStore.review`
  and `recordPracticeAnswer` bump it unconditionally. Legacy `updatedAt == nil` reads as
  `createdAt` (`lastModifiedAt`). `achievements.v1` and `dailyStudyActivity.v1` formats are
  owned by `ProgressRepositories.swift` and must stay byte-compatible.
- Due words and search results are filtered in memory after `@Query`. Flashcards
  use all due words, or up to 10 random words if none are due. Again sets `dueDate`
  to 10 minutes later and also appends the word to the current session.
- SRS intervals use days × 86,400 seconds, not calendar days. Learned statistics
  mean `repetitions >= 3`; Again resets that counter.
- Quiz requires at least 4 records and generates **up to** 10 questions. Options
  are deduplicated by exact text, so duplicate translations may yield fewer than
  four choices; questions without distractors are skipped.
- UI-test mode is DEBUG-only (`Services/UITestSupport/UITestLaunchConfiguration.swift`,
  `Services/UITestSupport/UITestFixtures.swift`) and is activated by `UITEST_FIXTURE=<name>` and/or
  `UITEST_PREFILL=<text>`. `UITEST_PREFILL` opens a scan result without the camera and
  implies fixture `empty` when no fixture is given. The app then uses an in-memory store
  seeded from `UITestFixture`, and the `MojSlownik.UITest` defaults suite (daily study,
  achievements) wiped on every launch. Translation and alternatives are stubbed at
  `Translator`/`TranslationAlternativesService` (no network). Fixture dates are relative
  to launch time. An unknown fixture name crashes at launch. Release builds contain none
  of this code.

Regenerate with `xcodegen generate` after adding source files or changing project
configuration. Build and verification instructions: [AGENTS.md](../AGENTS.md).
Personal iPhone installation: [README.md](../README.md).

## Backend Readiness

Words and folders sync (see Sync). Local SwiftData stays the source of truth (offline-first);
rows are exchanged by id, server `updated_at` and `deleted_at`.

`Backend/SupabaseConfiguration.swift` holds the project URL, publishable key (public;
secret keys never ship in the app) and OAuth redirect. `Backend/SupabaseClientProvider.swift`
creates one `SupabaseClient` lazily, owned by `AppResources`; `AuthStore.start()` creates it at
launch in production only (UI tests, previews and the unit-test host use `StaticAuthBackend`).

Auth: `signInWithOAuth` (PKCE, ASWebAuthenticationSession, no entitlement, so it works with a
free Personal Team). The redirect `com.kirill.personal.mojslownik://auth-callback` must be in
Supabase → Authentication → URL Configuration; Apple and Google providers are configured in the
Supabase dashboard (README). The session lives in the SDK's Keychain storage.

Remote schema (`supabase/migrations`, normalized by `20261121090000_language_workspaces`):
`workspaces` (one row per language pair; the languages live only here; id = uuid v5 of the pair),
`folders` and `words` (both with `workspace_id`; `words.entered_side` is `term` or `translation`;
`category` is `WordCategory.stableID`), `word_folders` (memberships with composite foreign keys that
keep word and folder in one workspace and one owner) and write-only `app_logs`. All RLS-scoped to
`user_id`; `anon` has no grants; no hard deletes. The migration dropped `term_language`,
`translation_language`, `entered_language` and `folder_ids`; their data is in
`private.words_backup_20261121` / `private.folders_backup_20261121` until a later migration drops them.
Pre-migration app builds cannot sync afterwards. The local `Word` keeps the ru/pl storage names
(`polish` → `term`, `russian` → `translation`).
`RemoteRecordValidator` runs on every pulled row (and on outgoing rows); `RemoteMergePolicy` decides.

Remaining gaps:

- **A.** Closed: a pull that changes folders refreshes `FolderLibraryStore.options`.
- **B.** Closed: `updated_at` is server-assigned (trigger); conflicts compare server time only.
- **C.** Tombstones are never purged; purging needs server acknowledgement.
- **D.** Device-local by design: daily activity is not synced (keyed by `PersistentIdentifier`; adoption keeps identifiers).
- **E.** Closed: membership conflicts are per (word, folder) (`word_folders`).
- **F.** Accepted: SRS state merges per whole row (last device to sync wins).
- **G.** Device-local by design: achievements are not synced; unlocks caused by pulled vocabulary are recorded silently.
- **H.** RLS and category encoding done; the pair is unique per user on the server (`workspaces`); words
  and folders stay unique only by id, mitigated by duplicate adoption on pull (scoped to the workspace).

## Tests and CI

`MojSlownikTests/` contains XCTest coverage for Word lowercase storage, category
assignment/overrides, normalized duplicate-pair matching, SwiftData round trips,
OCR tokenization, translation alternatives parsing/merging, language descriptors and MyMemory validation, SRS scheduling, and scan add/remove/category persistence, folder membership and scoped quiz options. The scanner reuses `Word.matches` for pair
lookup, so its duplicate-comparison rules are tested outside SwiftUI.
Run the isolated `MojSlownikUnitTests` scheme (see AGENTS.md); it does not include
`MojSlownikUITests`. New or changed nontrivial logic requires committed unit tests.
Network translation and physical-camera behavior are not exercised by these tests.

E2E: `MojSlownikUITests/` holds XCUITest classes (AddWordFlow, EditTranslationFlow,
FlashcardsFlow, QuizFlow, FoldersFlow, AccountFlow, SyncFlow, LocalizationFlow) on the shared `E2ETestCase`, each launching a
named fixture. Rule: when a user-facing flow changes, add or update E2E scenarios; reuse
fixtures or add new ones (with unit tests in `UITestSupportTests`) and never seed data
through UI steps. Typed E2E input must be ASCII; Cyrillic sources arrive via
`UITEST_PREFILL`. Run with the `MojSlownikE2E` scheme (parallel classes on simulator
clones). Existing classes run in Russian (the `language:` default); `LocalizationFlowTests` covers English, Russian, an unsupported language and a preferred-language list. Camera, OCR and physical-device checks stay manual.

CI (`.github/workflows/ci.yml`, PRs to `main`, pushes to `main`, manual dispatch):
`Build & unit tests`, E2E shards `practice` (Flashcards, Quiz) and `dictionary` and
`Branch freshness` (PR only; fails when the PR is more than 10 commits behind `main`).
The `dictionary` shard is the catch-all (`-only-testing:MojSlownikUITests` minus the
`-skip-testing` classes); a new class goes to `practice` only by adding it to both the
`practice` `-only-testing` and the `dictionary` `-skip-testing` lists. `ci-passed` is the
single aggregate check. `.github/rulesets/main.json` defines the `main` ruleset (PR
required, `ci-passed` required, no bypass, no force-push or deletion); apply it with
`gh api -X POST repos/KirillTK/MojSlownik/rulesets --input .github/rulesets/main.json`.
`.github/scripts/pick-simulator.sh` prints a destination for the newest iPhone simulator.
