# Dictionary folder membership

## Goal

Make folder changes from dictionary rows visible immediately and provide a clear way to remove a word from every folder while retaining the vocabulary entry and SRS progress.

## Acceptance criteria

- AC-1: Toggling a folder membership in a dictionary row updates the row icon/menu state and the currently selected folder's word list/count without relaunching.
- AC-2: A word can be removed from all folders through the row folder menu; it remains in the global dictionary with its category and SRS data intact.
- AC-3: Removing membership from one folder continues to preserve membership in other folders.
- AC-4: Persistence failures continue to show the existing Russian error alert and do not leave the UI in a falsely updated state.

## Source findings and likely changes

- `MojSlownik/Views/WordListView.swift`: `WordRow` currently invokes `FolderStore.setMembership(... container:)`; the store creates a separate `ModelContext`, which saves the change but leaves the view's queried model instance stale. Use the observed `modelContext` path so the displayed `Word` is mutated in the same context, and add a menu action for clearing all folder memberships.
- `MojSlownik/Services/FolderStore.swift`: add or use a `ModelContext` overload for membership updates and a focused clear-all-memberships operation. Save with existing rollback/error behavior, preserving the vocabulary model and all non-folder fields.
- `MojSlownikTests/FolderStoreTests.swift`: add regression coverage for membership changes via a shared observed context, clearing all memberships while preserving the word and SRS state, and retaining the existing other-folder semantics.

## Reuse

Keep using `FolderStore` for persistence and `Word.folderIDs` as the existing source of truth. Reuse the row's current menu and error alert; no model migration or new service is needed.

## Verification

- Run isolated unit tests: `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,name=iPhone 16' test` (select an installed simulator if needed).
- Build app: `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=iPhone 16' build`.
- Manually check a word assigned to multiple folders: toggle one membership and confirm immediate filtering/count/icon updates; clear all folders and confirm the word remains under “Все папки” with progress intact.
- No source-file or project.yml changes are expected, so `xcodegen generate` is not needed.

## Risks and unresolved decisions

- The row menu should communicate the all-folder removal action distinctly from toggling a single folder, preferably with an explicit Russian “Убрать из всех папок” action and destructive styling only if the design conventions support it.
- No unresolved product decision: removing a word from all folders must not delete it from the dictionary.
