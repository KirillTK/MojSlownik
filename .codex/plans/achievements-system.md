# Achievements system (WoW-style, extensible)

Base HEAD: `6a248570ee9d36d7500f0e98f4413aece8270180`, branch `t3/achievements-system`, clean tree.
Mode: full. Planning only; no app, test or project files were modified.

## Goal

Add a local, WoW-style achievements system: a data-driven catalog of achievements
grouped into categories, each with point value, tiered series (e.g. 3/7/30-day
streaks) and meta achievements ("complete these to earn this"), persisted unlock
dates, an unlock banner and an achievements screen. The design must make adding
an achievement a one-line catalog entry and adding a new kind of statistic a
small, localized change. Progress is derived from existing data (Word/SRS/
knowledge tier/folders) wherever possible; only practice history that the app
currently discards is recorded in a new lifetime ledger.

## Constraints (user instructions verbatim)

> "сделай система ачивок как в wow к примеру - должно быть расширяймо, переиспользование - как вообще по дизайну можно это сделать?"

Project constraints (AGENTS.md): iOS 17+, Swift 5.9, SwiftUI/SwiftData, Russian UI
copy, English code; preserve existing stored words; persistence actions live in
stores/services, not views; reuse Theme and Components; filter in memory, not
`#Predicate`; commit unit tests for new logic; no UI/E2E tests; no commit/push
without authorization; `xcodegen generate` after adding files.

## Architecture (the design answer)

Four layers, each replaceable independently. Data flows one way:
`sources -> metrics snapshot -> evaluator -> store (unlocks) -> UI`.

```
Word / WordFolder (SwiftData) ─┐
                               ├─> AchievementMetrics (pure [Metric: Int])
AchievementLedger (UserDefaults)┘          │
                                           v
AchievementCatalog (static definitions) -> AchievementEvaluator (pure)
                                           │ newly unlocked IDs, progress
                                           v
                                  AchievementStore (@Observable, app-scoped)
                                     │ unlocked [id: Date], ledger, banner queue
                                     v
   AchievementTracker (root, sync only)   .achievementBanner() (root + sheets)   AchievementsView
```

1. **Metric** (`AchievementMetric`, `String` raw enum). A named integer statistic,
   the only vocabulary achievements speak. Two kinds of source fill it:
   - *Derived* (`AchievementMetrics.vocabulary(words:folderCount:)`): recomputed from
     current SwiftData records every evaluation; zero new storage, automatically
     retroactive for existing users.
   - *Recorded* (`AchievementLedger`): lifetime counters for events the app does not
     keep today (DailyStudyStore resets at local midnight). Updated through typed
     events (`AchievementEvent`).
2. **Definition** (`AchievementDefinition`): pure data - stable string ID, Russian
   title/detail, SF Symbol, category, points, `isSecret`, and an
   `AchievementCriterion`:
   - `.threshold(metric, target)` - metric value >= target;
   - `.allOf([id])` - meta achievement (WoW "meta"), unlocked when every listed
     achievement is unlocked.
   Tiered series are simply several threshold definitions over the same metric
   with increasing targets (no special type needed); the screen orders them by target.
3. **Evaluator** (`AchievementEvaluator`, pure enum, no I/O): given catalog,
   metrics and already-unlocked IDs, returns newly unlocked IDs (thresholds first,
   then meta criteria iterated to a fixed point so chains unlock in one pass) and
   per-achievement progress (`current`, `target`, clamped).
4. **Store** (`AchievementStore`, `@MainActor @Observable`, app-scoped like
   `DailyStudyStore`): owns persistence (UserDefaults JSON), ledger event recording,
   sync of metrics -> unlocks, total points, and a FIFO queue of unlocks to announce.
   The store also owns banner presentation state (current item, single dismiss
   timer, announce-once), so any number of `.achievementBanner()` hosts (root,
   sheets) show the same banner without duplicate timers or VoiceOver announcements.

Why closed enums instead of a `protocol AchievementCriterion` with existential
evaluators: the catalog is compiled into the app, Swift's exhaustive `switch`
forces every new metric/criterion to be handled in both the evaluator and the
metric sources, and enums are trivially `Equatable`/testable. Extension points:

| To add | Touch |
| --- | --- |
| New achievement on an existing metric | one `AchievementDefinition` line in `AchievementCatalog.all` |
| New derived statistic | one `AchievementMetric` case + its computation in `AchievementMetrics.vocabulary` |
| New recorded statistic | one `AchievementMetric` case + ledger field (optional for decoding) + `AchievementEvent` case + call site |
| New criterion kind (e.g. "any of", "within N days") | one `AchievementCriterion` case + evaluator branch + test |
| New category | one `AchievementCategory` case (title, order) |

