# Spaced review cap, learned progress and hard words

Mode: FULL (`/ios-feature-flow`). Branch `t3/spaced-review-progress`, base `c065c21` (latest main; tree identical
to the earlier planning base `fe2f143`). The uncommitted `MojSlownik/InfoPlist.xcstrings` change predates
this task: do not touch, stage or attribute it.
Mockups: `.codex/plans/spaced-review-progress/mockups.html` (direction A); final design:
`.codex/plans/spaced-review-progress/final-design.html` (honey «учу», 30-day cap copy). The final design wins on conflicts.

## Goal

Make well-learned words come back regularly (at most every 30 days), let quiz/listening answers on due
words count toward the schedule without inflating it, show per-scope progress (learned / learning / new),
a short review forecast and a "hard words" (leech) entry point, and show next-interval captions on grade
buttons.

Root cause today: `SRSEngine` is simplified SM-2 capped at `maxIntervalDays = 36_500`, so a few "Easy"
answers push a word out for years; quiz/listening never touch SRS dates; there is no "learned" concept.

## Constraints (user instructions verbatim)

> я хочу улучшить процесс тренировок - и также чтобы очень хорошо изученные слова попадали в подбору раз
> в пару недель и месяц и чтобы в каждоый папке или общий пул - показывало сколько человек уже выучил слов
> в карточке и сколько нет - также что еще порекомунжуешь улучшить в моем worflow? какие практики
> существуют на рынке и тд?

Plus AGENTS.md invariants: SwiftData additive properties only, no word loss; logic in Services/Stores;
soft-delete reads filter `isActive`; due filtering in memory; every string en + ru (all plural forms);
Supabase changes as a new migration with RLS unchanged and a rolled-back test.

## Decisions

User decisions (binding):

1. **Interval cap: 30 days, no 60-day step.** Intervals grow by SM-2 and are clamped to 30 days for every
   grade, so learned words (≥ 21 days) come back about once a month. `Backend/RemoteRecords.swift` keeps
   accepting old values (server rows may still hold long intervals).
2. **Learned = `intervalDays >= 21`** (Anki "mature"). Three buckets: **new** (`repetitions == 0 &&
   lastReviewGradeRawValue == nil`, never graded; an "Again"-reset word has `repetitions == 0` but a grade,
   so it counts as learning), **learning** (everything else below 21), **learned**. Pure, unit-tested service.
3. In scope:
   a. Quiz/listening answers affect SRS (rule below).
   b. Leech detection: a word forgotten 6+ times is a "hard word" (Трудные слова). New persisted
      `Word.lapseCount: Int = 0`, synced (new migration column).
   c. Forecast text line «Завтра N · за неделю M» for the selected scope (no chart).
   d. Grade buttons show the next interval («10 мин / 2 дн. / 7 дн. / 14 дн.») from a pure preview in
      `SRSEngine` (no mutation).
4. FSRS migration is out of scope (follow-up).
5. UI direction A: Today hero unchanged; new «Прогресс» card below the modes and above achievements
   (segmented bar + three counts + labels, then forecast row and «Трудные слова N ›» row); FolderPicker
   sheet rows show «выучено 18 из 40» + thin bar, including «Все папки»; flashcard shows a «Трудное слово»
   pill for leeches. Scoped to the active workspace and selected folder, active words only: every count,
   forecast, hard-word list and folder breakdown starts from
   `WorkspaceScope.words(storedAllWords, workspaceID: workspaces.activeID)` (as TrainingView's `allWords`
   already does), then `FolderStore.words(_:in:memberships:)`; FlashcardsView's hard-words session uses its
   existing workspace-scoped `allWords`. `ScheduleNormalizer` is the only workspace-agnostic pass (data repair).
6. **New token `appLearning`**: light #B8860B (honey; 3.25:1 on white card, 3.06:1 on paper, so graphics
   only, never text), dark #FFD43B. Used for the learning bar segment, the learning legend dot, the folder
   mini-bar learning segment and knowledge ring tier 2 (`KnowledgeTierBadge` tier 2 switches from
   `appAccentText` to `appLearning`).

Planner decisions (implement as written; the material ones are repeated under Open decisions):

- **Monotonic grades (M2).** For a success grade, from state (I = interval, E = ease, R = repetitions):
  - `hard = max(1, round(I × 1.2))`, ease `max(1.3, E − 0.15)`;
  - `goodStep = 1` if R + 1 == 1, `3` if R + 1 == 2, else `round(I × E)`;
    `good = max(goodStep, round(I × E), I ≥ 1 ? hard + 1 : hard)`;
  - `easy = max(2, round((I == 0 ? 2 : I) × (E + 0.15) × 1.3), good + 1)`, ease `E + 0.15`;
  - then every value is `min(·, 30)`; `dueDate = now + interval × 86_400`. Again is unchanged (10 minutes,
    interval 0, repetitions 0, ease −0.2).
  Result: Hard ≤ Good < Easy below the cap, and Hard < Good for any word with I ≥ 1; values can be equal
  at the 30-day cap. A new word keeps Hard = Good = 1 day: forcing Good to 2 days would change the familiar
  first step for no benefit. Good is never below the current interval of a reviewed word (`round(I × E)`
  with E ≥ 1.3 is ≥ I). Hard is ≥ I too: a hesitant success should not shorten the gap; failures go
  through Again. Today's leech example (R 1, I 1, E 1.3) yields 10 min / 1 / 3 / 4 days (before this
  change Easy gave 2 days, below Good's 3).
