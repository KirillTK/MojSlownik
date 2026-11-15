# Knowledge tier badge

## Goal

Add one reusable SwiftUI badge showing a saved word's knowledge tier, and use it in dictionary rows and the scan-result word chips.

## Acceptance criteria

- AC-1: A shared `KnowledgeTierBadge` component accepts a `Word` and its resolved knowledge level, and renders a compact visual-only indicator (no visible word/number label). Each tier has a distinct Theme color and a corresponding filled/unfilled mark pattern.
- AC-2: Dictionary rows place the badge above the word, aligned to its upper right, without disrupting folder/category actions, narrow layouts, or accessibility Dynamic Type.
- AC-3: Scan-result chips display the same badge above the scanned word at upper right only when it matches a word already saved in the dictionary. New scanned words have no badge.
- AC-4: The visual-only component has a VoiceOver accessibility label that identifies the word and knowledge level; the level remains perceivable without relying on color alone.
- AC-5: Flashcards, quiz, and listening practice show the current word's knowledge tier without revealing hidden answers in audio/listening modes or disrupting response controls.
- AC-6: In practice screens, place the badge above the word at upper right; in audio-only prompts, position it in the prompt card without showing the answer text.
- AC-7: Existing save/remove actions, category menu, scanner selection, and practice answer flows remain unchanged.
- AC-8: Add unit tests for all four visual indicator states, their VoiceOver level descriptions, and legacy tier resolution. Verify saved-word-only scanner display and placement above words in practice during manual checks; do not add UI automation or extract private view logic solely for testing.

## Relevant files

- `MojSlownik/Views/Components/KnowledgeTierBadge.swift` (new): reusable label/presentation component.
- `MojSlownik/Views/WordListView.swift`: show badge for each saved word row.
- `MojSlownik/Views/ScannerView.swift`: show same badge when the scanned token matches a saved word.
- `MojSlownik/Views/FlashcardsView.swift`, `QuizView.swift`, `ListeningPracticeView.swift`: show the tier for the active word, placing it where the answer remains hidden until reveal/response.
- `MojSlownikTests/KnowledgeTierBadgeTests.swift` (new): verify tier-to-indicator mapping, accessibility descriptions and legacy tier resolution.
- `docs/architecture.md`: document shared badge presentation if useful.
- `.codex/plans/knowledge-tier-badge.md`: task record.

## Reuse and constraints

Resolve legacy/default tiers through `KnowledgeProgressService.tier(for:)`; do not duplicate tier derivation in views. Keep the component presentational, reuse `Theme` colors, keep copy in Russian, support iOS 17 and Dynamic Type, and do not change persistence or the confidence model. New scan candidates without a saved `Word` remain unbadged until they are saved and acquire a confidence level.

## Verification

- Run `xcodegen generate` after adding the component file.
- Build `MojSlownik` and run only the isolated `MojSlownikUnitTests` scheme on an available iPhone simulator.
- Manual UI checks: inspect visual badges above/right of words in dictionary rows and all three practice modes at regular and accessibility text sizes; confirm listening prompts remain hidden and VoiceOver announces the word/tier; scan text containing a saved word and a new word; confirm only the saved word shows its tier, and chip add/category actions still work.
- Run the new badge unit tests with the isolated `MojSlownikUnitTests` scheme.
- No E2E, XCUITest, or UI automation changes.

## Risks and unresolved decisions

- Scan chips without a saved `Word` have no confidence value. This plan intentionally hides the badge for those new candidates instead of assigning a default level that could misrepresent knowledge. If the desired behavior is a visible “Новое” state, revise the plan before implementation.
