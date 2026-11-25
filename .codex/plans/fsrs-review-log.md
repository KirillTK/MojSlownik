# FSRS scheduler with a synced review log

Branch `feature/fsrs-review-log` (HEAD 82ec829, main with PR #14). Mode: FULL. Revision 4 (see Revision log).
Base worktree: ` M MojSlownik/InfoPlist.xcstrings` (user's, not part of this task, never stage it) and
`?? supabase/.temp/` (Supabase CLI cache, see Open decision 11).

## Goal

Record every practice answer in an append-only review log (`ReviewLogEntry`, uploaded to
`public.review_logs`). Replace SM-2 with FSRS (open-spaced-repetition/swift-fsrs), storing difficulty,
stability and state on `Word` and syncing them. Convert existing SM-2 progress to FSRS once and
deterministically, without losing words or moving due dates. Keep today's user-facing behaviour (grade
captions, Progress card, hard words, folder counts, quiz/listening rules, 10-minute Again, the 30-day max-interval setting) except
for the changes listed under Open decisions.

## Constraints (user instructions, verbatim)

Task: "FSRS with a review log: start recording a synced log of every answer (word, time, grade, mode,
elapsed days, interval before/after), then switch the scheduler from SM-2 to FSRS
(difficulty/stability/retrievability, target retention, keep the 30-day max interval as a setting),
migrating existing SM-2 progress to FSRS state without losing words."

## Decisions

User decisions (binding):

1. Target retention is fixed at **0.90**, with no UI. Max interval stays **30 days** (a constant/"setting" in
   code, no UI).
2. **Default FSRS parameters** of the chosen library version. No on-device optimizer now; that is a follow-up
   once the log holds enough reviews.
3. Use the official **swift-fsrs** SPM package, pinned to an exact version in project.yml, with
   Package.resolved committed. Wrap it behind our own SRSEngine facade so Views and Stores never import it.
4. **No new UI.** Grade-button captions, the Progress card, hard words and folder counts keep working, now
   from FSRS state. Any copy change needs en+ru.
5. **The app is not in production, so breaking changes are allowed.** There is no backward compatibility
   with older app versions: every device runs the new build after the migration. Still binding:
   - never lose existing words or their progress (the account has about 98 synced words);
   - SwiftData additions must be optional or defaulted;
   - follow the RLS, migration and DB-test rules;
   - migrations are applied to Supabase only with separate user authorization, and before the build is
     installed.

   Persisted SM-2 properties and server columns may stay unused rather than be removed.
6. **User answers to the open decisions (2026-11-23):**
   - Open decision 2 → **option (c)**, not the planner default. A word answered correctly today stays
     counted as completed for the rest of the local day, even if FSRS makes it due again later today, so
     Today's bar never goes backwards. "Correctly" means Hard/Good/Easy in flashcards, or a correct
     quiz/listening answer. A "Не помню" or wrong answer still keeps the word pending and returns it in the
     session, as now. See D16.
   - Open decision 3 → accept FSRS after-lapse intervals.
   - Open decision 6 → accept FSRS early-review behaviour (it may shorten intervals).
   - Every other open decision keeps its recommended default: FSRS-6 weights, 10-minute steps, the FSRS lapse
     rule, learned = `intervalDays >= 21`, logging non-scheduling answers with `affects_schedule = false`,
     push-only log sync, an FK only to `auth.users`, and `supabase/.temp/` in `.gitignore`. The package is
     accepted, so the fallback is not needed.
7. **User decision 7 (2026-11-23): pure library intervals, always through our wrapper.**
   - **No post-processing of intervals.** Take what swift-fsrs returns with `maximumInterval: 30`.
     - Hard ≤ 30 d, Good ≤ 31 d, Easy ≤ 32 d (the package applies the max before
       `good = max(good, hard + 1)` and `easy = max(easy, good + 1)`).
     - There is no own 30-day post-clamp, and no own "Easy ≥ Good + 1" rule (Good may equal Easy after a
       lapse).
     - "The 30-day max interval as a setting" = `SRSEngine.maxScheduledIntervalDays = 30`, passed to the
       package as `maximumInterval`.
   - **App code never calls the package directly.** Every call goes through our wrapper
     (`FSRSScheduler`, used only by `SRSEngine` and `FSRSMigration`). The import boundary stays: only
     `FSRSScheduler.swift` and its test may import FSRS, enforced by the hygiene test.

Package research. I cloned the package read-only into the scratchpad and built it with a probe executable;
the reference values below come from that probe.

- Source: `https://github.com/open-spaced-repetition/swift-fsrs`, latest tag **6.0.0** (2026-11-12, commit
  `74cb02977ba94dd505aa2a13149238b5f5d48a1b`; the release before it was 5.0.0 in 2024-10).
- **MIT** license, product `FSRS`, no dependencies.
- `.iOS(.v14)`, `swift-tools-version: 5.10` (needs Xcode 15.3+; local Xcode 27.2 and CI `latest-stable`
  qualify). Our `SWIFT_VERSION 5.9` applies only to our own targets.
- It builds with zero warnings. Its `print` calls are on paths we never use, and none of them prints user
  text.
- API used:
  - `FSRS(parameters:)` (immutable, Sendable);
  - `FSRSParameters(requestRetention:maximumInterval:w:enableFuzz:enableShortTerm:learningSteps:relearningSteps:)`;
  - `FSRSDefaults.defaultWv6` (21 weights, FSRS-6);
  - `Card(due:stability:difficulty:elapsedDays:scheduledDays:learningSteps:reps:lapses:state:lastReview:)`;
  - `CardState` (.new 0, .learning 1, .review 2, .relearning 3) and `Rating` (.again 1 … .easy 4);
  - `try fsrs.repeat(card:now:)[rating] -> RecordLogItem { card, log }`;
  - `fsrs.getRetrievability(card:now:)`.
- When it throws: on `t < 0` (last review after now), and on corrupt memory (state ≠ new with D < 1 or
  S < 0.001). S = D = 0 is the exception: it re-initialises the memory instead.
- Facts that shape the plan:
  - (a) `maximumInterval` is applied before `good = max(good, hard + 1)` and `easy = max(easy, good + 1)`,
    so a 30-day max returns 30/31/32 days;
  - (b) in learning/relearning, Easy is not forced above Good (Good = Easy = 1 d after a lapse happens);
  - (c) elapsed days count whole UTC calendar days;
  - (d) the package log records state, S, D and scheduledDays from before the review, plus `elapsedDays`.

Planner decisions (implement as written; the material ones are repeated under Open decisions):