- **Lapse = a failure (`.again`) on a word with `repetitions > 0` before the failure**, meaning it had been
  answered correctly since its last failure. Repeated "Again" in one session, or on a never-learned word,
  does not count. This matches Anki's lapse semantics and the meaning of "forgotten".
- **Hard word = `lapseCount >= 6 && intervalDays < 21`.** The flag clears once the word becomes learned;
  the counter is kept.
- **Quiz/listening → SRS (M3)**, `SRSEngine.practiceGrade(for:isDue:)`, `isDue = dueDate <= now`:
  - not due → `nil` for every answer: SRS and `lapseCount` unchanged. A correct answer would inflate the
    interval. A wrong answer already makes the word pending in `DailyStudyStore`, so it gets a flashcard
    review today where the self-grade decides;
  - due + correct (choice correct / typed exact) → `.good`;
  - due + wrong (choice wrong, typed similarity < 0.7) → `.again` (+ lapse rule). `.again`, not `.hard`:
    recognising among four options is easier than recall, so failing it is strong evidence of forgetting,
    and `.hard` would *grow* the interval (×1.2);
  - due + typed soft miss (0.7 ≤ similarity < 1) → `nil` (typo tolerance; the tier logic handles it).
- **Long schedules: local-only normalization plus a clamp on pull (H1).** `ScheduleNormalizer` runs at
  launch, rewrites only SRS fields and **never touches `updatedAt`/`serverUpdatedAt`** (like
  `WordIdentityBackfill`), so it never makes rows dirty. Why: a dirty normalized row would win the merge
  over a newer remote edit (`RemoteMergePolicy.decide` branch 5 → `.keepLocal`, then the push overwrites
  the server). The same clamp runs inside `SwiftDataSyncStore.apply(_:to:pair:)` for pulled rows, before
  `markSynced`, so pulled rows also stay clean. The local copy can differ from the server's long values
  until the word's next real review, which pushes the capped values. Clamp-on-pull is simpler than running
  the normalizer after each pull: same function, no extra fetch or save.
- **Spread only what the clamp moved into the past (M1).** An already-overdue word keeps its `dueDate`
  (only the interval is clamped). A word whose original `dueDate > now` but whose clamped due date falls
  in the past gets `now + offset days`, `offset = Int(uuid.uuid.0) % 7` (stable per word).
- **Forecast (L3).** Only words not due yet (`dueDate > now`). `tomorrow` = due before the end of tomorrow
  (`dueDate < startOfDay(now) + 2 days`), so words due later today count here: they are part of what
  comes up "by tomorrow". `week` = due before `startOfDay(now) + 8 days`, which includes `tomorrow`.
  Already-due words belong to the Today hero.
- `DailyStudyStore.recordQuizAnswer` (no app callers) is removed and its tests move to
  `recordPracticeAnswer` (L2).
- Hard-words row hidden when its count is 0. Forecast row shown whenever the scope has words. The whole
  Progress card is hidden when the scope is empty.
- Folder progress only in the Practice FolderPicker (an optional progress provider); the Dictionary, Add
  and Scanner pickers are unchanged.
- Achievements' `learnedWords` metric (`repetitions >= 3`) is unchanged.

### User answers to open decisions (2026-11-22)

- Open decision 1: wrong quiz/listening answer on a not-due word leaves SRS and `lapseCount` unchanged; the word becomes pending today and the flashcard grade decides.
- Open decision 5: sync `lapse_count` through the new Supabase migration. Apply it to Supabase before installing the build; applying it needs separate user authorization.
- Open decision 10: free practice and the hard-words session keep updating the schedule for not-due words (current behaviour).
- The other open decisions keep the plan defaults.

## Acceptance criteria

- AC-1 No grade schedules beyond 30 days; Again stays 10 minutes; grade previews never exceed 30 days.
- AC-2 For every state below the cap Hard ≤ Good < Easy, and Hard < Good when the interval is ≥ 1 day;
  at the cap values may be equal.
- AC-3 After launch, no active word has `intervalDays > 30`, and none has `dueDate > now + 31 d`. Words
  that were overdue keep their due date. Words the clamp moved into the past become due within 7 days. No
  word is deleted, and normalized words are **not** made dirty (`updatedAt`/`serverUpdatedAt` unchanged).
  Pulled rows are clamped the same way and stay clean. A newer remote edit to a normalized word survives
  sync.
- AC-4 Each flashcard grade button shows its next interval («10 мин», «3 дн.»), and VoiceOver reads it as
  the value («Следующий показ через 3 дня»). The preview equals what `apply` stores.
- AC-5 On a due word, a correct quiz/listening answer schedules like Good and a wrong one like Again (due
  in 10 min, lapse rule). On a not-due word, every answer leaves SRS and `lapseCount` unchanged; the wrong
  answer still makes the word pending today. A typed soft miss leaves SRS unchanged. A failed save restores
  SRS, lapse and knowledge fields and publishes no activity.
- AC-6 `lapseCount` increments only per the lapse rule, persists, syncs (`lapse_count`), and old stores
  open with 0.
- AC-7 Practice shows a «Прогресс» card for the active workspace + selected folder: segmented bar,
  counts «выучено / учу / новые», «Завтра N · за неделю M», and «Трудные слова N ›» when N > 0; switching
  workspace or folder updates it.
- AC-8 «Трудные слова ›» opens a flashcard session with only the scope's hard words. Hard words show a
  «Трудное слово» pill in every session.
- AC-9 The Practice FolderPicker sheet shows «выучено X из Y» + thin bar for «Все папки» and each folder,
  with a footer explaining «Выучено».
