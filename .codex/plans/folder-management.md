# Folder rename and ordering

## Goal

Let users rename and reorder custom study folders from the existing folder
selector, without scattering folder-management UI across dictionary, add, scan,
and training screens. Keep `FolderPicker` as the reusable, self-contained
selection and management component: callers own only their selected destination
and presentation-specific state.

## Context and constraints

- The app supports iOS 17, Swift 5.9, SwiftUI and SwiftData; folders and all
  vocabulary are local only.
- One shared `FolderLibraryStore` is injected at the app root. Every folder list
  must use that catalog, while each screen keeps its own `selectedFolderID`.
- A `Word` may be in several folders; renaming or changing display order must
  never alter word memberships, vocabulary records, SRS state, or training
  scope semantics.
- Existing stored `WordFolder` records must remain readable. Do not add a
  destructive migration, reset data, or change UUID identities.
- Reuse the existing name normalization and duplicate-name policy in
  `FolderStore`; do not add E2E/XCUITest work or touch the UI-test target.
- Starting revision: `0f73719ca0bca4d8620cf39bbf7d3fe88c62b75f`. Preserve any
  unrelated worktree changes.

## Acceptance criteria

- AC-1: A user can rename a folder in the shared folder sheet. The new name is
  trimmed/collapsed exactly as creation is, blank names fail with the existing
  Russian validation, and case/Unicode/whitespace-equivalent duplicates are
  rejected unless the conflict is the same folder.
- AC-2: Rename preserves the folder UUID, its position, all `Word.folderIDs`,
  vocabulary, and SRS fields; the new name appears immediately in every
  consumer of the shared catalog.
- AC-3: A user can enter an explicit edit mode in the folder sheet and drag
  folders into a new order. The chosen order persists across closing/reopening
  the app and is used consistently in dictionary, add-word, scanner and
  training selectors.
- AC-4: Creation appends a folder to the end of the current custom order;
  deletion removes only that folder and retains the relative order of the
  others. Existing deletion confirmation and invalid-selection reconciliation
  remain intact.
- AC-5: Existing installs with folders created before this feature load in a
  deterministic legacy order (creation date, with a stable tie-breaker), then
  acquire the saved order on the first reorder. No existing folder or word is
  lost.
- AC-6: The component remains comfortable on iPhone: direct single-tap
  selection with a checkmark, clear `Править` entry point for reorder/rename,
  visible `Создать папку`, 44-point row targets, Russian copy, Dynamic Type and
  accessibility labels/actions. Destructive deletion stays explicit and
  confirmed.
- AC-7: Native XCTest coverage verifies rename validation/persistence,
  reordering/persistence, legacy deterministic ordering, and that rename/order
  changes leave word memberships and progress untouched. The app builds without
  warnings and `MojSlownikUnitTests` passes; no UI/E2E tests run.

## Implementation approach

1. Extend `WordFolder` with a declaration-default persisted ordering value
   (for example, `sortOrder: Int = 0`) so existing SwiftData records migrate
   additively. Continue retaining `id`, `name`, and `createdAt` unchanged.
2. Centralize folder mutations in `FolderStore`:
   - factor existing name normalization/uniqueness so `create` and `rename`
     apply identical rules;
   - add `rename(id:name:context:)`, saving only after locating the exact
     folder and returning the existing `missingFolder` error for stale IDs;
   - add a reorder API accepting the displayed UUID sequence, validating it is
     a complete non-duplicated catalog permutation before atomically assigning
     contiguous order values; use an isolated context for cross-screen safety;
   - append new folders after the current highest order, and provide a single
     deterministic sort descriptor/fallback for legacy equal order values.
   Preserve the current deletion behavior that only removes folder IDs from
   words.
3. Update `FolderLibraryStore.Option` to carry the ordering needed for
   reconciliation if useful, and make `load`, `create`, `rename`, `move`, and
   `delete` refresh the one observable `options` array. Every caller continues
   receiving the catalog update without adding its own `@Query` or store.
4. Evolve `Views/Components/FolderPicker.swift` rather than duplicating it by
   screen. Its existing sheet remains the focused folder-management surface:
   direct rows select and close; a `Править` toolbar action enables SwiftUI list
   moving and row editing; rename opens a small prefilled Russian form with
   inline error feedback; delete keeps its named confirmation; create stays
   discoverable. Exit edit mode before selection/close so ordinary selection
   remains frictionless. Keep state local to the component and call the shared
   store for persistence.