- **D1 FSRS-6 parameters:** `w = FSRSDefaults.defaultWv6`, `requestRetention 0.9`, `maximumInterval 30`,
  `enableFuzz false` (deterministic), `enableShortTerm true`, `learningSteps ["10m"]`,
  `relearningSteps ["10m"]` (Open decisions 2 and 5).
- **D1a No interval post-processing (user decision 7).** `FSRSScheduler` returns the package's
  `repeat(card:now:)` result for each grade unchanged. Preview and apply share this one path. What the
  package guarantees:
  - review state: Hard < Good < Easy, with Hard ≤ 30, Good ≤ 31, Easy ≤ 32;
  - learning/relearning: Again 10 min < Hard 15 min < Good ≤ Easy.

  Define `SRSEngine.maxLibraryIntervalDays = maxScheduledIntervalDays + 2` (32): the longest interval the
  package can return with the 30-day setting. It is the bound for the knock-on checks below.
- **D2 Reference values** (raw package output from the probe; `now` fixed, exact day offsets):

  | Word | Again | Hard | Good | Easy |
  |---|---|---|---|---|
  | new, or converted Again-reset (S = D = 0) | 10 min | 15 min | 2 d | 8 d |
  | converted E 1.3, I 1, due −1 d (E2E hard word) | 10 min | 2 d | 3 d | 4 d |
  | converted E 2.5, I 1, on time | 10 min | 2 d | 3 d | 4 d |
  | converted E 2.5, I 3, on time | 10 min | 6 d | 8 d | 11 d |
  | converted E 2.5, I 10, on time | 10 min | 19 d | 25 d | 30 d |
  | converted E 2.5, I 25 or 30, on time | 10 min | 30 d | 31 d | 32 d |
  | S 10, D 6.914: Again, then 10 min later | 10 min | 15 min | 1 d | 2 d |
  | S 3, D 7.657: Again, then 10 min later | 10 min | 15 min | 1 d | 1 d |
  | S 25, D 6.24: Again, then 10 min later | 10 min | 15 min | 2 d | 4 d |
  | new word: Hard, then 15 min later | 10 min | 15 min | 1 d | 2 d |
- **D2a Knock-on effects of intervals up to 32 days:**
  - **ScheduleNormalizer: keep it, aligned to 32.** Today it clamps `intervalDays > 30` and
    `dueDate > now + 31 d`, so on the next launch it would shorten every Good (31 d) or Easy (32 d)
    schedule. Change its cap from `maxScheduledIntervalDays` to `maxLibraryIntervalDays`. It then clamps
    only intervals above 32 and due dates beyond now + 33 d. That keeps it a safety net for corrupt or
    foreign rows, and it never touches what the package produced. Legacy SM-2 rows were already
    normalized to ≤ 30 by PR #14. Clamp-on-pull uses the same function.
  - **D6 conversion:** cap the SM-2 interval input at `maxLibraryIntervalDays` (in practice ≤ 30).
  - **StudyProgress:** learned = `intervalDays >= 21` and the forecast (tomorrow / 8-day window) are
    unaffected.
  - **The "Long memory" achievement** (`maxIntervalDays >= 30`, copy "30 days or more") stays accurate.
  - **FolderPicker footer copy is now inaccurate.** It says "Intervals grow to at most 30 days" /
    «не дальше 30 дней». Replace that key with (en) "“Learned”: the word is reviewed every 21 days or less
    often. Intervals grow to about a month, so learned words come back about once a month." and (ru)
    ««Выучено»: слово повторяется раз в 21 день и реже. Интервалы растут примерно до месяца, поэтому
    выученные слова возвращаются примерно раз в месяц.» Remove the old key so there is no dead key.
    `StudyProgressTests.testLearnedCopyMatchesTheConstants` then asserts `learnedThresholdDays == 21`,
    `maxScheduledIntervalDays == 30` and `maxLibraryIntervalDays == 32`; update its doc comment.
  - **E2E captions:** no change (all pinned values are below 30 d).

  For comparison, today's SM-2 gives:
  - a new word: 10 min / 1 d / 1 d / 2 d;
  - the E2E hard word: 10 min / 1 d / 3 d / 4 d;
  - right after Again: Good 1 d and Easy about 6–7 d (Open decision 3).
- **D3 What the app still reads, and therefore what is still written.** After each FSRS review, SRSEngine
  writes:
  - `dueDate` = the FSRS due date (read by "due", forecast and the daily store);
  - `intervalDays` = the package's scheduledDays (≤ 32), 0 in learning/relearning (read by StudyProgress
    learned = `intervalDays >= 21`, hard words, ScheduleNormalizer);
  - `repetitions` = 0 on Again, otherwise +1 (read by the StudyProgress "new" stage and the `learnedWords`
    achievement, `repetitions >= 3`);
  - `lastReviewGradeRawValue` (read by the "new" stage);
  - `lapseCount` (D4).

  **`easeFactor` is no longer written.** It is still read in two places: as an input to the conversion
  (D6), and by the legacy fallback of `KnowledgeProgressService.tier(for:)`
  (KnowledgeProgressService.swift:26-27). That fallback only applies when `knowledgeTier` and
  `lastReviewGradeRawValue` are both nil; every FSRS review sets a grade, so the frozen value stays correct
  there. The property and the `ease_factor` server column stay, and the column keeps being pushed with the
  frozen value.
- **D4 Lapse = FSRS lapse:** `lapseCount` grows by one only on Again for a card in FSRS `.review` state (the
  `card.lapses` delta). The hard-word rule is unchanged (`lapseCount >= 6 && intervalDays < 21`).
- **D5 Quiz/listening:** `SRSEngine.practiceGrade(for:isDue:)` is unchanged. Free practice and the hard-words
  session still schedule words that are not due (FSRS early review; Open decision 6).
- **D6 SM-2 → FSRS conversion (`FSRSMigration.derive`, pure, deterministic):**
  1. `intervalDays == 0 && repetitions == 0 && lastReviewGradeRawValue == nil` → state **new**, S = D = 0,
     step 0, `lastReviewedAt` nil.
  2. Otherwise, if `intervalDays < 1` (Again-reset) → state **relearning** if `lapseCount > 0`, else
     **learning**; S = D = 0; step 0; `lastReviewedAt = min(now, dueDate − 600 s)`.
  3. Otherwise → state **review**:
     - `S = I` (port of fsrs-rs `memory_state_from_sm2` with SM-2 retention 0.9 = target);
     - `D = clamp(11 − (E − 1) / (e^w8 × S^(−w9) × (e^(0.1 × w10) − 1)), 1, 10)`, with w from defaultWv6;
     - `I = min(intervalDays, SRSEngine.maxLibraryIntervalDays)` and `E = easeFactor` (non-finite values fall
       back to 2.5 / 1);
     - `lastReviewedAt = min(now, dueDate − I × 86 400)`, step 0.

  The conversion never changes `dueDate`, `intervalDays`, `repetitions`, `lapseCount` or `easeFactor`, so
  no due date moves. Check: E 2.5, I 10 reviewed on time gives Good 25 d = I × E.