- AC-10 Knowledge ring tier 2 uses `appLearning`; DESIGN.md, Theme.swift and ThemeTests agree.
- AC-11 Flashcard words never break mid-word (single long words and phrases containing one).
- AC-12 All new copy exists in en and ru (all plural forms), `check-localization.sh` is clean, and the
  build has zero warnings.

## Changes by file

### Model / services

1. `MojSlownik/Models/Word.swift`: add `var lapseCount: Int = 0` next to `consecutiveSoftMisses`
   (comment: "failures after a success; see SRSEngine lapse rule").

2. `MojSlownik/Services/Practice/SRSEngine.swift`
   - Keep `maxIntervalDays = 36_500`, re-documented as the **storage/sync acceptance bound** (validator and
     outgoing clamp keep using it). Add `maxScheduledIntervalDays = 30.0`, `againDelay: TimeInterval = 600`.
   - `struct SRSState: Equatable { easeFactor, intervalDays, repetitions, dueDate,
     lastReviewGradeRawValue, lapseCount }` with `init(word:)` and `func write(to word:)`.
   - `static func next(_ grade: ReviewGrade, from state: SRSState, now: Date) -> SRSState`: pure; the
     monotonic formulas from Decisions; lapse rule on `.again`; ease clamped to
     `minEaseFactor...maxEaseFactor`; sets `lastReviewGradeRawValue`.
   - `apply(_:to:now:)` = `next(...).write(to: word)` (signature unchanged).
   - `enum ScheduleDelay: Equatable { case minutes(Int), days(Int) }`;
     `static func preview(_ grade:, for word:, now:) -> ScheduleDelay` (from `next`, no mutation).
   - `static func practiceGrade(for answer: KnowledgeAnswer, isDue: Bool) -> ReviewGrade?` per Decisions
     (uses `KnowledgeProgressService.similarity` / `softMatchThreshold`).
   - `extension ScheduleDelay { var caption: String; var accessibilityText: String }` from the String
     Catalog keys below. `ReviewGrade.color` untouched.

3. `MojSlownik/Services/Practice/StudyProgress.swift` (new, pure):
   - `enum LearningStage { case new, learning, learned }`; `learnedThresholdDays = 21.0`,
     `hardWordLapseThreshold = 6`.
   - `stage(of:)`; `struct Breakdown: Equatable { new, learning, learned; total }`;
     `breakdown(_ words:)` (filters `isActive`).
   - `isHardWord(_:)`; `hardWords(_:)` (active only).
   - `struct Forecast: Equatable { tomorrow, week }`; `forecast(_ words:, now:, calendar:)` per
     Decisions, with day boundaries from `calendar.startOfDay` and `calendar.date(byAdding: .day…)`.

4. `MojSlownik/Services/Practice/ScheduleNormalizer.swift` (new, `@MainActor enum`):
   - Pure `static func normalized(_ state: SRSState, uuid: UUID?, now: Date) -> SRSState?` (nil = no
     change). Triggers when `intervalDays > 30` (or non-finite) or `dueDate > now + 31 d`:
     `interval = min(finite interval, 30)` (non-finite → 30);
     `review = min(now, dueDate − originalInterval × 86_400)` (non-finite → `now`);
     if `dueDate <= now` → keep `dueDate`;
     else `due = min(dueDate, review + 30 d)`; if `due < now` → `due = now + offset × 86_400`,
     `offset = Int(uuid?.uuid.0 ?? 0) % 7`. Idempotent: the output never triggers again.
   - `static func normalize(in context:, now:) throws -> Int`: active words; writes SRS fields only (no
     `updatedAt`, no `serverUpdatedAt`); one save; on failure `context.rollback()` and rethrow.
   - `@discardableResult static func run(container:now:) -> Int` with an os `Logger` on failure (no user text).

5. `MojSlownik/MojSlownikApp.swift`: call `ScheduleNormalizer.run(container: container, now: now)` right
   after `WorkspaceBackfill.run(...)` (~line 103).

6. `MojSlownik/Backend/RemoteRecords.swift`
   - `RemoteWordRecord`: `var lapseCount: Int? = nil` (last property, key `lapse_count`). Optional so
     decoding stays tolerant and existing memberwise call sites keep compiling.
   - `ValidatedRemoteWord`: `var lapseCount: Int = 0` (last). Validator: `lapseCount ?? 0`, negative →
     `.invalidSchedule`. Interval/due bounds unchanged (36_500).
   - `RemoteWordUpsert`: `var lapseCount: Int = 0` as the **last** property (default keeps existing
     memberwise call sites in SwiftDataSyncStore, UITestSyncRemote, SupabaseAdapterTests,
     RemoteRecordValidatorTests and SyncTestSupport compiling); always encoded (`lapse_count`); append
     `lapse_count` to `selectColumns`. `SwiftDataSyncStore.pendingWords` (~540-546) passes it explicitly.

7. `MojSlownik/Services/Sync/SwiftDataSyncStore.swift`
   - Private `apply(_:to:pair:)` gains `now: Date = .now`. After copying remote fields it sets
     `word.lapseCount = remote.lapseCount`, then
     `if let fixed = ScheduleNormalizer.normalized(SRSState(word: word), uuid: word.uuid, now: now) { fixed.write(to: word) }`.
     All three call sites (adopt, update, insert, ~lines 258/272/280) already call `markSynced`
     afterwards, so the row stays clean.
   - `pendingWords`: `lapseCount: max(0, word.lapseCount)` in the record and `valid.lapseCount` in the
     upsert. Outgoing interval clamp unchanged.

