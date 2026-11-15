# Shared adaptive word knowledge

## Goal

Add one service that updates a word's knowledge/confidence tier from outcomes in every practice mode, and use that tier to choose the next difficulty. Typed answers should distinguish a small spelling slip from a poor match: exact answers raise confidence; matches of at least 70% are soft misses and lower the tier only after two consecutive misses; matches below 70% lower it immediately.

## Acceptance criteria

- AC-1: Flashcards, multiple-choice quiz, listening choices, Russian-to-Polish typing, and Polish audio dictation all report outcomes through the same service.
- AC-2: Each word has a persisted, bounded confidence tier compatible with existing words. The service can raise/lower one tier and does not index past the lowest or highest tier.
- AC-3: Typed answers are normalized for case, edge whitespace and Unicode composition, then scored by a documented character-level similarity metric. Exact match raises one tier; similarity >= 70% records a soft miss and only lowers one tier after two consecutive soft misses; similarity < 70% lowers one tier immediately. Correct answers clear pending soft misses.
- AC-4: Choice answers update one tier per outcome: incorrect lowers one, correct raises one. Flashcard self-ratings set the tier to the selected grade (Again/Hard/Good/Easy), since those buttons explicitly ask the learner to judge recall; this is distinct from the one-step typed-answer penalty.
- AC-5: Answer recording remains single-shot per question, survives app relaunch, preserves existing Word data, and continues to feed daily answer statistics.
- AC-6: The tier remains the source for adaptive practice difficulty; all practice modes use the shared service rather than updating confidence independently.
- AC-7: Unit tests cover tier bounds/transitions, 70% boundary, consecutive soft misses, normalization, all answer-mode mappings, persistence and regression behavior.

## Relevant files and intended changes

- `MojSlownik/Models/Word.swift`: persist the confidence tier and consecutive soft-miss count with defaults safe for old records.
- `MojSlownik/Services/KnowledgeProgressService.swift` (new): shared answer assessment, similarity calculation, confidence transition and persistence-safe update API. Reuse `ReviewGrade` or a small tier type only if review confirms it avoids conflating user self-rating with answer correctness.
- `MojSlownik/Services/SRSEngine.swift`: keep scheduling behavior centralized; coordinate with the confidence service only if the chosen policy updates SRS due dates.
- `MojSlownik/Stores/DailyStudyStore.swift`: replace or extend the current ID-only `recordQuizAnswer` API with a word/context-aware answer API so quiz and listening choices can update SwiftData and daily activity together; prepare Codable activity before mutation, save the word first, restore its prior confidence/SRS fields on save failure, then publish daily activity.
- `MojSlownik/Views/FlashcardsView.swift`, `QuizView.swift`, `ListeningPracticeView.swift`: send self-ratings, choice correctness and typed submissions to the shared service; preserve result feedback and one-answer guards.
- `MojSlownik/Services/ListeningQuestion.swift`: read the shared confidence tier when selecting format; remove grade-specific mode duplication.
- `MojSlownikTests/KnowledgeProgressServiceTests.swift` (new), plus focused updates to existing store/question tests.
- `docs/architecture.md`: document confidence state, its relation to SRS schedule and adaptive mode selection.
- `.codex/plans/adaptive-knowledge-service.md`: this plan.

## Reuse and constraints

Use the existing SwiftData `Word`, `ReviewGrade`, `DailyStudyStore`, SRS scheduler, local-only persistence, and isolated `MojSlownikUnitTests` scheme. Preserve iOS 17 and existing records; avoid server, network and UI-test changes. Existing quiz and listening answers currently update daily statistics but do not change SRS. Keep update/rollback atomic so a failed model save does not publish a changed tier or daily answer.

## Verification

- Add committed XCTest unit tests for the shared progression and regression tests for current card, quiz, and listening flows.
- Run `xcodegen generate` if new source files are added.
- Build `MojSlownik` and run only `MojSlownikUnitTests` on an installed iPhone simulator.
- Manual checklist: enter exact and near-miss spellings on both typed modes, test <70% errors, make two consecutive >=70% errors, answer right/wrong in quiz and listening choices, grade cards, then verify the next mode and persisted tier for each word.

## Risks and unresolved decisions

- Approved policy: all exercise outcomes update the dedicated confidence tier, while SM-2 due scheduling remains tied to explicit flashcard grades.
- “70% match” needs a precise metric. Proposed default: normalized Levenshtein similarity `1 - editDistance / max(expectedCharacterCount, typedCharacterCount)`, with empty expected input handled as zero; preserve Polish diacritics as distinct characters.
- “A couple of times” is interpreted as two consecutive >=70% near misses. A correct answer clears that streak; an answer below 70% immediately lowers one tier and clears it.
- Flashcards currently ask for a self-rating rather than typed spelling; the shared service sets that selected confidence tier but cannot derive a character-match score there.