- **D7 When FSRS state counts as valid** (`FSRSMigration.isValid`): every FSRS field is present and in range.
  There is no consistency stamp, because no old clients exist. An invalid or missing state is derived from
  the SM-2 fields (D6).
- **D8 The conversion is local-only and runs in three places, always without dirtying rows:**
  - at launch, `FSRSMigration.migrate(in:)` runs after `ScheduleNormalizer` and writes the derived fields to
    active words without a valid state. It never touches `updatedAt` or `serverUpdatedAt`;
  - on pull, `SwiftDataSyncStore.apply` stores the remote FSRS block if it is valid, otherwise derives one,
    before `markSynced`;
  - in the engine, defensively, for any invalid state.

  Because the derivation depends only on synced fields, every device derives the same state. A word's next
  review pushes its FSRS columns.
- **D9 Every answer gets one log entry.**
  - Flashcard grades and due quiz/listening answers: `affectsSchedule = true`.
  - Quiz/listening answers that do not change the schedule (word not due, or a typed soft miss):
    `affectsSchedule = false`; `rating` is the grade it would have been (correct → good, wrong → again,
    soft miss → hard); the before and after fields are equal.
  - No synthetic history is created from SM-2 data.
- **D10 Log atomicity:** the entry is inserted into the same `ModelContext` and saved by the same
  `context.save()` as the word. If the save fails: `context.delete(entry)`, restore the full `SRSState`
  (including the FSRS fields), the knowledge fields and `updatedAt`, then rethrow. Nothing is published.
- **D11 Log entries are kept** when a word is soft-deleted or restored. Server rows cascade only on account
  deletion. There is no FK to `words`/`workspaces` (Open decision 10).
- **D12 Log sync is push-only for now (Open decision 9).**
  - Entries with `uploadedAt == nil` are sent ordered by `(reviewedAt, id)`, in batches of 200, as
    `INSERT … ON CONFLICT (user_id, id) DO NOTHING` (`ignoreDuplicates`, `returning: .minimal`).
  - A 2xx response marks the whole batch uploaded; a duplicate can only be our own row.
  - SQLSTATE 22/23 → the existing row-by-row isolation.
  - Pushed after memberships.
  - `prepareLink` resets `uploadedAt`. Adoption re-keys pending entries (D15).
  - The pull is deferred to the optimizer follow-up (nil-cursor backfill). The server already has the select
    policy and the keyset index.
- **D13 No capability bump and no forced re-pull.** With no old clients, server `fsrs_*` columns are only
  written by new builds:
  - rows that nobody has reviewed since the migration have null `fsrs_*`, and every device derives the same
    state from SM-2 (D8);
  - a review on any device bumps `updated_at` and arrives through the normal cursor with a valid block.

  So no device can miss real FSRS data, and critic finding 1 disappears.
- **D14 Import boundary:** only `MojSlownik/Services/Practice/FSRSScheduler.swift` may `import FSRS` in the
  app. In tests, only `MojSlownikTests/FSRSSchedulerTests.swift` may.
- **D16 Today's progress never goes backwards** (user answer to Open decision 2, option c). In
  `DailyStudyStore`, a word in today's `completedIDs` (or the legacy `quizCompletedIDs`) is exempt from
  "due" until the next local day:
  - `reviewWords(for:now:)` = `pendingIDs` ∪ (`dueDate <= now` and not in today's `completedIDs` ∪
    `quizCompletedIDs`). Today, only quiz completion exempts a due word; after this change, flashcard
    completion does too.
  - `progress(for:now:)`: completed = existing words in today's `completedIDs` that are not pending (drop
    the current `!dueIDs.contains` condition, because completed words are no longer in `dueIDs`);
    remaining = `reviewWords.count`.
  - Pending always wins, unchanged: "Не помню" or a wrong answer removes the completion and appends the word
    to `pendingIDs`. The flashcard session still re-appends "Не помню" words during their 10-minute step.
  - Effects:
    - a new session the same day does **not** offer a completed word (even if FSRS made it due 15 minutes
      later) unless it is pending;
    - "Continue · N" (TrainingView, from `progress.remaining`) and FlashcardsView's session queue (from
      `reviewWords`) follow automatically, with no view change;
    - free practice ("Practice up to ten random words") is unchanged.
  - Scheduling is unaffected. The word keeps its FSRS due date and shows up the next day as overdue; FSRS
    accounts for the elapsed time. The cost is that the 15-minute learning step after Hard is not shown on
    the same day.
- **D15 Adoption re-key:** when `applyWords` adopts a local unsynced word under a server id, every
  `ReviewLogEntry` with `wordID == oldID && uploadedAt == nil` gets `wordID = remote.id`, in the same save.
  Entries already uploaded are immutable and keep the old id.

## Acceptance criteria

- AC-1 Intervals and fixed captions:
  - every stored and previewed interval equals what swift-fsrs returns with `maximumInterval: 30`, with no
    own adjustment (so ≤ 32 d: Hard ≤ 30, Good ≤ 31, Easy ≤ 32);
  - previews equal what is stored;
  - Again is always 10 min;
  - a word that is new, or in learning/relearning with S = D = 0, shows 10 min / 15 min / 2 d / 8 d;
  - a relearning word with FSRS memory shows 10 min / 15 min, then days from its memory (e.g. 1 d / 2 d, or
    1 d / 1 d).
- AC-2 Ordering is exactly the library's:
  - review state: Hard < Good < Easy;
  - learning/relearning: Again < Hard < Good ≤ Easy (Good may equal Easy after a lapse).

  The preview equals what `apply` stores. ScheduleNormalizer never shortens a package-produced schedule
  (D2a).
- AC-3 After launch:
  - every active word has a valid FSRS state;
  - no word is deleted;
  - `dueDate`, `intervalDays`, `repetitions`, `easeFactor` and `lapseCount` are unchanged;
  - no row is dirty, and a second launch changes nothing.
