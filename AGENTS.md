# Mój Słownik

Personal iPhone dictionary and practice app for Russian speakers learning Polish.
SwiftUI, SwiftData, Swift 5.9, iOS 17+. No accounts or synchronization yet; the Supabase SDK is linked and configured
(Services/SupabaseClientProvider.swift) but nothing calls it.
All vocabulary is local; web translation sends entered/scanned text to external services.
UI copy is Russian; code, file names and project instructions are English.

## Invariants

- Persistence and business logic live in Stores/ and Services/, not in Views.
  Reuse existing services and Theme/Theme.swift; make the smallest complete change.
- Before any UI/visual work read [DESIGN.md](DESIGN.md) (tokens, components, icons, a11y).
- Stores/FolderLibraryStore.swift is injected once at the app root via environment;
  views keep only local selection/presentation state.
- Removing folders or folder memberships never deletes words.
- Views write vocabulary/folders only via VocabularyStore/FolderLibraryStore (repositories in
  Services/). Words and folders are soft-deleted (`deletedAt`): reads filter `\.isActive` in
  memory, and a changed row gets `updatedAt`.
- SwiftData: never lose stored words. New properties must be optional or have defaults;
  do not rename or remove persisted properties without a migration.
- Achievements: catalog/evaluator in Services/Achievements.swift, state in
  Stores/AchievementStore.swift (see docs/architecture.md).
- Filter due words in memory with words.filter(\.isDue), not SwiftData #Predicate.
- Apple translation sessions exist only through a view's translationTask.
- OCR and camera behavior need a physical device.
- Read [docs/architecture.md](docs/architecture.md) only for the area you touch
  (flows, translation chain, components, constraints). Do not preload the source tree.
- Installation and signing on a personal iPhone: README.md.

## Verification

- After adding source files or changing project.yml, run `xcodegen generate`
  (the generated .xcodeproj is not tracked).
- Pick `<device>` from `xcrun simctl list devices available`. If CommandLineTools is
  active, set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- Filter output: `| grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'`.

```sh
# Build — must have zero warnings
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination 'platform=iOS Simulator,name=<device>' build
# Unit tests (MojSlownikTests target)
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests \
  -destination 'platform=iOS Simulator,name=<device>' test
# E2E (MojSlownikUITests; classes run in parallel on simulator clones)
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikE2E \
  -destination 'platform=iOS Simulator,name=<device>' test
# Single test: append to a test command
#   -only-testing:MojSlownikTests/<Class>/<testMethod>
```

- New or changed nontrivial logic and every bug fix need committed unit tests;
  build-only checks or temporary assertions do not count.
- When a user-facing flow changes, add or update XCUITest E2E scenarios in
  MojSlownikUITests built on named fixtures (`UITEST_FIXTURE`, Services/UITestFixtures.swift):
  reuse existing fixtures, add new ones (with unit tests) when needed, and never seed data
  through UI steps inside a test. Run them with the MojSlownikE2E scheme. Never run tests
  through the MojSlownik app scheme. Camera, OCR and physical-iPhone checks stay manual.
- Documentation-only changes need no build.
- Done = clean build + green unit tests + green E2E for changed flows + a list of
  manual checks you could not run.

## Boundaries and workflow

- Do not commit/push without authorization or discard existing user changes.
- `main` is protected: merge only via PR with a green `ci-passed` check.
- Feature workflow (only when requested): Codex `$feature-flow <context>`
  (.agents/skills/feature-flow); Claude Code: see CLAUDE.md. Plans live in .codex/plans/.
- Keep this file concise: details go to docs/architecture.md, procedures to skills,
  task history to plans.
