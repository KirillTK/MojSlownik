# E2E fixtures, sharded XCUITest, CI and merge blocking

Mode: full. Planned against `origin/main` d593a09 (see "Base and branch").

## Goal

Lift the project-wide E2E ban and replace it with a rule: when a user-facing flow changes,
fixture-based XCUITest E2E scenarios must be added or updated and run. Deliver:

1. A DEBUG-only UI-test mode, activated by launch environment, with named SwiftData
   fixtures, stubbed translation (no network) and isolated UserDefaults.
2. Accessibility identifiers on key controls and 5 E2E test classes built on a shared helper.
3. A dedicated `MojSlownikE2E` scheme that runs in parallel on simulator clones locally,
   plus CI sharding across a job matrix.
4. An extended GitHub Actions workflow (build + unit tests, E2E shards, one aggregate
   `ci-passed` check).
5. A committed GitHub ruleset for `main` that requires a PR and a green, up-to-date
   `ci-passed`. Merging is then blocked while pipelines run and when they fail.
6. Updated agent rules (AGENTS.md, CLAUDE.md, hook, Claude and Codex workflow files, docs).

## Constraints

User task (verbatim): "давай добавим шан и сетап под e2e и обнови ci/cd и заблочь мерж пока
идут пайплайны и если что-то зафейлилось" ("шан" means sharding of E2E tests).

Agreed in conversation (binding):
- The user explicitly lifts the E2E ban. This task changes the AGENTS.md rule. The old ban does not apply here.
- New rule: when a user-facing flow changes, add or update XCUITest E2E scenarios built on named
  fixtures. Reuse existing fixtures and add new ones when needed. Never seed data through
  UI steps inside a test. Run the E2E scheme. Camera, OCR and physical-iPhone checks remain manual.
- The hook keeps blocking tests run through the `MojSlownik` app scheme. It allows `MojSlownikUnitTests`
  and the new `MojSlownikE2E`.
- Test mode is `#if DEBUG` only. Production behaviour is unchanged and stored words are preserved.
  Integrate the existing `UITEST_PREFILL` mechanism instead of duplicating it.
- Fixture definitions get unit tests in MojSlownikTests.
- Keep and adapt `MojSlownikUITests/AddWordFlowTests.swift`.
- CI: `pull_request` (never `pull_request_target`) and push to `main`. Use `permissions: contents: read`,
  concurrency cancel-in-progress per PR and pinned action versions. Upload `.xcresult` on failure.
  Pick the simulator dynamically. Add an aggregate final job.
- Merge blocking is applied via `gh api` only after the workflow has run once, and only with
  explicit user authorization (the orchestrator asks). Recommend enforcing it for admins.
- Do not edit historical plans in `.codex/plans/`.
- No commit, push or PR without user authorization.
- Tooling: `/opt/homebrew/bin/xcodegen`, `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
  simulator from `xcrun simctl list devices available`.

## Base and branch (read first)

- Local `main` (6a24857) is stale. `origin/main` is d593a09 (17 Nov 2026). It already contains
  commit 3bd8dde from `translation-alternatives`, so that branch has nothing unmerged. It also
  contains the "Marker" redesign, achievements (`AchievementStore`, banners) and
  **an existing `.github/workflows/ci.yml`** (PR #4). The premise "no .github/ exists" is
  outdated: this plan **extends** that workflow.
- Implementation must start on a new branch from fresh `origin/main`:
  `git fetch origin && git switch -c e2e-fixtures-ci origin/main`. The orchestrator asks the user first.
  All paths and line numbers below refer to `origin/main`.
- `project.yml`, `MojSlownikUITests/AddWordFlowTests.swift`, `.claude/hooks/guard-xcodebuild.sh`,
  `.claude/settings.json`, `TranslationService.swift` and `TranslationAlternatives.swift` are
  identical between HEAD and `origin/main`.

## Acceptance criteria

- AC-1 Production is unchanged. A Release build contains no UI-test code: `nm` on the Release binary
  finds no `UITestLaunchConfiguration`/`UITestFixture`/`UITestTranslationStub` symbols, and `strings`
  finds no "Unknown UITEST_FIXTURE". When neither `UITEST_FIXTURE` nor `UITEST_PREFILL` is set,
  a Debug launch uses the on-disk store, `UserDefaults.standard` and the real translators exactly
  as before.
- AC-2 Launching a Debug build with `UITEST_FIXTURE=<name>` opens an in-memory SwiftData store
  seeded with that fixture. Daily study and achievements start empty in a dedicated defaults
  suite that is wiped on every launch. Translation and alternatives return deterministic stub
  values with no network access. An unknown fixture name crashes at launch with a message naming
  the bad value.
- AC-3 `UITEST_PREFILL=<text>` still opens the scan result sheet without the camera. It now implies
  the test mode (fixture `empty` unless `UITEST_FIXTURE` is also set), so it never writes to the
  real store or the network.
- AC-4 Fixtures `empty`, `basicVocabulary`, `dueForReview` and `foldersOrdered` exist. Unit tests verify
  word/folder counts, due counts, folder order and memberships, env parsing and stub determinism.
- AC-5 `MojSlownikUITests` contains 5 test classes (AddWord, EditTranslation, Flashcards, Quiz,
  Folders) with 9 tests on a shared `E2ETestCase` helper. No test creates its preconditions
  through UI steps. All of them pass locally via `-scheme MojSlownikE2E`.
- AC-6 The `MojSlownikE2E` scheme runs only `MojSlownikUITests` with parallelizable classes, so Xcode
  uses simulator clones locally.
- AC-7 The CI workflow runs on PRs to `main`, pushes to `main` and manual dispatch. It runs these jobs:
  - `Build & unit tests`: the existing job, unchanged in behaviour.
  - `E2E (practice)` and `E2E (dictionary)`: matrix shards running in parallel with the build job. The
    `dictionary` shard runs every class not explicitly assigned to `practice`, so new classes are
    never left unrun.
  - `ci-passed`: always runs and fails unless every needed job succeeded.
  Each shard uploads its `.xcresult` on failure. All actions are pinned to full commit SHAs.
- AC-8 `.github/rulesets/main.json` defines a ruleset for the default branch with no bypass actors.
  It requires a PR (0 approvals), requires the status check `ci-passed` from GitHub Actions (`integration_id` 15368) with
  non-strict policy (per D4, freshness is enforced by the `Branch freshness` job: ≤ 10 commits behind), and blocks force-push and deletion. Exact apply and verify commands
  are documented. After it is applied, a PR with running or failed CI shows merging as blocked.
- AC-9 The hook blocks any command containing a test action, including when it is glued to shell
  operators (`test|…`, `test;…`, `test&&…`), unless every `-scheme` in the command is
  `MojSlownikUnitTests` (without UI-test references) or `MojSlownikE2E`. A missing scheme blocks.
- AC-10 AGENTS.md, CLAUDE.md, both workflow skills, all Claude feature agents that mention E2E,
  all six Codex agent TOMLs and docs/architecture.md state the new rule. None still forbids XCUITest.
- AC-11 The build has zero warnings (CI's `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` build-for-testing,
  which also compiles UI tests). Unit tests are green.

## Changes by file

### 1. Services: test mode (new, DEBUG-only)

**`MojSlownik/Services/UITestLaunchConfiguration.swift`** (new). The entire file is wrapped in `#if DEBUG … #endif`.

