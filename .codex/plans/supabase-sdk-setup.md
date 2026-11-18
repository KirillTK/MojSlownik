# Supabase SDK setup (supabase-swift, configured client, no sync)

Mode: full. Base: HEAD da2443c (clean tree). Branch: current worktree branch.

## Goal

Add the official `supabase-swift` SDK to the XcodeGen project, along with one configured,
injectable and lazily created `SupabaseClient` for the project
`https://bjwptrfbtcmxlhjaxiip.supabase.co`. The client uses the publishable key.
This is plumbing only:
- the app makes no network calls to Supabase, at launch or anywhere else;
- there is no auth, sync, schema or UI change;
- user-visible behavior and stored data stay identical.

This work follows `backend-abstraction-prep.md` (D1 offline-first: local SwiftData stays the
source of truth, and repositories stay synchronous and `@MainActor`). A future sync engine
gets a ready client seam. Gaps A–H stay open.

## Constraints

User task (verbatim): "Установи supabase в проект" + Supabase quickstart
(`swift package add-dependency https://github.com/supabase/supabase-swift`; `Supabase.swift`
with `let supabase = SupabaseClient(supabaseURL: URL(string: "https://bjwptrfbtcmxlhjaxiip.supabase.co")!, supabaseKey: "sb_publishable_5gYMyVsuL5k5UHxIrWWiTA__Bf6BbMe")`;
`Todo.swift` + `ContentView` listing `supabase.from("todos").select()`; optional
`npx skills add supabase/agent-skills`).
Follow-up (verbatim): "я установил mcp supabase - поэтому можешь и там добавлять что-то".

Binding interpretation agreed with the orchestrator:
- The user chose the supabase-swift client with the publishable key and RLS, not a direct Postgres
  connection or Drizzle. The publishable key is public by design and may be committed.
  **Never** put DB passwords, `sb_secret_…` keys or service-role keys in the repo, the plan or CI.
- There is no `Package.swift`. The project is generated from `project.yml` (`.xcodeproj` is
  untracked), so add the dependency through XcodeGen `packages:`. Do not use `swift package add-dependency`.
- Do **not** adopt the `Todo`/`ContentView` demo: `RootTabView` stays the root.
- Supabase-side changes (MCP) happen only after explicit user approval. This task changes nothing remotely (see
  Open decisions OD-2).
- AGENTS.md invariants:
  - logic stays in Services/ and Stores/;
  - no stored word is ever lost;
  - new source files require `xcodegen generate`;
  - the build has zero warnings;
  - committed unit tests;
  - E2E tests only through `MojSlownikE2E`, and never through the `MojSlownik` scheme.

## Facts verified during planning

- Latest supabase-swift tag: **v2.55.7**, and there is no 3.x. `Package.swift` uses `swift-tools-version:6.1`,
  so it needs **Xcode 16.3+**. Local Xcode is 27.2, and CI uses `latest-stable`. Platforms: `.iOS(.v16)`, so it is
  compatible with the iOS 17.0 deployment target. The package compiles in its own language mode, and the app
  stays on Swift 5.9 language mode. That is fine.
- Products: `Auth`, `Functions`, `PostgREST`, `Realtime`, `Storage`, and the umbrella `Supabase`, which depends on all
  five. `SupabaseClient` exists only in the umbrella. The `OpenTelemetry` trait is opt-in, so it is not pulled.
  No macros or package plugins are on the linked graph.
- `SupabaseClient.init` makes no network call. It does the following:
  - it calls `APIKeyFormat.checkFormat`, which accepts `sb_publishable_…` silently;
  - it builds an `AuthClient` with Keychain storage by default;
  - it calls `listenForAuthEvents()`. With the default
    `emitLocalSessionAsInitialSession: false`, this raises a runtime `reportIssue`
    ("Initial session emitted after attempting to refresh…") outside tests. Passing
    `emitLocalSessionAsInitialSession: true` avoids it.
- With the default `autoRefreshToken`, `AuthClient` observes `didBecomeActive`. When there is no stored session,
  it has nothing to refresh. Even so, nothing should be constructed at launch, so the client is lazy.

## Acceptance criteria