8. `MojSlownik/Services/UITestSupport/UITestSyncRemote.swift`: store and echo `lapseCount` from upserts.

9. `supabase/migrations/20261122120000_words_lapse_count.sql` (new):
   `alter table public.words add column lapse_count integer not null default 0 constraint
   words_lapse_count_nonnegative check (lapse_count >= 0);` + `comment on column`. RLS and grants are
   table-level and unchanged. A defaulted column fires no update trigger, so `updated_at` does not move.
   Old app versions upsert without the column: inserts get 0, updates keep the value.

10. `supabase/tests/words_lapse_count.sql` (new, `begin … rollback`, pattern of `sync_server_timestamps.sql`):
    insert without `lapse_count` → 0; update to 7 succeeds; −1 fails the CHECK (caught in `do`); user B
    sees no row; `anon` has no access.

11. `MojSlownik/Services/UITestSupport/UITestFixtures.swift`: new fixture `studyProgress` (pl ← ru), in
    the `// l10n:data` region. All day offsets use `calendar.date(byAdding: .day, value:, to: now)` with
    `Calendar.autoupdatingCurrent` (DST-safe, L6):
    - Folders «Урок 1» (`lesson1ID`) and «Урок 2» (`lesson2ID`).
    - Learned (interval 30, reps 3, ease 2.5, due +30 days): kot*, dom*, woda.
    - Learning: chleb* (reps 2, interval 3, due `now + 12 h` via `.hour`, so always "tomorrow" in the
      forecast); okno (reps 1, interval 1, due +3 days); przyzwyczajenie / привычка (reps 1, interval 1,
      ease 1.3, `lapseCount = 7`, grade `good`, due −1 day).
    - New (reps 0, no grade, due = createdAt), all in «Урок 2»: jabłko / яблоко, mleko / молоко,
      ser / сыр, ryba / рыба.
    - (* = in «Урок 1».) Expected values. All folders: learned 3 / learning 3 / new 4 of 10, tomorrow 1,
      week 2, hard 1, due now 5. «Урок 1»: 2 / 1 / 0 of 3, hard 0. «Урок 2»: 0 / 0 / 4 of 4.

### Stores

12. `MojSlownik/Stores/DailyStudyStore.swift`
    - `review(...)`: snapshot `SRSState(word:)` (now including `lapseCount`) and restore via `write(to:)` on failure.
    - `recordPracticeAnswer(...)`: after `prepareSave`, snapshot `SRSState`, knowledge fields and
      `updatedAt`. Then apply `KnowledgeProgressService.apply`, then
      `if let grade = SRSEngine.practiceGrade(for: answer, isDue: word.dueDate <= now) { SRSEngine.apply(grade, to: word, now: now) }`.
      On save failure restore all three groups. Activity/commit/log order unchanged.
    - Remove `recordQuizAnswer` (L2). Owned test files that call it and must be ported:
      `MojSlownikTests/DailyStudyStoreTests.swift`, `MojSlownikTests/StoreLoggingTests.swift`,
      `MojSlownikTests/SoftDeleteExclusionTests.swift` (see Verification). Update the `progress(for:)` doc comment: correct answers on due words
      now schedule like Good, and the quiz exemption matters only for not-due words.

### Theme and components

13. `MojSlownik/Theme/Theme.swift`: `Palette.learning = pair(0xB8860B, 0xFFD43B)`, `Color.appLearning`.
14. `MojSlownik/Views/Components/KnowledgeTierBadge.swift`: rename `IndicatorColor.accent` to
    `.learning`, mapped to `.appLearning`.
15. `MojSlownik/Views/Components/ProgressSegmentsBar.swift` (new; used by TrainingView and FolderPicker):
    `struct ProgressSegmentsBar: View { struct Segment: Identifiable { id: String; value: Int; color: Color };
    segments; track = .appSecondarySurface; height: CGFloat = 12; spacing: CGFloat = 2 }`. Non-zero segments
    sit in an `HStack(spacing:)`, each width proportional to its value over `(width − spacing × (n−1))`,
    clipped to a `Capsule`; total 0 → track only.
    `.animation(reduceMotion ? nil : .snappy(duration: 0.3), value:)`; `.accessibilityHidden(true)`.
16. `MojSlownik/Views/Components/FolderPicker.swift`: new
    `var progress: ((UUID?) -> StudyProgress.Breakdown)? = nil`. When it is set, `optionRow` shows a
    footnote line and a 4 pt bar under the name and sets `.accessibilityValue` (Design spec). The first
    section gets the «Выучено» footer. Management rows unchanged.

### Views

17. `MojSlownik/Views/Practice/StudyProgressCard.swift` (new, Practice-only). Inputs: `breakdown`,
    `forecast`, `hardWordCount`, `folderID`. The hard-words row is a
    `NavigationLink { FlashcardsView(folderID: folderID, session: .hardWords) }` styled with
    `TileButtonStyle`; change that style in TrainingView.swift from `private` to `internal`.
18. `MojSlownik/Views/Practice/TrainingView.swift`: inside the `TimelineView`, compute
    `StudyProgress.breakdown(words)`, `.forecast(words, now:, calendar: .autoupdatingCurrent)` and
    `.hardWords(words).count`. Insert `StudyProgressCard` between `modeGrid` and `achievementsRow`
    (hidden when `words.isEmpty`). Pass
    `progress: { StudyProgress.breakdown(FolderStore.words(allWords, in: $0, memberships: memberships)) }`
    to the `FolderPicker`.