- AC-4 Each flashcard grade and each quiz/listening answer persists exactly one complete `ReviewLogEntry`
  (D9). A failed save leaves no entry and restores every word field.
- AC-5 Quiz/listening scheduling rules are unchanged. Today's progress never goes backwards (D16):
  - a word answered correctly today stays completed, and is neither counted as remaining nor offered by a new
    session, until the next local day, even if FSRS makes it due earlier;
  - a "Не помню" or wrong answer keeps it pending and returns it in the session.
- AC-6 `lapseCount` grows only on Again from FSRS review state. It still syncs and still drives hard words.
- AC-7 The Progress card, forecast, hard-words row and folder "learned X of Y" show the same buckets as before
  for the same `intervalDays`/`repetitions`/grade data. After the upgrade, the ~98 synced words keep their
  counts and due dates.
- AC-8 Signed in:
  - log entries upload once (idempotent) and re-upload after a re-link;
  - pending entries follow an adopted word's id;
  - words push and pull `fsrs_*`;
  - a pulled row with null `fsrs_*` is derived and stays clean.
- AC-9 Server:
  - `review_logs` is owner-only (RLS `(select auth.uid()) = user_id`, WITH CHECK on INSERT);
  - only insert and select are granted (no anon access);
  - `updated_at` is server-assigned, and the CHECKs hold;
  - the `words.fsrs_*` columns are nullable or defaulted.
- AC-10 Build, copy and boundary:
  - the build has zero warnings;
  - `check-localization.sh` is clean: the FolderPicker footer key is replaced in en+ru (D2a), with no dead
    or missing keys;
  - the import boundary holds (D14 / user decision 7): app code reaches the package only through
    `FSRSScheduler`.

## Changes by file

### Package / project

1. `project.yml`:
   - add `FSRS: { url: https://github.com/open-spaced-repetition/swift-fsrs, exactVersion: 6.0.0 }` under
     `packages:`;
   - add `- package: FSRS` / `product: FSRS` to the `MojSlownik` target. If the test target fails to link
     `import FSRS`, add the same dependency to `MojSlownikTests`;
   - then run `xcodegen generate` and
     `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -resolvePackageDependencies`;
   - check that `MojSlownik.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` has
     `swift-fsrs` version `6.0.0`, revision `74cb02977ba94dd505aa2a13149238b5f5d48a1b`, and that the Supabase
     pins are unchanged;
   - commit `Package.resolved`, then build with `-onlyUsePackageVersionsFromResolvedFile`.

### Model

2. `MojSlownik/Models/Word.swift`: add after `lapseCount`:
   - `var fsrsStateRawValue: Int? = nil`
   - `var fsrsStability: Double? = nil`
   - `var fsrsDifficulty: Double? = nil`
   - `var fsrsLearningStep: Int = 0`
   - `var fsrsLastReviewedAt: Date? = nil`

   Mark `easeFactor` with a comment: "Legacy SM-2, no longer written; read by the FSRS conversion and the
   KnowledgeProgressService tier fallback".
   Change the section comment to "FSRS state + fields the app still reads (see SRSEngine)".
3. `MojSlownik/Models/ReviewLogEntry.swift` (new `@Model`; defaults where possible. A new entity needs
   none for migration, so `wordID`, `workspaceID`, `reviewedAt`, the raw values and the due dates are set by
   the init):
   - `id: UUID = UUID()`, `wordID: UUID`, `workspaceID: UUID`, `reviewedAt: Date`;
   - `ratingRawValue: String`, `modeRawValue: String`, `affectsSchedule: Bool = true`;
   - `elapsedDays: Double = 0`;
   - `intervalDaysBefore` / `intervalDaysAfter: Double = 0`, `dueBefore` / `dueAfter: Date`;
   - `stateBefore` / `stateAfter: Int = 0`, `stabilityBefore` / `stabilityAfter: Double = 0`,
     `difficultyBefore` / `difficultyAfter: Double = 0`;
   - `lastReviewedAtBefore: Date? = nil`, `uploadedAt: Date? = nil`.

   Add an init from `(wordID:workspaceID:mode:transition:affectsSchedule:reviewedAt:)`. There is no
   relationship to Word.
4. `MojSlownik/Models/AppSchema.swift`: append `ReviewLogEntry.self`.

### Services

5. `MojSlownik/Services/Practice/FSRSScheduler.swift` (new; the only app file that imports FSRS).
   Isolation: everything here is nonisolated (no `@MainActor`). `FSRSMemory` and `Outcome` are
   `Sendable`, and `FSRSScheduler` is a nonisolated `enum` whose static `FSRS` instance is Sendable.
   - `struct FSRSMemory: Equatable, Sendable { state: Int; stability: Double; difficulty: Double;
     learningStep: Int; lastReviewedAt: Date? }`.
   - Constants: `targetRetention = 0.9`, `maxIntervalDays = SRSEngine.maxScheduledIntervalDays`,
     `learningSteps = ["10m"]`, `relearningSteps = ["10m"]`. One private static `FSRS` instance (D1), and
     `static var weights`.
   - `struct Outcome: Equatable { memory; due; scheduledDays; lapses; elapsedDays }`.
   - `outcomes(memory:due:intervalDays:lapses:now:) -> [ReviewGrade: Outcome]`:
     - builds a `Card` with `lastReview` capped at `now`;
     - calls `try repeat`; if it throws, retries with S = D = 0 in the same state, then with a `.new` card
       (it never throws);
     - returns the package's due, scheduledDays and memory per grade unchanged (D1a: no clamp, no reordering).
   - `review(... grade:)`, `elapsedDays(since:now:)` (UTC start-of-day floor),
     `retrievability(memory:now:)`.
6. `MojSlownik/Services/Practice/FSRSMigration.swift` (new; `@MainActor enum`, mirrors ScheduleNormalizer).
   `derive`, `isValid`, `effective` and `migrated` are **`nonisolated static`**, because they are called from
   the nonisolated `RemoteRecordValidator` and `SRSEngine`. Only `migrate(in:now:)` and `run` stay
   main-actor:
   - `derive(from:now:)` (D6);
   - `isValid(_:)`: state 0…3; state 0 needs S = D = 0; states 1 and 3 allow S = D = 0, or S ≥ 0.001 with
     D in 1…10; state 2 needs S in 0.001…36 500 and D in 1…10; step 0…100;
   - `effective(_:now:)`, `migrated(_:now:) -> SRSState?`;
   - `migrate(in:now:) throws -> Int`: active words; one save; rollback on failure; never touches
     `updatedAt` or `serverUpdatedAt`;
   - `run(container:now:)`, which logs only the error type.
