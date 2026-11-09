# Modern UI/UX options

## Task and baseline
The user requests modern design options, UI/UX best practices, and advice on component kits and animation. This pass is a source-based audit and a concrete proposal; the visual direction is unresolved, so it does not implement a redesign.

Starting HEAD: `c77cdb828e2e221e20e69380c03ff739de74ee47`. Working tree was clean. Existing warm cream/terracotta styling and the earlier `warm-mobile-design.md` are the baseline, not new work.

## Constraints and reuse
- Preserve iOS 17+, Russian interface copy, existing SwiftData vocabulary and SRS, shared folder store, editable translations and OCR correction/save behavior.
- Reuse SwiftUI native navigation, sheets, menus, SF Symbols, `Theme`, `cardStyle`, `FolderPicker`, `PronounceButton` and `SessionProgress`.
- No third-party UI dependency is justified by the current request. UIKit is Apple's existing platform framework, not an additional design kit to install. A Figma kit can help mockups but is not a runtime requirement.
- No app edits, schema changes, commits, pushes, E2E or UI automation in this discovery pass. Preserve all other changes.

## Acceptance criteria for this pass
- AC-1: Present three distinct, feasible directions with tradeoffs and a recommended default.
- AC-2: Ground prioritized improvements in current source rather than claiming a visual/device audit.
- AC-3: Explain useful motion and accessibility requirements, and distinguish existing animation from proposed work.
- AC-4: Identify a small first implementation slice and the remaining material design choice.
- AC-5: Record verification and limitations honestly; no build is required for this document-only change.

## Directions
1. **Native clarity:** system-oriented surfaces and typography, compact hierarchy, familiar menus and sheets. Lowest visual maintenance; limited visual personality.
2. **Warm editorial (recommended):** refine existing cream/terracotta/olive identity, clearer type and spacing, fewer equally prominent cards, quiet native interactions. Builds on existing Theme and avoids throwing away the previous refresh.
3. **Study coach:** more prominent today's review action, progress and celebratory feedback, friendly rounded typography. More motivational but may increase clutter; daily goals/streaks would require separate product and data decisions and are not part of a cosmetic pass.

## Evidence and prioritized proposal
### First: clarify actions and state
- `Views/TrainingView.swift:24-34` describes zero due words as "Пока нечего повторять", while `Views/FlashcardsView.swift:38-43` actually starts up to ten random words. Distinguish "Повторить N слов" from optional free practice using existing behavior. Make the next recommended action more prominent than the statistics.
- `Views/WordListView.swift:31-49` shows folder and category filters but the no-results text mentions only category/query. Show the active scope and an actionable reset; avoid implying an empty selected folder is a failed search. Keep folder and category concepts distinct.
- `Views/AddWordView.swift:33-37` puts folder selection ahead of word input. Consider word/translation as primary, with folder/category secondary, while keeping destination visible and editable. Preserve auto translation and manual correction.
- `Views/ScannerView.swift:239-257` turns a saved word into a deletion action. Make destructive consequences explicit and consider undo as a separate scoped behavior change with regression coverage. Do not silently change dictionary deletion into folder removal or vice versa.

### Then: visual consistency and accessibility
- `Theme/Theme.swift` already defines light/dark warm tokens and a reusable card style; refine shared spacing, text roles and control hierarchy before adding components.
- `Views/WordListView.swift:193-240` combines bilingual text, category menu, folder menu and sound. Keep vocabulary dominant and secondary actions visually quieter without hiding essential actions behind unexplained gestures.
- `Views/FlashcardsView.swift:54-62,100` uses an `onTapGesture` and a 360-degree card rotation. Prefer a clearly announced button action for reveal, with a restrained transition and an explicit Reduce Motion branch. The only current animation calls are in this screen; no Reduce Motion handling was found.
- `Views/FlashcardsView.swift:104-120` places all rating buttons in one horizontal row. Provide an adaptive arrangement for large text rather than shrinking labels. Validate quiz and statistics at accessibility sizes as well.
- `Views/QuizView.swift:105-113` advances after 0.9 seconds. Consider an explicit "Дальше" action so users have time to read the correction; this is an interaction change needing regression tests, not merely animation.
- Validate 44-point targets, VoiceOver action names/order and selected/saved/answer states conveyed by text/icons as well as color. Several existing controls already satisfy these patterns; do not claim they are universally missing.

### Motion, last
Use short state-linked feedback for save/checkmark, answer reveal and progress; optional light haptics for confirmed actions. Respect Reduce Motion, avoid delaying actions, and avoid animated lists that shift under the user's finger. No animation library is needed for these SwiftUI interactions.

## Proposed changes by file after direction selection
1. `Theme/Theme.swift`: shared visual tokens actually reused across screens; keep light/dark support.
2. `Views/TrainingView.swift`: primary review/free-practice hierarchy and accurate empty-due copy.
3. `Views/WordListView.swift`: clearer active filters/no-results action, calmer row hierarchy.
4. `Views/AddWordView.swift`: word/translation first, secondary metadata and explicit save/loading/error hierarchy.
5. `Views/FlashcardsView.swift`, `Views/QuizView.swift`: accessible reveal/rating layout, restrained motion; quiz pacing only if selected for scope.
6. `Views/ScannerView.swift`: consistent typography/state visuals; undo/deletion changes only as a separate tested slice.
7. `Views/Components/*`: adjust existing shared components only when multiple screens need it.
8. Unit tests: repository tests for any changed nontrivial behavior. `docs/architecture.md`: update only if implemented flows change.

## Small first slice
Refine the warm direction on Training and Dictionary first, including actual zero-due behavior, filter clarity, typography and shared spacing. Review these representative screens before expanding the same language to Add Word, scanning and practice. Do not add streaks, a new tab, a custom navigation framework or a dependency without a specific need.

## Future implementation verification
- Run `xcodegen generate` if adding sources or changing `project.yml`.
- Build the app without warnings on an installed iPhone simulator.
- Add/run committed unit tests for changed nontrivial logic using `MojSlownikUnitTests` only.
- Manual checks: Russian/Polish input, editable translations/save, folder/category/search/reset, ratings updating due dates, quiz reading time, light/dark, long words, large text, VoiceOver and Reduce Motion. No UI automation.
- Physical iPhone only: scan a line, translation, word/chip selection, correction sheet dismissal preserving scan results.

## Risks and unresolved decisions
- Choose Native clarity, Warm editorial, or Study coach; Warm editorial is the proposed default.
- Source inspection establishes structure, not actual rendered usability or measured contrast. Device/simulator visual validation has not been performed.
- Avoid hardcoding today's OS appearance or relying on newer APIs without availability fallbacks on iOS 17.
- Treat quiz pacing and destructive-action undo as separate behavior changes, preserving SRS and persistence semantics and adding regression coverage if implemented.

## Checks performed
Read relevant screens, shared components, Theme, AGENTS.md and the earlier design plan. Documentation-only changes; app build, unit tests, manual UI checks and physical-device OCR were not run.