```swift
struct UITestLaunchConfiguration: Equatable, Sendable {
    static let fixtureKey = "UITEST_FIXTURE"
    static let prefillKey = "UITEST_PREFILL"
    static let defaultsSuite = "MojSlownik.UITest"

    let fixture: UITestFixture
    let prefill: String?

    enum ParseError: LocalizedError, Equatable { case unknownFixture(String) }
    // errorDescription: "Unknown UITEST_FIXTURE '<name>'. Known: empty, basicVocabulary, …"

    /// nil when neither key is set (empty strings count as unset).
    /// Prefill without a fixture → fixture .empty. Unknown fixture name → throws.
    static func parse(_ environment: [String: String]) throws -> UITestLaunchConfiguration?

    /// Cached for non-throwing call sites (Translator, WordListView). App launch calls
    /// parse(ProcessInfo.processInfo.environment) itself so errors surface.
    static let current: UITestLaunchConfiguration? =
        try? parse(ProcessInfo.processInfo.environment)
}

enum UITestTranslationStub {
    static func translate(_ text: String, from source: AppLanguage, to target: AppLanguage) -> String
    static func alternatives(_ text: String, pair: TranslationPair) -> [[TranslationAlternative]]
}
```

Stub rules:
- Key = `text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()`.
- `translate` looks the key up in a table keyed by target language.
  - Polish target: привет→cześć, мир→świat, привет мир→cześć świecie, собака→pies, кот→kot, дом→dom.
  - Russian target: dom→дом, kot→кот, woda→вода, dziękuję→спасибо, bardzo→очень,
    dziękuję bardzo→спасибо большое.
  - Fallback: Polish target → `"słowo"`, Russian target → `"слово"`. The fallbacks are script-valid,
    so the language-direction check never sees the wrong alphabet.
- `alternatives` returns raw groups `[google, myMemory]` so that the real
  `TranslationAlternatives.merge`/validation still runs:
  - "dom" → `[[("дом","существительное"), ("жилище", nil)], []]`
  - "собака" → `[[("pies","rzeczownik"), ("psina", nil)], []]`
  - anything else → `[[], []]`
- There is no artificial delay. The drafts' debounce still applies.

**`MojSlownik/Services/UITestFixtures.swift`** (new, wrapped in `#if DEBUG`).

```swift
enum UITestFixture: String, CaseIterable, Sendable {
    case empty, basicVocabulary, dueForReview, foldersOrdered
    static let lesson1ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let lesson2ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let lesson3ID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F3")!
    @MainActor func seed(into context: ModelContext, now: Date) throws   // inserts + context.save()
}
```

All dates are relative to `now`, which is the launch time. See Open decision 6.

Words are created with `Word(russian:polish:sourceLanguage:createdAt:)`. The i-th word gets `createdAt = now - (i+1) h`.
- **"learned"**: `repetitions = 3`, `intervalDays = 30`, `easeFactor = 2.5`, `dueDate = now + 30 d`.
- **"due"**: `repetitions = 1`, `intervalDays = 1`, `dueDate = now - 1 d`.

Fixtures:
- `empty`: nothing.
- `basicVocabulary`: 5 learned words, none due:
  - кот/kot (ru)
  - дом/dom (pl)
  - вода/woda (pl)
  - хлеб/chleb (ru)
  - книга/książka (ru)
- `dueForReview`: learned кот/kot, дом/dom, вода/woda, plus due яблоко/jabłko (ru) and окно/okno (pl).
  That is 5 words, exactly 2 due.
- `foldersOrdered`:
  - `WordFolder`s are inserted in the order Урок 3, Урок 1, Урок 2, which is deliberately not their sort order.
    Each gets an `id` from the constants above, `sortOrder` 0/1/2 for Урок 1/2/3 and
    `createdAt = now - 1 d`.
  - Words, all learned: kot and dom in Урок 1, woda in Урок 2, chleb in no folder.

### 2. Services: stub hooks

**`MojSlownik/Services/TranslationService.swift`**: add at the top of `Translator.translate`, before the Apple path:
```swift
#if DEBUG
if UITestLaunchConfiguration.current != nil {
    return UITestTranslationStub.translate(text, from: source, to: target)
}
#endif
```

**`MojSlownik/Services/TranslationAlternatives.swift`**: same pattern at the top of
`TranslationAlternativesService.fetch`, returning `UITestTranslationStub.alternatives(text, pair: pair)`.

This one seam covers `AddWordDraft` and `ScanResultDraft`, which use these defaults. No store changes.

### 3. App resources

**`MojSlownik/MojSlownikApp.swift`**:
- In `AppResources`, add:
```swift
#if DEBUG
static func uiTest(_ configuration: UITestLaunchConfiguration, now: Date = .now) throws -> AppResources {
    UserDefaults().removePersistentDomain(forName: UITestLaunchConfiguration.defaultsSuite)
    let defaults = UserDefaults(suiteName: UITestLaunchConfiguration.defaultsSuite)!
    let resources = try AppResources(configuration: ModelConfiguration(isStoredInMemoryOnly: true),
                                     defaults: defaults, now: now)
    try configuration.fixture.seed(into: resources.container.mainContext, now: now)
    return resources
}
#endif
```
- In `MojSlownikApp.init`, inside the existing `do`, choose the resources:
  - Under `#if DEBUG`: if `try UITestLaunchConfiguration.parse(ProcessInfo.processInfo.environment)` returns a value,
    use `try AppResources.uiTest(config)`. Otherwise use `try AppResources()`.
  - Under `#else`: `try AppResources()` only.
  - A parse error reaches the existing `fatalError("Unable to open the dictionary: \(error)")`.
- Do not change `preview` or the existing init signature.

### 4. Views: prefill integration and identifiers

Only add identifiers and the prefill change. No layout, copy or behaviour changes.

**`MojSlownik/Views/WordListView.swift`**
- `.onAppear` (around line 124): replace the `ProcessInfo…["UITEST_PREFILL"]` read with
  `UITestLaunchConfiguration.current?.prefill`, inside `#if DEBUG … #endif`. Keep `didHandleTestPrefill`.
- Identifiers:
  - Floating "Добавить слово" button: `addWordButton`.
  - "Сканировать текст" button: `scanButton`.