19. `MojSlownik/Views/Practice/FlashcardsView.swift`
    - `enum FlashcardSession { case review, hardWords }`, `var session: FlashcardSession = .review`.
      `.hardWords` uses `StudyProgress.hardWords(words).shuffled()` (no 10-word fallback) and the
      navigation title "Hard words". `.review` is unchanged.
    - Hard-word pill in `faceHeader` after the badge when `StudyProgress.isHardWord(word)`. `faceHeader`
      stacks vertically at accessibility sizes. Card `accessibilityValue` = one localized format
      `"%@, hard word"` with the tier description (L5); otherwise the tier description as today.
    - Word text: private `WholeWordText` (Design spec), used by both faces.
    - Grade buttons: two-line label (title + `preview.caption`), `.accessibilityLabel(grade.title)`,
      `.accessibilityValue(preview.accessibilityText)`. Previews are computed from the word's state before
      `apply`.
20. `QuizView.swift`, `ListeningPracticeView.swift`: no code change (scheduling happens in `recordPracticeAnswer`).

### Strings: `MojSlownik/Localizable.xcstrings`

Plural keys need every form: en `one`/`other`; ru `one`/`few`/`many`/`other`.

| Key (en) | en forms | ru forms |
|---|---|---|
| Progress | — | Прогресс |
| learned / learning / new | — | выучено / учу / новые |
| learned %lld, learning %lld, new %lld of %lld (VO) | invariant | выучено %lld, учу %lld, новые %lld из %lld |
| Tomorrow %lld · this week %lld | invariant | Завтра %lld · за неделю %lld |
| Tomorrow: %lld, this week: %lld (VO) | invariant | Завтра: %lld, за неделю: %lld |
| Scheduled reviews | — | Повторения по расписанию |
| Hard words | — | Трудные слова |
| Forgotten at least %lld times | one "Forgotten at least %lld time", other "Forgotten at least %lld times" | one "Забыты %lld раз и больше", few "Забыты %lld раза и больше", many "Забыты %lld раз и больше", other "Забыты %lld раза и больше" |
| Practice only the hard words | — | Тренировать только трудные слова |
| %lld of %lld learned | invariant | выучено %lld из %lld |
| “Learned”: the word is reviewed every 21 days or less often. Intervals grow to at most 30 days, so learned words come back once a month. | — | «Выучено»: слово повторяется раз в 21 день и реже. Интервалы растут не дальше 30 дней, поэтому выученные слова возвращаются раз в месяц. |
| Hard word | — | Трудное слово |
| %@, hard word (VO) | — | %@, трудное слово |
| %lld min | one/other "%lld min" | one/few/many/other "%lld мин" |
| %lld d | one "%lld day", other "%lld days" | one/few/many/other "%lld дн." |
| Next review in %lld minutes | one "Next review in %lld minute", other "… %lld minutes" | one "Следующий показ через %lld минуту", few "… %lld минуты", many "… %lld минут", other "… %lld минуты" |
| Next review in %lld days | one "Next review in %lld day", other "… %lld days" | one "Следующий показ через %lld день", few "… %lld дня", many "… %lld дней", other "… %lld дня" |

The Hard-words subtitle interpolates `StudyProgress.hardWordLapseThreshold`.

### Docs

21. `docs/architecture.md`:
    - Practice: quiz/listening schedule only due words, replacing "quiz answers do not change SRS
      fields" and "without changing SM-2 scheduling".
    - Daily progress: the quiz exemption now only matters for not-due words.
    - Non-obvious constraints: 30-day cap and monotonic grades; local-only launch normalization and the
      pull clamp (and why rows stay clean); "Learned" means interval ≥ 21 in Progress while achievements
      keep `repetitions >= 3`; the lapse rule and hard words; the forecast definition.
    - Sync: `lapse_count`.
    - Reusable Views: `ProgressSegmentsBar`.
    - Follow-up: FSRS.
22. `DESIGN.md`: see Design spec › DESIGN.md updates.

## Design spec

Tokens only; values in Theme.swift. Section gap 20, side margin 20.

**Progress card** (TrainingView, after Modes, before Achievements). It opens with the section header
«ПРОГРЕСС» (existing `sectionHeader`), then one `cardStyle()` card with padding `AppSpacing.m` and
`VStack(spacing: s)`:
- `ProgressSegmentsBar`, height `@ScaledMetric(relativeTo: .footnote) 12`: learned `appMastery`, learning
  `appLearning`, new `appRingTrack`, track `appSecondarySurface`.
- Legend: three equal columns. Each column has the count (`.title2.weight(.heavy)`, `.monospacedDigit()`,
  `.contentTransition(.numericText())`, `appInk`). Below the count: an 8 pt dot
  (`@ScaledMetric(relativeTo: .footnote)`, segment colour, hidden from VoiceOver) and the label
  (`.footnote`, `subtleText`). The text label carries the state, not the colour. At AX sizes the legend
  stacks into rows (count, dot, label) via `AnyLayout`. Bar + legend form one element:
  `.accessibilityElement(children: .ignore)`, label "Progress", value "learned X, learning Y, new Z of T",
  id `studyProgressSummary`.
- 1 pt `appBorder` hairline, then the **forecast row**, min height 44:
  - 32 pt `@ScaledMetric` `appAccentSoft` tile with an ink `calendar` glyph (`.fontWeight(.medium)`);
  - title «Завтра N · за неделю M» (`.body`, `.monospacedDigit()`);
  - subtitle «Повторения по расписанию» (`.footnote`, `subtleText`);
  - not interactive; accessibility label "Scheduled reviews", value "Tomorrow: N, this week: M",
    id `studyForecast`.