7. `MojSlownik/Services/Practice/SRSEngine.swift`:
   - `SRSState` gains `fsrsState: Int?, fsrsStability: Double?, fsrsDifficulty: Double?, fsrsLearningStep: Int,
     fsrsLastReviewedAt: Date?` (init defaults nil/0). `init(word:)` and `write(to:)` cover them.
     `easeFactor` stays in `SRSState` so the conversion and rollback can read it.
   - `struct ReviewTransition: Equatable { before, after: SRSState; beforeMemory, afterMemory: FSRSMemory;
     elapsedDays: Double }`.
   - `transition(_:from:now:)`: takes the effective memory, calls `FSRSScheduler.review`, then writes the D3
     fields, the lapse delta and the FSRS fields. It does not touch ease.
   - `next` = `transition(...).after`. `apply` and `preview` keep their signatures; `preview` returns
     `.minutes(round((due − now) / 60))` when the interval is 0, otherwise `.days(Int(interval))`.
   - `observation(_:from:now:)` and `wouldBeGrade(for:)`.
   - Remove the SM-2 formulas. Keep `minEaseFactor`, `maxEaseFactor` (still used by the sync validator),
     `maxIntervalDays`, `maxScheduledIntervalDays = 30` (the "setting", passed as `maximumInterval`), the new
     `maxLibraryIntervalDays = maxScheduledIntervalDays + 2` (D2a), `againDelay = 600` (a test checks it equals
     the 10m step) and `practiceGrade`.
8. `ScheduleNormalizer.swift`: its cap becomes `SRSEngine.maxLibraryIntervalDays` (32) instead of
   `maxScheduledIntervalDays` (D2a). The logic is otherwise unchanged, and the doc comment says it is a safety
   net that never shortens package-produced schedules.
9. `StudyProgress.swift`: doc comment only (`intervalDays` = the FSRS scheduled interval, up to 32 d).
9a. `MojSlownik/Views/Components/FolderPicker.swift:124` and `MojSlownik/Localizable.xcstrings`: replace the
    footer string with the D2a en+ru copy and delete the old key.
10. `MojSlownik/MojSlownikApp.swift`: call `FSRSMigration.run(container:now:)` after `ScheduleNormalizer.run`.

### Backend / sync

11. `MojSlownik/Backend/RemoteRecords.swift`:
    - `RemoteWordRecord` gets optional `fsrs_state`, `fsrs_stability`, `fsrs_difficulty`,
      `fsrs_learning_step` and `fsrs_last_review`. `ValidatedRemoteWord` gets `var fsrs: FSRSMemory? = nil`.
      The block is built only when it is complete and passes `isValid`, with `fsrs_last_review` (if present)
      in `earliestDate…now + allowedClockSkew`. A word's `due_date` far in the future (e.g. +20 d) does not
      affect the block. An invalid or absent block → nil, and the row is still accepted.
    - `RemoteWordUpsert`: the same keys, always encoded; `selectColumns` extended. `ease_factor` keeps being
      sent (the frozen value).
    - New `RemoteReviewLogInsert` (Encodable; every column of item 22 except `updated_at`), and the outgoing
      validator `validate(_ RemoteReviewLogInsert, ownerID:, now:)`:
      - owner and non-nil uuids, else `.invalidID`;
      - rating and mode known, else `.invalidSchedule`;
      - `reviewed_at` within `earliestDate…now + skew`, else `.invalidDate`;
      - due dates ≥ `earliestDate`;
      - finite numbers in range: elapsed and intervals 0…36 500, S 0…36 500, D 0…10, state 0…3.
12. `SyncRemote.swift`: add `func insertReviewLogs(_ rows: [RemoteReviewLogInsert]) async throws`.
13. `SupabaseSyncRemote.swift`: `reviewLogsTable = "review_logs"`. Use
    `.upsert(rows, onConflict: "user_id,id", returning: .minimal, ignoreDuplicates: true).execute()` with
    `classify` and an empty-input guard.
14. `SyncState.swift`: no change.
15. `SyncEngine.swift`: no capability bump (D13). Add `pushReviewLogs` last:
    `local.pendingReviewLogs(ownerID:now:)`, then the generic `push(kind: .reviewLogs)` with
    `send = { try await remote.insertReviewLogs($0); return $0.map { RemoteAck(id: $0.id, updatedAt: now()) } }`.
16. `SwiftDataSyncStore.swift`:
    - `SyncKind.reviewLogs`; `markPushed(.reviewLogs)` sets `uploadedAt`. The snapshot is `reviewedAt`.
    - `prepareLink` sets every entry's `uploadedAt = nil`.
    - `apply(_ remote: ValidatedRemoteWord, …)`: after the remote fields and the ScheduleNormalizer clamp,
      write `remote.fsrs` if it is non-nil, otherwise `FSRSMigration.migrated`. This runs before
      `markSynced`.
    - Adoption branch: `rekeyReviewLogs(word: oldID, to: remote.id, context:)` next to `rekeyMemberships`,
      using `#Predicate { $0.wordID == oldID && $0.uploadedAt == nil }`.
    - `pendingWords`: encode `FSRSMigration.effective`.
    - `pendingReviewLogs(ownerID:now:)`: `#Predicate { $0.uploadedAt == nil }`, sorted `(reviewedAt, id)`,
      validated; invalid rows are counted and stay local.
17. `UITestSyncRemote.swift` (`InMemorySyncRemote`): add `server.reviewLogs`, `insertedReviewLogBatches`, and
    `insertReviewLogs` (ignores duplicates; honours `enter` and the failure hooks). Word records round-trip
    `fsrs_*`.

### Stores

18. `MojSlownik/Stores/DailyStudyStore.swift`:
    - `review`: compute `transition`, write `after`, insert `ReviewLogEntry(mode: .flashcards, affectsSchedule:
      true)` if `word.uuid != nil`, then save. On failure, roll back as in D10.
    - `recordPracticeAnswer`: with a grade → `transition` (affects true); without → `observation(wouldBeGrade)`
      (affects false). The mode is the one passed in.
    - `reviewWords(for:now:)` and `progress(for:now:)` follow D16: today's `completedIDs` ∪
      `quizCompletedIDs` exempt a due word until the next local day; pending wins; completed = in today's
      `completedIDs` and not pending. `nextActivity` is unchanged. Update the doc comments on both methods.
    - No new AppLog event.

### Views

19. No other view changes. The only String Catalog change is the FolderPicker footer (item 9a).

