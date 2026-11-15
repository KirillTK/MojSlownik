# Scanner selection UX revision

## Goal

Replace the precision-heavy freehand lasso with easy selection of OCR text blocks (“bubbles”). Let users select one or more blocks, revise that selection before translating, and keep the whole-frame translation and freeze/retake actions. Reduce the stacked scanner controls so they cover substantially less of the camera image.

## Baseline before this revision

Before this revision, `ScannerScreen` reused live OCR bounds after capture. The revised flow must stop and remove the scanner as soon as `capturePhoto()` returns, show only the still image, and run Vision text recognition on that exact UIImage. Map normalized Vision bounds to the full-screen image viewport before creating bubbles. `WordListView` continues to pass selected text through the existing `onPick` route into `ScanResultView`.

## Recommended interaction

- In live mode, keep the current line tap and freeze action. After the still is captured, remove the live scanner view and run OCR on the captured UIImage itself; show block selection only after this still-image analysis completes.
- Group frozen OCR lines into nearby visual text blocks using view-coordinate bounds, line spacing, and horizontal overlap, with a three-line maximum per bubble so a dense page cannot collapse into one selectable block. Render each block as a light, tappable outline/highlight (“bubble”) over the captured image; avoid opaque text cards that obscure the source.
- Tap a bubble to select it; tap again to remove it. Multiple blocks can be combined. Keep selected bubbles visibly accented.
- Show a compact selection count and a clear “Перевести выбранное” action. Users revise the selected region by toggling bubbles; a separate movable/resizable rectangle is unnecessary. Do not retain the lasso.
- Keep “Перевести всё” and retake as compact secondary actions. Do not show the tall stack of four large controls.
- Replace the vertical stack with one compact translucent bottom action bar: selected-block translation as the primary button, whole-frame translation and freeze/retake as compact secondary icon/text actions. Move the instructional copy into a small dismissible/short top hint or a compact status label. Respect safe area and 44-point touch targets; collapse secondary controls responsively at accessibility text sizes rather than covering half the view.

## Acceptance criteria

- **AC-1:** In live mode, users can tap a recognized line or freeze the frame. After freezing, nearby OCR lines appear as tappable, visually bounded text blocks aligned with recognized content.
- **AC-2:** Users can select multiple blocks with taps and remove any selected block before translation; the selected block count makes the current selection clear.
- **AC-3:** “Перевести выбранное” passes selected block transcripts in reading order, joined with line breaks, into the existing result route. Empty selection disables the action or provides a clear hint.
- **AC-4:** “Перевести всё” continues to translate all current recognized text, and tapping a recognized line while live continues to translate that line.
- **AC-5:** Freeze captures a transient frame, stops and removes the live scanner, and recognizes text from the captured UIImage. Retake clears the frozen state and resumes the live camera. No photo is persisted.
- **AC-6:** Scanner action controls occupy a compact bottom area instead of a tall stack; overlays do not block most of the view. VoiceOver labels, Dynamic Type behavior, and minimum touch targets remain usable.
- **AC-7:** Existing `ScanResultView` translation, word chips, saving, and persistence behavior remains intact.

## Files and implementation scope

- `MojSlownik/Views/ScannerView.swift`: replace lasso with bubble selection on the full-screen captured image, OCR results from that image, selected block IDs, selection count, and compact adaptive controls. Remove the live scanner branch after capture. Preserve retake, live tap-to-pick, permission handling, and `onPick(String)`.
- `MojSlownik/Services/ScannedTextTokenizer.swift`: add still-image `VNRecognizeTextRequest` and map normalized Vision bounds through the image's aspect-fill crop into viewport coordinates. Keep pure helpers for block grouping (maximum three OCR lines per bubble), stable member-ID selection, reading order, and text joining. Preserve the existing tokenizer API.
- `MojSlownikTests/ScannedTextTokenizerTests.swift`: cover grouping nearby lines, splitting dense continuous text into selectable blocks, separating columns/paragraphs, stable block IDs across reordered snapshots, selection toggling/joining, and normalized Vision bounds mapped through aspect-fill. Keep tests deterministic with synthetic rectangles and fixed UUIDs.
- `docs/architecture.md`: describe bubble/block selection, multi-select, compact controls, freeze/retake, and existing translation route; remove the obsolete closed-contour description.
- `MojSlownik/Views/WordListView.swift`: no change expected; only adjust if concrete presentation behavior requires it.

## Reuse

Use VisionKit `capturePhoto()` and Vision `VNRecognizeTextRequest` on the resulting still image; do not save the image to Photos or disk or add a translation service. Reuse the existing `onPick` presentation path and `ScanResultView`, which handles paragraph translation, unique word translations, chips, and word saving. Preserve ru/pl recognition and iOS 17 support.

## Verification after approval

- Add and run the committed unit tests using the isolated `MojSlownikUnitTests` scheme.
- Build `MojSlownik` for an installed iPhone Simulator; run `xcodegen generate` only if a source file or `project.yml` is added/changed.
- Review the final diff with the feature-flow quality and SwiftUI reviewers.
- On a physical iPhone, verify still-image OCR and alignment, grouping, selecting/toggling several blocks, translation order/content, whole-frame translation, live line tap, freeze, retake, and persistence of the result while opening/dismissing AddWord. Test VoiceOver and larger text where feasible. OCR/alignment cannot be fully verified in Simulator.
- Do not create or run E2E/UI automation.

## Risks and assumptions

- OCR rectangle grouping can merge adjacent paragraphs or split irregular layouts. Start with deterministic vertical-gap plus horizontal-overlap heuristics and a three-line cap per bubble; tune using real-device samples without persisting image data.
- Still-image OCR returns normalized Vision rectangles with a bottom-left origin. Convert to top-left image coordinates, account for UIImage orientation, then apply the same aspect-fill scale and centered crop used by the full-screen SwiftUI image. Verify alignment on device because capture and preview framing may differ slightly.
- Block selection runs only against OCR computed from the frozen still, so observation UUIDs remain stable while the user selects. Derive each block ID from its sorted member observation IDs so identical transcript blocks remain distinct; test that an unchanged OCR result preserves selection across state recomputation.
- Compact controls still need to remain readable at accessibility text sizes; adaptive layout may use a compact second row only when needed.
- Product recommendation: no movable/resizable selection rectangle. With selectable blocks and toggle-to-edit, users can correct the selection directly and the UI is simpler.
- No unresolved product decisions: preserve the currently implemented freeze/retake option and whole-text action, but present them compactly.