- Hairline, then the **hard-words row**, only when N > 0:
  - `appWarningSurface` tile with an `appWarning` `exclamationmark.triangle` glyph;
  - title «Трудные слова» (`.body`), subtitle «Забыты 6 раз и больше» (`.footnote`, `subtleText`);
  - trailing N (`.body.bold`, monospaced) and a `chevron.right` (`subtleText`);
  - a `NavigationLink` with `TileButtonStyle`, min height 44; `.accessibilityElement(children: .combine)`,
    value N, hint "Practice only the hard words", id `hardWordsRow`.
- AX: both rows switch to `VStack(alignment: .leading)` (icon above the text, then the value), like
  `achievementsRow`.
- Motion: counts use `numericText`, the bar `.snappy(0.3)`; neither animates with Reduce Motion. No haptics.

**Folder sheet rows** (Practice picker only): name `.body` `appInk`; under it «выучено 18 из 40»
(`.footnote`, `subtleText`, `.monospacedDigit()`); under that a 4 pt `ProgressSegmentsBar` (learned
`appMastery`, learning `appLearning`, track `appSecondarySurface` = new). Checkmark unchanged. Min height
44; content wraps at AX. `.accessibilityValue("18 of 40 learned")`; ids stay `folderOption-all` /
`folderOption-<name>`. Section footer: the explanation string (`.footnote`, `subtleText`).

**Flashcard pill «Трудное слово»**: `Label` with `exclamationmark.triangle`, `.caption.weight(.semibold)`,
`appWarning` on an `appWarningSurface` `Capsule`, padding h 8 / v 4 (≈ 6.3:1 light, ≈ 7.6:1 dark). It
follows the knowledge ring in the face header and is hidden from VoiceOver (announced via the card value).

**Grade buttons**: surfaces and borders as today. The label is a `VStack(spacing: 2)`: title
`.body.weight(.semibold)`, then the caption `.footnote.weight(.medium)` `.monospacedDigit()` in
`subtleText` (on Easy: `appOnAccent.opacity(0.75)`). Vertical padding `AppSpacing.xs`, min height 50; 2×2
grid, one column at AX.

**Knowledge ring**: tier 2 arc uses `appLearning` (was `appAccentText`).

**Flashcard word never breaks mid-word (L4).** Today the word `Text` uses `.fixedSize(horizontal: false,
vertical: true)` with no line limit or scale factor, so «przyzwyczajenie» at 38 pt (or any long word at AX
sizes) is split across lines. Replace it in both faces with a private `WholeWordText(text:, baseSize:
cardWordSize)`. It is a `ViewThatFits(in: .horizontal)` over the scales `[1.0, 0.85, 0.7, 0.55, 0.4]`.
Each candidate is:
```swift
VStack(spacing: 0) {
    Text(longestWord).font(.system(size: baseSize * scale, weight: .heavy))
        .fixedSize().frame(height: 0).hidden().accessibilityHidden(true)   // ideal width = longest word
    Text(text).font(.system(size: baseSize * scale, weight: .heavy))
        .multilineTextAlignment(.center).foregroundStyle(Color.appInk)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)           // phrase width does not count
}
```
`longestWord` is the longest whitespace-separated token. The first scale at which the longest word fits on
one line wins, so phrases still wrap between words and no word is split. The smallest scale also gets
`.minimumScaleFactor(0.8)` as a last resort. The back face's original-text line keeps normal wrapping.

**DESIGN.md updates** (same diff as Theme.swift + ThemeTests):
- Colour table: `appLearning` | learning bucket, ring tier 2; graphics only, never text | #B8860B | #FFD43B.
- Verified contrast rows: honey on card / paper 3.25 / 3.06 (graphics only); dark yellow on card 11.7.
- Colour rule 7 adds "`appLearning` graphics only". Note: the `appRingTrack` "new" segment is a track-like
  graphic; the counts are text.
- Components: Progress card; `ProgressSegmentsBar`; folder progress row; hard-word pill; rating buttons
  with next-interval caption; knowledge ring tier 2 colour; whole-word flashcard text.
- Iconography: forecast `calendar`; hard words / pill `exclamationmark.triangle`.

## Reuse

`WorkspaceScope`, `FolderStore.words(_:in:memberships:)`, `MembershipIndex`, `DailyStudyStore` atomic
pattern (`prepareSave` → mutate → save → commit/restore), `KnowledgeProgressService.similarity`,
`MarkerProgressBar` conventions, `cardStyle()`, `sectionHeader`, `TileButtonStyle`, `AppSpacing`/`AppRadius`,
`WordIdentityBackfill` launch pattern (local-only, no `updatedAt`), `UITestFixture` + `E2ETestCase`
helpers (`waitForValue`, `waitFor`).

## Data compatibility

- `Word.lapseCount: Int = 0` is additive (lightweight migration); existing words start at 0, so hard words
  appear only after future lapses.
- Long schedules are clamped locally at launch and on pull without dirtying rows. Server copies keep their
  long values until the word's next review pushes the capped schedule. The validator keeps accepting up to
  36_500, so old clients' rows are never rejected.
- Server: defaulted column, no `updated_at` bump; old clients' upserts leave it untouched. The migration
  must be applied to the Supabase project **before** this build syncs (`selectColumns` names `lapse_count`).
- `dailyStudyActivity.v1` format unchanged. Existing fixtures (intervals 30 and 1) are unaffected.

## Verification