- AC-1: `project.yml` declares the package `https://github.com/supabase/supabase-swift` pinned
  to `exactVersion: 2.55.7`. The `MojSlownik` app target depends on product `Supabase`.
  `xcodegen generate` succeeds, and a clean build resolves the package with no manual Xcode steps.
- AC-2: The `MojSlownik` scheme builds for the simulator with **zero warnings**. The CI-equivalent
  `build-for-testing` command with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`
  succeeds.
- AC-3: `SupabaseConfiguration.production` has URL `https://bjwptrfbtcmxlhjaxiip.supabase.co`
  and a key that starts with `sb_publishable_`. Validation rejects these:
  - a non-https URL;
  - a URL without a host;
  - an empty key;
  - any key that starts with `sb_secret_`;
  - any key that does not start with `sb_publishable_`.
- AC-4: `SupabaseClientProvider` creates no `SupabaseClient` until `client` is first accessed.
  Later accesses return the same instance (`===`).
- AC-5: Constructing `AppResources` creates no Supabase client. This covers the production `init` path with
  in-memory configuration and the DEBUG `uiTest` path. The app therefore makes no Supabase
  network or Keychain activity at launch, in UI-test mode or in previews.
- AC-6: No view, store, model or `RootTabView` changes. There is no `Todo`/`ContentView` file and no global
  `let supabase`. The SwiftData schema is unchanged.
- AC-7: All existing unit tests are green, plus the new tests. All existing E2E tests (`MojSlownikE2E`) are green
  and unchanged.
- AC-8: AGENTS.md and docs/architecture.md describe the SDK as present but unused (no sync or accounts).
  No secret appears anywhere in the diff.

## Changes by file

### 1. `project.yml`
Add a top-level `packages:` block, placed after `settings:` and before `targets:`:
```yaml
packages:
  Supabase:
    url: https://github.com/supabase/supabase-swift
    exactVersion: 2.55.7
```
In `targets.MojSlownik`, add:
```yaml
    dependencies:
      - package: Supabase
        product: Supabase
```
Do not add the package to `MojSlownikTests` or `MojSlownikUITests`. The hosted unit tests use
`@testable import MojSlownik` and never `import Supabase` (see Risks R3 for the fallback). Change nothing else.

### 2. New `MojSlownik/Backend/SupabaseConfiguration.swift` (Foundation only, no `import Supabase`)
```swift
struct SupabaseConfiguration: Equatable, Sendable {
    let url: URL
    let publishableKey: String

    enum ValidationError: Error, Equatable { case invalidURL, invalidKey }

    /// https scheme, non-empty host; key must start with "sb_publishable_" (never "sb_secret_").
    init(urlString: String, publishableKey: String) throws

    /// Project "bjwptrfbtcmxlhjaxiip". The publishable key is public by design (RLS protects data).
    /// Secret/service-role keys must never be added to the app.
    static let production: SupabaseConfiguration
}
```
- Validation:
  - `URL(string:)` must be non-nil;
  - `scheme == "https"`;
  - `host(percentEncoded: false)` must be non-nil and non-empty;
  - the key, trimmed, must be non-empty, must have the prefix `sb_publishable_`, and must have more characters after the prefix.

  A `sb_secret_…` key fails the prefix check (`invalidKey`).
- `production` is built in a closure that uses `do { try SupabaseConfiguration(urlString: "https://bjwptrfbtcmxlhjaxiip.supabase.co", publishableKey: "sb_publishable_5gYMyVsuL5k5UHxIrWWiTA__Bf6BbMe") } catch { preconditionFailure("Invalid Supabase configuration: \(error)") }`.
  A unit test guarantees that this never fires.
- Why a source constant rather than Info.plist or xcconfig: there is one environment, and the key is public. A constant is
  the smallest change, and it is fully unit-testable. OD-4 records the alternative.