Rules: achievement IDs are permanent and never reused; removing a definition
leaves its stored unlock ignored, not deleted. Unlocks are permanent (WoW-like):
deleting words or a falling metric (e.g. "Не помню" resets `repetitions`) never revokes.

## Initial catalog (15 achievements, 240 points)

Russian copy is final unless the user revises it. `Metric` source in brackets
(D = derived, L = ledger).

| ID | Category | Title | Detail | Criterion | Pts | Symbol |
| --- | --- | --- | --- | --- | --- | --- |
| `vocabulary.words.1` | Словарь | Первое слово | Добавьте первое слово | wordCount >= 1 [D] | 5 | `text.badge.plus` |
| `vocabulary.words.50` | Словарь | Полсотни | Соберите 50 слов | wordCount >= 50 [D] | 10 | `books.vertical` |
| `vocabulary.words.200` | Словарь | Библиотекарь | Соберите 200 слов | wordCount >= 200 [D] | 25 | `books.vertical.fill` |
| `vocabulary.folders.3` | Словарь | Организатор | Создайте 3 папки | folderCount >= 3 [D] | 10 | `folder.fill` |
| `vocabulary.categories.all` | Словарь | Эрудит | Слова во всех темах, кроме «Другое» | categoriesCovered >= 7 [D] | 15 | `square.grid.3x3.fill` |
| `practice.answers.100` | Практика | Сотня ответов | Дайте 100 ответов в практике | totalAnswers >= 100 [L] | 10 | `checkmark.circle` |
| `practice.answers.500` | Практика | Упорство | Дайте 500 ответов в практике | totalAnswers >= 500 [L] | 25 | `checkmark.seal.fill` |
| `practice.quiz.perfect` | Практика | Без ошибок | Пройдите викторину без единой ошибки | perfectQuizzes >= 1 [L] | 10 | `trophy.fill` |
| `practice.listening.50` | Практика | Острый слух | 50 верных ответов «На слух» | listeningCorrect >= 50 [L] | 15 | `ear.fill` |
| `streak.days.3` | Постоянство | Три дня подряд | Занимайтесь 3 дня подряд | longestStreakDays >= 3 [L] | 10 | `flame` |
| `streak.days.7` | Постоянство | Неделя практики | Занимайтесь 7 дней подряд | longestStreakDays >= 7 [L] | 25 | `flame.fill` |
| `mastery.learned.10` | Мастерство | Закреплено | 10 слов повторены 3 раза подряд | learnedWords >= 10 [D] | 10 | `brain` |
| `mastery.tier.25` | Мастерство | Знаток | 25 слов на высшем уровне знания | masteredWords >= 25 [D] | 25 | `star.fill` |
| `mastery.interval.30` | Мастерство | Долгая память | Слово с интервалом повторения от 30 дней | maxIntervalDays >= 30 [D] | 20 | `calendar.badge.clock` |
| `meta.polyglot` | Подвиги | Полиглот | Получите «Библиотекарь», «Неделя практики», «Знаток» и «Без ошибок» | allOf(words.200, streak.7, tier.25, quiz.perfect) | 25 | `crown.fill` |

`meta.polyglot` is `isSecret = false`; no MVP achievement is secret, but the
flag and its locked rendering ship so secret ones can be added by data only.

Metric definitions (exact):
- `wordCount` = `words.count`.
- `folderCount` = number of `WordFolder` records.
- `categoriesCovered` = distinct `word.category` values excluding `.other`; target
  is `WordCategory.allCases.count - 1` (write it as that expression, currently 7).
- `learnedWords` = words with `repetitions >= 3` (matches the documented "learned" rule).
- `masteredWords` = words with `KnowledgeProgressService.tier(for:) == KnowledgeProgressService.maximumTier`
  (uses the legacy-tier fallback, so existing records count).
- `maxIntervalDays` = `Int(words.map(\.intervalDays).max() ?? 0)`.
- `totalAnswers`, `correctAnswers` = every accepted answer in flashcards, quiz and
  listening (flashcard correct = grade != `.again`, same rule as DailyStudyStore).
- `listeningCorrect` = correct accepted answers in listening practice.
- `perfectQuizzes` = completed quizzes with `questions.count >= 4` and `score == questions.count`.
- `currentStreakDays` / `longestStreakDays` = consecutive local calendar days with
  at least one accepted answer (see ledger rules). Achievements use `longestStreakDays`.

## Acceptance criteria