**`MojSlownik/Views/AddWordView.swift`**
- Bottom "Сохранить" (line 57): `saveWordButton`.
- `alternativeChip`: `.accessibilityIdentifier("translationOption-\(option.text)")`.

**`MojSlownik/Views/ScannerView.swift`** (`ScanResultView`)
- "Готово" toolbar button: `scanDoneButton`.
- Chip `.contextMenu` (around line 447): put `scanEditWordButton` on the "Исправить слово…" `Button`.
  ScanResultView has no "Исправить слово" Menu. Word editing is reached only through this context
  menu and the chip's `accessibilityActions` (line 422), and those are left unchanged.

**`MojSlownik/Views/Components/FolderPicker.swift`**
- Picker button (line 33): `folderPickerButton`.
- `optionRow`: `folderOption-\(name)`. The "all words" row uses `folderOption-all`, so pass an
  identifier string from the caller: `id == nil ? "all" : name`.
- "Создать папку" button: `createFolderButton`.
- New-folder `TextField`: `folderNameField`.
- "Создать" confirm: `confirmCreateFolderButton`.

**`MojSlownik/Views/TrainingView.swift`**
- `practiceButton`: `practiceStartButton`.
- Today panel element with label "Повторено сегодня" (line 84): `todayProgress`.
- `Text("Ответов: …")` (line 93): `answerTotal`.
- Flashcards tile NavigationLink: `flashcardsModeTile`.
- Quiz tile: `quizModeTile`.

**`MojSlownik/Views/FlashcardsView.swift`**
- Grade buttons: `gradeButton-\(grade.rawValue)`.
- "Тренировка завершена" text: `flashcardsCompleted`.
- "К практике": `backToPracticeButton`.

**`MojSlownik/Views/QuizView.swift`**
- Iterate options as `ForEach(Array(question.options.enumerated()), id: \.element)` and set
  `quizOption-\(offset)` on each option Button.
- Prompt text: `quizPrompt`.
- Result `Text("\(score) из …")`: `quizScore`.

**`MojSlownik/Views/Components/SessionProgress.swift`**: `sessionProgress`.

### 5. Project

**`project.yml`**: add the scheme. Leave the `MojSlownik` and `MojSlownikUnitTests` schemes unchanged.
```yaml
  MojSlownikE2E:
    build:
      targets:
        MojSlownik: all
        MojSlownikUITests: [test]
    test:
      config: Debug
      targets:
        - name: MojSlownikUITests
          parallelizable: true
```
Then run `xcodegen generate`.

### 6. UI tests (`MojSlownikUITests/`)

**`E2ETestCase.swift`** (new): base `class E2ETestCase: XCTestCase`.
- `enum Fixture: String { case empty, basicVocabulary, dueForReview, foldersOrdered }`. This mirrors the
  app enum. A unit test pins the app-side raw values (see Verification).
- `override func setUpWithError() throws { continueAfterFailure = false }`
- `@MainActor` helpers:
  - `launch(_ fixture: Fixture, prefill: String? = nil) -> XCUIApplication`: sets
    `launchEnvironment["UITEST_FIXTURE"]` and, when given, `["UITEST_PREFILL"]`, then launches.
  - `element(_ id: String) -> XCUIElement` (`app.descendants(matching: .any)[id].firstMatch`).
  - `waitForHittable(_:timeout:)`.
  - `waitForLabel(_:equals:timeout:)` and `waitForValue(_:equals:timeout:)` (`XCTNSPredicateExpectation`;
    default timeout 10 s).
  - `openTab(_ title: String)` (`app.tabBars.buttons[title]`).
  - `waitForEnabled(_:timeout:)` (predicate `isEnabled == true`).
  - `replaceText(in:with:)`:
    1. Tap the field's trailing edge with `field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()`
       so the caret sits at the end.
    2. Type `XCUIKeyboardKey.delete` repeated (current value count + 5) times, then type the new text.
    3. `waitForValue` the new text.
  - `dismissAchievementBannerIfPresent()`:
    - Query `app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Достижение получено'"))`.
    - Loop at most 5 times: wait up to 1 s for any match, pick the first match that `isHittable`, tap it,
      then wait up to 2 s for it to disappear. Stop when no match exists.
    - Several unlocks can queue banners, which is why it loops.
- Typed text must be ASCII only. Cyrillic typing is unreliable, so Cyrillic sources come from
  `UITEST_PREFILL`. Stub tables are designed for this.

Test classes, one file per class. Every test method is `@MainActor`. Every class is `final class X: E2ETestCase`.

1. **`AddWordFlowTests.swift`** (rewrite the existing file; this removes the stale `scanInlineWord`,
   "Тренировка" and "Флешкарточки" references and the network dependency):
   - `testAddRussianWordViaScanQuickAdd`:
     1. `launch(.empty, prefill: "привет мир")`.
     2. `scanTranslationText` label equals "cześć świecie".
     3. `waitForEnabled(scanWordChip-привет-0)`: the chip is disabled until its word translation arrives,
        and its label then contains "cześć". Tap it (quick add).
     4. Tap `scanDoneButton` (dismiss the banner first).
     5. The list shows staticTexts "привет" and "cześć".
   - `testAddPolishWordManually`:
     1. `launch(.empty)` and tap `addWordButton`.
     2. Type "dom" into `sourceField`.
     3. `translationField` value equals "дом".
     4. Tap `saveWordButton` and dismiss the banner.
     5. The list shows "dom" and "дом".
2. **`EditTranslationFlowTests.swift`**:
   - `testManualTranslationEditIsSaved`:
     1. `launch(.empty, prefill: "собака")`.
     2. `waitForEnabled(scanWordChip-собака-0)`, then `press(forDuration: 1.0)` on it to open the
        context menu. Tap `scanEditWordButton`; AddWordView opens with initialText "собака".
     3. `translationField` equals "pies".
     4. `replaceText` with "piesek", then tap `saveWordButton`.
     5. Dismiss the banner and tap `scanDoneButton`.
     6. The list shows "собака" and "piesek".
   - `testAlternativeChipReplacesTranslation`:
     1. `launch(.empty)` and tap `addWordButton`.
     2. Type "dom" and wait for "дом".
     3. Tap `translationOption-жилище`. `translationField` equals "жилище".
     4. Save. The list shows "жилище".
3. **`FlashcardsFlowTests.swift`** (fixture `dueForReview`):
   - `testGoodRatingClearsDueWords`:
     1. Open the "Практика" tab. `practiceStartButton` label equals "Начать повторение · 2".
     2. Tap it. For n in 1…2:
        1. Wait for `flashcard` and tap it.
        2. Wait for `gradeButton-good` to exist and tap it.
        3. While cards remain, wait for `sessionProgress` value "Ответов: n из 2". After the last grade,
           go straight to step 3.
     3. `flashcardsCompleted` exists and staticText "Повторено слов: 2" exists.
     4. Tap `backToPracticeButton`.
     5. `practiceStartButton` label equals "Свободная практика" and `todayProgress` value equals
        "2 из 2. Осталось: 0". This shows the ratings moved `dueDate` forward.
   - `testAgainRequeuesWord`:
     1. Start the session, tap `flashcard`, wait for `gradeButton-again` to exist, then tap it.
     2. `sessionProgress` value equals "Ответов: 1 из 3".