5. Update `docs/architecture.md` to document persisted ordering, legacy sort
   fallback, and the self-contained picker/management responsibilities. No
   screen-specific changes should be required because all relevant screens
   already use `FolderPicker` and read `FolderLibraryStore.options`.
6. Add narrow tests in `MojSlownikTests/FolderStoreTests.swift` and
   `MojSlownikTests/FolderLibraryStoreTests.swift`. Test data uses the existing
   in-memory model containers and avoids UI automation.

## Unit-test matrix

The implementation must add committed XCTest coverage for both successful and
rejected persistence paths; a build alone is not sufficient. Tests remain in
the existing unit-test target only—no XCUITest, E2E or UI-test-target changes.

| Area | Happy path | Negative / boundary path |
| --- | --- | --- |
| Rename | Rename a persisted folder, reload it, and observe its new name from the shared catalog while retaining its UUID and position. A rename to the same normalized name for that folder succeeds. | Empty/whitespace-only input and a name equivalent to *another* folder by case, collapsed whitespace, or canonical Unicode fail and leave the stored name/catalog unchanged. Renaming a missing UUID reports `missingFolder` and changes nothing. |
| Reordering | Submit a complete permutation, verify the new sequence immediately and after a fresh context/store reload, then confirm the shared catalog publishes it. | Reject a sequence with a duplicate, omitted UUID, unknown/stale UUID, or extra UUID; assert no folder receives a partial new order. |
| Legacy/add/delete order | Seed legacy-equivalent equal/default ordering values with distinct creation dates/UUIDs and assert the documented deterministic fallback. Verify first reorder replaces it with persisted custom order; a new folder appends; deletion retains the other folders' relative sequence. | Include creation-date ties in the fixture to exercise the stable UUID tie-breaker rather than relying on unordered SwiftData fetch results. |
| Data preservation | Rename and reorder folders that contain a word with memberships and non-default SRS fields; assert the word's UUID memberships, vocabulary fields and every progress field are unchanged. | Run the same assertions after failed rename/reorder attempts to prove validation failures do not mutate words, folders or study state. |

## Files expected to change

| File | Change |
| --- | --- |
| `MojSlownik/Models/WordFolder.swift` | Add additive persisted display-order field. |
| `MojSlownik/Services/FolderStore.swift` | Rename, ordering, validation reuse and deterministic fetch sorting. |
| `MojSlownik/Stores/FolderLibraryStore.swift` | Publish refreshed ordered catalog and expose rename/move operations. |
| `MojSlownik/Views/Components/FolderPicker.swift` | Self-contained friendly folder management UI: edit/reorder/rename. |
| `MojSlownikTests/FolderStoreTests.swift` | Persistence and data-preservation tests. |
| `MojSlownikTests/FolderLibraryStoreTests.swift` | Shared-catalog rename/order publication tests. |
| `docs/architecture.md` | Folder ordering and reusable component behavior. |

## Verification

1. Run `xcodegen generate` only if project inputs/source registration require
   it (expected not to be necessary for edits to already included folders).
2. Select an installed iPhone simulator and run:
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=iPhone 16' build`
   (set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if needed).
3. Run only:
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,name=iPhone 16' test`.
4. Confirm every row of the unit-test matrix above is implemented and passing;
   test rejected paths as well as happy paths, rather than relying on UI-only
   validation.
5. Manual post-build checklist (not UI automation): create a Russian- and a
   Polish-input word; create/select/rename/reorder/delete folders in dictionary,
   add and training; save editable translation; complete a flashcard and quiz
   to confirm normal SRS behavior. On a physical iPhone separately check scan
   folder selection, line translation, chips and preserved scan result after
   dismissing Add Word.

## Risks and safeguards

- SwiftData ordering migration: a declaration default is additive, but legacy
  values may tie. Always sort legacy ties deterministically; never infer order
  from an unordered fetch.
- Reorder API integrity: reject malformed/stale UUID lists rather than silently
  losing folders or overwriting unrelated state.
- Rename conflicts: exclude only the target folder from duplicate detection;
  preserve current canonical Unicode comparison for all others.
- UI mode conflict: list move controls and selection compete. Keep reordering
  behind an explicit edit mode and disable/avoid selection actions while it is
  active.
- Multiple open selectors: use the shared observable catalog refresh and the
  existing `reconcileSelection` behavior after deletion; rename/reorder must
  not reset a valid selected UUID.

## Unresolved decisions

None material. The plan uses an explicit `Править` mode with drag handles,
rename action, and deletion confirmation as the clearest iPhone-friendly design;
`FolderPicker` remains the standalone component requested by the user.
