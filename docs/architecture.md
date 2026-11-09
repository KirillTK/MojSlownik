# Mój Słownik Architecture

Personal ru ↔ pl dictionary for iPhone, using SwiftUI and SwiftData on iOS 17+.
No backend, accounts or synchronization. Vocabulary is stored locally; web
translation sends entered or recognized text to an external service.

## Application Map

Paths below are relative to `MojSlownik/` unless stated otherwise.

| Area | Files and responsibilities |
| --- | --- |
| Startup | `MojSlownikApp.swift` creates a model container for `Word` and `WordFolder` and `RootTabView`. |
| Navigation | `Views/RootTabView.swift`: Dictionary and Training tabs, root `AppleTranslationHost`. |
| Persistence | `Models/Word.swift`: Russian/Polish pair, source language, persisted category, creation date and SRS state; alongside the `WordFolder` model for custom study packs. |
| Dictionary | `Views/WordListView.swift`: creation-date `@Query`, search in both languages, deletion, add and camera presentation. |
| Adding words | `Views/AddWordView.swift`: language detection, 600 ms translation debounce, manual editing, automatic/manual category selection, insertion through `modelContext`. |
| Translation | `Services/TranslationService.swift`: `Translator` facade; implementations in `AppleTranslator.swift`, `GoogleWebTranslator.swift`, `MyMemoryTranslator.swift`. |
| Camera and results | `Views/ScannerView.swift`: permission, VisionKit bridge, line translation, compact bilingual quick-add cards and an explicit correction menu opening nested `AddWordView`. `Services/ScannedTextTokenizer.swift` separates words and punctuation. |
| Practice | `Views/TrainingView.swift`: statistics and entry points to `FlashcardsView`/`QuizView`; `Services/SRSEngine.swift`: scheduling. |
| Speech and styling | `Services/SpeechService.swift`, `Views/Components/PronounceButton.swift`: system speech; `Theme/Theme.swift`: dynamic colors and cards. |
| Build | Root `project.yml`: XcodeGen, application and `MojSlownikUITests`, iOS 17.0, Swift 5.9. |

## Data Flows

**Adding:** input → `LanguageDetector` → `Translator` → editable translation →
`Word` → SwiftData → dictionary/training `@Query` updates. Pair fields always
follow their languages regardless of input direction. These screens use the
SwiftData context and autosaving, without a repository layer or explicit `save()`.

**Scanning:** tap a recognized line → dismiss camera → present `ScanResultView`
after 0.4 seconds → translate the line, then each unique word sequentially.
Chips show original, translation and category. With no destination folder, tapping a ready card toggles its pair in the dictionary: add, remove, then add again.
The saved state shows a checkmark and an explicit removal hint. Removing a word also
removes its SRS progress; re-adding starts a new record. `Services/ScanWordStore.swift`
uses a fresh context for each operation, normalizes pair lookup with `Word.matches`,
and rolls back only that operation on failure. It does not save or roll back unrelated
pending edits in the screen context.
The source is a plain paragraph preserving punctuation. An explicit word-correction
menu opens `AddWordView(initialText:)`; scan translation pauses
while that sheet is open and resumes on dismissal. Closing either screen cancels its
translation work. Translation failures can be retried.

**Categories:** `Services/WordCategory.swift` assigns one of seven topics using
exact normalized Russian/Polish keyword matches, falling back to Other. This is a
small local vocabulary, not semantic classification; inflections may be unrecognized.
`Word.categoryRawValue` has a declaration-level Other default for existing stores;
new words are classified automatically unless a manual override is supplied.
Categories can be changed through a chevron menu inside each scan card (including
saved words), in the add form, or through the dictionary row's category menu.
A horizontal category/count strip filters the dictionary alongside text search.

**Practice:** session snapshot → flip card → rating → mutate SRS fields on the
same `Word`. Quiz questions and score live in view state and do not change SRS.

## Study Folders