### Fixtures

20. `UITestFixtures.swift` (`.studyProgress`): set the hard word's due date to exactly `now − 86 400`, so its
    captions are deterministic (10 min / 2 d / 3 d / 4 d).

### Supabase

The SQL follows the supabase-postgres-best-practices rules read for this plan: primary keys, data types,
constraints, upsert, RLS performance, FK indexes.

21. `supabase/migrations/20261123100000_words_fsrs_state.sql` (`begin; … commit;`, with a header on the
    security model). Add to `words`, each with a named CHECK and a `comment on column`:

    | Column | Type | Range / default |
    |---|---|---|
    | `fsrs_state` | `smallint` | 0…3 |
    | `fsrs_stability` | `double precision` | 0…36 500 |
    | `fsrs_difficulty` | `double precision` | 0…10 |
    | `fsrs_learning_step` | `integer not null default 0` | 0…100 |
    | `fsrs_last_review` | `timestamptz` | — |

    All are nullable except `fsrs_learning_step`, because existing rows have no FSRS state until their next
    review. Add a comment that `ease_factor` is legacy and frozen.
22. `supabase/migrations/20261123100100_review_logs.sql`:
    - Table `public.review_logs`, primary key `(user_id, id)`. Every column is `not null` except
      `last_reviewed_before`; range CHECKs follow item 11.

      | Column | Type / constraint |
      |---|---|
      | `id` | `uuid` |
      | `user_id` | `uuid default auth.uid() references auth.users (id) on delete cascade` |
      | `workspace_id`, `word_id` | `uuid` |
      | `reviewed_at` | `timestamptz`, ≥ 2020-01-01 |
      | `rating` | `text`, CHECK in again/hard/good/easy |
      | `mode` | `text`, CHECK in flashcards/quiz/listening |
      | `affects_schedule` | `boolean` |
      | `elapsed_days` | `double precision` |
      | `interval_days_before`, `interval_days_after` | `double precision` |
      | `due_before`, `due_after` | `timestamptz` |
      | `state_before`, `state_after` | `smallint` |
      | `stability_before`, `stability_after` | `double precision` |
      | `difficulty_before`, `difficulty_after` | `double precision` |
      | `last_reviewed_before` | `timestamptz`, nullable |
      | `updated_at` | `timestamptz default now()` |

    - Trigger `review_logs_set_server_updated_at`, reusing `private.set_server_updated_at()`.
    - Index `(user_id, updated_at, id)`, for the future pull. The PK covers the FK.
    - RLS: enable it; `revoke all … from anon, authenticated`; `grant select` and a column-level
      `grant insert (all columns except updated_at)` to authenticated.
    - Policies `review_logs_select_own` (using) and `review_logs_insert_own` (with check), both
      `(select auth.uid()) = user_id`. No update or delete grant or policy, no SECURITY DEFINER.
    - A growth comment: about 250 B per row, about 9 MB per year at heavy use.
23. `supabase/tests/words_fsrs_state.sql` (rolled back):
    - an insert without the fsrs columns gives nulls and step 0;
    - an update with values succeeds;
    - check violations: state 4, difficulty 11, stability −1, step −1;
    - user B sees nothing;
    - anon has no column privileges.
24. `supabase/tests/review_logs.sql` (rolled back):
    - `updated_at` is server-assigned with ms precision;
    - sending `updated_at` → `insufficient_privilege`;
    - a duplicate with `on conflict do nothing` leaves count 1;
    - update and delete → `insufficient_privilege`;
    - an insert with B's `user_id` → RLS violation;
    - B sees 0 rows;
    - check violations;
    - anon has no privileges;
    - the index exists.

### Docs

25. `docs/architecture.md`:
    - SRS section: FSRS-6 via swift-fsrs 6.0.0, reached only through FSRSScheduler/SRSEngine; D1, pure
      library intervals (≤ 32 d) and the ScheduleNormalizer bound (D1a/D2a); which SM-2 fields are
      still written and that ease is frozen; the conversion; the lapse rule; the log.
    - Sync section: `words.fsrs_*`, the push-only `review_logs`, the adoption re-key, that there is no
      backward compatibility with pre-FSRS builds, and the deploy order.
    - **Daily progress** paragraph (around line 144): any success today, from flashcards or quiz/listening,
      exempts the word from today's remaining practice until local midnight. That exemption now replaces
      the sentences "due status still overrides flashcard-only completion" and "a flashcard success returns
      the word to ordinary SRS-based due handling". Pending still wins. The "Не помню" re-append now
      happens during the 10-minute FSRS (re)learning step.
26. `AGENTS.md` Invariants, one line: "Only Services/Practice/FSRSScheduler.swift imports FSRS (in tests only
    MojSlownikTests/FSRSSchedulerTests.swift); scheduling goes through SRSEngine."

## Reuse

- Rollback and local-only patterns: `SRSState` rollback, ScheduleNormalizer and WordIdentityBackfill, and
  `rekeyMemberships`.
- Sync: `SyncEngine.push` (row isolation), `classify`, and the InMemorySyncRemote hooks.
- Database: the `private.set_server_updated_at()` trigger, the `app_logs` column-grant pattern, and the
  `words_lapse_count.sql` test pattern.
- Existing: caption keys, `ReviewGrade`, `PracticeMode`, `KnowledgeProgressService.similarity`, and the
  SaveFailureRestoreTests `allowsSave: false` container.

## Data compatibility

- **Local store:**
  - new Word properties are optional or defaulted, and `ReviewLogEntry` is a new entity, so the migration
    is lightweight and no words are lost;
  - the launch conversion fills FSRS state without dirtying rows or moving due dates.
- **Synced data:** the account's ~98 synced words pull with null `fsrs_*` and derive the same state on every
  device. Their first review pushes real FSRS columns.
- **Stopped writing:** `Word.easeFactor` / `words.ease_factor`, which keep their last SM-2 value. Nothing is
  removed.
- **Older builds:** not supported (user decision 5). Install the new build on every device.
- **Deploy order:**
  1. Apply both migrations to Supabase (needs separate user authorization).
  2. Run the security advisors.
  3. Install the build.

  If the migrations are missing, the words pull and the log insert fail as transient sync errors, and the
  app keeps working offline.

## Verification

Unit tests (MojSlownikUnitTests):

