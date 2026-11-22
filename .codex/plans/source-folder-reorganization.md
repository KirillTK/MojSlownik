# Source folder reorganization

Base: `cf31d231e2096161e81b9848244a554762416586` (branch `t3/i18n-en-ru`).
Pre-existing, unrelated working-tree change: ` M MojSlownik/InfoPlist.xcstrings`. It must stay
as it is: do not stage, revert or rewrite it as part of this task.

## Goal

`MojSlownik/Services/` is one flat folder with 45 files covering translation, sync, logging,
workspaces, practice, UI-test mode and persistence. `Views/` mixes every screen at one level.
Group them into domain sub-folders **inside the existing layers**, so the layer boundaries the
AGENTS.md invariants depend on (`Backend/`, `Services/`, `Stores/`, `Views/`, `Models/`,
`Theme/Theme.swift`) stay exactly as they are. The change is a pure move: `git mv` plus doc
path updates. No code, behavior, type or file-name changes.

## Constraints (user instructions verbatim)

> я хочу сделать реоргонизацию папок - страктурно чтоб были не все в одной папке скинуто как в
> сервисах и тд - я хочу чтобы было сгрупировано более граммтоно

Caller requirements: pure structural move (`git mv` only, no code or behavior changes, no
renames of types or files); keep the architectural layers; sub-folders inside the layers;
full old→new table; find and fix every stale path reference; do not edit `.codex/plans`
history files; tests regrouped only if clearly worth it.

## Facts that make this safe

- **No import changes.** Each target (`MojSlownik`, `MojSlownikTests`, `MojSlownikUITests`) is
  one Swift module. Folder placement inside a target does not affect visibility; Swift has
  no path-based imports. Tests use `@testable import MojSlownik`, which is unchanged.
- **project.yml needs no edit.** `sources: - MojSlownik` with `createIntermediateGroups: true`
  picks up sub-folders recursively on `xcodegen generate`. `info.path: MojSlownik/Info.plist`
  and both `.xcstrings` stay at `MojSlownik/` (they are not moved).
- **No duplicate basenames are introduced.** No file is renamed, so object files and
  `.stringsdata` (flat per target, named by basename) stay unique. `scripts/check-localization.sh`
  globs `Objects-normal/*/*.stringsdata`, which does not depend on source folders.
- **Source-scanning tests are recursive.** `SourceHygieneTests.swiftFiles(in:)` uses
  `FileManager.enumerator`, which descends into sub-folders, and only uses the top-level
  directory names `MojSlownik`, `MojSlownikTests`, `MojSlownikUITests`.
- **String Catalogs hold no source paths** (`grep -c '\.swift'` is 0 in both catalogs).
- **No Swift comment references a moved path.** The only path mentions in code are
  `Backend/...` (`Services/Auth.swift:22`, `Services/AppLogQueue.swift:25`,
  `Services/SRSEngine.swift:30`, `MojSlownikTests/SupabaseAdapterTests.swift:6`), and `Backend/` does not move.

## Acceptance criteria

- AC-1: `MojSlownik/Services/` contains no `.swift` files at its top level; every former
  Services file lives in exactly one sub-folder listed in the table below.
- AC-2: `MojSlownik/Views/` top level contains only `RootTabView.swift` and the folders
  `Account/`, `Components/`, `Dictionary/`, `Practice/`, `Workspaces/`.
- AC-3: `Backend/`, `Models/`, `Stores/`, `Theme/`, `Views/Components/`, `MojSlownikApp.swift`,
  `Info.plist`, both `.xcstrings`, `Assets.xcassets`, `MojSlownikTests/`, `MojSlownikUITests/`
  and `project.yml` are unchanged.
- AC-4: `git diff -M --stat <base>` shows every moved Swift file as a 100 % rename
  (`R100`), with no content change in any `.swift` file.
