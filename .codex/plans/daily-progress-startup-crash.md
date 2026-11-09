# Register SwiftData before restoring daily progress

## Goal and baseline
Fix the reported launch fatal error: PersistentIdentifier cannot decode Word without a registered data container. Base HEAD e453180; preserve all uncommitted Lilac UI changes and its plan/docs. No reset, schema migration, ID-format change, commit/push or UI/E2E automation.

## Cause
MojSlownikApp eagerly initializes @State DailyStudyStore before its body installs .modelContainer(for:). DailyStudyStore decodes Codable PersistentIdentifiers from UserDefaults immediately. This fatal error is not throwable, so try? cannot protect it. Existing tests construct a container first and mask application ordering.

## Acceptance criteria
- AC-1: Construct and retain the Word + WordFolder ModelContainer before decoding daily identifiers; inject that exact container into the scene.
- AC-2: Preserve vocabulary, folders, SRS, completion/pending IDs, answer counts, equality-array matching and v1 compatibility.
- AC-3: Startup/preview entry points never restore persisted identifiers before schema registration; previews use isolated data/defaults.
- AC-4: Add repository regression coverage through the exact production bootstrap path, including disk-store reopen and saved progress restoration.
- AC-5: App build and MojSlownikUnitTests pass; no UI automation or unrelated Lilac edits.

## Implementation and files
MojSlownik/MojSlownikApp.swift: explicitly create ModelContainer(for: Word.self, WordFolder.self), then initialize daily store, retain both and inject .modelContainer(container). Use a tiny internal AppResources value in this existing file to unit-test the exact production path. It owns only container and store, creates them in order and accepts isolated configuration/defaults/time for testing. Avoid generic factory orchestration or test-only ordering observers. App constructs resources first, initializes State from resources.dailyStudy and injects resources.container, retaining the default persistent store location.

MojSlownikTests/DailyStudyStoreTests.swift or a focused startup test file: isolated disk-store/defaults regression. Preview blocks in RootTabView, TrainingView, FlashcardsView and QuizView use the same AppResources.preview helper with an in-memory container and isolated preview defaults, injecting its container and dailyStudy. Container creation always precedes restoration; previews never read standard user defaults. docs/architecture.md: record container-before-progress startup ordering. DailyStudyStore only if explicit container dependency is selected; preserve codec and equality behavior.

Reuse Word/WordFolder schema, DailyStudyStore, SwiftData and XCTest. Do not decode private PID JSON, add model UUIDs, clear defaults/vocabulary or recreate an empty data store.

## Regression strategy
Seed a temporary disk-backed store, save words plus successful/pending daily answers, release initial resources, then recreate through production bootstrap using same URL/defaults. Assert both entity types registered, vocabulary/SRS preserved and progress/answer totals restored. Retain existing empty/corrupt/legacy activity tests. Run targeted startup test then full isolated suite.
XCTest may retain prior global registration, so do not claim in-process reopen is a true cold-process reproduction. Source review must verify startup ordering, and physical-device cold launch remains a manual check.

## Verification and risks
Run xcodegen generate if adding source/test files. Build MojSlownik; test MojSlownikUnitTests only on available iPhone simulator, previously iPhone17Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D. Run git diff --check. Known Xcode AppIntents tooling warning is separate. Quality/data review required; UI review only if preview/UI setup changes beyond dependency initialization.
Container creation may fail independently: preserve existing failure policy without deleting/recreating storage. No unresolved user decision.

## Planning evidence
Read AGENTS, app root, DailyStudyStore, unit tests and all store/container call sites. No app edits, builds, tests, manual launch or UI checks performed.

## Implementation and verification results
Implemented ordered AppResources in existing MojSlownikApp.swift, retaining the default ModelContainer configuration/location and injecting the exact instance. DailyStudyStore initializer now runs after container construction. Four preview blocks use the shared ordered memory/isolated-defaults resources. No schema, codec, SRS or Lilac UI behavior changes. Added two tests in existing DailyStudyStoreTests.swift; no new source/test file, so XcodeGen regeneration not needed.

Verification on iPhone 17 Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D:
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived build: passed. Log /private/tmp/moj-startup-build.log.
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived -parallel-testing-enabled NO test: all 61 tests passed, zero failures. Log /private/tmp/moj-startup-tests.log.
- git diff --check: passed. Plan, data and quality source reviews: no findings. No source compiler warnings/errors; known AppIntents metadata extractor tooling warning remains.

Disk-backed production-bootstrap tests verify vocabulary, folder, SRS and daily completed/pending/statistics persistence. In-process tests do not prove a fresh process with no globally registered schema. Physical iPhone cold launch is not performed; manual follow-up is to install updated build, fully close/open twice with saved activity, verify dictionary/folders and partial quiz or flashcard progress after reopen. Existing ru/pl input/editable translation/save and physical OCR checks were not performed by this bugfix; no UI/E2E automation or commits.