Unit tests (MojSlownikUnitTests):
- `SRSEngineTests`:
  - Replace the 36_500 cap test: computed > 30 → 30 for Hard/Good/Easy; Good on a 30-day word → 30; high
    ease never exceeds 30; Again unchanged.
  - **Ordering property test**: grid I ∈ {0, 1, 2, 3, 5, 8, 13, 21, 25, 30} × E ∈ {1.3, 1.8, 2.5, 3.0} ×
    R ∈ {0, 1, 2, 3, 5}. Assert Hard ≤ Good ≤ Easy ≤ 30; Good < Easy when Good < 30; Hard < Good when
    I ≥ 1 and Good < 30; Good ≥ I and Hard ≥ I for I ≥ 1.
  - Leech example → 1 / 3 / 4 days.
  - Preview equals the `apply` result and does not mutate; previews ≤ 30 days.
  - Lapse rule: reps > 0 counts, reps 0 does not, repeated Again counts once.
  - `practiceGrade` table: not due → nil for correct / wrong / soft miss; due: correct → good,
    wrong choice → again, typed < 0.7 → again, soft miss → nil.
  - `ScheduleDelay` caption and accessibility text.
- `StudyProgressTests` (new):
  - Stage, including an Again-reset word = learning; boundary 20.9 / 21; inactive words excluded.
  - Hard words: (6, < 21) yes; (5) no; (6, ≥ 21) no.
  - Forecast with a fixed calendar/time zone: a word due later today counts in tomorrow and week; due at
    the end-of-tomorrow boundary is excluded from tomorrow; already due is excluded from both; day 7 is in
    week, day 8 is not.
- `ScheduleNormalizerTests` (new, in-memory container):
  - long interval clamped; far due clamped to review + 30 d;
  - **already overdue keeps `dueDate`** (M1); future due clamped into the past → now + uuid offset (0–6 days);
  - idempotent second run returns 0;
  - **`updatedAt` and `serverUpdatedAt` unchanged** (H1);
  - deleted and short-schedule rows untouched.
- `SwiftDataSyncStoreTests`: a pulled row with interval 400 is stored as ≤ 30 and is not sync-dirty;
  `lapseCount` round-trips through apply and pending.
- `SyncEngineTests` (H1): a clean local word with interval 400 and an old server stamp; the server holds a
  newer version with edited text. Run `ScheduleNormalizer.normalize`, then a sync cycle. Expect: the remote
  text is stored locally, the interval is ≤ 30, the row is not dirty, and nothing was pushed for that word.
- `DailyStudyStoreTests`:
  - due + correct → Good; not due + correct → SRS unchanged;
  - due + wrong → due +10 min and lapse; not due + wrong → SRS and `lapseCount` unchanged but pending;
  - listening soft miss → SRS unchanged;
  - save failure restores SRS + lapse + tier (failing context from `SaveFailureRestoreTests`);
  - `review` restores `lapseCount` on failure;
  - explicit due-word scheduling cases for `.choice` and `.typed` answers in both `.quiz` and `.listening`
    modes (correct → Good, wrong → Again + lapse, typed soft miss → unchanged);
  - the former `recordQuizAnswer` tests (~lines 191-291) are rewritten against
    `recordPracticeAnswer(word:answer:context:mode: .quiz)` with an in-memory container (L2).
- `StoreLoggingTests` (~135, 141): port the `recordQuizAnswer` logging and throw cases to
  `recordPracticeAnswer` with a failing `DailyActivityRepository` (`prepareSave` throws): the error
  propagates, nothing is logged as answered, and the word's SRS/knowledge fields are unchanged.
- `SoftDeleteExclusionTests` (~54): replace the `recordQuizAnswer` call with `recordPracticeAnswer` on an
  active word, then soft-delete a second word; assert the inactive word is excluded from `progress` /
  `answerTotals` / `StudyProgress.breakdown` and keeps its SRS fields and `lapseCount`.
- `SaveFailureRestoreTests` (~42, `testReviewRestoresFieldsAndUpdatedAtWhenSaveFails`): also assert
  `lapseCount` is restored (use a word with reps > 0 graded Again so the lapse would have incremented).
- `RemoteRecordValidatorTests`: missing `lapse_count` → 0; negative rejected; 36_500 still accepted.
- `SupabaseAdapterTests`: decode/encode `lapse_count`; `selectColumns`.
- `LegacySchemaMigrationTests`: a pre-`lapseCount` store opens with every word intact and `lapseCount == 0`.
- `UITestSupportTests`: `studyProgress` breakdowns per scope, memberships, forecast; pinned fixture names.
- `ThemeTests`: `appLearning` in the palette table; graphics contrast ≥ 3 on card and paper in both modes.
- `KnowledgeTierBadgeTests`: tier 2 → `.learning`.

E2E (MojSlownikE2E). New `MojSlownikUITests/StudyProgressFlowTests.swift`; add `studyProgress` to
`E2ETestCase.Fixture`:
- `testProgressCardShowsBucketsForecastAndHardWords`: `studyProgressSummary` = «выучено 3, учу 3, новые 4
  из 10»; `studyForecast` = «Завтра: 1, за неделю: 2»; `hardWordsRow` value «1».
- `testFolderSheetShowsLearnedCounts`:
  - sheet values: `folderOption-all` «выучено 3 из 10», `folderOption-Урок 1` «выучено 2 из 3»,
    `folderOption-Урок 2` «выучено 0 из 4»;
  - select «Урок 1» → summary «выучено 2, учу 1, новые 0 из 3», `hardWordsRow` absent.
- `testHardWordsSessionShowsPillAndCaptions`: tap `hardWordsRow`; the `flashcard` value contains «трудное
  слово»; flip; grade values «Следующий показ через 10 минут / 1 день / 3 дня / 4 дня» (unchanged by M2).
