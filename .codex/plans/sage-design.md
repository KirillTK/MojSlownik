# Sage design and understandable review progress

## Task and baseline
Implement the user-selected Sage concept: linen surfaces, muted sage actions, clear circular review progress and quiet native hierarchy. Achievements are deferred. Base HEAD: c77cdb828e2e221e20e69380c03ff739de74ee47. Preserve pre-existing modern-ui-ux-options.md and all concurrent work. Do not commit/push, modify Word schema/SRS, add dependencies, change quiz pacing or create/change/run UI/E2E automation.

## Progress semantics
One shared observable DailyStudyStore persists a local-calendar-day bucket and completed/pending Set<PersistentIdentifier> values in UserDefaults using Codable; inject defaults, time and calendar for tests. Non-again grades add a completed ID once and clear its pending ID; again removes completion and adds a pending ID. Pending IDs keep forgotten words in the remaining workload while SRS schedules their next dueDate ten minutes ahead. Apply SRS and successfully save SwiftData before updating the daily ledger; never show a completed review whose data save failed.

For currently existing words in selected folder: remaining = union of currently due IDs and today’s pending IDs within scope; completed = stored successful IDs intersect scoped IDs minus remaining IDs; total = completed + remaining. Remaining work overrides old completion. Flashcards starts from DailyStudyStore.reviewWords using this same pending-plus-due set, preserving the existing up-to-ten random-word fallback when none remain. Deleted/out-of-folder words do not inflate progress. New due words may grow workload; this is not a fixed goal or knowledge percentage. Quiz does not alter the ledger. Zero-total ring is neutral, not100%; existing words still allow up-to-ten random free-practice words. Calendar-day rollover and foreground refresh must remove stale completions; refresh clock-based due changes as well as data changes. Persist only saved stable identifiers.

## Acceptance criteria
- AC-1: Sage light/dark Theme, readable charcoal/linen/sage and on-accent text, restrained borders, sans typography, no new UI kit.
- AC-2: Training circle shows completed/total and remaining explicitly, primary review/free-practice action and correct no-vocabulary/no-due/completed states. All progress and library metrics match selected folder.
- AC-3: Persisted progress deduplicates success, handles again, deletion/membership, due words and local-day boundaries without schema migration. Quiz/SRS semantics remain.
- AC-4: Dictionary keeps words dominant with calmer metadata/filters. Add Word prioritizes input/translation over folder/category while retaining editable translations and save behavior.
- AC-5: SessionProgress describes completed responses without off-by-one; Flashcards respects Reduce Motion, supports accessible reveal and larger-text grade layout. Do not nest PronounceButton inside another Button.
- AC-6: Repository unit tests cover nontrivial state, app builds without warnings, isolated unit tests pass, no UI automation runs.

## Files and ownership
Data implementer owns new Stores/DailyStudyStore.swift, MojSlownikTests/DailyStudyStoreTests.swift, MojSlownikApp.swift injection, FlashcardsView.swift integration/save/feedback/motion/adaptive ratings and docs/architecture.md progress semantics. UI implementer owns Theme/Theme.swift, TrainingView.swift, WordListView.swift, AddWordView.swift and Components/SessionProgress.swift. Keep writes disjoint and accommodate concurrent changes. Update previews that require shared store injection. Reuse FolderPicker, PronounceButton, SessionProgress, Theme and native SwiftUI. No Word migration or new tab/achievement system.

## Verification
Run xcodegen generate after new files. Build MojSlownik without warnings and test MojSlownikUnitTests only, with installed iPhone 17 Pro/iOS26.5 or another available iPhone. Use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer as needed. Run git diff --check. Required read-only plan, quality, UI and data reviewers inspect this task diff/new files; fix confirmed findings and rerun affected checks.

Test persistence/recreation, duplicate successful review, again retaining pending workload despite its ten-minute future dueDate, pending persistence and clearing after success, selected-folder scope and membership changes, deleted/new due words, due overriding completed, zero work, local-day rollover/DST and failed-save protection where practical. Existing tests remain.

Manual checklist, report only checks performed: ru/pl input, editable translation/save, folders/categories/search, partial review then return/relaunch, grades and dueDate, quiz, light/dark, long text/large text, VoiceOver, Reduce Motion. Physical iPhone OCR: line translation, text/chip selection and preserved scan after dismissing Add Word. No manual checks are claimed by this plan.

## Risks and open decisions
Sage is selected, no material design decision remains. Live workload can grow; avoid claiming a fixed daily target or permanent learning. UserDefaults progress is local presentation state, not authoritative SRS history. Shared Theme also affects scanner/quiz. Ensure saved stable model IDs and successful model save before ledger update. Unavailable device checks must be disclosed.

## Planning verification
Read AGENTS.md, app root, Training, Flashcards, folder store and training tests. Planner only writes this plan; no app build/tests/UI checks performed.

## Final implementation and verification
Implementation is complete. DailyStudyStore and eight new unit tests implement the completed/pending daily ledger; Sage theme, Training ring/actions, dictionary hierarchy, input-first Add Word and accessible session feedback are integrated. The parent also injected the store into RootTabView’s preview. Existing stored words, schema and SRS algorithm remain intact. No commits or pushes.

- `xcodegen generate`: passed.
- `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived build`: passed on iPhone 17 Pro.
- `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived -parallel-testing-enabled NO test`: passed, 54 tests, zero failures, including eight new DailyStudyStore tests.
- Source compilation produced no warnings or errors. Xcode emitted its AppIntents extractor tooling warning, “Metadata extraction skipped, no AppIntents.framework dependency found”, for targets. It was not suppressed and no unused framework was added.
- Logs: `/private/tmp/moj-sage-build.log` and `/private/tmp/moj-sage-tests.log`.
- Plan, quality, UI and data reviews: no findings. `git diff --check`: passed.

Limitations: no manual UI, physical-device or OCR checks were performed; no UI tests or E2E were run. The SRS save-failure restoration path was reviewed but not exercised with an injected persistence failure.
