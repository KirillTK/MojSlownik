# Dictionary header and category labels

## Goal and baseline
Fix screenshot-confirmed dictionary layout: category labels split inside a word and scan/add sit above the large title. Base HEAD e453180; preserve uncommitted Lilac and startup fixes. Presentation only, WordListView scope. No data/filtering/membership/save/schema/SRS changes, commit/push or UI/E2E automation.

## Acceptance criteria
- AC-1: «Словарь», scan and add share one native navigation-bar row; inline title and trailing scan/add group. Selected-folder deletion remains available and accessible.
- AC-2: Category labels such as «Другое» stay on one line at ordinary sizes, with natural label width rather than compression to the trailing controls' minimum width.
- AC-3: Long categories and vocabulary do not push each other offscreen. Fall back to a stacked word/actions layout when the natural horizontal row cannot fit. Preserve full VoiceOver labels and 44-point targets at large text sizes; truncate a constrained category label instead of mid-word wrapping if necessary.
- AC-4: Search, filters, category changes, pronunciation, membership menus, swipe deletion and presentation handlers retain behavior.
- AC-5: Build and existing isolated unit suite pass; no tests mirroring styling or UI automation.

## Files and reuse
WordListView.swift only: inline navigation title; existing scan/add Buttons in a trailing ToolbarItemGroup, preserving labels/handlers. Keep folder deletion available without placing it between scan and add.

Refine private WordRow presentation. Prefer natural-width single-line category plus a width-aware fallback (ViewThatFits or less constrained metadata placement) over high layout priority alone that squeezes vocabulary. Current accessibility-size-only AnyLayout misses normal-size narrow rows containing category/folder/pronunciation. Reuse CategoryMenu, PronounceButton, Theme and bindings/actions; no shared component API change. Parent updates architecture only if its description becomes inaccurate.

## Verification and risks
Run git diff --check, build MojSlownik and test MojSlownikUnitTests only on an installed iPhone simulator (last iPhone 17 Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D; expected 61 tests). No new source files, so XcodeGen not expected. Known AppIntents extractor tooling warning is separate.

Source review checks regular/accessibility layouts, «Еда и напитки»/«Работа и учёба», long translations and selected-folder state. Manual device/rendered checks remain unperformed unless actually done. Check scan/add destinations and folder deletion preserving vocabulary. No unresolved user decision.

## Planning evidence
Read AGENTS.md, WordListView and CategoryMenu. Only this plan written; no app edits, builds, tests or UI checks run.

## Implementation and results
Changed only WordListView.swift relative to the pre-task source captured at /private/tmp/moj-dictionary-layout-before.swift. Title now inline with scan/add in a trailing ToolbarItemGroup; folder deletion remains available on the leading side. WordRow uses natural-width horizontal fit measurement with a stacked fallback for narrow/long content and accessibility sizes; category label is one line with tail truncation, full VoiceOver label and 44-point target. Existing bindings and handlers retained. No new source files or behavior logic, no XcodeGen/new styling tests needed. Prior Lilac/startup edits preserved; no commit/push.

Validation on iPhone 17 Pro BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D:
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived build: passed. Log /private/tmp/moj-dictionary-layout-build.log. Known AppIntents metadata extractor tooling warning remains; no source compiler errors.
- xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,id=BB6497BE-CFF7-4D85-9787-67DFCFF4AA4D' -derivedDataPath /private/tmp/moj-sage-derived -parallel-testing-enabled NO test: all61 tests passed, zero failures. Log /private/tmp/moj-dictionary-layout-tests.log.
- git diff --check passed; plan, UI and quality source reviews: no findings.

Rendered/device checks not performed. Manual follow-up: ordinary and large text with long category/word/translation, category/folder filters and selection, pronunciation/membership/swipe-delete, scan and add destinations, selected-folder deletion preserving words. Existing ru/pl editable translation/save, flashcards/quiz and physical iPhone OCR checks not performed here. No UI/E2E automation created, changed or run.