- AC-5: Every `(Services|Views|Stores|Models|Backend|Theme)/….swift` path mentioned in
  `AGENTS.md`, `docs/architecture.md`, `DESIGN.md`, `README.md`, `.claude/` and `.agents/`
  resolves to an existing file under `MojSlownik/` (check script in Verification).
  `supabase/migrations/` is excluded from this check on purpose: applied migrations are never
  edited (AGENTS.md), so their comments may keep old paths (see "No edits needed").
- AC-6: `docs/architecture.md` has a short "Source layout" section describing the folders,
  so new files have an obvious home.
- AC-7: `xcodegen generate` + app build with zero warnings, all unit tests green,
  `check-localization.sh` and `check-secrets.sh` pass, E2E smoke subset green.
- AC-8: `MojSlownik/InfoPlist.xcstrings` keeps its pre-existing modification, and
  `Package.resolved` is unchanged.

## Changes by file

### Grouping rationale

- **Services** split by domain, matching the rows of the docs/architecture.md table
  (Data access, Translation, Practice, Achievements, Sync, Account and logs, Workspaces).
  `Data/` holds the repository seams, their SwiftData/UserDefaults implementations and the
  SwiftData writers (`ScanWordStore`, `FolderStore`); it is what the docs "Data access" row
  already describes. `ProgressRepositories.swift` goes there too: besides achievement/daily
  state it holds `ActiveWorkspaceRepository` and `InputSideRepository`, so it is general
  UserDefaults persistence, not practice logic. `LoggingRepositories.swift` decorates those
  repositories, so it sits next to them, not in `Logging/`. `DeterministicUUID.swift` (word,
  workspace and membership identities) and `WordIdentityBackfill.swift` are identity of stored
  rows, so `Data/` as well. `WordCategory`/`WordSide` are word value types used by the data
  layer and the views; they go to `Data/` instead of a separate two-file folder.
- `Language/` is the language descriptor layer (descriptor table, supported codes, script
  detection, UI locale), used by translation, speech, OCR and workspaces alike, so it is not
  inside `Translation/`.
- `UITestSupport/` keeps DEBUG-only UI-test mode together (`UITestSyncRemote.swift` also
  contains `InMemorySyncRemote`, which unit tests use; it remains test-mode infrastructure,
  not production sync).
- **Views** split by tab/flow: `Dictionary/` (word list, adding, scanning; the scanner is
  presented from the dictionary and saves into it), `Practice/` (Training tab, its three
  sessions and Achievements, which is pushed from Training), `Workspaces/` (wizard and
  Languages sheet), `Account/`. `RootTabView.swift` is the app shell and stays at
  `Views/` top level. `Views/Components/` stays flat: it is already a group, and
  `.claude/skills/mobile-ios-design/SKILL.md` and DESIGN.md define it as one folder.
- **Not regrouped:** `Stores/` (9), `Models/` (5), `Backend/` (7), `Theme/` (1) are small and
  cohesive. `Backend/` must also stay a single obvious folder for the "only Backend/ imports
  Supabase" rule.
- **Tests not regrouped (deliberate).** `LocalizationCatalogTests`, `SourceHygieneTests` and
  `ThemeTests` find the repo root via `URL(fileURLWithPath: #filePath)` with exactly two
  `deletingLastPathComponent()` calls. Moving them into sub-folders breaks them, so the move
  would need code edits, which this task excludes. The flat test folders (68 + 10 files,
  named `<Subject>Tests.swift`) are still easy to navigate. Mirroring tests is listed as an
  open decision for a later change.

### Move table: MojSlownik/Services (45 files)

All paths are relative to `MojSlownik/`.