`Models/WordFolder.swift` stores a UUID, display name and creation date.
`Word.folderIDs` is an additive array defaulting to empty: one vocabulary entry can
belong to multiple folders, sharing its SRS progress. Categories remain independent.
`Services/FolderStore.swift` validates folder names, prevents case-equivalent duplicates,
changes memberships and deletes folders without deleting vocabulary or SRS.
`Stores/FolderLibraryStore.swift` is the single app-scoped observable catalog, injected through
SwiftUI's environment at MojSlownikApp. All selectors and dictionary folder menus
read its options; creation and deletion actions refresh the same catalog. SwiftData
remains persistent storage. Membership/deletion operations use isolated contexts;
creation uses the observed context. Names collapse whitespace and compare using
canonical Unicode and lowercase to reject duplicates.

Folder selection uses a dedicated sheet with a direct list and checkmarks. The
catalog is loaded explicitly when opening a selector; it does not rely on a nested
native Menu/Picker or on a per-view Query snapshot. Only the destination selection
and presentation state stay local to each screen, preserving the no-folder default
for a new scan. Removing a folder clears invalid local selections through the shared
catalog update.

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
SessionProgress and the errorAlert modifier. CategoryMenu shares available choices
and selected-state behavior while callers supply their label and persistence action.
SessionProgress shares practice-session progress rendering. errorAlert shares optional
error presentation and dismissal. Screens retain navigation, session state and content;
Theme.cardStyle handles shared surfaces instead of a universal card component.

## Presentation

Theme uses adaptive cream/paper surfaces, terracotta actions, warm ink and olive
success colors. `appOnAccent` supplies contrasting text on solid accent fills in
both appearances. Controls retain 44-point targets and use Dynamic Type text;
scan cards switch to a single column at accessibility text sizes. Save and category
selection are sibling controls. Saved cards remain readable rather than dimmed.

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
  unchanged and alphabet-incompatible candidates; it tries the main response,
  then `matches` in descending score order. This filters candidates but does not
  guarantee quality. Requests include the implementation's default contact email.
- The camera requires permission and positive `DataScannerViewController.isSupported`
  and `isAvailable` checks. OCR languages are selected from supported ru/pl languages;
  if neither is supported, an empty list allows automatic selection. Polish
  diacritics are not guaranteed.
- Tokenization preserves punctuation. Alphanumeric characters, apostrophes and
  hyphens belong to words. Only tokens longer than one character are selectable
  in text and chips; repeated words are preserved.
- Due words and search results are filtered in memory after `@Query`. Flashcards
  use all due words, or up to 10 random words if none are due. Again sets `dueDate`
  to 10 minutes later and also appends the word to the current session.
- SRS intervals use days × 86,400 seconds, not calendar days. Learned statistics
  mean `repetitions >= 3`; Again resets that counter.
- Quiz requires at least 4 records and generates **up to** 10 questions. Options
  are deduplicated by exact text, so duplicate translations may yield fewer than
  four choices; questions without distractors are skipped.
- The `UITEST_PREFILL` launch environment variable opens a scan result without
  the camera. It is an existing UI-test entry point, not a separate data source.
  The feature workflow does not create, update or run UI automation.

Regenerate with `xcodegen generate` after adding source files or changing project
configuration. Build and verification instructions: [AGENTS.md](../AGENTS.md).
Personal iPhone installation: [README.md](../README.md).

## Unit Tests

`MojSlownikTests/` contains XCTest coverage for Word lowercase storage, category
assignment/overrides, normalized duplicate-pair matching, SwiftData round trips,
OCR tokenization, SRS scheduling, and scan add/remove/category persistence, folder membership and scoped quiz options. The scanner reuses `Word.matches` for pair
lookup, so its duplicate-comparison rules are tested outside SwiftUI.
Run the isolated `MojSlownikUnitTests` scheme (see AGENTS.md); it does not include
`MojSlownikUITests`. New or changed nontrivial logic requires committed unit tests.
Network translation and physical-camera behavior are not exercised by these tests.
