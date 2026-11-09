# Swipe to delete words and folders

## Goal

Expose normal left-swipe red «Удалить» buttons for dictionary words and custom folders. Word deletion removes the exact record globally, even in a selected folder. Folder deletion preserves all vocabulary and study progress. Baseline: `da6f24a3b29ffc500f3ce60372f9881ea55043ed`, clean worktree reported at task start.

## Acceptance criteria

- **AC-1:** Left swiping a word reveals red «Удалить». Tapping persistently deletes only that record in all/search/category/folder views; other matching legacy duplicates survive.
- **AC-2:** Every custom folder in the shared picker has the same swipe action. Synthetic «Все папки» / «Без папки» rows do not.
- **AC-3:** Folder confirmation names the folder and says «Слова останутся в словаре». Cancel changes nothing; confirm removes only that folder and its memberships, preserving words, other memberships and SRS.
- **AC-4:** Shared catalog consumers refresh and a deleted selected folder falls back to nil through existing reconciliation. Other selections remain. Existing dictionary toolbar deletion stays consistent.
- **AC-5:** Persistence failures display Russian errors; deletion explicitly saves in an isolated context without saving or rolling back unrelated pending edits.
- **AC-6:** Preserve iOS 17, existing records and UI tests/targets. No dependency, schema, SRS or translation change.

## Source and reuse

`WordListView` currently uses implicit `.onDelete` and view-context deletes without explicit save/error handling. `FolderPicker` already lists custom options and reconciles selection when shared IDs change. `FolderLibraryStore.delete` already delegates to isolated `FolderStore.delete`, preserves words, removes matching memberships and refreshes shared options. Existing folder tests cover progress preservation and shared refresh. Reuse those services and native SwiftUI swipe actions, plus existing Russian error presentation.

## Changes by file

- **`MojSlownik/Services/ScanWordStore.swift`:** Add `delete(wordID: PersistentIdentifier, container: ModelContainer)`. Follow existing isolated context, disabled autosave, explicit save and rollback-on-error pattern. Fetch/match exact persistent identity as `FolderStore.setMembership` does; reuse localized missing-word error. Do not use pair-based `toggle`, which intentionally removes all matching duplicates.
- **`MojSlownik/Views/WordListView.swift`:** Replace implicit `.onDelete`/offset handler with a trailing `.swipeActions` destructive «Удалить» button on each word row. Handler captures exact persistent ID and calls the service; show failure through `errorAlert` titled «Не удалось удалить слово». Disable full swipe so the requested visible button performs deletion. Keep existing row controls. Retain toolbar folder deletion and include the selected folder name in its confirmation for consistency.
- **`MojSlownik/Views/Components/FolderPicker.swift`:** Add trailing red swipe actions only to custom option rows, disable full swipe, capture the pending option ID/name and show sheet-local confirmation. Confirm calls `library.delete(id:context:)`; reuse existing selection reconciliation. Cancel/success clear pending confirmation. Keep errors visible inside the picker sheet using existing presentation patterns. Do not duplicate folder state or persistence logic.
- **`MojSlownikTests/ScanWordStoreTests.swift`:** Add meaningful exact-ID regressions: delete one of two duplicate pairs; preserve unrelated vocabulary, folder records/memberships and SRS; fresh context observes deletion; unrelated pending edits stay pending/unpersisted; missing record reports failure without mutations. Register WordFolder in the test container where required.
- **`MojSlownikTests/FolderLibraryStoreTests.swift` / `FolderStoreTests.swift`:** Reuse existing deletion/progress coverage. Add only missing preservation-of-other-folder-membership coverage, if absent.
- **`docs/architecture.md`:** Update only relevant deletion-flow descriptions if needed. No AGENTS.md/project.yml change expected.

## Verification

Review exact-ID persistence, query refresh and absence of schema/UI-test changes. Run isolated `MojSlownikUnitTests` tests and warning-free `MojSlownik` build using AGENTS.md commands on installed iPhone 16 or another installed iPhone simulator. Set DEVELOPER_DIR when necessary. Run xcodegen only after adding source files or changing project.yml.

Manual checklist: word swipes under all/search/category/folder filters; exact row, counts and empty-state refresh; persistence after reopen; selected/unselected folder swipes, cancel and confirm; shared Dictionary/Training/Add Word picker updates and selection fallback; vocabulary/other memberships survive. Check Russian/Polish add, editable translation/save, flashcards and quiz. Physical-device OCR smoke check: line translation, word/chip selection and preserved scan result after dismissing AddWordView. Report unavailable checks honestly.

Never create/update/run E2E, Playwright or XCUITest. Preserve existing UI tests/targets. No commits, pushes, branch changes or discarded work. Planning pass only: relevant source read; tests, build and manual checks not run.

## Risks and unresolved decisions

Cross-context deletion must refresh the observed `@Query`; verify row/count/empty-state changes manually. Do not fix refresh by unconditional view-context save or broad rollback. Folder deletion is noncascading and confirmation explains this; word deletion is global. Both disable full swipe; folder deletion confirms and word deletion uses one button tap. No unresolved product decisions. Undo/recovery and extra management screens are outside scope.

## Implementation, steering and results
Implemented exact-ID ScanWordStore.delete with isolated save/rollback and missing-word error. Explicit red Russian word/folder swipe buttons require a tap (no full swipe). Folder confirmation captures Option through presenting: so dismissal binding cleanup cannot change the target; only confirmation has destructive role. Folder catalog/selection reuse existing store behavior. Added two regression tests for exact duplicate preservation, folders/other memberships/SRS, saved deletion, missing IDs and unrelated pending edits. No model/schema/SRS/UI-test changes or new source files, so no XcodeGen needed.

Latest user correction: do not change screen structure to align toolbar items. Restored WordList large native title, matching Practice; scan/add remain together on the trailing toolbar. Practice unchanged. This supersedes prior inline-title design decisions.

Validation on iPhone17Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D: xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived build passed (/private/tmp/moj-delete-build.log). xcodebuild sameproject/destination/derivedDataPath -scheme MojSlownikUnitTests -parallel-testing-enabled NO test passed all63 tests, zero failures (/private/tmp/moj-delete-tests.log). Known AppIntents metadata tooling warning remains; no source compiler errors. git diff --check passed. Plan, quality, UI and data reviews: no findings. No commits/push.

No rendered/manual UI, physical iPhone or OCR checks performed; follow the manual checklist above. Usage reached96% of5hour window after the bounded implementation/review wave; no new work waves launched, existing test run allowed to finish. All required implementation and automated verification completed.