| Old path | New path |
| --- | --- |
| Services/DataRepositories.swift | Services/Data/DataRepositories.swift |
| Services/SwiftDataRepositories.swift | Services/Data/SwiftDataRepositories.swift |
| Services/LoggingRepositories.swift | Services/Data/LoggingRepositories.swift |
| Services/ProgressRepositories.swift | Services/Data/ProgressRepositories.swift |
| Services/ScanWordStore.swift | Services/Data/ScanWordStore.swift |
| Services/FolderStore.swift | Services/Data/FolderStore.swift |
| Services/MembershipIndex.swift | Services/Data/MembershipIndex.swift |
| Services/DeterministicUUID.swift | Services/Data/DeterministicUUID.swift |
| Services/WordIdentityBackfill.swift | Services/Data/WordIdentityBackfill.swift |
| Services/WordCategory.swift | Services/Data/WordCategory.swift |
| Services/WordSide.swift | Services/Data/WordSide.swift |
| Services/WorkspaceBackfill.swift | Services/Workspaces/WorkspaceBackfill.swift |
| Services/WorkspaceCatalog.swift | Services/Workspaces/WorkspaceCatalog.swift |
| Services/WorkspaceGate.swift | Services/Workspaces/WorkspaceGate.swift |
| Services/WorkspaceLabels.swift | Services/Workspaces/WorkspaceLabels.swift |
| Services/WorkspaceScope.swift | Services/Workspaces/WorkspaceScope.swift |
| Services/Language.swift | Services/Language/Language.swift |
| Services/LanguageCodes.swift | Services/Language/LanguageCodes.swift |
| Services/LanguageDetector.swift | Services/Language/LanguageDetector.swift |
| Services/AppLocale.swift | Services/Language/AppLocale.swift |
| Services/TranslationService.swift | Services/Translation/TranslationService.swift |
| Services/AppleTranslator.swift | Services/Translation/AppleTranslator.swift |
| Services/GoogleWebTranslator.swift | Services/Translation/GoogleWebTranslator.swift |
| Services/MyMemoryTranslator.swift | Services/Translation/MyMemoryTranslator.swift |
| Services/TranslationAlternatives.swift | Services/Translation/TranslationAlternatives.swift |
| Services/SpeechService.swift | Services/Speech/SpeechService.swift |
| Services/SpeechRecognitionService.swift | Services/Speech/SpeechRecognitionService.swift |
| Services/ScannedTextTokenizer.swift | Services/Scanning/ScannedTextTokenizer.swift |
| Services/SRSEngine.swift | Services/Practice/SRSEngine.swift |
| Services/KnowledgeProgressService.swift | Services/Practice/KnowledgeProgressService.swift |
| Services/ListeningQuestion.swift | Services/Practice/ListeningQuestion.swift |
| Services/Achievements.swift | Services/Achievements/Achievements.swift |
| Services/AchievementLedger.swift | Services/Achievements/AchievementLedger.swift |
| Services/SyncEngine.swift | Services/Sync/SyncEngine.swift |
| Services/SyncRemote.swift | Services/Sync/SyncRemote.swift |
| Services/SyncState.swift | Services/Sync/SyncState.swift |
| Services/SwiftDataSyncStore.swift | Services/Sync/SwiftDataSyncStore.swift |
| Services/LocalChangeSignal.swift | Services/Sync/LocalChangeSignal.swift |
| Services/Auth.swift | Services/Account/Auth.swift |
| Services/AppLog.swift | Services/Logging/AppLog.swift |
| Services/AppLogQueue.swift | Services/Logging/AppLogQueue.swift |
| Services/BackgroundLogFlush.swift | Services/Logging/BackgroundLogFlush.swift |
| Services/UITestFixtures.swift | Services/UITestSupport/UITestFixtures.swift |
| Services/UITestLaunchConfiguration.swift | Services/UITestSupport/UITestLaunchConfiguration.swift |
| Services/UITestSyncRemote.swift | Services/UITestSupport/UITestSyncRemote.swift |

Counts: Data 11, Workspaces 5, Language 4, Translation 5, Speech 2, Scanning 1, Practice 3,
Achievements 2, Sync 5, Account 1, Logging 3, UITestSupport 3 = 45.

### Move table: MojSlownik/Views (12 files; Components/ untouched)

