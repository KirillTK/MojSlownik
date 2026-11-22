# Mój Słownik

Personal iPhone dictionary and practice app for Russian speakers learning Polish.
SwiftUI, SwiftData, Swift 5.9, iOS 17+. Optional Supabase account (Apple/Google via the SDK's
OAuth); words and folders sync with the account (offline-first, see docs/architecture.md › Sync). Local vocabulary stays the source of truth; web translation sends entered/scanned
text to external services; signed-in users upload content-free diagnostics (app_logs).
UI copy is localized: English source strings and a Russian translation in String Catalogs
(Localizable.xcstrings, InfoPlist.xcstrings); iOS picks the system language and falls back to
English. Code, comments, file names and project instructions are English.

## Invariants

- Persistence and business logic live in Stores/ and Services/, not in Views.
  Reuse existing services and Theme/Theme.swift; make the smallest complete change.
- Remote backend (Supabase) code lives in Backend/, separate from Services/; in the app only
  Backend/ may `import Supabase` (in tests only MojSlownikTests/SupabaseAdapterTests.swift). Auth uses supabase-swift's native API only (no custom token code).
- Supabase: only the publishable key ships; never commit `sb_secret_`/service-role keys or DB
  passwords (`scripts/check-secrets.sh`, CI). Schema changes are new files in
  supabase/migrations (never edit an applied one); every table gets RLS scoped by
  `(select auth.uid()) = user_id`, WITH CHECK on INSERT/UPDATE, no `anon` grants, and a
  rolled-back test in supabase/tests (`scripts/test-db.sh`, CI). After applying a migration
  run Supabase security advisors. Avoid SECURITY DEFINER functions in `public`.
- Server rows are untrusted: validate with Backend/RemoteRecords.swift before touching
  SwiftData; Backend/RemoteMergePolicy.swift never hard-deletes local words.
- Logging (Services/Logging/AppLog.swift): events/keys are enums, values Int/Bool/ASCII ids; never
  log user text, emails, tokens or error messages (domain/code only). No SDK logger.
- Before any UI/visual work read [DESIGN.md](DESIGN.md) (tokens, components, icons, a11y).
- No hardcoded UI copy: every user-facing string goes through the String Catalog
  (Localizable.xcstrings, InfoPlist.xcstrings). Adding or changing a string means writing both
  `en` and `ru` (all plural forms) in the same change; never leave one language missing or
  stale. `scripts/check-localization.sh` and SourceHygieneTests enforce it. Domain data
  (words, folder names, WordCategory raw values, fixtures) is never localized and sits in
  `// l10n:data` regions.
- Stores/FolderLibraryStore.swift is injected once at the app root via environment;
  views keep only local selection/presentation state.
- Removing folders or folder memberships never deletes words.
- Views write vocabulary/folders only via VocabularyStore/FolderLibraryStore (repositories in
  Services/). Words and folders are soft-deleted (`deletedAt`): reads filter `\.isActive` in
  memory, and a changed row gets `updatedAt`.
- SwiftData: never lose stored words. New properties must be optional or have defaults;
  do not rename or remove persisted properties without a migration.
- Achievements: catalog/evaluator in Services/Achievements/Achievements.swift, state in
  Stores/AchievementStore.swift (see docs/architecture.md).
- Filter due words in memory with words.filter(\.isDue), not SwiftData #Predicate.
- Apple translation sessions exist only through a view's translationTask.
- OCR and camera behavior need a physical device.
- Read [docs/architecture.md](docs/architecture.md) only for the area you touch
  (flows, translation chain, components, constraints). Do not preload the source tree.
- Installation and signing on a personal iPhone: README.md.

## Verification

- After adding source files or changing project.yml, run `xcodegen generate`
  (the generated .xcodeproj is not tracked, except its committed Package.resolved;
  build with `-onlyUsePackageVersionsFromResolvedFile` like CI).
- Database: `scripts/test-db.sh <URL of an empty Postgres>` (CI does this in a container).
- Pick `<device>` from `xcrun simctl list devices available`. If CommandLineTools is
  active, set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- After building, run `scripts/check-localization.sh <DerivedData>` (extracted string keys vs the
  catalog: no missing, no dead keys; CI runs it after the build).
- Filter output: `| grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'`.

```sh
# Build — must have zero warnings
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination 'platform=iOS Simulator,name=<device>' build
# Unit tests (MojSlownikTests target)
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,name=<device>' test
# E2E (MojSlownikUITests). Locally one simulator, only the classes the change affects
# (-only-testing:MojSlownikUITests/<Class>); the full suite runs in CI on the PR
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikE2E -parallel-testing-enabled NO \
  -destination 'platform=iOS Simulator,name=<device>' test
# Single test: append to a test command
#   -only-testing:MojSlownikTests/<Class>/<testMethod>
```

- New or changed nontrivial logic and every bug fix need committed unit tests;
  build-only checks or temporary assertions do not count.
- When a user-facing flow changes, add or update XCUITest E2E scenarios in
  MojSlownikUITests built on named fixtures (`UITEST_FIXTURE`, Services/UITestSupport/UITestFixtures.swift):
  reuse existing fixtures, add new ones (with unit tests) when needed, and never seed data
  through UI steps inside a test. Run them with the MojSlownikE2E scheme. Never run tests
  through the MojSlownik app scheme. Camera, OCR and physical-iPhone checks stay manual.
- Documentation-only changes need no build.
- Done = clean build + green unit tests + green E2E for changed flows + a list of
  manual checks you could not run.

## Skills

Use the skill that matches the task; several can apply at once (a feature with a new screen
and a table uses all three groups).

| When | Skill | What it does |
|---|---|---|
| New feature or user-facing change across several files | Claude Code `/ios-feature-flow [--lite] <context>` (`.claude/skills/ios-feature-flow`); Codex `$feature-flow <context>` (`.agents/skills/feature-flow`) | Plan → critique → implement → verify (build, unit, fixture-based E2E) → review, with project subagents. `--lite` for small tasks; a plan path resumes an approved plan. |
| Any UI or visual work: new screen, restyle, component, design review | `/mobile-ios-design` (`.claude/skills/mobile-ios-design`) | Design process (HTML mockups → spec → simulator screenshots for approval) and the review bar; values live in DESIGN.md and Theme/Theme.swift. |
| Backend: Supabase auth, client SDK, RLS, Edge Functions, debugging Supabase errors | `supabase` (`.claude/skills/supabase`) | Supabase product, auth and security guidance, CLI/MCP usage. |
| Database: tables, columns, migrations, RLS policies and their tests, indexes, functions, slow queries | `supabase-postgres-best-practices` (`.claude/skills/supabase-postgres-best-practices`) | Postgres schema, migration, security and performance rules. Load before writing SQL. |

Skill rules never override the invariants above (e.g. Supabase migrations still follow the
RLS/test rules here). Supabase skills are pinned in skills-lock.json
(update with `npx skills add supabase/agent-skills`).

## Boundaries and workflow

- Do not commit/push without authorization or discard existing user changes.
- `main` is protected: merge only via PR with a green `ci-passed` check.
- Plans live in .codex/plans/.
- Keep this file concise: details go to docs/architecture.md, procedures to skills,
  task history to plans.
