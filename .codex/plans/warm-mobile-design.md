# Warm mobile design refresh

## Goal
Make scanner results readable and quick to use, and dictionary categories easy to browse, while preserving the current quick-add behavior and iOS 17 compatibility.

## Scope and context
The working tree already contains quick-add/category/lowercase work. Preserve it. No persistence/schema/network changes are needed for this design task. Root base is 23e96ba; review against the pre-design working state as well as HEAD to avoid attributing earlier work to this refresh.

## Acceptance criteria
- AC-1: Recognized source is a naturally wrapping paragraph with original punctuation/spacing, normal readable foreground, and no link underlines. An explicit edit action still lets users choose a word for AddWordView.
- AC-2: Word cards are compact, original and translation have distinct visual hierarchy, save action is clear, and saved state remains legible with a checkmark/text rather than only color.
- AC-3: Category is a single native Menu affordance inside each card, with category name and chevron. Remove duplicate category text and external “change category” link. Category selection never accidentally triggers save.
- AC-4: Dictionary filtering moves outside vocabulary rows into a horizontal category strip, with All and current-category selection visibly and accessibly distinguished. Existing search and swipe-delete behavior remain correct.
- AC-5: Shared palette is warm cream/terracotta in light mode and warm dark neutrals with lighter terracotta in dark mode. Body text uses primary/secondary roles; accent is reserved for actions/selection. Dynamic Type wraps without clipping, and controls keep sufficient hit areas.
- AC-6: Quick-add, deduplication, retries, explicit save errors, lowercase persistence and serialized translation/cancellation remain unchanged. Existing records and SRS remain unchanged.
- AC-7: Simulator build succeeds; no E2E/UI automation is created, updated or run.

## Changes by file
1. Theme/Theme.swift: replace cool indigo with a dark readable terracotta and lighter dark-mode variant; cream canvas and warm surface/dark surface; warmer secondary text. Add only shared tokens actually used by multiple views. Reduce broad shadows in cardStyle for a calmer hierarchy.
2. Views/ScannerView.swift sourceCard: render Text(scannedText), preserving source punctuation and natural wrapping. Replace per-token link styling with an explicit edit Menu selecting a word and setting existing selectedWord. This reuses AddWordView and existing task pause logic. A context menu on word cards is also acceptable if discoverable, but keep an explicit correction affordance.
3. Views/ScannerView.swift wordChips: compact consistent card layout using natural wrapping or adaptive grid; keep save Button and category Menu as siblings, never nested controls. Save button contains original + translation and small plus/check indicator. Show selected category once as a capsule/row with chevron; keep a minimum 44-point hit area. Maintain loading, retry and save-error states. Saved cards keep normal text contrast; only save is disabled, not an enclosing container that dims category UI.
4. Views/WordListView.swift: use VStack(category strip, List), with horizontal ScrollView and selected pills outside List. Keep ForEach onDelete attached to actual filtered rows and preserve snapshot deletion. Expose selected accessibility traits. Row label/spacing can be refined within existing hierarchy, with no behavior change.
5. Views/Components/PronounceButton.swift only if required: retain warm accent via Theme and add accessible name/minimum hit target if touched. No new asset or dependency.
6. docs/architecture.md: update scanner presentation description and category browsing only if its existing wording becomes stale.

## Reuse
Theme, cardStyle, WordCategory, existing Menu/SwiftUI controls, AddWordView selectedWord sheet, save/translation functions. No custom text engine, image generation, new design framework or new test target.

## Risks and safeguards
- Category selection must stay independent of save, and remain possible where current flow permits. Native Menu sibling avoids nested Button interactions.
- A plain source paragraph removes inline hit targets: preserve correction through explicitly labeled Menu/action with word options.
- Compact appearance must not mean tiny targets: use 44-point hit areas, Dynamic Type fonts and wrapping. At accessibility sizes use one column if a grid is chosen.
- Horizontal filters need selected traits and meaningful labels, and must not alter deletion offsets.
- Palette has global impact on training/add screens; inspect all uses of appAccent and surface/text tokens, especially white text on accent backgrounds and dark mode.

## Verification
Build with existing scheme and installed iPhone simulator; do not run xcodebuild test. Run git diff --check. Review actual scanner/list/theme diff for quality and UI accessibility; data reviewer only if persistence/data behavior changes. Manual checklist to report honestly: source punctuation/readability, card save and category menu independence, saved state, long translations/large text, light/dark, category filtering + search + deletion, correction sheet resume. OCR requires a physical iPhone. No new logic tests are necessary for presentation-only changes unless behavior changes emerge.

## Open questions
None required: screenshots and user request establish intended direction. Terracotta/cream is the proposed warm treatment; preserve standard native interaction behavior.