- `testCorrectQuizAnswerMovesNewWordToLearning` (M4, deterministic): select «Урок 2» → «выучено 0, учу 0,
  новые 4 из 4». Open the quiz (4 words → 4 questions). Read `quizPrompt`'s label and map it through the
  fixture pairs (both directions) to the correct answer. Find options via
  `app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'quizOption-'"))`,
  filtered to the element whose `label.hasPrefix(correctAnswer)`; tap it. Wait for `sessionProgress` value
  «Ответов: 1 из 4» (as QuizFlowTests does), then leave the quiz mid-way with the back button: summary
  «выучено 0, учу 1, новые 3 из 4».
- `WorkspaceFlowTests.testSwitchingScopesDictionaryFoldersAndPractice` (M4): with «Слов в выбранном
  наборе: 2» (de), assert `studyProgressSummary` «выучено 2, учу 0, новые 0 из 2». After switching to pl
  («… 5»), assert «выучено 5, учу 0, новые 0 из 5».
- Local regression (one simulator, affected classes): `StudyProgressFlowTests`, `FlashcardsFlowTests`,
  `QuizFlowTests`, `FoldersFlowTests`, `SyncFlowTests`, `WorkspaceFlowTests`, `LocalizationFlowTests`. The
  full suite runs in CI.

Database: `scripts/test-db.sh <empty Postgres>`. After applying the migration to Supabase, run the
security advisors.

Build: `xcodegen generate` (new files), then a zero-warning build with
`-onlyUsePackageVersionsFromResolvedFile`, then `scripts/check-localization.sh <DerivedData>`.

Manual checks:
- Flashcard text at default size and AX5: «przyzwyczajenie» and a phrase with a long word (e.g.
  «nieprzyzwyczajony do pracy») are not split mid-word.
- Simulator screenshots of Practice (light, dark, AX5), the folder sheet and a hard-word card.
- VoiceOver over the Progress card and grade buttons; Reduce Motion.
- Upgrade an existing install: long-interval words reappear within a week, the word count is unchanged,
  and no mass push follows launch.
- Two-device sync of `lapse_count` against the real project.

## Risks

- Normalization makes words whose clamped due date passed come due over 7 days. Already-overdue words were
  due anyway.
- Local and server schedules differ for clamped-but-unreviewed words. Another device pulls the long value
  and clamps it the same way, so the behaviour matches.
- An app build that syncs before the migration is applied gets PostgREST errors (unknown column): mind the
  deploy order.
- Quiz/listening on due words now changes schedules (more churn); a wrong answer on a due word resets it.
- The `appRingTrack` "new" segment is 1.6:1 on card (graphics, labelled by text).
- `WholeWordText` builds up to five candidates per face. Cheap for one card, but keep it out of lists.
- Free practice and the hard-words session still apply SRS to not-due words (existing behaviour).

## Open decisions

1. Wrong quiz/listening answer on a **not-due** word: leave SRS and `lapseCount` unchanged (recommended,
   implemented: the word becomes pending and the flashcard grade decides) vs apply Again.
2. Lapse counts only failures after a success (`repetitions > 0`) vs every "Again"/wrong answer.
3. A new word keeps Hard = Good = 1 day (Hard ≤ Good) vs strict Hard < Good (first Good = 2 days).
4. The hard-word flag clears when the word becomes learned (counter kept).
5. Sync `lapse_count` via a new migration (recommended) vs device-local only.
6. Forecast «Завтра» counts words due later today plus tomorrow (implemented) vs strictly the next
   calendar day.
7. Hard-words row hidden at 0 (vs shown disabled).
8. Folder progress only in the Practice picker (the Dictionary picker could show it too).
9. Achievements' "learned words" keeps `repetitions >= 3` (could align to interval ≥ 21 later).
10. Free practice / hard-words session on not-due words keeps SRS updates (follow-up: apply the
    no-inflation rule).

## Revision log (critic findings)

- H1: the normalizer is local-only (no `updatedAt`), plus a clamp on pull in `apply` before `markSynced`;
  AC-3 rewritten; SyncEngineTests case added; the "devices converge" claim removed.
- M1: spread only when the clamp moved a future due date into the past; already-overdue words keep theirs;
  tested.
- M2: monotonic `next()` with justification; grid property test; E2E captions re-derived (unchanged
  10 min / 1 / 3 / 4).
- M3: wrong on not-due → no change; Open decision 1.
- M4: WorkspaceFlowTests assertions, a deterministic quiz scenario, and the extended local regression list.
- L1: covered by the pull clamp. L2: `recordQuizAnswer` removed and its tests moved. L3: forecast defined
  and tested. L4: `WholeWordText` sized to the longest word, plus a phrase in manual checks. L5: plural forms
  spelled out, single VO format string. L6: fixture dates via `calendar.date(byAdding:)`.

## Follow-ups and workflow recommendations (not in this change)

- FSRS scheduler (Anki 23.10+ default): per-user retention target, fewer reviews for the same recall.
- Interval fuzz (±5 %) to avoid review clumps; daily new-word limit and a review cap.
- Typed recall in flashcards and the production direction (ru → pl) as a separate schedule.
- Example sentences / cloze with context; audio-first cards for listening.
- Leech actions: suspend, edit (mnemonic/note), or move to a «Трудные» folder.

## Approval

- 2026-11-22: approved by user. Base c065c21783fbec73a59a9b6c5457bebfe2f9295f on branch t3/spaced-review-progress; pre-existing ` M MojSlownik/InfoPlist.xcstrings` is not part of this task.