### 3. New `MojSlownik/Backend/SupabaseClientProvider.swift` (the only file with `import Supabase`)
```swift
import Foundation
import Supabase

/// Lazily creates the app's single SupabaseClient. Nothing calls it yet: local SwiftData stays the
/// source of truth (offline-first). Constructing the provider performs no I/O.
@MainActor
final class SupabaseClientProvider {
    let configuration: SupabaseConfiguration
    private var cachedClient: SupabaseClient?

    init(configuration: SupabaseConfiguration = .production)

    var isClientCreated: Bool { cachedClient != nil }

    var client: SupabaseClient  // creates on first access, then returns cachedClient
}
```
- The client is created with
  `SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey, options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true)))`.
  Keep the default Keychain storage, `autoRefreshToken` and flow type. If the
  `SupabaseClientOptions(auth:)` label differs in 2.55.7, use its memberwise-default init with only `auth:`
  set. This is a mechanical fix, not a design choice.
- Why a provider and not a global `let supabase`:
  - it matches the app-root injection pattern (`AppResources` builds every service);
  - it is testable;
  - it keeps construction lazy, so launch, UI tests and previews never touch Keychain or the network;
  - a future sync service can receive it through `AppResources` without hidden globals.

### 4. `MojSlownik/MojSlownikApp.swift` (`AppResources` only)
- Add a stored property `let supabase: SupabaseClientProvider`.
- Add the init parameter `supabase: SupabaseClientProvider? = nil`, placed last. Assign
  `self.supabase = supabase ?? SupabaseClientProvider()` at the end of init. Use an optional instead of a default
  expression because default arguments of a `@MainActor` initializer cannot portably call
  another `@MainActor` init in Swift 5.9.
- `uiTest(_:now:)` and `preview` need no change: they use the default provider, which stays lazy.
- Do **not** add it to `.environment(...)` in `MojSlownikApp.body`, and do not store it in `MojSlownikApp`
  `@State`. No consumer exists yet, so injecting it into the environment would be dead UI wiring.

### 5. Views and stores
None.

### 6. `AGENTS.md`
Replace "No backend, accounts or synchronization." with:
"No accounts or synchronization yet; the Supabase SDK is linked and configured
(Backend/SupabaseClientProvider.swift) but nothing calls it."
No other edits.

### 7. `docs/architecture.md`
- Line 4: change "No backend, accounts or synchronization." to the same wording as AGENTS.md.
- Application Map, **Build** row: append "Swift package `supabase-swift` (product `Supabase`, exact
  2.55.7; needs Xcode 16.3+)."
- **Backend Readiness**: add a paragraph before the gaps list:
  "`Backend/SupabaseConfiguration.swift` holds the project URL and publishable key (public;
  secret keys never ship in the app). `Backend/SupabaseClientProvider.swift` creates one
  `SupabaseClient` lazily, owned by `AppResources` and not placed in the environment. Nothing calls it, and
  launch, UI-test mode and previews never create it. Remote schema, RLS, auth and sync are not implemented (Gap H)."

### 8. `README.md`
In the requirements line (line 23 area), add a note that the first build downloads Swift
packages, so it needs internet, and that it needs Xcode 16.3 or newer. Write it in Russian, like the rest of the README:
"Первая сборка скачивает Swift-пакеты (нужен интернет); нужен Xcode 16.3 или новее."

### 9. `.github/workflows/ci.yml`
No change in this task. `xcodebuild` resolves packages automatically inside `-derivedDataPath DerivedData`.
Caching is OD-3.

## Reuse

- The `AppResources` composition root and its existing pattern of injectable dependencies with
  defaults (`defaults:`, `calendar:`, `configuration:`).
- The in-memory `ModelConfiguration(isStoredInMemoryOnly: true)` and `UserDefaults(suiteName:)` pattern
  from the existing tests (e.g. `UITestSupportTests`, `VocabularyStoreTests`) for constructing `AppResources`.
- No Theme or Components usage (no UI).

## Data compatibility

- There is no SwiftData model change, so existing `Word`/`WordFolder` rows are untouched and no migration is needed.
- No UserDefaults keys change.
- Keychain: nothing is written, because the client is not created in the app. Even once it is, it writes only on
  sign-in (`sb-bjwptrfbtcmxlhjaxiip-auth-token`).

## Verification

Pick `<device>` from `xcrun simctl list devices available`. If needed, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

1. `xcodegen generate` (new files and the `project.yml` change).
2. Build with zero warnings:
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=<device>' build | grep -E 'error:|warning:|SUCCEEDED|FAILED'`.
3. CI-equivalent strict build. This is required because of Risk R1:
   `xcodebuild build-for-testing -project MojSlownik.xcodeproj -scheme MojSlownik -destination '…' -derivedDataPath /private/tmp/…/scratchpad/dd CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`.