4. **`QuizFlowTests.swift`** (fixture `basicVocabulary`):
   - `testQuizCompletesAndRecordsAnswers`:
     1. Open "Практика" and tap `quizModeTile`.
     2. The fixture yields exactly 5 questions, since every word has distractors. Loop i in 0..<5:
        1. Before tapping, `waitForEnabled(quizOption-0)`. Options are `.disabled(selectedAnswer != nil)`
           until the 900 ms auto-advance.
        2. Tap it, then wait for `sessionProgress` value "Ответов: \(i+1) из 5".
     3. Wait for `quizScore`. Its label matches `^[0-5] из 5$`.
     4. Navigate back (`app.navigationBars.buttons.firstMatch`). `answerTotal` label equals "Ответов: 5".
5. **`FoldersFlowTests.swift`** (fixture `foldersOrdered`):
   - `testFolderOrderAndFiltering`:
     1. Tap `folderPickerButton`.
     2. The `frame.minY` of `folderOption-Урок 1` < `Урок 2` < `Урок 3`.
     3. Tap `folderOption-Урок 1`.
     4. "kot" and "dom" exist, "woda" does not, and the `folderPickerButton` label equals "Папка: Урок 1".
   - `testCreateFolderSelectsIt`:
     1. Tap `folderPickerButton`, then `createFolderButton`.
     2. Type "Lekcja" into `folderNameField` and tap `confirmCreateFolderButton`.
     3. The `folderPickerButton` label equals "Папка: Lekcja" and button "Показать все слова" exists
        (the new folder is empty).

### 7. Unit tests (`MojSlownikTests/`)

**`UITestSupportTests.swift`** (new, `@testable import MojSlownik`, `@MainActor`, in-memory containers).

Fixture tests:
- `UITestFixture.allCases.map(\.rawValue) == ["empty","basicVocabulary","dueForReview","foldersOrdered"]`.
  This pins the names that the UI-test `Fixture` enum mirrors.
- Each fixture is seeded with a fixed `now` into
  `ModelContainer(for: Word.self, WordFolder.self, configurations: .init(isStoredInMemoryOnly: true))`:
  - `empty`: 0 words, 0 folders.
  - `basicVocabulary`: 5 words, 0 with `dueDate <= now`, and polish set {kot, dom, woda, chleb, książka}.
  - `dueForReview`: 5 words and exactly {jabłko, okno} due at `now`.
  - `foldersOrdered`: `FolderStore.folders(in:)` names == ["Урок 1","Урок 2","Урок 3"]; kot/dom
    folderIDs == [lesson1ID]; woda == [lesson2ID]; chleb == [].

Launch-configuration tests (`parse`):
- `[:]` → nil.
- `["UITEST_PREFILL": "x"]` → fixture `.empty`, prefill "x".
- `["UITEST_FIXTURE": "dueForReview"]` → `.dueForReview`, prefill nil.
- `["UITEST_PREFILL": ""]` → nil.
- `["UITEST_FIXTURE": "nope"]` throws `.unknownFixture("nope")`.

Translation-stub tests:
- ru→pl results for "Привет " and "собака" contain no Cyrillic and equal "cześć" and "pies".
- pl→ru "dom" equals "дом".
- Unknown text gives "słowo" or "слово" depending on the target.
- `alternatives("dom", …)` passed through `TranslationAlternatives.merge(primary: "дом", …)` contains "жилище".

`AppResources.uiTest` test:
1. Write a sentinel key into the `MojSlownik.UITest` suite.
2. Build with `.dueForReview`.
3. The sentinel is gone, the container holds 5 words, and the suite is cleaned up in `tearDown`.

### 8. CI

**`.github/scripts/pick-simulator.sh`** (new, executable):
- Move the existing inline jq selection from `ci.yml` (the newest iOS ≥ 17 runtime and the last
  iPhone on it) into this script.
- Print `platform=iOS Simulator,id=<UDID>` to stdout. Exit 1 with `simctl list` output on failure.
- Developers can reuse it locally.

**`.github/workflows/ci.yml`** (modify).
- Triggers: `push: branches: [main]`, `pull_request: branches: [main]`, `workflow_dispatch`. Keep
  `permissions: contents: read`. Keep the concurrency block as it is.
- No `paths`/`paths-ignore` filters: the required check must report on every PR.
- Pin every `uses:` to a full commit SHA with a version comment. Resolve the latest release tag
  and its SHA with:
  - `gh release view -R <owner/repo> --json tagName -q .tagName`
  - `gh api repos/<owner/repo>/commits/<tag> -q .sha`
  - Write `uses: actions/checkout@<sha> # <tag>`.
  - This applies to `actions/checkout`, `actions/upload-artifact` and `maxim-lobanov/setup-xcode`.
- Job `build-and-test` (name "Build & unit tests"):
  - Unchanged, except the "Pick iPhone simulator" step becomes
    `echo "destination=$(.github/scripts/pick-simulator.sh)" >> "$GITHUB_OUTPUT"`.
  - It keeps build-for-testing with warnings-as-errors, which also compiles the UI tests.
- New job `e2e`:
```yaml
  e2e:
    name: E2E (${{ matrix.shard.name }})
    runs-on: macos-latest
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        shard:
          - name: practice
            selector: >-
              -only-testing:MojSlownikUITests/FlashcardsFlowTests
              -only-testing:MojSlownikUITests/QuizFlowTests
          - name: dictionary   # everything not in another shard → new classes are never dropped
            selector: >-
              -only-testing:MojSlownikUITests
              -skip-testing:MojSlownikUITests/FlashcardsFlowTests
              -skip-testing:MojSlownikUITests/QuizFlowTests
    steps:
      # checkout (pinned) → setup-xcode latest-stable (pinned) → brew install xcodegen xcbeautify
      # → xcodegen generate → pick simulator (script, step id sim) →
      # boot: xcrun simctl boot "$UDID" || true; xcrun simctl bootstatus "$UDID" -b
      - name: Run E2E shard
        run: |
          set -o pipefail
          xcodebuild test \
            -project MojSlownik.xcodeproj -scheme MojSlownikE2E \
            -destination '${{ steps.sim.outputs.destination }}' \
            -derivedDataPath DerivedData \
            -resultBundlePath E2E-${{ matrix.shard.name }}.xcresult \
            -parallel-testing-enabled NO \
            -test-timeouts-enabled YES -maximum-test-execution-time-allowance 300 \
            ${{ matrix.shard.selector }} \
            | xcbeautify --renderer github-actions
      - name: Upload E2E results
        if: failure()
        uses: actions/upload-artifact@<sha> # <tag>
        with: { name: E2E-${{ matrix.shard.name }}, path: E2E-${{ matrix.shard.name }}.xcresult, retention-days: 7 }
```
  - The pick step should output both `udid` and `destination`. The script prints the destination; the
    step extracts the UDID with `${DEST##*id=}`.
  - Do not pass `CODE_SIGNING_ALLOWED=NO` to the E2E run: UI-test runners need the default ad-hoc
    simulator signing. Only if the first CI run fails on signing, retry with `CODE_SIGNING_ALLOWED=NO`
    and record which one worked.