| Old path | New path |
| --- | --- |
| Views/WordListView.swift | Views/Dictionary/WordListView.swift |
| Views/AddWordView.swift | Views/Dictionary/AddWordView.swift |
| Views/ScannerView.swift | Views/Dictionary/ScannerView.swift |
| Views/TrainingView.swift | Views/Practice/TrainingView.swift |
| Views/FlashcardsView.swift | Views/Practice/FlashcardsView.swift |
| Views/QuizView.swift | Views/Practice/QuizView.swift |
| Views/ListeningPracticeView.swift | Views/Practice/ListeningPracticeView.swift |
| Views/AchievementsView.swift | Views/Practice/AchievementsView.swift |
| Views/WorkspaceManagerView.swift | Views/Workspaces/WorkspaceManagerView.swift |
| Views/WorkspaceWizardView.swift | Views/Workspaces/WorkspaceWizardView.swift |
| Views/AccountView.swift | Views/Account/AccountView.swift |
| Views/RootTabView.swift | (stays) Views/RootTabView.swift |

### Move script (run from repo root)

```sh
set -euo pipefail
cd MojSlownik
mv_to() { dir="$1"; shift; mkdir -p "$dir"; for f in "$@"; do git mv "$f" "$dir/"; done; }
S=Services
mv_to $S/Data $S/DataRepositories.swift $S/SwiftDataRepositories.swift $S/LoggingRepositories.swift \
  $S/ProgressRepositories.swift $S/ScanWordStore.swift $S/FolderStore.swift $S/MembershipIndex.swift \
  $S/DeterministicUUID.swift $S/WordIdentityBackfill.swift $S/WordCategory.swift $S/WordSide.swift
mv_to $S/Workspaces $S/WorkspaceBackfill.swift $S/WorkspaceCatalog.swift $S/WorkspaceGate.swift \
  $S/WorkspaceLabels.swift $S/WorkspaceScope.swift
mv_to $S/Language $S/Language.swift $S/LanguageCodes.swift $S/LanguageDetector.swift $S/AppLocale.swift
mv_to $S/Translation $S/TranslationService.swift $S/AppleTranslator.swift $S/GoogleWebTranslator.swift \
  $S/MyMemoryTranslator.swift $S/TranslationAlternatives.swift
mv_to $S/Speech $S/SpeechService.swift $S/SpeechRecognitionService.swift
mv_to $S/Scanning $S/ScannedTextTokenizer.swift
mv_to $S/Practice $S/SRSEngine.swift $S/KnowledgeProgressService.swift $S/ListeningQuestion.swift
mv_to $S/Achievements $S/Achievements.swift $S/AchievementLedger.swift
mv_to $S/Sync $S/SyncEngine.swift $S/SyncRemote.swift $S/SyncState.swift $S/SwiftDataSyncStore.swift \
  $S/LocalChangeSignal.swift
mv_to $S/Account $S/Auth.swift
mv_to $S/Logging $S/AppLog.swift $S/AppLogQueue.swift $S/BackgroundLogFlush.swift
mv_to $S/UITestSupport $S/UITestFixtures.swift $S/UITestLaunchConfiguration.swift $S/UITestSyncRemote.swift
V=Views
mv_to $V/Dictionary $V/WordListView.swift $V/AddWordView.swift $V/ScannerView.swift
mv_to $V/Practice $V/TrainingView.swift $V/FlashcardsView.swift $V/QuizView.swift \
  $V/ListeningPracticeView.swift $V/AchievementsView.swift
mv_to $V/Workspaces $V/WorkspaceManagerView.swift $V/WorkspaceWizardView.swift
mv_to $V/Account $V/AccountView.swift
ls $S/*.swift 2>/dev/null && { echo "Services top level not empty"; exit 1; } || true
```

Do not use `git add -A` / `git add .` afterwards (it would stage the unrelated
`InfoPlist.xcstrings` change). Stage doc edits by explicit path.

### Documentation path updates (exact edits)