4. Unit tests. Add a new `MojSlownikTests/SupabaseClientProviderTests.swift` (`@MainActor`, XCTest,
   `@testable import MojSlownik`, **no** `import Supabase`):
   - `testProductionConfigurationPointsAtProjectOverHTTPS`: scheme `https`, host
     `bjwptrfbtcmxlhjaxiip.supabase.co`.
   - `testProductionKeyIsPublishable`: has the prefix `sb_publishable_`, and does not contain `sb_secret_`.
   - `testRejectsNonHTTPSURL` (`http://x.supabase.co`), `testRejectsURLWithoutHost` (`https://`),
     and `testRejectsMalformedURL` (`""`). Each expects `.invalidURL`.
   - `testRejectsSecretKey` (`sb_secret_abc`), `testRejectsEmptyKey` (`"  "`),
     `testRejectsBarePrefixKey` (`sb_publishable_`), and `testRejectsLegacyJWTKey` (`eyJhbGciOi…`).
     Each expects `.invalidKey`. A legacy anon JWT is also publishable, but this app pins the new key
     format. The rejection is deliberate and documented in the test name.
   - `testProviderIsLazy`: a new provider has `isClientCreated == false`.
   - `testClientIsCreatedOnceAndReused`: `provider.client === provider.client` and
     `isClientCreated == true`. This performs no network, and Keychain is touched only by the auth listener in the
     simulator test host.
   - `testAppResourcesDoesNotCreateSupabaseClient`: `AppResources(configuration: in-memory, defaults: UserDefaults(suiteName: "SupabaseClientProviderTests")!)`
     produces `resources.supabase.isClientCreated == false`. Remove the defaults suite in `tearDown`.
   - `testUITestResourcesDoNotCreateSupabaseClient`: `#if DEBUG`, using `AppResources.uiTest(UITestLaunchConfiguration(fixture: .empty, prefill: nil))`
     produces `isClientCreated == false`.

   Run them:
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination '…' test`. Everything must be green.
5. E2E: no user-facing flow changes, so add no new scenarios or fixtures. Run the whole
   `MojSlownikE2E` scheme once to prove that launch in fixture mode is unaffected by the linked SDK.
6. Secret scan of the diff:
   `git diff da2443c -- . | grep -nE 'sb_secret_|service_role|postgres(ql)?://|DATABASE_URL'` must print nothing.
7. Manual checks (not runnable by the agent):
   - Install on the physical iPhone (README flow) and confirm that the app launches and existing words are intact.
   - Confirm that the first Xcode GUI open resolves packages without prompts.
   - Watch the first CI run: duration of package resolution and the three jobs still green.

## Risks

- **R1 Warnings-as-errors and remote packages.** CI passes `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the
  command line, which applies to package targets too. Xcode builds remote packages with suppressed
  warnings. Some Xcode versions report `conflicting options '-warnings-as-errors' and '-suppress-warnings'`,
  or fail on package warnings. Verification step 3 detects this locally.
  **Fallback (pre-decided):** remove the two `*_TREAT_WARNINGS_AS_ERRORS` overrides from the CI build
  step, and instead add `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` and `GCC_TREAT_WARNINGS_AS_ERRORS: YES` under
  `targets.MojSlownik.settings.base` in `project.yml`. That target-scoped setting does not reach packages, keeps the app
  zero-warning, and also enforces it locally. Report it if the fallback was applied.
- **R2 CI time and network.** Each of the 3 macOS jobs clones supabase-swift plus its transitive packages
  (swift-crypto, swift-http-types, pointfree helpers) and compiles about 6 package modules. Expect roughly 1–3 minutes per job.
  If clones of test-only dependencies (snapshot-testing and swift-syntax) appear, they cost time but are not linked.
  A GitHub or network outage now fails CI. OD-3 decides caching.