- New job `ci-passed`:
```yaml
  ci-passed:
    name: ci-passed
    if: always()
    needs: [build-and-test, e2e]
    runs-on: ubuntu-latest
    steps:
      - name: Require all jobs to succeed
        run: |
          echo '${{ toJSON(needs) }}'
          if [ "${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') || contains(needs.*.result, 'skipped') }}" = "true" ]; then
            exit 1
          fi
```
  The status check context is `ci-passed`, a stable name however the shards change.

**`.github/rulesets/main.json`** (new):
```json
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [ { "context": "ci-passed", "integration_id": 15368 } ] } }
  ]
}
```

Apply this only after `ci-passed` has reported at least once on the PR, and only with explicit user authorization (orchestrator step, not the implementer):
```sh
gh api repos/KirillTK/MojSlownik/rulesets --jq '.[] | {id,name,enforcement}'   # must not already contain main-protection
gh api -X POST repos/KirillTK/MojSlownik/rulesets --input .github/rulesets/main.json
gh api repos/KirillTK/MojSlownik/rules/branches/main --jq '.[].type'            # expect deletion, non_fast_forward, pull_request, required_status_checks
# later edits: gh api -X PUT repos/KirillTK/MojSlownik/rulesets/<id> --input .github/rulesets/main.json
```
`integration_id` 15368 is the GitHub Actions app, so only Actions can satisfy `ci-passed`; no other
source can post a fake status. Before applying, confirm it with
`gh api repos/KirillTK/MojSlownik/commits/<sha>/check-runs --jq '.check_runs[] | select(.name=="ci-passed") | .app.id'`.
If it differs, fix the JSON first.

### 9. Rules, hook and docs

**`.claude/hooks/guard-xcodebuild.sh`**: replace the test branch logic.
```bash
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *xcodebuild*) ;; *) exit 0 ;; esac
# test actions even when glued to shell operators: "test|tail", "test;echo", "test&&…"
echo "$cmd" | grep -qE '(^|[^[:alnum:]_-])(test|test-without-building)([^[:alnum:]_-]|$)' || exit 0
schemes=$(echo "$cmd" | grep -oE -- '-scheme[[:space:]=]+["'"'"']?[A-Za-z0-9_]+' \
          | sed -E 's/^-scheme[[:space:]=]+["'"'"']?//')
block() { echo "Blocked: test only with -scheme MojSlownikUnitTests or -scheme MojSlownikE2E; the MojSlownik app scheme's tests are not allowed (AGENTS.md)." >&2; exit 2; }
[ -z "$schemes" ] && block                                   # test without an explicit scheme
for s in $schemes; do
  case "$s" in
    MojSlownikE2E) ;;
    MojSlownikUnitTests) echo "$cmd" | grep -q 'MojSlownikUITests' && block ;;
    *) block ;;
  esac
done
exit 0
```
- The command is evaluated as a whole: if a test action appears anywhere, every `-scheme` value in the
  command must be allowed. A chained `xcodebuild -scheme MojSlownik build && xcodebuild -scheme
  MojSlownikUnitTests test` is therefore blocked. This conservative false positive is accepted; agents
  run build and test as separate commands.
- Update the header comment to match.

**`AGENTS.md`** (`origin/main` lines 36–50):
- Line 39: the comment becomes `# Unit tests (MojSlownikTests target)`.
- After the unit-test commands, add:
  ```
  # E2E (MojSlownikUITests; classes run in parallel on simulator clones)
  xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikE2E \
    -destination 'platform=iOS Simulator,name=<device>' test
  ```
- Line 48 becomes: "- When a user-facing flow changes, add or update XCUITest E2E scenarios in
  MojSlownikUITests built on named fixtures (`UITEST_FIXTURE`, Services/UITestFixtures.swift):
  reuse existing fixtures, add new ones (with unit tests) when needed, and never seed data
  through UI steps inside a test. Run them with the MojSlownikE2E scheme. Never run tests
  through the MojSlownik app scheme. Camera, OCR and physical-iPhone checks stay manual."
- Line 50 becomes: "- Done = clean build + green unit tests + green E2E for changed flows + a list of
  manual checks you could not run."
- Under Boundaries add: "- `main` is protected: merge only via PR with a green `ci-passed` check."

**`CLAUDE.md`** (line 8): "`.claude/hooks/guard-xcodebuild.sh` allows `xcodebuild … test` only for
the `MojSlownikUnitTests` and `MojSlownikE2E` schemes; testing through the `MojSlownik` app scheme
stays blocked."

**`.claude/skills/ios-feature-flow/SKILL.md`** (`origin/main` lines):
- Line 3: replace "Excludes E2E and UI automation." with "Includes fixture-based XCUITest E2E for
  changed user-facing flows; no browser/Playwright."
- Line 61: replace with "Do not ask whether to write E2E: changed user-facing flows always get
  fixture-based XCUITest scenarios. Never ask about browser testing."
- Step 5.2 (implement): add "and adds/updates fixture-based E2E scenarios for changed user-facing flows".
- Step 6: append the `MojSlownikE2E` test command using `$SIM`, filtered with `grep -E 'error:|failed|Executed|TEST (SUCCEEDED|FAILED)'`.
- Line 102: replace with "Never run tests through the `MojSlownik` app scheme; use
  `MojSlownikUnitTests` and `MojSlownikE2E` (the hook enforces this)."
- Step 8 (line 118): report E2E results. The manual checklist covers only what E2E does not cover
  (camera/OCR on a physical iPhone, visual polish).

**`.claude/agents/feature-implementer.md`** line 10: replace the final sentence with "For changed
user-facing flows, add or update XCUITest scenarios in MojSlownikUITests on named
UITEST_FIXTURE fixtures. Add a fixture and its unit test when needed, and never seed via UI steps.
Run the MojSlownikE2E scheme. Never run the MojSlownik app scheme's tests and never create
Playwright/browser tests."

**`.claude/agents/feature-{plan-reviewer,plan-critic,quality-reviewer,data-reviewer,ui-reviewer}.md`**
(the line containing "Never demand E2E/XCUITest"): replace it with "Never demand Playwright/browser
tests, a backend, server migrations or authentication. Missing or UI-seeded XCUITest coverage for a
changed user-facing flow is a valid finding; camera/OCR stays manual."