- AC-1: Adding the first word shows a banner "Достижение получено" with icon,
  "Первое слово" and "+5" within one second of the dictionary updating, on whichever
  layer is topmost: the root tabs, AddWordView, or ScanResultView (which stays open
  after a nested AddWordView save or a chip tap). It is visible for 4 s across those layers (one timer;
  if the app goes inactive the item stays queued and the 4 s restart on reactivation), dismisses on tap or upward
  swipe, and VoiceOver announces it exactly once.
- AC-1a: The banner sits below the navigation bar (top safe area + 56 pt), so the
  back button, «Готово» and other navigation-bar controls in pushed practice
  screens and sheets stay tappable while it is shown.
- AC-2: A third tab «Достижения» (trophy) opens AchievementsView, and Training shows a «Достижения» row with "N из 15 · P очков"; it opens
  AchievementsView listing every catalog entry grouped by category in catalog order.
- AC-3: Locked threshold achievements show a progress bar and "current из target"
  (current clamped to target); locked meta achievements show "k из n" required
  achievements; unlocked ones show the accent icon, points and the unlock date
  in Russian ("16 ноября 2026 г."). A secret locked achievement shows
  "Секретное достижение" without title/detail/progress. The header shows the
  current streak ("Серия: N дн."), which is 0 when the last study day is older than yesterday.
- AC-4: Unlocks persist across relaunch and are never revoked: deleting words so
  that wordCount drops below a target keeps the achievement and its original date.
- AC-5: On the first launch after the update, achievements already satisfied by
  existing words/folders unlock silently (no banner flood) with the launch date;
  ledger achievements start from zero (no invented history). Later unlocks show banners one at a time, in unlock order.
- AC-6: Every accepted flashcard rating, quiz answer and listening answer
  increments lifetime answers; rejected (save-failed) answers do not. Practising on
  consecutive local days increases the streak; skipping a day resets the current
  streak but not the longest.
- AC-7: Finishing a quiz of at least 4 questions with all answers correct unlocks
  «Без ошибок»; leaving mid-quiz, one wrong answer, or a quiz that generated fewer
  than 4 questions does not.
- AC-8: When the last requirement of `meta.polyglot` unlocks, the meta achievement
  unlocks in the same evaluation and both banners are queued.
- AC-9: Existing Word/WordFolder records, SRS fields, knowledge tiers and
  `dailyStudyActivity.v1` are unchanged; no SwiftData schema change.
- AC-10: Unit tests for catalog validity, evaluator, metric derivation, ledger and
  store pass in `MojSlownikUnitTests`; app builds with no new warnings.

## Changes by file

### Services (pure logic)

**New `MojSlownik/Services/Achievements.swift`** (single file; models + catalog + evaluator):

- `enum AchievementMetric: String, CaseIterable, Codable` with cases listed above
  (`wordCount, folderCount, categoriesCovered, learnedWords, masteredWords,
  maxIntervalDays, totalAnswers, correctAnswers, listeningCorrect, perfectQuizzes,
  currentStreakDays, longestStreakDays`).
- `enum AchievementCategory: String, CaseIterable` - `vocabulary, practice, streak,
  mastery, feats`; `title` ("Словарь", "Практика", "Постоянство", "Мастерство",
  "Подвиги"); declaration order is display order.
- `enum AchievementCriterion: Equatable` - `.threshold(AchievementMetric, Int)`, `.allOf([String])`.
- `struct AchievementDefinition: Identifiable, Equatable` - `id: String, category,
  title, detail, symbol, points: Int, isSecret: Bool = false, criterion`.
- `struct AchievementMetrics: Equatable` - `private(set) var values: [AchievementMetric: Int]`;
  `subscript(metric) -> Int` (default 0); `merging(_:)`;
  `static func vocabulary(words: [Word], folderCount: Int) -> AchievementMetrics`
  (single pass over words, definitions above).
- `struct AchievementProgress: Equatable` - `current: Int, target: Int, isUnlocked: Bool,
  unlockedAt: Date?`; `fraction: Double` (0 when target 0).
- `enum AchievementCatalog` - `static let all: [AchievementDefinition]` (table above);
  `static func definition(id:) -> AchievementDefinition?`.
- `enum AchievementEvaluator`:
  - `static func newlyUnlocked(catalog:, metrics:, unlocked: Set<String>) -> [String]` -
    first all thresholds met and not yet unlocked (catalog order), then repeat over
    `.allOf` definitions until no change; an `.allOf` with an unknown or self ID never unlocks.
  - `static func progress(for:, metrics:, unlocked: [String: Date]) -> AchievementProgress` -
    threshold: `min(metrics[m], target)`/`target`; allOf: unlocked count / required count;
    unlocked achievements report `current = target`.

