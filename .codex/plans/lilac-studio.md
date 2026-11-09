# Lilac Studio across the app

## Goal and baseline
Implement the user-selected Lilac Studio (variant A) visual language across Dictionary, Practice, Add Word, scanning/results, flashcards, quiz/results and folder selection. Base HEAD: `e453180`; working tree clean. Preserve prior daily-progress/quiz fixes. This is a presentation refresh, not a data or scheduling change. Earlier authorization to commit was fulfilled by the base commit; do not commit or push this work without new authorization.

## Design and constraints
Use warm pearl `#FBFAF7`, dark ink `#241D35`, violet actions near `#7046C5`, pale lavender `#EEE7F8`, with readable dark equivalents. Sans typography, consistent titles and spacing, open lists and fine dividers rather than an outlined card around every element. Keep accent for actions/selection; normal text remains dark ink. Use semantic success/error text+icons, not color alone. Native SwiftUI, two tabs only, iOS 17+, Dynamic Type, VoiceOver and Reduce Motion. No new UI dependency, assets, achievements, schema/API changes or UI/E2E automation.

## Acceptance criteria
- AC-1: Shared light/dark colors and surface treatment express Lilac Studio with readable foreground/on-accent roles; all main screens use the same type, spacing and icon language.
- AC-2: Practice replaces the 196-point ring and greeting paragraphs with a compact Today panel: completed/total, thin progress bar, concise remaining state and check/error count badges. Separate attempt counts from unique words. Keep folder-scoped real progress, day/clock refresh, no-vocabulary/no-due/complete/partial states and free practice. No decorative achievement preview.
- AC-3: Dictionary keeps search, folder/category filtering, counts, swipe deletion, camera/add entry and folder actions. Use compact folder selection, word-first rows and quieter metadata; category and folder stay distinct concepts.
- AC-4: Add Word, scan results, flashcards and quiz/results receive deliberate layout changes beyond global recoloring: clear content/actions, restrained surfaces and consistent compact headers. Keep word/translation input before metadata; preserve editable translations and visible loading/error/save states.
- AC-5: All tappable controls keep at least 44-point areas. Long words and large text wrap; badge/header/control rows adapt vertically. Pronunciation stays a sibling of reveal/save buttons. State remains clear without color. Camera overlay uses readable material; unavailable-camera state remains readable.
- AC-6: All data behavior remains: stable quiz source IDs, immediate answer persistence and counts, pending retries, SRS save/restore, folder membership, translation/cancellation, OCR correction sheet and saved state. Keep current quiz pacing.
- AC-7: Build and full isolated unit suite pass; inspect changes through quality/UI review. Add repository tests only if nontrivial behavior changes emerge; do not mirror static styling with tests.

## Files and ownership
Worker 1 owns `Theme/Theme.swift`, `Views/TrainingView.swift`, `Views/WordListView.swift`, `Views/Components/FolderPicker.swift`, `Views/RootTabView.swift`. Update palette/card roles; build compact practice layout with real progress/badges; quiet dictionary hierarchy; make shared folder control compact while retaining current sheet/create/error behavior. Use the same Russian tab/page name `Практика` if renaming the entry. Do not place interactive folder control inside another button or hide error text.

Worker 2 owns `Views/AddWordView.swift`, `Views/ScannerView.swift`, `Views/FlashcardsView.swift`, `Views/QuizView.swift`, `Views/Components/SessionProgress.swift`. Refine forms, source/translation hierarchy, scan word cards, explicit reveal and ratings, quiz options/result actions and compact session header. Changes below presentation helpers must be avoided; preserve all existing actions/task lifecycle and scanner toggle semantics. Keep physical camera preview native.

Parent owns `docs/architecture.md` presentation documentation and integration. Writers are not alone; preserve concurrent changes and keep writes disjoint. Reuse Theme/cardStyle, FolderPicker, SessionProgress, PronounceButton, CategoryMenu, errorAlert and all existing stores/services. Avoid adding files unless a genuinely reused helper is necessary.

## Verification
Run `xcodegen generate` only if adding source files or changing project.yml. Select an installed simulator; previously iPhone 17 Pro `BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D` was available. Build MojSlownik, test MojSlownikUnitTests only (full suite, expected 59 current tests), and run git diff --check. The base had a known Xcode AppIntents metadata extractor tooling warning; distinguish it from source warnings, do not add fake framework imports or suppress diagnostics. No app UI-test scheme, UI automation or E2E.

Source plan/quality/UI reviews required. Data review is necessary if persistence/SRS/translation flow changes accidentally enter the diff; otherwise confirm no such change. Manual checks, report honestly: ru/pl input, editable translation/save, filtering/folders, partial quiz then Back/relaunch, flashcard ratings, light/dark, long words, large text, VoiceOver/Reduce Motion. Physical iPhone OCR: scan line, translation, word/chip selection and preserved result after dismissing Add Word. No manual checks have been performed by planning.

## Risks and decisions
Direction is selected; no material unresolved user decision. Compact must not mean tiny hit targets or hidden metadata actions. Global palette affects native controls and scanner status styling. Do not present historical attempt statistics as unique pending words. Generated concept text/data is illustrative, not authoritative copy or filter behavior.

## Planning evidence
Read AGENTS.md and current WordList, FolderPicker, Scanner/result structure, SessionProgress, RootTab and inherited current Training/Theme source. No application files changed, builds/tests/UI checks run by planner.

## Implementation and verification results
Implemented Lilac Studio across all main screens and shared controls. No models, stores, services, tests or project configuration changed. Action/translation/scheduling function bodies remain unchanged; no new nontrivial logic was introduced. Existing unit tests are the verification rather than tests mirroring styling. No new source files, so XcodeGen regeneration was unnecessary. No commits or pushes.

Quality review: no findings. UI review found a P2 unbounded compact folder name in the dictionary horizontal strip; fixed with bounded text/control widths, two-line wrapping and preserved 44-point target/full accessibility label. Second UI review confirmed resolved, no findings. Parent checked source diffs and shared palette contrast: all measured text-role pairs exceed 5.16:1 in light/dark appearances. This is a color calculation, not rendered UI validation.

Verification on iPhone 17 Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D:
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived build: passed; final build repeated after folder sizing fix, passed. Logs /private/tmp/moj-lilac-build.log and /private/tmp/moj-lilac-final-build.log.
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived -parallel-testing-enabled NO test: 59 tests, zero failures. Log /private/tmp/moj-lilac-tests.log. The later folder-only sizing fix was validated by final app build and source re-review; logic tests were not repeated for that styling change.
- git diff --check: passed. No source compiler warnings/errors; known Xcode AppIntents metadata-extractor warning remains, not suppressed.

No rendered/manual UI, VoiceOver, physical-camera or OCR checks performed. Manual checklist remains: ru/pl input and editable translation/save; dictionary folder/category/search/deletion; partial quiz then Back/relaunch and flashcard ratings; light/dark and large text/long folder names; on physical iPhone scan line, translation, word/chip selection and preserved scan result after closing Add Word. No UI/E2E automation created, changed or run.