**`.claude/agents/feature-planner.md`** line 12: the Verification item becomes "Verification (unit tests to
add, E2E scenarios and fixtures for changed user-facing flows, build, manual checks)".

**`.agents/skills/feature-flow/SKILL.md`**: make the same semantic edits as the Claude skill.
- Line 3 description.
- Line 42: "Do not ask about E2E/browser testing" becomes "Do not ask whether to write E2E (changed
  user-facing flows always get fixture-based XCUITest); never ask about browser testing".
- Lines 63–66, item 11: rewrite to the new rule.
- Line 75: "never run the application scheme's tests" stays, and the MojSlownikE2E run is added.
- Lines 83–86, item 15: manual checks limited to what E2E does not cover.

**`.codex/agents/feature-*.toml`** (all six, line 8): replace "Do not create, update or run E2E,
Playwright or XCUITest. Preserve existing UI tests." with role-specific text. Leave the rest of the line unchanged.
- `feature-implementer.toml`: "Do not create or run Playwright/browser tests. For changed user-facing
  flows, add or update XCUITest E2E scenarios in MojSlownikUITests built on named UITEST_FIXTURE
  fixtures (add a fixture plus its unit test when needed; never seed through UI steps) and run them
  only via the MojSlownikE2E scheme. Never run the MojSlownik app scheme's tests. Camera/OCR checks
  stay manual. Preserve existing UI tests."
- `feature-planner.toml`: "Do not plan Playwright/browser tests. For changed user-facing flows, plan
  which XCUITest E2E scenarios to add or update and which named UITEST_FIXTURE fixtures they reuse or
  add (never seed through UI steps); verification runs the MojSlownikE2E scheme. Camera/OCR checks
  stay manual. Preserve existing UI tests."
- `feature-plan-reviewer.toml`, `feature-quality-reviewer.toml`, `feature-ui-reviewer.toml`,
  `feature-data-reviewer.toml`: "Never demand Playwright/browser tests. Missing or UI-seeded XCUITest
  E2E coverage for a changed user-facing flow is a finding; camera/OCR stays manual. Preserve
  existing UI tests."

**`docs/architecture.md`**:
- Line 23 Build row: list the schemes `MojSlownik` (app), `MojSlownikUnitTests` and `MojSlownikE2E`
  (UI tests, parallel), and mention `.github/workflows/ci.yml`.
- Lines 261–263: replace the `UITEST_PREFILL` bullet with a "UI-test mode" description:
  - DEBUG-only, activated by `UITEST_FIXTURE` and/or `UITEST_PREFILL`.
  - In-memory store seeded from `UITestFixture`, `MojSlownik.UITest` defaults wiped per launch.
  - Translation stubbed at `Translator`/`TranslationAlternativesService`.
  - Fixture dates are relative to launch time.
- Rename "## Unit Tests" to "## Tests and CI" and add:
  - E2E classes and the fixture rule.
  - The shard layout. The `dictionary` shard is the catch-all; a new class goes to `practice` only by
    adding it to both the `-only-testing` and `-skip-testing` lists.
  - The `ci-passed` aggregate.
  - The ruleset file and its apply command.
  - Typed E2E input must be ASCII.

Do not edit historical plans in `.codex/plans/`.

## Reuse

- `AppResources(configuration:defaults:calendar:now:)` (already supports in-memory and custom defaults).
- `FolderStore.folders(in:)` for ordering assertions.
- `TranslationAlternatives.merge`, kept live behind the stub.
- `AddWordDraft`/`ScanResultDraft` default translator closures, so no store changes are needed.
- Existing identifiers: `sourceField`, `translationField`, `scanOriginalText`,
  `scanWordChip-…`, `scanTranslationText` and `flashcard`.
- Existing CI simulator jq logic (moved into a script) and the xcbeautify/xcresult upload pattern.

## Data compatibility

- No model or schema changes. Existing on-disk SwiftData records and `UserDefaults.standard`
  (daily study, achievements) are never touched in test mode: it uses an in-memory container and the
  `MojSlownik.UITest` suite.
- `UITEST_PREFILL` was previously honoured in every configuration and used the real store and network.
  It is now DEBUG-only and in-memory. This is a deliberate test-only behaviour change, and no user
  ever sets this variable.

## Verification

