# Quiz answers in daily study progress

## Goal and baseline
Save each quiz answer immediately so partial sessions survive Back/relaunch and both practice modes contribute to the daily ring. Base HEAD: `c77cdb828e2e221e20e69380c03ff739de74ee47`. Preserve the existing Sage work: app root, Theme, Add Word, SessionProgress, Flashcards, RootTab, Training, WordList, architecture, DailyStudyStore/tests and the two existing plans are already dirty/untracked. Do not attribute those earlier changes to this fix.

## Constraints and model
Keep iOS 17, Russian copy, current Sage presentation, existing Word records and the SRS algorithm. No Word migration, dependencies, achievements, commit/push or UI/E2E automation. Quiz results affect daily practice only; they do not set a word permanently learned or change its SRS fields.

Extend DailyStudyStore's existing local-day activity with a quiz-success ID set and answer events (saved word ID plus correctness) for daily counts. New fields must decode as empty when reading the existing v1 payload; retain its storage key and previous completion/pending IDs. Optional Codable fields or explicit decodeIfPresent are sufficient. Do not invent historical answer counts for older activity.

For each scoped, existing word: latest wrong answer in either mode removes all successful completion/exemption and adds pending; quiz success clears pending and adds today's quiz success; flashcard success clears pending and quiz exemption, then uses its existing saved SRS/completion behavior. Pending always wins. A current quiz success exempts the word from daily remaining work even if its unchanged SRS dueDate is past. Clear that exemption at local midnight. Ring completion is unique IDs, while attempts/correct/errors count every saved answer. Existing due precedence remains for flashcard-only completions.

Prefer a separate pure scoped statistics(for:now:) result alongside the existing Summary so progress equality/callers stay simple. Both read paths ignore stale local days and deleted/out-of-scope words. Keep encoding-before-publish and flashcard save-before-count behavior.

## Acceptance criteria
- AC-1: A correct quiz answer immediately changes the daily ring; leaving mid-session or recreating the store preserves it.
- AC-2: A wrong answer immediately persists as pending. Later correct answers clear it; later wrong answers reopen it across either mode.
- AC-3: Duplicate successes do not inflate unique completed words; answer totals/correct/errors still count attempts and remain folder-scoped.
- AC-4: Existing v1 activity decodes without losing completion/pending state. Day rollover clears all daily fields. Quiz never changes SRS fields.
- AC-5: Each generated QuizQuestion carries its saved source PersistentIdentifier. Submission guards duplicate taps, persists before feedback/score, and reports save errors without accepting an unsaved answer. Cancelling auto-advance on disappearance must not lose the already saved answer or permit stale delayed mutation.
- AC-6: Training shows daily answer/correct/error counts, with accessible wrapping text; empty states do not claim no activity after wrong answers. Progress/session labels reflect accepted answers.
- AC-7: Committed repository unit tests cover the regression and transitions; app build and isolated unit suite succeed. No UI/E2E tests run.

## Changes and reuse
- `Stores/DailyStudyStore.swift`: backward-compatible daily fields, quiz recording, shared outcome transitions and scoped answer statistics; preserve current SRS review save handling.
- `Views/QuizView.swift`: shared store environment, stable question source ID, immediate guarded persistence, errorAlert, cancellable advance and preview injection. Retain the current 0.9-second pacing unless cancellation correctness requires restructuring.
- `Views/TrainingView.swift`: scoped statistics under progress; adjust activity-empty wording and VoiceOver label only as needed.
- `MojSlownikTests/DailyStudyStoreTests.swift`: partial answer/reload, mixed outcomes, duplicates, cross-mode transitions, legacy payload decode, local-day reset, folder/deletion scope and unchanged SRS checks.
- Existing quiz/folder tests: verify generated source IDs identify the actual prompt word and belong to the selected scope. Add a small new focused test file only if it keeps test ownership clearer.
- `docs/architecture.md`: replace the obsolete statement that quiz does not affect daily progress; distinguish daily activity from SRS.

Reuse DailyStudyStore, Theme, SessionProgress, errorAlert, FolderStore filtering and the current app-scoped injection. Data/test implementer owns store/tests/docs; UI implementer owns Quiz/Training. Preserve concurrent work.

## Verification and risks
Run xcodegen generate only if adding source/test files. Build `MojSlownik`, then test `MojSlownikUnitTests` only on an installed iPhone simulator (previously available iPhone 17 Pro, BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D). Run git diff --check. Source reviews: plan, quality, UI and data. Existing Xcode AppIntents extractor warning was observed in the prior task; do not add a fake framework or suppress unrelated warnings.

Manual checks to report honestly: answer several quiz questions correctly/incorrectly, immediately go Back, verify ring/statistics, reopen/relaunch, retry a failed word, repeat a successful word, change folder; also smoke-check ru/pl input, editable translation/save, flashcards and quiz. Physical-device OCR checks remain separate and unavailable unless actually performed.

Main risks are stale dueDate overriding quiz success, lost v1 activity during decoding, one answer being counted twice, delayed tasks firing after exit, and confusing mistakes (attempts) with unique pending words. Use explicit labels such as "Ответов", "Верных", "Ошибок" and keep "Осталось повторить" for unique remaining words. No material user decision remains.

## Planning evidence
Read AGENTS.md and current DailyStudyStore, Quiz, Training, existing daily tests and relevant architecture references. Planning only: no app edits, build, tests or manual UI checks performed.

## Implementation and verification
Implemented immediate quiz answer recording, source word IDs, shared unique-word progress, scoped answer totals, cancellation-safe auto advance, compatible daily-data decoding and five new regression tests. Updated architecture. The user subsequently authorized committing the combined Sage and quiz changes; the later lilac request is research/concepts only.

The first full isolated unit run executed 59 tests and reported seven assertions failing in daily-progress reload cases; the other 46 tests passed. Diagnostics confirmed decoded PersistentIdentifier values compare equal to live IDs but can hash differently on this runtime. Persisted ID collections now use equality-based arrays with the same legacy JSON array representation; live IDs may still use sets. Temporary diagnostics were removed and reload-duplicate coverage strengthened.

After the fix, all 13 DailyStudyStoreTests passed using MojSlownikUnitTests with -only-testing:MojSlownikTests/DailyStudyStoreTests on iPhone 17 Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D; this also rebuilt the modified app/tests successfully. Logs: /private/tmp/moj-quiz-fixed.log. Earlier app build passed (/private/tmp/moj-quiz-build.log). Known Xcode AppIntents metadata tooling warning remains; no source compiler errors. git diff --check passed. Plan, quality, UI and data source reviews completed; UI caption finding was fixed and rechecked. Full 59-test suite was not repeated after the targeted fix because the five-hour usage window reached 95%; no new work waves were launched. No manual UI/device/OCR checks or UI/E2E tests ran.