`AGENTS.md`:
- line 25: `Logging (Services/AppLog.swift)` → `Logging (Services/Logging/AppLog.swift)`.
- line 42: `catalog/evaluator in Services/Achievements.swift` → `catalog/evaluator in Services/Achievements/Achievements.swift`.
- line 81: `Services/UITestFixtures.swift` → `Services/UITestSupport/UITestFixtures.swift`.
- Unchanged and still valid: line 14 (`Theme/Theme.swift`), 23-24 (`Backend/...`), 34
  (`Stores/FolderLibraryStore.swift`), 43 (`Stores/AchievementStore.swift`), and the layer
  wording "Stores/ and Services/", "Backend/, separate from Services/".

`docs/architecture.md` (paths there are relative to `MojSlownik/`):
- line 17 (Data access): `Services/DataRepositories.swift`, `Services/ProgressRepositories.swift`,
  `Services/SwiftDataRepositories.swift`, `Services/WordIdentityBackfill.swift` → `Services/Data/…`.
- line 19 (Dictionary): `Views/WordListView.swift` → `Views/Dictionary/WordListView.swift`.
- line 20 (Adding words): `Views/AddWordView.swift` → `Views/Dictionary/AddWordView.swift`.
- line 21 (Translation): `Services/TranslationService.swift` → `Services/Translation/TranslationService.swift`;
  the bare `` `Language.swift` `` → `` `Services/Language/Language.swift` `` (it is no longer
  in the same folder as the translators; `AppleTranslator.swift`, `GoogleWebTranslator.swift`,
  `MyMemoryTranslator.swift`, `TranslationAlternatives.swift` stay bare, they share the folder).
- line 22 (Camera): `Views/ScannerView.swift` → `Views/Dictionary/ScannerView.swift`;
  `Services/ScannedTextTokenizer.swift` → `Services/Scanning/ScannedTextTokenizer.swift`.
- line 23 (Practice): `Views/TrainingView.swift`, `Views/ListeningPracticeView.swift` →
  `Views/Practice/…`; `Services/KnowledgeProgressService.swift`, `Services/ListeningQuestion.swift`,
  `Services/SRSEngine.swift` → `Services/Practice/…`. (`Stores/DailyStudyStore.swift` unchanged.)
- line 24 (Achievements): `Services/Achievements.swift`, `Services/AchievementLedger.swift` →
  `Services/Achievements/…`; `Views/AchievementsView.swift` → `Views/Practice/AchievementsView.swift`.
- line 25: `Services/SpeechService.swift` → `Services/Speech/SpeechService.swift`.
- line 27 (Account and logs): `Services/Auth.swift` → `Services/Account/Auth.swift`;
  `Views/AccountView.swift` → `Views/Account/AccountView.swift`; `Services/AppLog.swift`,
  `Services/AppLogQueue.swift` → `Services/Logging/…`.
- line 77: `Services/ScanWordStore.swift` → `Services/Data/ScanWordStore.swift`.
- line 90: `Services/WordCategory.swift` → `Services/Data/WordCategory.swift`.
- line 185: `Services/WorkspaceGate.swift` → `Services/Workspaces/WorkspaceGate.swift`.
- lines 202-203: `Services/SyncEngine.swift`, `Services/SwiftDataSyncStore.swift`,
  `Services/SyncRemote.swift`, `Services/SyncState.swift` → `Services/Sync/…`.
- line 218: `Services/LanguageCodes.swift` → `Services/Language/LanguageCodes.swift`.
- line 270: `Services/Language.swift` → `Services/Language/Language.swift`.
- line 298: `Services/MembershipIndex.swift` → `Services/Data/MembershipIndex.swift`.
- line 301: `Services/FolderStore.swift` → `Services/Data/FolderStore.swift`.
- lines 402-403: `Services/UITestLaunchConfiguration.swift`, `Services/UITestFixtures.swift` →
  `Services/UITestSupport/…`.