Use `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and
`DEST=$(.github/scripts/pick-simulator.sh)`. Edit the hook (section 9) **before** running E2E,
otherwise the hook blocks it.

1. `/opt/homebrew/bin/xcodegen generate`
2. Run the CI-equivalent build:
   `xcodebuild build-for-testing -project MojSlownik.xcodeproj -scheme MojSlownik -destination "$DEST" CODE_SIGNING_ALLOWED=NO SWIFT_TREAT_WARNINGS_AS_ERRORS=YES | grep -E 'error:|warning:|SUCCEEDED|FAILED'`.
   Zero warnings.
3. Run a Release build (AC-1):
   `xcodebuild build -project MojSlownik.xcodeproj -scheme MojSlownik -configuration Release -destination "$DEST" -derivedDataPath /private/tmp/…/scratchpad/rel CODE_SIGNING_ALLOWED=NO`.
   Then check the Release binary for leaked UI-test code.
   - `nm <rel>/Build/Products/Release-iphonesimulator/MojSlownik.app/MojSlownik | grep -cE 'UITestLaunchConfiguration|UITestFixture|UITestTranslationStub'` must print 0.
   - Use `nm` on type symbols rather than `strings` for `UITEST_FIXTURE`: Swift inlines strings of 15
     bytes or fewer into immediates, so `strings` could miss them.
   - Also check a long literal: `strings … | grep -c 'Unknown UITEST_FIXTURE'` must print 0.
4. Run unit tests: `xcodebuild test -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination "$DEST"`, including the new `UITestSupportTests`.
5. Run E2E locally with simulator clones: `xcodebuild test -project MojSlownik.xcodeproj -scheme MojSlownikE2E -destination "$DEST"`.
   All 9 tests pass: AddWord 2, EditTranslation 2, Flashcards 2, Quiz 1, Folders 2. Run it a second
   time to spot flakiness.
6. Run each CI shard selector locally with `-parallel-testing-enabled NO`. Confirm `practice` runs
   3 tests (Flashcards 2 + Quiz 1) and `dictionary` runs 6, together exactly the full set.
7. Check the hook. Feed JSON to `.claude/hooks/guard-xcodebuild.sh`, e.g.
   `echo '{"tool_input":{"command":"xcodebuild -scheme MojSlownik test"}}' | .claude/hooks/guard-xcodebuild.sh; echo $?`.
   - `-scheme MojSlownik test` → 2
   - `-scheme MojSlownikUnitTests test` → 0
   - `-scheme MojSlownikUnitTests test -only-testing:MojSlownikUITests` → 2
   - `-scheme MojSlownikE2E test -only-testing:MojSlownikUITests/QuizFlowTests` → 0
   - `-scheme MojSlownik build` → 0
   - `-scheme MojSlownik test|tail -5` → 2
   - `-scheme MojSlownik test;echo done` → 2
   - `-scheme MojSlownik test&&echo ok` → 2
   - `xcodebuild -scheme MojSlownikE2E build && xcodebuild -scheme MojSlownik test` → 2 (chained, mixed schemes)
   - `xcodebuild -scheme MojSlownik build && xcodebuild -scheme MojSlownikUnitTests test` → 2 (accepted conservative block)
   - `xcodebuild test` without a scheme → 2
   - `-scheme MojSlownikE2E test-without-building` → 0
8. Workflow lint: run `actionlint .github/workflows/ci.yml` if it is installed; otherwise report it as not run.
   Run `jq . .github/rulesets/main.json`.
9. Run `grep -rn "Never create, update or run UI/E2E\|Do not create, update or run E2E\|Never demand E2E\|Excludes E2E\|XCUITest/Playwright\|UI automation\|only test scheme agents may run" AGENTS.md CLAUDE.md .claude .agents .codex/agents docs` → no matches.
   Review any remaining hit by hand. A match is acceptable only if it states the new rule, e.g.
   "Playwright/browser". In that case reword it to avoid the forbidden phrase rather than keeping the old ban.
10. After the user authorizes a push and PR, check:
    - The PR shows "Build & unit tests", "E2E (practice)", "E2E (dictionary)" and "ci-passed".
    - All are green and the total wall-clock time is noted.
    - Then the orchestrator applies the ruleset (with authorization) and verifies via `rules/branches/main`.
    - The PR shows "Merging is blocked" while a re-run is in progress.
11. Manual checks (unchanged, physical iPhone): scan a line, check its translation, select a word in text and
    chips, and confirm the scan result stays after dismissing AddWordView. Report them as not run if no device is available.

## Risks

- **Simulator flakiness / runner image changes.** `macos-latest` may change Xcode or iOS runtimes.
  Mitigations: dynamic simulator pick, pre-boot with `bootstatus`, per-test time allowance,
  `fail-fast: false`, xcresult upload.
- **Achievement banners** (4 s top overlay, shown at the root, in AddWordView and in ScanResultView)
  can cover the scan sheet's "Готово" and the folder picker. Mitigation: the looping, hittable-only
  `dismissAchievementBannerIfPresent()` helper before top-area taps. The initial sync of seeded
  fixtures does not announce (`didInitialSync` is false in fresh defaults).
- **Keyboard input.** Cyrillic `typeText` is unreliable. All typed input is ASCII and Cyrillic arrives
  via prefill. The hardware-keyboard setting on CI simulators can affect `typeText`; the field is tapped
  first and `waitForValue` is used.
- **TabView keeps both tabs' views.** Duplicate identifiers (e.g. two `folderPickerButton`s) are
  resolved with `.firstMatch` after `openTab`. If an off-screen match is chosen, scope the query to
  `app.navigationBars`/the visible scroll view instead.
- **Context menu via long-press** (`scanEditWordButton`). It requires the chip to be laid out and
  hittable. Wait for `isEnabled` first and use `press(forDuration: 1.0)`. If the context-menu preview
  makes the button hard to reach, fall back to the chip's accessibility custom action. XCUITest has
  no direct API for that, so the long-press stays primary.
- **UI-test signing on the runner.** See the e2e job note: fall back to `CODE_SIGNING_ALLOWED=NO` only if needed.
- **Strict up-to-date policy** forces rebasing or updating every PR after another merge, then a full CI
  re-run (about 15–25 min). This is acceptable for a solo repo; the alternative is listed in Open decisions.
- **No path filters.** Docs-only PRs also run full CI, because the required check must always report.
- **Ruleset with empty bypass** also blocks the owner's and agents' direct pushes to `main`. This is
  intended. An emergency fix requires temporarily disabling the ruleset via
  `gh api -X PUT …/rulesets/<id>` with `"enforcement":"disabled"`.
- **Swift concurrency warnings in UI tests** (XCUIApplication is MainActor-isolated) would fail the
  warnings-as-errors CI build. Keep every helper and test method `@MainActor`, and do not touch
  `XCUIApplication` in `setUpWithError`.
- **A stale local `main`.** Implementation must branch from fresh `origin/main` or the plan's line
  references and the existing ci.yml will not match.

## Open decisions

Recommended option first. All 9 are still open: the critic's revision changed none of them. The
orchestrator should confirm 1, 4 and 6 with the user. Resolved during revision 1 (no longer open):
the ruleset check source is pinned to GitHub Actions, and the hook policy is that chained commands
are blocked conservatively.

1. CI sharding:
   - **(a) Recommended:** 2 static shards (`practice` via `-only-testing`, `dictionary` as a catch-all
     via `-skip-testing`), each building on its own, running in parallel with the unit job. Public repo,
     so macOS minutes are free. Lowest wall-clock time, simplest.
   - (b) A single E2E job using parallel clones.
   - (c) One `build-for-testing` job plus `test-without-building` shards via an uploaded `.xctestrun`
     artifact. Fewer minutes, but more moving parts and serial latency.
2. In-shard parallel clones on CI:
   - **(a) Recommended:** off (`-parallel-testing-enabled NO`). macOS runners have about 3 vCPU; clones
     risk timeouts.
   - (b) On, with `-parallel-testing-worker-count 2`.
3. Retries:
   - **(a) Recommended:** none; failures are signal.
   - (b) `-retry-tests-on-failure -test-iterations 2` to mask simulator flakes.
4. Admin enforcement:
   - **(a) Recommended:** `bypass_actors: []`, enforced for the owner too, as the user asked to block merges.
   - (b) Repository-admin bypass for emergencies.
5. Achievement banners in E2E:
   - **(a) Recommended:** tests dismiss them with the helper, so the real UX is kept.
   - (b) Suppress banners in test mode (e.g. `AchievementStore(displayDuration: .zero)`).
6. Fixed "now":
   - **(a) Recommended:** fixture dates relative to launch time. Assertions are relative (due vs. not
     due), and `Word.isDue`, `SRSEngine` and `TrainingView`'s `TimelineView` read `.now` directly, so
     no clock injection is needed.
   - (b) A `UITEST_NOW` clock override. This is invasive: it touches the model, SRS and views.
7. Action pinning:
   - **(a) Recommended:** full SHAs of the latest release tags.
   - (b) Keep the current `@v4`/`@v1` major tags.
8. Strict up-to-date status checks:
   - **(a) Recommended:** on, which matches "blocked until pipelines pass".
   - (b) Off, to avoid re-runs after every merge to `main`.
9. The `MojSlownik` app scheme keeps `MojSlownikUITests` in its test action:
   - **(a) Recommended:** keep, so existing targets are preserved and the hook blocks it.
   - (b) Remove it so only `MojSlownikE2E` references the UI tests.

## Decisions

Recorded 2026-11-17 from the user:
- D1 Admin enforcement: block everyone. `bypass_actors: []` (open decision 4a).
- D2 Sharding: 2 parallel static shards, `practice` and `dictionary` catch-all (open decision 1a).
- D3 Branch: a new branch `e2e-fixtures-ci` from fresh `origin/main`.
- D4 Up-to-date policy, which replaces open decision 8: the user does NOT want strict mode. A PR may be behind
  `main` by at most 10 commits; more than 10 → fail. Implementation:
  - Ruleset: `strict_required_status_checks_policy: false`.
  - New CI job `branch-freshness` (name "Branch freshness"), on `ubuntu-latest`, only for `pull_request`.
    It is skipped for push/dispatch, and `ci-passed` must treat a skipped `branch-freshness` as OK on non-PR events.
  - The job uses `actions/checkout` with `fetch-depth: 0` and computes
    `BEHIND=$(git rev-list --count "${{ github.event.pull_request.head.sha }}..origin/${{ github.base_ref }}")`.
    It fails with a clear message if `BEHIND > 10`. The limit is an env var `MAX_BEHIND_COMMITS: 10`.
  - Add it to `ci-passed.needs`. Adjust the aggregate check so `skipped` is only an error for jobs other than
    `branch-freshness`, or only on `pull_request` events.
  - Limitation: the check is evaluated when CI runs. If `main` advances past 10 commits after a green run, the
    PR stays green until CI re-runs. This is acceptable for a solo repo. A `push: main` event does not re-run
    PR checks. A cheap mitigation is out of scope.
- Other open decisions take the recommended option: 2a, 3a, 5a, 6a, 7a and 9a.

## Revision log

Revision 1 addresses all 11 critic findings. Each was checked against `origin/main` d593a09 and confirmed.

1. HIGH, confirmed: ScanResultView has no "Исправить слово" Menu. Editing goes through the chip's
   `.contextMenu` (ScannerView.swift:447) and `accessibilityActions` (:422).
   - Fix: `scanEditWordButton` now goes on the context-menu Button, and the test long-presses
     `scanWordChip-собака-0` after it is enabled.
   - The Menu identifier bullet and the Risks bullet are removed; a long-press risk replaces them.
2. Confirmed (`.disabled(selectedAnswer != nil)`, 900 ms advance). The quiz loop now runs exactly 5
   times: wait for `quizOption-0` to be enabled, tap, then wait for `sessionProgress` "Ответов: i+1 из 5".
3. Confirmed (the chip is disabled until translated). The quick-add test waits for `isEnabled`.
4. Flashcards: wait for `gradeButton-*` to exist after the card tap, and for `sessionProgress`
   "Ответов: n из 2" between cards.
5. The Release leak check uses `nm` on type symbols plus a string longer than 15 bytes.
6. Hook: the boundary-safe test-action regex, every `-scheme` value checked against the allow-list,
   and bypass cases added to Verification.
7. Test counts corrected to 9 total: practice 3, dictionary 6.
8. The banner helper picks a hittable match and loops, capped at 5.
9. `replaceText` taps the trailing edge (0.95, 0.5) and adds 5 extra deletes.
10. The rule grep now also covers `XCUITest/Playwright` and `UI automation`. Codex TOMLs get
    role-specific wording: implementer/planner "add/update E2E", reviewers "missing E2E coverage is a finding".
11. `"integration_id": 15368` added to the required `ci-passed` check, with a pre-apply confirmation command.

Revision 2 (orchestrator, final plan-review findings; review passes exhausted):
- Hook verification (Verification step 7) cannot be typed as a Bash command: the PreToolUse hook
  inspects the whole command string and blocks it (confirmed — it blocked even a heredoc writing this plan).
  Add a committed `.claude/hooks/test-guard-xcodebuild.sh` that builds the cases from fragments
  (e.g. `x=xcode; "${x}build …"`), pipes them to the hook and asserts exit codes. Step 7 then runs only
  `bash .claude/hooks/test-guard-xcodebuild.sh`.
- Flashcards: before tapping the card, wait until exactly one `flashcard` element exists
  (the outgoing card fades for ~0.3 s and shares `isFlipped`).
- Hook regex: match the test action only in xcodebuild's action position, e.g.
  `xcodebuild([^|;&]*[[:space:]])(test|test-without-building)([[:space:]|;&]|$)`, so paths such as
  `-derivedDataPath /tmp/test/dd` or `test.xcresult` do not block. Add both as must-pass (exit 0) cases.
  Also only inspect commands that actually invoke xcodebuild, so plain text/heredocs mentioning it are not blocked
  when no xcodebuild process is run (best effort: require `xcodebuild` at a command position).
- Minor: TrainingView "Повторено сегодня" label is at line 85, not 84.

## Approval

2026-11-17 — approved by user.

## Implementation notes

Implemented on branch `e2e-fixtures-ci`. Deviations and findings:

- Hook: besides the Revision 2 action-position regex, `xcodebuild` must appear at a command position
  (after `;`, `&`, `|`, `(` or line start, optionally behind `VAR=value`, `xcrun` or a path prefix).
  `.claude/hooks/test-guard-xcodebuild.sh` has 18 cases (all pass), incl. `/tmp/test/dd`, `test.xcresult`,
  and text-only mentions. Heredocs that contain a full test command at line start are still blocked,
  so the workflow file was written with the Write tool.
- `QuizFlowTests`: the `sessionProgress` wait is skipped after the 5th answer, because the result screen
  replaces the progress view within 900 ms (the wait raced and failed). The flow then waits for `quizScore`.
- `E2ETestCase` has an extra `waitFor(_:_:timeout:)` helper and keeps the current app in a `var app`.
- `pick-simulator.sh` prints the progress line to stderr and only the destination to stdout.
- `ci.yml`: `pull_request` now has `branches: [main]`; `branch-freshness` (D4) is added to `ci-passed.needs`,
  and `ci-passed` evaluates `needs` with `jq` (skipped is OK only for `branch-freshness` on non-PR events).
  Pinned SHAs: checkout v7.0.1 3d3c42e5, upload-artifact v7.0.2 cf430e03, setup-xcode v1.7.0 ed7a3b1f.
- Ruleset: `strict_required_status_checks_policy: false`, `bypass_actors: []`. Not applied.
- Local simulator: `pick-simulator.sh` selected "iPhone Duo" (iOS 27.2) on this machine, where E2E clones failed to
  launch the runner. E2E ran on iPhone 17 (iOS 26.5, id 714212C4). CI picks its own device.
- `actionlint` is not installed; not run. No `yaml` Python module, so the workflow was not parsed locally.
- Not run: CI itself, ruleset apply, physical-iPhone manual checks.
