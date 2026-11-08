# Mój Słownik Architecture

Personal ru ↔ pl dictionary for iPhone, using SwiftUI and SwiftData on iOS 17+.
No backend, accounts or synchronization. Vocabulary is stored locally; web
translation sends entered or recognized text to an external service.

## Application Map

Paths below are relative to `MojSlownik/` unless stated otherwise.

| Area | Files and responsibilities |
| --- | --- |
| Startup | `MojSlownikApp.swift` creates `ModelContainer(for: Word.self)` and `RootTabView`. |
| Navigation | `Views/RootTabView.swift`: Dictionary and Training tabs, root `AppleTranslationHost`. |
| Persistence | `Models/Word.swift`: Russian/Polish pair, source language, creation date and SRS state; the only SwiftData model. |
| Dictionary | `Views/WordListView.swift`: creation-date `@Query`, search in both languages, deletion, add and camera presentation. |
| Adding words | `Views/AddWordView.swift`: language detection, 600 ms translation debounce, manual editing, insertion through `modelContext`. |
| Translation | `Services/TranslationService.swift`: `Translator` facade; implementations in `AppleTranslator.swift`, `GoogleWebTranslator.swift`, `MyMemoryTranslator.swift`. |
| Camera and results | `Views/ScannerView.swift`: permission, VisionKit bridge, line translation, word selection and nested `AddWordView`. `Services/ScannedTextTokenizer.swift` separates words and punctuation. |
| Practice | `Views/TrainingView.swift`: statistics and entry points to `FlashcardsView`/`QuizView`; `Services/SRSEngine.swift`: scheduling. |
| Speech and styling | `Services/SpeechService.swift`, `Views/Components/PronounceButton.swift`: system speech; `Theme/Theme.swift`: dynamic colors and cards. |
| Build | Root `project.yml`: XcodeGen, application and `MojSlownikUITests`, iOS 17.0, Swift 5.9. |

## Data Flows

**Adding:** input → `LanguageDetector` → `Translator` → editable translation →
`Word` → SwiftData → dictionary/training `@Query` updates. Pair fields always
follow their languages regardless of input direction. These screens use the
SwiftData context and autosaving, without a repository layer or explicit `save()`.

**Scanning:** tap a recognized line → dismiss camera → present `ScanResultView`
after 0.4 seconds → translate the line and select a word → `AddWordView(initialText:)`.
Dismissing the add screen keeps the scan result available for further selections.

**Practice:** session snapshot → flip card → rating → mutate SRS fields on the
same `Word`. Quiz questions and score live in view state and do not change SRS.

## Non-obvious Constraints

- Language detection checks Unicode `U+0400…U+04FF`: any Cyrillic means Russian;
  everything else means Polish. This is an alphabet heuristic, not full detection.
- New input cancels the previous translation task and clears the translation so
  an old value cannot be saved with a new word. Translation remains editable;
  insertion does not enforce pair uniqueness.
- On physical iOS 18+ devices: Apple with a 4-second timeout → Google → MyMemory.
  Apple is skipped on iOS 17 and in the simulator. Cancellation propagates to the
  caller rather than triggering fallback.
- Apple provides `TranslationSession` only through a view's `.translationTask`.
  `AppleTranslationModel.shared` connects the facade to the root modifier using
  a continuation. It holds one pending request; a new request cancels the previous
  one. Cancellation handling prevents session waiting from blocking the timeout.
- Google uses an unofficial endpoint without a key. MyMemory rejects empty,
  unchanged and alphabet-incompatible candidates; it tries the main response,
  then `matches` in descending score order. This filters candidates but does not
  guarantee quality. Requests include the implementation's default contact email.
- The camera requires permission and positive `DataScannerViewController.isSupported`
  and `isAvailable` checks. OCR languages are selected from supported ru/pl languages;
  if neither is supported, an empty list allows automatic selection. Polish
  diacritics are not guaranteed.
- Tokenization preserves punctuation. Alphanumeric characters, apostrophes and
  hyphens belong to words. Only tokens longer than one character are selectable
  in text and chips; repeated words are preserved.
- Due words and search results are filtered in memory after `@Query`. Flashcards
  use all due words, or up to 10 random words if none are due. Again sets `dueDate`
  to 10 minutes later and also appends the word to the current session.
- SRS intervals use days × 86,400 seconds, not calendar days. Learned statistics
  mean `repetitions >= 3`; Again resets that counter.
- Quiz requires at least 4 records and generates **up to** 10 questions. Options
  are deduplicated by exact text, so duplicate translations may yield fewer than
  four choices; questions without distractors are skipped.
- The `UITEST_PREFILL` launch environment variable opens a scan result without
  the camera. It is an existing UI-test entry point, not a separate data source.
  The feature workflow does not create, update or run UI automation.

Regenerate with `xcodegen generate` after adding source files or changing project
configuration. Build and verification instructions: [AGENTS.md](../AGENTS.md).
Personal iPhone installation: [README.md](../README.md).