- Unchanged: line 16 (`Views/RootTabView.swift`), 18 and 293 (`Models/…`), 26 and 204, 421-422
  (`Backend/…`), 205 and 304 (`Stores/…`), 341 (`Views/Components/`).
- **Add** (AC-6) a `### Source layout` subsection directly after the sentence
  "Paths below are relative to `MojSlownik/` unless stated otherwise." and before the table:

  ```markdown
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
  ```

  This is English documentation, no UI copy, so no String Catalog change.

No edits needed (checked):
- `CLAUDE.md`: no source paths.
- `DESIGN.md` line 8: `MojSlownik/Theme/Theme.swift` unchanged.
- `README.md`: no source paths ("Services ID" on lines 86/88 is Apple's term).
- `.claude/skills/mobile-ios-design/SKILL.md` lines 9, 55: `Theme/Theme.swift`,
  `Views/Components/` unchanged.
- `.claude/agents/*.md`, `.claude/skills/ios-feature-flow/SKILL.md`, `.agents/skills/feature-flow/SKILL.md`:
  no source paths ("Theme/Components" in feature-plan-reviewer.md is a concept, still valid).
- `.claude/hooks/guard-xcodebuild.sh`: matches schemes, not paths.
- `scripts/check-localization.sh`: uses `MojSlownik/Localizable.xcstrings` (not moved) and a
  DerivedData glob independent of source folders. `scripts/check-secrets.sh`: `git grep` over
  the whole tree. `scripts/test-db.sh`: database only.
- `.github/workflows/ci.yml`: no source paths (line 152 "Backend" is a job name).
- `project.yml`: no change (see Facts).
- Swift sources and tests: no moved path is referenced; `l10n:data` markers are per-file and
  move with their files.
- `.codex/plans/*`: historical, intentionally left with old paths.
- `supabase/migrations/20261117225955_app_logs.sql` line 2 mentions `Services/AppLog.swift`
  (new path `Services/Logging/AppLog.swift`). Accepted stale reference: this migration is
  applied, and AGENTS.md forbids editing an applied migration. Leave it unchanged.

## Reuse

Nothing new is written. Existing tooling does the checks: `xcodegen`, `SourceHygieneTests`
(recursive scan), `scripts/check-localization.sh`, `scripts/check-secrets.sh`.

## Data compatibility

No SwiftData model, property, UserDefaults key or file format changes; the binary is built from
identical sources. Existing installs are unaffected.

## Verification

Use one simulator (`xcrun simctl list devices available`); set
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if CommandLineTools is active.

1. Pure-move check:
   ```sh
   git diff --cached -M --name-status cf31d231 -- MojSlownik | grep -v '^R100' | grep '\.swift$' && echo "NOT PURE" || echo "pure"
   git status --short MojSlownik/InfoPlist.xcstrings   # still " M" (unstaged, untouched)
   ```
2. Doc path check (AC-5), from repo root; must print nothing:
   ```sh
   grep -rhoE '(MojSlownik/)?(Services|Views|Stores|Models|Backend|Theme)/[A-Za-z/]+\.swift' \
     AGENTS.md DESIGN.md README.md docs .claude/agents .claude/skills/ios-feature-flow \
     .claude/skills/mobile-ios-design .agents | sed 's#^MojSlownik/##' | sort -u |
     while read p; do [ -f "MojSlownik/$p" ] || echo "stale: $p"; done
   grep -rn 'Services/[A-Za-z]*\.swift' AGENTS.md docs   # expect no hits
   ```
3. `xcodegen generate`, then `git status --short` must not list
   `MojSlownik.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
   (if it does, `git checkout -- <that file>`).
4. Build with zero warnings (DerivedData in the scratchpad or a fixed path):
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=<device>' -derivedDataPath <DD> -onlyUsePackageVersionsFromResolvedFile build | grep -E 'error:|warning:|SUCCEEDED|FAILED'`.
5. `scripts/check-localization.sh <DD>` (no missing, no dead keys) and `scripts/check-secrets.sh`.
6. Full unit tests: `xcodebuild … -scheme MojSlownikUnitTests -parallel-testing-enabled NO … test`;
   read totals from the xcresult summary (grep "Executed" under-reports). `SourceHygieneTests`,
   `LocalizationCatalogTests`, `ThemeTests` must be green (they read sources/catalog/DESIGN.md
   from disk). No new unit tests: there is no new or changed logic; the existing source-scanning
   tests already cover the moved tree.
7. E2E smoke only, justified: no user-facing flow, string, fixture or resource changes; the
   compiled sources are byte-identical, so only bundle wiring (target membership, catalogs,
   assets) could regress, and a launch-plus-flow smoke covers it. Run
   `-only-testing:MojSlownikUITests/AddWordFlowTests -only-testing:MojSlownikUITests/LocalizationFlowTests`
   with the `MojSlownikE2E` scheme (app launch with fixtures, dictionary, translation stub,
   ru catalog in the bundle). The full E2E suite runs in CI on the PR.
8. Manual: open the project in Xcode once and confirm the navigator shows the new groups
   (optional, cosmetic). No device checks needed.

## Risks

- **History/blame:** files are byte-identical, so git records 100 % renames;
  `git log --follow <new path>` and `git blame` keep history. Keep the moves free of content edits
  (doc edits are in non-Swift files) so similarity stays 100 %. Recommended: moves and doc
  updates in one commit titled e.g. "Group Services and Views into domain sub-folders" (only if
  the user authorizes committing).
- **Conflicts with other branches** (`t3/language-workspaces`, `t3/achievements-system`,
  `t3/app-redesign-modern-palette`, `t3/backend-abstraction-prep`, …): git's rename detection
  usually carries edits to a moved file across a merge/rebase, but new files those branches add
  under `Services/` land at the old flat level and must be moved by hand afterwards; edits to
  the same doc lines conflict. Prefer merging this right after `t3/i18n-en-ru`, before other
  feature branches continue; rebase them afterwards with `git rebase` (rename detection is on by
  default; increase `merge.renameLimit` if git warns).
- **Package.resolved:** `xcodegen generate` regenerates the untracked `.xcodeproj` but should
  keep the committed `Package.resolved`; step 3 checks and restores it.
- **Pre-existing `InfoPlist.xcstrings` change:** accidental staging via `git add -A` would mix it
  into this change; stage by explicit path only.
- **Stale paths in future docs/plans:** new plans copied from old ones may reuse flat paths; the
  added "Source layout" section and the AC-5 check mitigate it.

## Open decisions

1. **Single-file folders** `Services/Scanning/` (ScannedTextTokenizer) and `Services/Account/`
   (Auth) and `Views/Account/` (AccountView). Plan: keep them, since each is a distinct domain
   matching a docs row and likely to grow. Alternative: leave `Auth.swift`/`AccountView.swift`
   at the layer top level and put the tokenizer with Speech under `Services/Input/`.
2. **`ScannerView.swift` under `Views/Dictionary/`** (plan) versus its own `Views/Scanner/`.
3. **`WordCategory`/`WordSide` in `Services/Data/`** (plan) versus a `Services/Words/` folder.
4. **Tests stay flat** (plan). Mirroring `MojSlownikTests` into the same domain folders would need
   a small code change in `LocalizationCatalogTests`, `SourceHygieneTests` and `ThemeTests` (find
   the repo root by searching upward for `project.yml` instead of two
   `deletingLastPathComponent()` calls); propose as a separate follow-up if wanted.
5. **Stores/** (9 files) stays flat (plan); splitting it would add folders of 1-2 files.

## Decisions

- Single-file folders (Services/Scanning, Services/Account, Views/Account): keep them (user, 2026-11-22).
- Other open decisions: keep the plan's defaults (ScannerView in Views/Dictionary, WordCategory/WordSide in Services/Data, tests flat, Stores flat).

## Approval

- 2026-11-22: approved by user.