**New `MojSlownik/Services/AchievementLedger.swift`**:

- `enum PracticeMode: String, Codable { case flashcards, quiz, listening }`.
- `enum AchievementEvent: Equatable { case answer(mode: PracticeMode, isCorrect: Bool); case quizFinished(correct: Int, total: Int) }`.
- `static func AchievementEvent.quizAnswer(index: Int, count: Int, scoreAfter: Int, isCorrect: Bool) -> [AchievementEvent]` -
  pure helper used by QuizView: always returns `.answer(mode: .quiz, isCorrect:)`;
  when `index == count - 1` also appends `.quizFinished(correct: scoreAfter, total: count)`.
  `scoreAfter` is the score including this answer. Returns no finish event for
  `index < count - 1` or invalid input (`count <= 0`, `index >= count`).
- `struct AchievementLedger: Codable, Equatable` - all fields `Int`/`Date?` with
  defaults so future fields decode as optional: `totalAnswers, correctAnswers,
  listeningCorrect, perfectQuizzes, currentStreakDays, longestStreakDays,
  lastStudyDay: Date?`. Implement `init(from:)` with `decodeIfPresent` defaults
  (or make new fields Optional) so adding fields later never drops the payload.
- `mutating func apply(_ event:, now:, calendar:)`:
  - `.answer`: increment totals (`listeningCorrect` only for `.listening` + correct);
    streak: `today = calendar.startOfDay(for: now)`; if `lastStudyDay` is the same
    day, no change; else if `calendar.dateComponents([.day], from: startOfDay(last), to: today).day == 1`,
    `currentStreakDays += 1`; else if `today < startOfDay(lastStudyDay)` (clock moved
    backwards) the streak update is a no-op (totals still increment; current, longest and
    `lastStudyDay` unchanged); else (nil or gap) `currentStreakDays = 1`;
    `longestStreakDays = max(...)`; `lastStudyDay = today`.
  - `.quizFinished`: increment `perfectQuizzes` when `isPerfectQuiz(correct:total:)`.
- `static func isPerfectQuiz(correct: Int, total: Int) -> Bool` - `total >= 4 && correct == total`.
- `var metrics: AchievementMetrics` - maps fields to the L metrics.
- `func currentStreak(now:calendar:) -> Int` - returns `currentStreakDays` only if
  `lastStudyDay` is today or yesterday, else 0. Display only (AchievementsView header via
  `AchievementStore.currentStreak(now:)`); criteria use `longestStreakDays`.

### Stores

**New `MojSlownik/Stores/AchievementStore.swift`** - `@MainActor @Observable final class`:

- Init `(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent,
  catalog: [AchievementDefinition] = AchievementCatalog.all, displayDuration: Duration = .seconds(4))`.
- Private Codable `Stored { unlocked: [String: Date]; ledger: AchievementLedger; didInitialSync: Bool }`,
  key `"achievements.v1"`. Load in init; on missing or undecodable data start empty
  (`didInitialSync = false`).
- Public read state: `private(set) var unlocked: [String: Date]`, `private(set) var ledger`,
  `private(set) var pendingAnnouncements: [AchievementDefinition]` (FIFO), `catalog`.
- `var totalPoints: Int` (sum over unlocked IDs present in catalog), `var unlockedCount: Int`
  (same filter), `var possiblePoints: Int`.
- `func record(_ event: AchievementEvent, now: Date = .now)` - applies to ledger, persists.
  Non-throwing: encoding failure is ignored after `assertionFailure` (the answer
  itself is already saved; achievements must never block practice).
- `func sync(vocabulary: AchievementMetrics, now: Date = .now)` - merges with
  `ledger.metrics`, calls the evaluator, stores `now` for each new ID, persists;
  if `didInitialSync` was false, sets it true and does **not** enqueue announcements;
  otherwise appends definitions to `pendingAnnouncements`. No-op write when nothing changed
  and `didInitialSync` is already true.
- Banner presentation (single source of truth for every banner host):
  - `var currentAnnouncement: AchievementDefinition? { pendingAnnouncements.first }`.
  - `private var dismissTask: Task<Void, Never>?`, `private var announcedIDs: Set<String>`
    (in-memory only), `private var isSceneActive = true`, `let displayDuration: Duration` (from init).
  - `func setSceneActive(_ active: Bool)` - called by AchievementTracker on `scenePhase`;
    inactive cancels the timer (the item stays queued), active restarts it via `presentNextIfNeeded()`.
  - `private func presentNextIfNeeded()` - called after enqueue, dismiss and activation:
    if there is a current item, the scene is active and no timer is running: post
    `AccessibilityNotification.Announcement("Достижение получено: \(title)")` only if
    its ID is not in `announcedIDs` (then insert), and start the one `dismissTask`
    that sleeps `displayDuration` and calls `dismissAnnouncement()`.
  - `func dismissAnnouncement()` - cancels `dismissTask`, removes the first item,
    calls `presentNextIfNeeded()`.