- `FSRSSchedulerTests.swift` (new; may `import FSRS`):
  - every D2 row as raw package output, including "Again from review, then 10 min later" (S 10 → 1 d / 2 d;
    S 3 → 1 d / 1 d) and "new word Hard, then 15 min later";
  - on-time E 2.5, I 25 → 30 / 31 / 32 d, with due = now + days × 86 400 (no own clamp);
  - for random inputs, the wrapper's outcomes equal a direct `FSRS.repeat` call (the wrapper adds nothing);
  - parameters (0.9, 30, defaultWv6, fuzz off, steps), and `againDelay` == the 10m step;
  - a last review after now does not throw;
  - corrupt memory falls back;
  - `elapsedDays` matches the package across UTC midnight;
  - retrievability at t = S ≈ 0.9.
- `SRSEngineTests.swift` (rewrite the SM-2 tests):
  - a library-ordering grid (states × intervals 0…32 × ease × elapsed):
    - review state: Hard < Good < Easy;
    - learning/relearning: Again < Hard < Good ≤ Easy;
    - every interval ≤ `maxLibraryIntervalDays`;
  - preview == apply;
  - the D3 fields, with ease untouched;
  - D4 lapses;
  - `practiceGrade` kept;
  - `wouldBeGrade`.
- `FSRSMigrationTests.swift` (new):
  - D6 branches (E 2.5, I 10 → S 10, D ≈ 6.914; E 1.3, I 1 → D 10);
  - SM-2 fields and due dates unchanged;
  - idempotent and deterministic;
  - `isValid` bounds;
  - no dirtying;
  - deleted words untouched;
  - normalizer followed by the conversion.
- `DailyStudyStoreTests.swift`:
  - one complete entry per answer: flashcards; due quiz → affects true; not due or soft miss → affects
    false, word unchanged, ratings good/again/hard; listening mode;
  - no uuid → no entry, save still happens;
  - **D16 pins:** a single new due word graded Hard at t0 (FSRS due t0 + 15 min) →
    - `progress(now: t0 + 16 min)` = 1 completed / 0 remaining;
    - `reviewWords(now: t0 + 16 min)` is empty, so a new same-day session does not offer it;
    - the next local day, it is due and remaining again;
    - a correct quiz answer behaves the same;
    - Again ("Не помню") at t0 → pending: in `reviewWords` at once and at t0 + 16 min, and counted as
      remaining;
    - Hard, then a wrong quiz answer the same day → pending again.
- **Existing tests to update:** search the tests for SM-2 interval and due expectations
  (`grep -rnE 'intervalDays|dueDate|easeFactor|SRSEngine\.(apply|next|preview)' MojSlownikTests MojSlownikUITests`)
  and update every assertion that encodes SM-2 values or the old "due overrides flashcard completion"
  semantics. Known places:
  - `DailyStudyStoreTests.swift:317` and `:347`: the entity set / schema list must include `ReviewLogEntry`;
  - `DailyStudyStoreTests.swift:204`, `:328-330` and `:413`: SM-2 interval/due assertions → FSRS values (D2);
  - `ListeningQuestionTests.swift:79-82`: Easy followed by Hard on a new word; still asserts only the grade,
    but recheck it against FSRS learning steps;
  - `SRSEngineTests.swift:58` and `:93`: cap assertions → `maxLibraryIntervalDays`. The rest of the file is
    rewritten above. Also update any `DailyStudyStoreTests` that expect a flashcard-completed word to be due
    again the same day;
  - `RemoteRecordValidatorTests.swift:99` (`testEveryLocalScheduleIsAccepted`): the expected interval
    becomes `SRSEngine.maxLibraryIntervalDays` (32, after repeated Easy), and the row is still accepted;
  - `SyncEngineTests.swift:224`: a pulled 400-day interval is clamped by `ScheduleNormalizer` (cap now 32);
    assert `local.intervalDays <= SRSEngine.maxLibraryIntervalDays` instead of `<= 30`. Also update the
    `SRSEngine.swift:86` doc comment that still says the schedule is clamped to `maxScheduledIntervalDays`;
  - `StudyProgressTests.swift:44-49` (`testLearnedCopyMatchesTheConstants`): see D2a;
  - `ScheduleNormalizerTests.swift`: thresholds move from 30 to 32. Add a case: a 31-day Good and a 32-day
    Easy schedule are left untouched.
- `SaveFailureRestoreTests.swift`: no `ReviewLogEntry` is left behind, and the FSRS fields are restored.
- `RemoteRecordValidatorTests.swift`:
  - fsrs block valid / missing / out of range → nil, with the row accepted;
  - **due = now + 20 d with a valid block is accepted with the block**;
  - `fsrs_last_review` later than now + skew → block nil;
  - each review-log validation error.
- `SwiftDataSyncStoreTests.swift`:
  - a pulled valid block is stored clean; a null block is derived clean;
  - `pendingWords` encodes FSRS and keeps the frozen ease;
  - **adoption re-keys only the `uploadedAt == nil` entries**;
  - `pendingReviewLogs`, `markPushed(.reviewLogs)`;
  - `prepareLink` resets `uploadedAt`.
- `SyncEngineTests.swift`:
  - logs pushed last, in batches of 200;
  - a lost ack followed by a retry is idempotent;
  - a rejected row is isolated;
  - two devices: A reviews and pushes `fsrs_*`, B pulls the same memory; an unreviewed word derives
    identically on both.
- `LegacySchemaMigrationTests.swift`: a frozen pre-FSRS store opens with every word intact, FSRS filled,
  rows clean and no log entries.
- `SourceHygieneTests.swift`: the D14 import boundary (user decision 7). No file other than
  `FSRSScheduler.swift` and `FSRSSchedulerTests.swift` contains `import FSRS`.
- `LocalizationCatalogTests` / `check-localization.sh`: the new footer key has en+ru, and the old key is
  gone.
- `UITestSupportTests.swift`: the hard word's due date is exactly now − 86 400.
- `ScheduleNormalizerTests.swift` and `StudyProgressTests.swift`: compile with the extended `SRSState`, and the
  buckets are unchanged.

E2E (MojSlownikE2E, affected classes only locally):

- `StudyProgressFlowTests.testHardWordsSessionShowsPillAndCaptions`: Hard → «Следующий показ через 2 дня».
- New `StudyProgressFlowTests.testNewWordCaptionsFollowFSRSSteps`:
  - launch `.studyProgress` and pick the folder «Урок 2» with the existing helper;
  - start flashcards and reveal the card;
  - check «через 10 минут / 15 минут / 2 дня / 8 дней».
- Also run `FlashcardsFlowTests`, `QuizFlowTests` and `SyncFlowTests`.

DB: `scripts/test-db.sh <empty Postgres URL>`, then the advisors after the authorized apply.

