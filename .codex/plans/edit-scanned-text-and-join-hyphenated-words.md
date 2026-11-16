# Edit scanned text and join hyphenated words

## Goal

After opening a scan result, let the user correct the recognized source text before
translation and saving. Automatically join a word split at the end of an OCR line
by a hyphen plus line break (for example, `przy-
klad` becomes `przykład`).

## Constraints

- Keep iOS 17 compatibility and the existing Vision/OCR capture flow.
- The captured image and OCR lines remain transient; do not persist scan text or
  images.
- Reuse the existing scan-result translation and tokenizer flow. No UI/E2E tests
  may be created, changed, or run.
- Preserve punctuation and ordinary compound-word hyphens; only remove ASCII
  hyphen-minus (`-`) or soft hyphen (U+00AD) when it is immediately followed by
  a supported line separator and another letter. En/em dashes remain untouched.
- The edited text, rather than the immutable scan input, must drive paragraph
  translation, selectable-word chips, manual correction, and retry identity.

## Acceptance criteria

- **AC-1:** A scan result shows the recognized source text in an editable,
  multiline control, so a user can fix OCR mistakes before using its translation
  or word cards.
- **AC-2:** On initial result presentation, a Unicode letter + (`-` or U+00AD)
  + `\\n`/`\\r\\n` + Unicode letter sequence is joined into one word; surrounding
  line breaks and punctuation are otherwise retained.
- **AC-3:** The normalization never removes hyphens from same-line compound words
  (for example, `biało-czerwony`) or from text where a hyphen is not the direct
  end-of-line marker.
- **AC-4:** Changing the source text debounces a replacement request and
  cancels/invalidates the previous one with an explicit revision token. Every
  asynchronous state write, including loading-state cleanup, must verify that
  token. The edit clears stale paragraph and per-word results/errors plus
  `savedOverrides`, `categoryOverrides`, and `saveErrors`; it retains only the
  selected destination folder. Chips are rebuilt from the current text.
- **AC-5:** The existing retry, word correction sheet, folder selection,
  quick-add/remove, Dynamic Type layout, and cancellation when the result closes
  continue to behave correctly.
- **AC-6:** Focused XCTest coverage proves the normalization for Polish/Russian
  letter cases, ASCII and soft-hyphen joining, CRLF support, normal compound
  hyphens, excluded en/em dashes, and nonmatching/newline-preserving cases. A
  controllable delayed translator proves an older request cannot replace the
  result or loading state after an edit.

## Implementation plan

1. In `MojSlownik/Services/ScannedTextTokenizer.swift`, add a narrowly scoped
   text-normalization API next to OCR tokenization. It will join only a Unicode
   letter + ASCII/soft hyphen + LF/CRLF + Unicode letter; tokenization continues
   to preserve punctuation and ordinary hyphens.
2. Extract the debounced, revision-guarded scan translation lifecycle into a small
   testable draft/store under `MojSlownik/Stores/`. Inject its translator in unit
   tests, cancel its task on deinitialization/dismissal, and require its active
   revision before any loading, result, or error write. It will retain paragraph
   and word translation state for the current source only, and translate serially
   to respect Apple Translation's single-pending-request constraint.
3. In `MojSlownik/Views/ScannerView.swift`, initialize that draft from normalized
   scan text and replace the read-only source paragraph with the project-styled
   multiline editor and accessible label/hint. On every edit, clear card-specific
   optimistic/error/category state, retain the folder selection, debounce the
   draft, and derive chips, correction menu, language detection, and displayed
   source from the current draft text.
4. Extend `MojSlownikTests/ScannedTextTokenizerTests.swift` with deterministic
   normalizer tests. Add a focused draft/store test file patterned after
   `AddWordDraftTests.swift`, using delayed continuations to prove stale success,
   failure, and loading cleanup cannot overwrite a newer edit. Leave UI-test
   targets untouched.
5. Update the scanning paragraph in `docs/architecture.md` to document editable
   post-scan text and the deliberately limited end-of-line hyphenation cleanup.

## Relevant files

- `MojSlownik/Views/ScannerView.swift` — editable result UI and translation state.
- `MojSlownik/Services/ScannedTextTokenizer.swift` — pure cleanup helper.
- `MojSlownikTests/ScannedTextTokenizerTests.swift` — regression/unit coverage.
- `MojSlownik/Stores/ScanResultDraft.swift` — testable debounced translation
  lifecycle (new).
- `MojSlownikTests/ScanResultDraftTests.swift` — stale-request regression
  coverage (new).
- `docs/architecture.md` — resulting OCR-flow behavior.

## Verification

- Run `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,name=iPhone 16' test`.
- Run `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=iPhone 16' build`.
- Manual physical-iPhone check (not automated): scan text containing an end-of-line
  hyphenated Polish word; confirm it is joined, edit a character, confirm the
  paragraph and chip translations reflect the edit, and check a same-line compound
  remains hyphenated. While a translation is visibly loading, edit the source and
  confirm no result/chip/loading state from the former text returns. Also perform
  the existing scan checks for line translation, chip/word selection, and
  scan-result persistence after dismissing `AddWordView`.

## Risks and decisions

- OCR geometry and reading order can make a genuine printed hyphen look like a
  line-wrap hyphen. The exact limited character/separator rule reduces that risk;
  users retain an editable field to restore it when context is ambiguous.
- Editing while translation is in flight needs debouncing and revision-guarded
  loading/result/error writes, because cancellation cannot stop every provider
  request already in progress.
- No additional persisted model data or migration is needed.

## Unresolved decisions

- None material. The implementation should recognize the common Unicode hyphen
  forms actually emitted by Vision while deliberately excluding punctuation that
  does not represent a hyphenation marker.