- `func currentStreak(now: Date = .now) -> Int` - forwards to `ledger.currentStreak(now:calendar:)`.
- `func progress(for definition:, vocabulary:) -> AchievementProgress` (merges ledger metrics).

**`MojSlownik/MojSlownikApp.swift`**: `AppResources` gets `let achievements: AchievementStore`
built with the same `defaults`/`calendar`; app holds `@State private var achievements`
and injects `.environment(achievements)`. Preview resources use the existing preview defaults suite.
DailyStudyStore is not changed.

### Views

**New `MojSlownik/Views/Components/AchievementTracker.swift`** (`struct AchievementTracker: View`,
mounted once at the root; sync only, renders nothing visible):
- `@Query private var words: [Word]`, `@Query private var folders: [WordFolder]`,
  `@Environment(AchievementStore.self)`, `@Environment(\.scenePhase)`.
- `let vocabulary = AchievementMetrics.vocabulary(words: words, folderCount: folders.count)`;
  `.onChange(of: SyncKey(vocabulary, store.ledger), initial: true) { store.sync(vocabulary:) }`
  (a small private `Equatable` struct; ledger changes from `record` also trigger sync).
  `@Query` at the root observes saves from sheets and isolated contexts, so unlocks
  are evaluated even while a sheet is open.
- `.onChange(of: scenePhase, initial: true) { store.setSceneActive(scenePhase == .active) }`.
- Body: `Color.clear.frame(width: 0, height: 0).allowsHitTesting(false).accessibilityHidden(true)`.

**New `MojSlownik/Views/Components/AchievementBannerModifier.swift`** -
`extension View { func achievementBanner() -> some View }` backed by a private
`ViewModifier` that reads `@Environment(AchievementStore.self)` and reduce motion:
- `.overlay(alignment: .top)` showing `AchievementBanner(store.currentAnnouncement)` when non-nil,
  padded `.padding(.top, 56)` inside the top safe area (below an inline navigation bar,
  keeping back/«Готово» buttons uncovered) and `.padding(.horizontal, 16)`.
- Dismiss: tap, or `DragGesture` ending with `translation.height < -24` -> `store.dismissAnnouncement()`.
- Transition `.move(edge: .top).combined(with: .opacity)`, or `.opacity` with Reduce Motion;
  animate on `store.currentAnnouncement?.id`.
- No timers or announcements in the modifier (they live in the store), so applying
  it at several presentation levels is safe: a lower host is simply covered by the sheet.
- Applied at: RootTabView (root), `ScanResultView` root (on its NavigationStack, alongside
  `.toolbar`/`.sheet`), and `AddWordView` root. Sheets inherit the environment store.

**New `MojSlownik/Views/Components/AchievementBanner.swift`** - card: 44 pt accent
icon tile (`appSecondarySurface`), "Достижение получено" caption (`subtleText`),
title (headline, `appInk`), "+N" points capsule (`appAccent` on `appSecondarySurface`);
`cardStyle()`, shadow, horizontal padding 16; whole banner is one accessibility element
with hint "Дважды коснитесь, чтобы скрыть" (VoiceOver swipe does not reach DragGesture) and a `.accessibilityAction(named: "Скрыть")`.
Dynamic Type: title wraps, no fixed heights.

**New `MojSlownik/Views/Components/AchievementBadge.swift`** - reusable icon tile
(`symbol`, `isUnlocked`, `size`): unlocked = `appAccent` symbol on `appSecondarySurface`;
locked = `subtleText` symbol at 0.5 opacity plus a small `lock.fill`. Used by banner and rows.

**New `MojSlownik/Views/AchievementsView.swift`**:
- `@Query` words and folders, `@Environment(AchievementStore.self)`; compute
  vocabulary metrics once per body.
