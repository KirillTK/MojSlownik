# Custom study folders

## Goal
Users can create named folders such as “Урок 1”, add existing or new words to several folders without duplicating vocabulary, and study an individual folder through flashcards or quiz. Every newly opened scan starts without a selected destination.

## Context and decisions
The user explicitly chose multiple folders per word. Categories remain independent topic labels. Use one new WordFolder model and declaration-default UUID memberships on Word. No backend, no relationships/cascade deletion, no E2E/UI automation. Existing working-tree category, lowercase, toggle, unit-test and design changes must remain intact.

## Acceptance criteria
- AC-1: Create a named folder with trimmed, nonempty name; duplicate names are resolved consistently (case-insensitive reuse or clear validation). A new folder is selectable immediately.
- AC-2: A word can belong to several folders. Adding it to a folder reuses the existing normalized ru/pl pair, preserves its category and SRS, and does not create a duplicate.
- AC-3: At the top of every scan result, a destination control starts at “Без папки”, supports selecting a folder and creating one. Changing destination updates each chip’s membership state.
- AC-4: In folder mode, chip tap adds/removes membership only; removing never deletes the word or other memberships. With no folder, retain explicit existing global dictionary add/remove behavior.
- AC-5: Users can browse folders, add/remove existing dictionary words, create/delete folders, and add a new word into a chosen folder. Deleting a folder preserves vocabulary and SRS.
- AC-6: Training statistics, flashcard candidates, quiz prompts and distractors are all restricted to the selected folder. Nil study selection means all words. Empty folders and fewer than four quiz words have clear disabled/empty states.
- AC-7: Existing stores retain words, category and SRS after migration; memberships start empty. Existing no-folder flows and tests remain compatible.
- AC-8: Native XCTest tests verify folder creation/validation, multi-membership persistence, scoped toggle and deletion behavior, study selection and migration where practical. App build and isolated unit suite pass; no E2E.

## Minimal model/API
- Models/WordFolder.swift: @Model with `id: UUID`, `name: String`, `createdAt: Date`; declaration-level defaults wherever required by additive migration. Initialize fresh UUID.
- Models/Word.swift: `var folderIDs: [UUID] = []`; simple add/remove/contains helpers avoid duplicate UUIDs. Keep old initializer source compatible, optionally accept folder IDs.
- MojSlownikApp.swift: ModelContainer schema includes Word and WordFolder. Update previews/test containers that query WordFolder as well.
- Services/FolderStore.swift: `create(name:container:)` validates trimmed nonempty name and normalized uniqueness; `delete(id:container:)` removes membership IDs from all words then removes folder in one isolated save. Membership writes use explicit save and isolated rollback so unrelated pending edits are not committed/discarded.
- Services/FolderStore.swift also exposes `words(_ words: [Word], in folderID: UUID?) -> [Word]`, returning all for nil or members otherwise; reuse for Training, Flashcards and Quiz. `create` returns WordFolder. `setMembership(wordID: PersistentIdentifier, folderID: UUID, included: Bool, container:)` supports explicit dictionary membership writes.
- Services/ScanWordStore.swift: optional `folderID: UUID? = nil` appended to toggle. Validate a selected folder still exists before writing. With folder, reuse exact matching pair; toggle only that folder ID. For legacy duplicate pairs, coordinate state across matches and avoid toggling one match while showing another. No-folder behavior retains global add/remove, including removing legacy exact duplicates.
- Reusable Views/Components/FolderPicker.swift: `FolderPicker(selectedFolderID: Binding<UUID?>, allowsAll: Bool = false)`; nil means “Все слова” when allowsAll, otherwise “Без папки”; @Query folders; native Menu with current selection, no-selection option and create action. Create sheet/alert has validation/error feedback and selects newly created folder. Re-query selection validity if folder removed.

## Changes by screen
1. ScannerView: destination picker before source card; @State selectedFolderID nil. Compute isSaved as membership in selected folder, otherwise dictionary presence. Local immediate saved overrides must be cleared on folder selection and correction dismissal to avoid stale per-folder state. Pass selected folder to correction AddWordView and toggle. Saved copy says “В папке”/“Убрать из папки” in folder mode and existing dictionary wording otherwise. Category edit still affects the shared word, not a folder copy.
2. AddWordView: optional initialFolderID, destination picker; save attaches selected folder to word (and reuses existing pair when assigning it to a folder). New form defaults nil unless opened from an explicit folder destination.
3. WordListView: folder selection/browsing alongside category filters; per-row folder membership selection supports multiple checkmarks. Folder deletion removes organization only; do not overload normal word deletion with membership removal without clear labels. Preserve search and stable delete offsets.
4. TrainingView: folder selector; use scoped words for stats and enablement; pass immutable selected ID to FlashcardsView and QuizView.
5. FlashcardsView and QuizView: optional folderID default nil. Filter before snapshot/session generation; quiz distractors must use same scope. No fallback to global words when folder empty. A running session is a snapshot; changing parent selection does not mutate it.
6. docs/architecture.md and short AGENTS architecture map: explain new folder schema, shared SRS, nil selection semantics and unit tests.

## Verification
Run xcodegen generate after new files. Build application using installed iPhone simulator. Run only MojSlownikUnitTests scheme. Tests: multi-folder memberships persist, duplicate adds reuse pair, selected folder toggle removal preserves word/other folders/SRS, no-folder toggle unchanged, folder deletion preserves vocabulary/progress, empty/duplicate folder names, unknown/deleted folder IDs fail clearly, scoped flashcard and quiz pool exclude outsiders, nil scope includes all, stale scanner state reset reviewed. Add an isolated old-schema migration check if feasible; do not equate fresh container tests with migration proof. Report physical camera/manual UI checks as not performed unless actually done.

## Risk and safeguards
- UUID arrays are additive and simple but need cleanup on folder deletion; centralized FolderStore owns that cleanup.
- Shared Word means SRS progress is shared across packs. This matches no-duplicate requirement; do not reset progress when adding/removing memberships.
- Scanner currently uses savedOverrides keyed only by source. Clear on destination change or key by folder scope.
- Isolated contexts avoid saving unrelated pending work but require UI immediate state reconciliation and fresh persisted lookups for subsequent actions.
- SwiftData previews and tests using Word-only schemas must include WordFolder when they instantiate querying folder views.
- Folder deletion must never cascade to words. Global deletion intentionally removes the word from all folders because the one Word record is removed.

## Open questions
None required. Shared SRS across folders follows the one-word, many-folder design. “Без папки” is no destination in scanner; “Все слова” is unrestricted scope in training.