Build: `xcodegen generate`; a zero-warning build with `-onlyUsePackageVersionsFromResolvedFile`;
`check-localization.sh`; `check-secrets.sh`.

Manual (iPhone, after the migrations):
- after the upgrade, the word count, due count and Progress card are unchanged;
- the captions;
- `review_logs` rows appear in the dashboard.

## Risks

- **Scheduling feel changes** (Open decisions 3, 5, 6). The E2E tests pin the captions.
- **D16 hides same-day learning steps:** after Hard on a new word, the 15-minute step is not shown until
  the next day. FSRS accounts for the longer gap; this is the user's choice.
- **Package quirks are accepted as-is** (user decision 7): Good/Easy can reach 31/32 d despite the 30-day
  setting, and Easy can equal Good after a lapse. The ScheduleNormalizer bound (32) and the footer copy
  ("about a month") are aligned. The exact pin plus reference tests catch drift in a future package
  version.
- **UTC-day elapsed days:** only near local midnight. `reviewedAt` is stored for recomputation.
- **An old build left installed on a device:** it would ignore `fsrs_*` and overwrite schedules with SM-2.
  User decision 5 excludes this; reinstall every device.
- **Log growth:** unbounded, about 9 MB per year at heavy use. Retention is a follow-up.
- **Single-maintainer package:** it sits behind one facade file.
- **Migrations not applied before install:** sync errors until they are.

## Open decisions (all resolved 2026-11-23; see user decision 6). [UV] = user-visible.

1. FSRS version: **FSRS-6 `defaultWv6`** (default kept). [UV: interval values]
2. Today's progress: **option (c), "never goes backwards"** (user choice, D16). [UV]
3. Easy right after a lapse: **accept FSRS** (user choice). [UV]
4. Lapse semantics: **FSRS lapses** (default kept). [UV: the hard-word count can be slightly lower]
5. Step length: **10 min** (default kept). [UV]
6. Early reviews: **accept FSRS; intervals may shorten** (user choice). [UV]
7. Learned bucket: **`intervalDays >= 21`** (default kept).
8. Non-scheduling answers: **logged with `affects_schedule = false`** (default kept).
9. Review-log sync: **push-only** (default kept).
10. `review_logs` FKs: **only `auth.users`** (default kept).
11. `supabase/.temp/`: **add it to the root `.gitignore` in this change** (default kept).
12. Package fallback: **not needed**; the package is accepted.

## Follow-ups (not in this change)

- On-device optimizer, with the log pull/backfill. Interval fuzz, daily limits, log retention,
  retrievability in the UI.

## Revision log

- **Revision 2:** applies the critic findings, plus binding user decision 5 (not in production, breaking
  changes allowed).
  - **User decision 5 simplifications:**
    - removed the `fsrs_due_date` stamp and re-convert-on-pull for old clients (D7 is now validity only);
    - stopped writing `easeFactor` (nothing reads it after the conversion; property and column kept);
    - removed the mixed-version risk and the related Open decisions (old 7, 9, 11, 14);
    - the conversion still runs locally at launch and on pull for rows with null `fsrs_*`, so the ~98
      synced words keep their progress.
  1. Capability bump: dropped (D13). With no old clients, no device can have skipped real FSRS data. Null
     blocks derive deterministically, and reviewed rows arrive through the normal cursor. This is simpler
     than both the bump and a fill-only merge branch.
  2. Easy = Good after a lapse (probe: S 3 → 1 d / 1 d): added D1a step 2. Reworded AC-1 and AC-2. Added D2
     rows and the test "Again from review, then 10 min later". Added Open decision 3.
  3. Validator: only `fsrs_last_review` is bounded by now + skew. The `fsrs_due_date` column no longer exists.
     Added a test with due = now + 20 d.
  4. Adoption re-keys pending `ReviewLogEntry.wordID` (D15, item 16), with a test.
  5. The Hard-in-learning Today-progress regression is now Open decision 2. Computed the `["10m","1d"]`
     values. Recommend accepting it. Added a DailyStudyStoreTests pin at t0 + 16 min.
  6. Exempted `MojSlownikTests/FSRSSchedulerTests.swift` from the import rule (D14, AGENTS.md).
  7. Review-log pull deferred (push-only default, Open decision 9).
- **Revision 3 (final):** user answers recorded (user decision 6) and plan-reviewer findings applied.
  - Open decision 2 → option (c): added D16, updated AC-5, item 18, the docs Daily progress text and the
    DailyStudyStoreTests pins. A same-day session does not re-offer a completed word unless it is pending.
  - Open decisions 3 and 6 → accept FSRS. All other decisions keep their defaults.
  - Findings:
    1. `FSRSMigration` pure functions are `nonisolated static`; `FSRSScheduler`, `FSRSMemory` and `Outcome`
       are nonisolated and Sendable.
    2. Listed the existing tests to update, with a grep instruction.
    3. The `easeFactor` tier fallback is now noted in D3 and in the Word.swift comment.
    4. Cross-reference fixed (item 22).
    5. Package resolve and verification step added.
    6. ReviewLogEntry defaults wording fixed.
- **Revision 4:** user decision 7 recorded.
  - Removed the own 30-day post-clamp and the own "Easy ≥ Good + 1" rule; intervals are now pure library
    output (≤ 30/31/32 d).
  - Updated D1a, D2 (I 25/30 → 30/31/32; S 3 after a lapse → 1 d / 1 d), AC-1, AC-2 and the scheduler and
    engine tests (non-strict library-ordering grid; the wrapper equals a direct package call).
  - Package access only through FSRSScheduler, enforced by the hygiene test.
  - Knock-on effects (D2a):
    - new `maxLibraryIntervalDays = 32`;
    - ScheduleNormalizer cap aligned to 32, so it never shortens package schedules;
    - conversion input cap aligned to 32;
    - StudyProgress, forecast and the "Long memory" achievement unaffected;
    - FolderPicker footer copy changed in en+ru to "about a month", old key removed;
    - existing tests at SRSEngineTests:58/93, RemoteRecordValidatorTests:99, StudyProgressTests:44-49 and
      ScheduleNormalizerTests updated;
    - E2E captions unchanged.

## Approval

- 2026-11-23: approved by user (revision 4). Base 82ec829defb347bfe84c74d1f66fd6e70ee05d9a on branch feature/fsrs-review-log; pre-existing ` M MojSlownik/InfoPlist.xcstrings` and `?? supabase/.temp/` are not part of this task (the plan adds supabase/.temp/ to .gitignore).