- **R3 Test target cannot see module `Supabase`.** `@testable import MojSlownik` loads the app module's
  dependencies, and package modules are emitted in `BUILT_PRODUCTS_DIR`, so this normally works. If the compile fails
  with "missing required module 'Supabase'", add `SWIFT_INCLUDE_PATHS: $(BUILT_PRODUCTS_DIR)` to
  `MojSlownikTests.settings.base`. Do **not** link the product into the test bundle, because that would create duplicate class
  implementations.
- **R4 Transitive versions float.** `Package.resolved` lives inside the untracked `.xcodeproj`, so transitive
  versions can drift between runs even with an exact top-level pin. OD-3 covers this.
- **R5 Runtime issue noise.** The provider sets `emitLocalSessionAsInitialSession: true` to avoid the
  SDK's initial-session `reportIssue`. If a future SDK update adds init-time issues, they surface
  only when `client` is accessed. Today that happens only in unit tests, where `isTesting` suppresses the issue.
- **R6 App size and export compliance.** The binary grows (swift-crypto). The app uses only standard HTTPS/TLS, so
  `ITSAppUsesNonExemptEncryption: false` stays accurate.

## Open decisions (recommended option first)

- **OD-1 SDK scope.**
  - (a) **Recommended:** SDK plus a lazy configured provider only, as planned. No calls, no UI.
  - (b) Also add a DEBUG-only health check (e.g. a Settings row that pings `/rest/v1/`). This adds UI and E2E work
    for little value.
  - (c) The quickstart `Todo` demo. Rejected, because it replaces the app root.
- **OD-2 Supabase remote project (MCP).**
  - **Recommended: no remote changes in this task.**
  - Before implementation, the orchestrator should run **read-only** checks and report the results to the user:
    - `get_project_url`: must equal the planned URL;
    - `get_publishable_keys`: the key must exist and be enabled;
    - `list_tables` (schemas `public`): note whether the quickstart `todos` table exists;
    - `get_advisors` (type `security`): flag any table with RLS disabled. If `todos` exists without RLS,
      ask the user whether to drop it or enable RLS. Do not change it unilaterally.
  - Ask the user as a separate future task: create `words`/`folders` tables mirroring `Word`/`WordFolder` (uuid PK,
    `user_id`, `updated_at`, `deleted_at`, `folder_ids uuid[]`), with RLS `auth.uid() = user_id`, plus an
    auth method (Sign in with Apple vs anonymous vs email OTP), plus a sync engine. That task needs its own plan
    resolving Gaps B, C, E, F and H.
- **OD-3 CI package caching and reproducibility.**
  - (a) **Recommended now:** no CI change. Measure the first run.
  - (b) Add a cache step for `DerivedData/SourcePackages`, keyed on `hashFiles('project.yml')` and pinned by
    commit SHA like the other actions.
  - (c) Commit a `Package.resolved` copy (e.g. `ci/Package.resolved`) and have CI copy it into
    `MojSlownik.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/` after `xcodegen generate`. This gives fully
    reproducible transitive versions. Revisit (b) and (c) if a run is slow or flaky.
- **OD-4 Where the URL and key live.**
  - (a) **Recommended:** Swift constant in `SupabaseConfiguration.production`. There is one environment, and the key is public.
  - (b) Info.plist keys from `project.yml` `info.properties`, or per-configuration xcconfig. This is worth it only when a
    staging project appears.
- **OD-5 Version pin.**
  - (a) **Recommended:** `exactVersion: 2.55.7`, which keeps builds reproducible while `Package.resolved` is untracked.
  - (b) `from: 2.55.7` (up to the next major), which picks up fixes automatically but can introduce new package behavior unannounced.
- **OD-6 `npx skills add supabase/agent-skills`.**
  - This is AI-agent tooling, not app code. It installs skill folders into the agent directories it detects
    (`.agents/skills/` for Codex and `.claude/skills/` for Claude Code). It is interactive and fetches from npm and GitHub.
  - **Recommended:** do not run it in this task. If the user wants it, run it as a separate commit after this
    one, review the added files, and keep them repo-local (no global install). It becomes useful when the
    schema/RLS task (OD-2) starts.
- **OD-7 Legacy anon JWT keys.**
  - **Recommended:** reject them in validation (AC-3), which pins the new `sb_publishable_` format.
  - The alternative is to accept any non-`sb_secret_` key. A secret key would still be rejected either way.
