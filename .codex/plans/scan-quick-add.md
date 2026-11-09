# Scan quick-add and categories

Base: 23e96ba553b1483eb6c9ffbebafbadba1815d5cd. Initial working tree clean.

## Goal
After scanning a line, display original words and translations in chips. One tap on a ready chip persists the pair without presenting AddWordView. Words have useful persistent categories visible in the dictionary.

## Category decision
User chose automatic categorization per word. Implement a local keyword topic classifier over source and translated text with a transparent Other fallback; allow editing the assigned category. This is a bounded heuristic, not semantic AI classification. No remote classifier or new dependency. Categories are one stored string per Word. Existing records default to Other (Другое).

## Acceptance criteria
- AC-1: Each unique selectable scanned word has a chip with original and opposite-language translation; show individual loading/error/retry states and never save empty translations.
- AC-2: Tapping a ready chip immediately saves a correctly oriented Russian/Polish Word; no add modal. Show saved feedback. Repeated taps and repeated tokens cannot create duplicate pairs.
- AC-3: Each translated chip receives a local automatic topic category, editable before saving; new pairs persist that category. Existing records survive migration with Other; already-saved words retain their category unless explicitly edited.
- AC-4: Dictionary exposes category labels and filtering so categories are usable; manual AddWordView can assign a category too.
- AC-5: Sentence translation and inline word correction remain available. Dismissing a correction sheet preserves scan results. Word preload and sentence translation never compete for AppleTranslationModel's single pending continuation.
- AC-6: Closing the result cancels translation work; failures can be retried; explicit persistence failures are reported rather than labeled saved.
- AC-7: iOS 17 build succeeds; no E2E/XCUITest/Playwright creation, changes or execution.

## Minimal changes
1. Models/Word.swift: add categoryRawValue with declaration-level default «Другое» for lightweight migration and a computed WordCategory property. Initializer accepts an optional category; nil automatically classifies the pair. No Category @Model or relationship.
2. Services/scan helper only if needed: pure local keyword topic classification, canonicalization/category normalization and pair lookup shared by scan persistence, with assert-based checks. Compare trimmed locale-aware case-insensitive strings while preserving Polish diacritics. Reuse ScannedTextTokenizer and Translator.
3. Views/ScannerView.swift: retain inline words as correction path; replace chip tap modal with quick add. Store unique chip state keyed by normalized source, use a serial task to translate sentence then words (or words then sentence), never parallel requests through Apple bridge. Cache success within result view; use task cancellation checks before updates. Source direction is detected per word with LanguageDetector. Chip states pending/ready/failed/saved; retry only a failed word and serialize retry work with preload. Use @Query or current context fetch to detect existing pairs, modelContext.insert and explicit save; delete only the newly inserted object on save failure, never rollback unrelated work. Classify from original and translation when ready, show the category and allow changing it; capture that chip category at tap. Loading chips disabled, failed chips retry, saved chips inert. VoiceOver includes original, translation and state; Dynamic Type can wrap.
4. Views/AddWordView.swift: category field/picker defaulting to automatic detection, pass to initializer. Avoid scope creep into general word editing.
5. Views/WordListView.swift: derive available categories from records, category selector and row label; combine existing search with category filter and meaningful empty-results view. Preserve stable delete snapshot.
6. docs/architecture.md: update quick-add flow, categories, serial translation and persistence behavior. AGENTS.md only if always-needed rule changes.

## Reuse
Existing Translator fallback/error semantics, LanguageDetector orientation, tokenizer, Word, SwiftData model context, Theme and FlowLayout. No backend, package or translation protocol change. No global Apple queue required if scan work is serialized and add-sheet presentation suspends/cancels scan translation until dismissal.

## Risks and safeguards
- AddWordView's own task currently is not canceled on disappear: suspend scan queue while correction sheet is presented and cancel correction task on disappear to prevent cross-view Apple requests.
- Existing single Apple pending request can be canceled by concurrent callers; serial scan translation is mandatory, including retries.
- SwiftData lightweight migration requires declaration-level default; preserve all SRS fields and existing data. Verify a legacy store migration if feasible; do not claim a build proves migration.
- Bulk per-word network translation can be slow/rate limited; show incremental progress and bounded serial requests, cache per unique word, no invisible saving while loading.
- Category string normalization should prevent whitespace/case duplicates in picker without destroying existing labels.
- Source currently has unusual FlowLayout brace/identifier nesting in sourceCard; only adjust if necessary for changed section, avoid unrelated rewrites.

## Verification
Read available Xcode/simulator tools. If files added, xcodegen generate. Build app with installed iPhone simulator and DEVELOPER_DIR if needed; no xcodebuild test because scheme includes UI tests. Run focused pure-logic assertions for canonicalization/orientation/duplicates when helpers added. If SwiftData available, verify old schema store opens and records/SRS survive plus category defaults in isolated temporary store. Review plan before implementation, then quality/UI/data review against actual diff. Manual checklist: ru/pl line, repeated words/taps, retry offline, automatic topics, Other fallback, category editing and filtering, correction sheet lifecycle, dismiss during loading, old vocabulary and flashcards. OCR remains physical-device only; report manual checks not performed.