- `ScrollView` on `appBackground`, title «Достижения» (inline). Header panel
  (same `appSecondarySurface` rounded-18 style as Training's Today panel):
  trophy icon, "P очков" (title2 bold, monospaced digits), "N из M получено", ProgressView,
  and a `Label("Серия: \(store.currentStreak()) дн.", systemImage: "flame")` plus
  "Рекорд: \(store.ledger.longestStreakDays) дн." (subheadline `subtleText`).
- One section per `AchievementCategory` that has definitions: section header
  (category title + "k/n"), rows in catalog order inside a `cardStyle()` container
  with `appBorder` dividers. Row: `AchievementBadge`, title (headline), detail
  (subheadline `subtleText`), trailing "N" points; below - unlocked date
  (`Text(date, format: .dateTime.day().month(.wide).year().locale(Locale(identifier: "ru_RU")))`
  prefixed "Получено ") or ProgressView + "current из target". Secret locked rows per AC-3.
  Rows are `accessibilityElement(children: .combine)`; minimum 44 pt height.

**`MojSlownik/Views/TrainingView.swift`**: add `@Environment(AchievementStore.self)`;
after `modes`, a `NavigationLink { AchievementsView() }` row reusing `modeRow`
(title "Достижения", subtitle "\(store.unlockedCount) из \(store.catalog.count) · \(store.totalPoints) очков",
icon `trophy`), wrapped in the same plain button style. Not disabled when empty.

**`MojSlownik/Views/RootTabView.swift`**: add a third tab
`NavigationStack { AchievementsView() }.tabItem { Label("Достижения", systemImage: "trophy.fill") }`
(Decision 1: tab + Training row; AchievementsView itself contains no NavigationStack so it works
both pushed from Training and inside the tab); `.background { AchievementTracker() }` and
`.achievementBanner()` on the TabView (after `.tint`).

**`MojSlownik/Views/ScannerView.swift`** (`ScanResultView`) and **`MojSlownik/Views/AddWordView.swift`**:
add `.achievementBanner()` to the root view (after existing modifiers). No other changes.

**Event call sites** (each only after the existing `dailyStudy` call succeeds, i.e.
after its `do/catch` returns without error; add `@Environment(AchievementStore.self) private var achievements`):
- `FlashcardsView.apply`: `achievements.record(.answer(mode: .flashcards, isCorrect: grade != .again))`.
- `QuizView.select`: after `score` is updated,
  `AchievementEvent.quizAnswer(index: currentIndex, count: questions.count, scoreAfter: score, isCorrect: isCorrect).forEach { achievements.record($0) }`.
  The finish event fires exactly once per quiz because `selectedAnswer` guards duplicate taps.
- `ListeningPracticeView.submit`: `achievements.record(.answer(mode: .listening, isCorrect: isCorrect))`.
- No change needed for word/folder adds: derived metrics reach the tracker via `@Query`.

**Previews**: add `.environment(resources.achievements)` (or `AppResources.preview.achievements`)
to RootTabView, TrainingView, FlashcardsView, QuizView, ListeningPracticeView,
AddWordView and WordListView (presents ScanResultView) previews and the new AchievementsView preview.

### Docs

**`docs/architecture.md`**: add an "Achievements" section (layers, metric sources,
ledger key, unlock permanence, silent initial sync, banner hosts on root/sheets with
store-owned timer, how to add an achievement/metric); list `achievementBanner()` and
`AchievementBadge` under Reusable Views;
add rows to the Application Map; remove the two "No achievements are implemented/shown"
statements. **AGENTS.md**: one line under architecture map pointing to
`Services/Achievements.swift` + `Stores/AchievementStore.swift` (keep concise).

Run `xcodegen generate` after adding files.

## Reuse

- `KnowledgeProgressService.tier(for:)` / `maximumTier` for mastery; `Word.category`,
  `WordCategory.allCases`, `Word.repetitions`, `Word.intervalDays` for derived metrics.
- App-scoped `@Observable` + `AppResources(defaults:calendar:)` injection pattern from `DailyStudyStore`;
  same UserDefaults/Codable persistence style and test `withDefaults` helper pattern.
- Theme: `appAccent`, `appOnAccent`, `appSecondarySurface`, `appInk`, `subtleText`,
  `appBorder`, `cardStyle()`. TrainingView's `modeRow` for the entry row; Today-panel
  styling for the header. No new colors.

## Data compatibility

- No SwiftData model or container change; `Word`/`WordFolder` stores untouched.
- New UserDefaults key `achievements.v1`; absent on upgrade -> empty state with
  `didInitialSync = false` -> first sync unlocks derived achievements silently with the
  first-sync date (exact historical dates are unknowable).
- Ledger starts at zero; today's `dailyStudyActivity.v1` answers are not imported
  (the user may choose otherwise - Open decision 2).
- Ledger fields decode with defaults so future fields are additive; unknown unlocked
  IDs are kept in storage but ignored for counts/points.
- Undecodable payload falls back to empty state (would re-unlock derived achievements
  silently on next sync, losing original dates). Accepted for MVP.

## Verification

Unit tests (new files, `@MainActor`, isolated `UserDefaults(suiteName:)` per test,
fixed `Europe/Warsaw` Gregorian calendar and fixed `now` as in DailyStudyStoreTests,
in-memory `ModelContainer` for Word fixtures):

`MojSlownikTests/AchievementEvaluatorTests.swift`
- Catalog: IDs unique; every `.allOf` ID exists and is not self; targets/points > 0;
  every category used has a title; catalog count 15 and total points 240.
- Threshold unlocks at exactly target, not at target - 1; already-unlocked not returned again.
- Meta unlocks in the same call as its last requirement; meta referencing an unknown ID never unlocks;
  chained meta (meta of meta, test-only catalog) resolves in one call.
- Progress: clamps current to target; unlocked reports full; allOf counts unlocked requirements.
- `AchievementMetrics.vocabulary`: word count, folder count, categories excluding `.other`,
  learned (`repetitions` 2 vs 3), mastered via explicit `knowledgeTier = 3` and via
  legacy `lastReviewGradeRawValue = "easy"` fallback, max interval, empty input = zeros.

`MojSlownikTests/AchievementLedgerTests.swift`
- Answer counting per mode; `listeningCorrect` only for listening correct.
- Streak: same day twice = 1; consecutive days 1,2,3; gap resets current to 1, longest kept;
  across DST change in Warsaw (late March) still counts consecutive; clock moved backwards
  (answer dated before `lastStudyDay`) increments totals but leaves current, longest and
  `lastStudyDay` unchanged.
- `isPerfectQuiz`: (4,4) true, (3,3) false, (9,10) false.
- `AchievementEvent.quizAnswer`: middle answer (index 2 of 10) -> only `.answer`;
  last correct with full score (index 9, count 10, scoreAfter 10) -> `.answer` + `.quizFinished(10,10)`
  and the ledger increments `perfectQuizzes`; last wrong (index 9, scoreAfter 9) -> finish
  event but `perfectQuizzes` unchanged; 3-question quiz all correct (index 2, count 3,
  scoreAfter 3) -> finish event, `perfectQuizzes` unchanged; `count 0` -> only `.answer`.
- `currentStreak(now:calendar:)`: last study day today -> stored value; yesterday -> stored value;
  two days ago -> 0; nil -> 0.
- Legacy decode: JSON missing some fields decodes with zero defaults.

`MojSlownikTests/AchievementStoreTests.swift`
- First sync with satisfying metrics unlocks silently (no announcements), second
  sync with new satisfied threshold enqueues it; dismiss pops FIFO.
- Persist/reload: unlocked dates and ledger survive a new store on the same defaults.
- Permanence: sync with lower metrics keeps unlocks and dates.
- `record` changes ledger and subsequent sync unlocks ledger achievements (100 answers).
- Points/count ignore unknown stored IDs.
- Banner state (store built with `displayDuration: .milliseconds(50)`): two unlocks queue
  FIFO and `currentAnnouncement` is the first; `dismissAnnouncement()` advances; after
  waiting > duration the item auto-advances (await with `Task.sleep`, no UI);
  `setSceneActive(false)` keeps the item queued past the duration, `true` resumes;
  the same item is not re-announced after deactivate/reactivate (expose `announcedIDs`
  count as `internal` for `@testable` assertions).

Build and test (pick an installed simulator via `xcrun simctl list devices available`):
```sh
xcodegen generate
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=<device>' build | grep -E 'error:|warning:|SUCCEEDED|FAILED'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,name=<device>' test | grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'
git diff --check
```
No UI/E2E tests.

Manual checks (report honestly what was not run): fresh install -> add first Russian
and first Polish word (banner once, VoiceOver announcement); existing-data upgrade
(install over previous build with words) -> no banner flood, achievements screen shows
retroactive unlocks; edit/save translation; flashcards ratings still update dueDate
and answer counter rises; perfect quiz unlocks «Без ошибок», a quiz with an error does not;
listening answers count; delete words below 1 and confirm «Первое слово» stays; dark
mode, largest Dynamic Type and Reduce Motion on banner/screen. Banner placement:
trigger an unlock inside Flashcards/Quiz (e.g. 100th answer, perfect quiz) and tap the
back button while the banner is visible - it must navigate back; swipe the banner up to
dismiss. Sheets: with a fresh store, open AddWordView from the dictionary and save -> banner
shows on the root after the sheet closes; on a physical iPhone scan text, tap a chip to save
(ScanResultView still open) -> banner appears above the scan result; open the correction
AddWordView from the scan result and save -> banner remains visible on ScanResultView,
announced once by VoiceOver, total about 4 s.

## Risks

- Banner hosts must be added to any future sheet that can save words; a sheet without
  `.achievementBanner()` hides the banner for its 4 s (the unlock remains on the screen).
  Currently covered: root, AddWordView, ScanResultView. ScannerScreen (fullScreenCover)
  does not save words. Folder creation in FolderPicker's sheet can unlock «Организатор»
  beneath that sheet - accepted (low value); add the modifier there later if wanted.
- The 56 pt top offset assumes an inline navigation bar; on the root large-title screens
  the banner briefly overlaps the large title (non-interactive), never the toolbar buttons.
- `@Query` of all words in the root tracker recomputes metrics on every Word change
  (O(n) per change). Fine for a personal dictionary (thousands of words); revisit if slow.
- Streak semantics around midnight/timezone travel use the device calendar at answer time;
  travel can create or break a streak by a day.
- First-sync dates are the upgrade date, not historical dates.
- Undecodable `achievements.v1` loses unlock dates (see Data compatibility).
- Perfect-quiz detection relies on QuizView passing `currentIndex`/`questions.count`/
  updated `score` to `AchievementEvent.quizAnswer`; the helper is unit-tested, the call
  site is covered by the manual perfect-quiz check.

## Decisions

Recorded 2026-11-16 (user answers):
1. Screen placement: **both** - third tab «Достижения» and a row in «Практика».
2. Retroactive unlock: **silent** for derived achievements; ledger starts at zero.
3. Points: **display only**.
4. Notifications: **in-app banner only**.
5. Catalog: the 15 achievements above, no secret ones (subject to approval).
6. Persistence: UserDefaults JSON `achievements.v1` (default).

## Open decisions (original options)

1. **Screen placement**: default = row in «Практика» opening AchievementsView.
   Alternatives: third tab «Достижения» (trophy) in RootTabView; or both.
2. **Retroactive unlock**: default = derived achievements unlock silently on first launch,
   ledger ones start from zero. Alternatives: announce them all once as a summary
   banner ("Получено 4 достижения"); seed ledger with today's DailyStudyStore answer count.
3. **Points/rewards**: default = cosmetic points total only (WoW-like). Alternatives:
   titles/levels from points, or unlocking themes - each needs extra scope.
4. **Notifications**: default = in-app banner only. Local push notifications (e.g. streak
   at risk) are out of scope and would need permission prompts.
5. **Catalog content**: confirm the 15 achievements, Russian titles and point values,
   and whether some should be secret (e.g. «Долгая память»).
6. **Persistence**: default = UserDefaults JSON (matches DailyStudyStore, no schema
   change). Alternative: SwiftData `AchievementUnlock` model (adds an entity to the
   container; lightweight migration, slightly higher upgrade risk, future-proof for sync).

## Revision log

Critic findings addressed (revision 1):
1. (Medium) Banner under sheets - accepted. Presentation state, the single dismiss timer and
   announce-once now live in `AchievementStore`; a reusable `.achievementBanner()` modifier is
   applied at the root, `ScanResultView` and `AddWordView`; `AchievementTracker` only syncs.
   AC-1, tracker/modifier spec, store tests, Risks and manual checks updated; former Open
   decision 5 removed.
2. (Low) Quiz finish detection - accepted. Pure `AchievementEvent.quizAnswer(index:count:scoreAfter:isCorrect:)`
   with tests for middle, last-correct, last-wrong, 3-question and empty quizzes; AC-7 updated.
3. (Low) Banner over back button - accepted. Banner offset 56 pt below the top safe area,
   tap/swipe-up dismissal and an accessibility action; AC-1a and a manual back-button check added.
4. (Low) Unused `currentStreak` - accepted (shown). AchievementsView header shows current and
   record streak; tests cover today, yesterday, two days ago and nil.

- Plan review (pass 2, approve): backwards-clock answer is a streak no-op; AC-1 timer restarts on reactivation; `displayDuration` in store init.

## Approval

2026-11-16 - approved by user (decisions above).

## Implementation result

- Build (MojSlownik) succeeded; MojSlownikUnitTests: 139 tests, 0 failures (one earlier run failed with no failing test - simulator flake; two reruns passed).
- Reviews: quality and data - no findings. UI - VoiceOver hint fixed; 56 pt banner offset kept intentionally (AC-1a).
- Manual checks: user confirmed in Xcode ("все ок").
