# Адаптивная практика на слух и правописание

## Goal

Добавить в «Практику» отдельный режим, где сложность выбирается по последней оценке слова в карточках: «Трудно/Не помню» — выбор польского варианта из четырёх, «Хорошо» — русский перевод и ввод польского слова, «Легко» — аудио диктант польского слова.

## Acceptance criteria

- AC-1: Вкладка «Практика» показывает отдельный режим «На слух» и передаёт выбранную папку.
- AC-2: Последняя оценка карточки определяет формат: `again`/`hard` → прослушать польское слово и выбрать его из четырёх вариантов, `good` → ввод польского по русской подсказке, `easy` → ввод польского по произношению. Старые слова без записанной оценки классифицируются по SRS: `easeFactor < 2.5` или 0 повторов → аудио и варианты; `easeFactor == 2.5` с повторами → ввод по русской подсказке; `easeFactor > 2.5` → аудио диктант.
- AC-3: У нового слова и слов с недостаточной историей сохраняются четыре уникальных польских ответа. Если в выбранном наборе нельзя собрать четыре уникальных варианта, используется ввод польского по русскому переводу.
- AC-4: Ответы проверяют польские диакритические знаки; сравнение нечувствительно к регистру, пробелам по краям и канонической Unicode-композиции.
- AC-5: Аудио берётся из `SpeechService`, можно прослушать снова; микрофон и распознавание речи не нужны.
- AC-6: Ответ записывается один раз в дневную статистику через `DailyStudyStore`; эта практика сама по себе не меняет SRS расписание. Ошибка в этой практике не меняет сохранённую последнюю оценку карточки.
- AC-7: Сессия ограничена и заканчивается экраном результата. Существующие карточки и викторина работают как прежде.
- AC-8: Новая логика выбора режима и проверки ответов покрыта unit-тестами; не менять и не запускать UI/E2E tests.

## Relevant files

- `MojSlownik/Models/Word.swift`: optional last review grade, nil for pre-existing records.
- `MojSlownik/Services/SRSEngine.swift`: persist the grade alongside existing schedule updates.
- `MojSlownik/Services/ListeningQuestion.swift` (new): adaptive tier, answer choice generation, spelling normalization.
- `MojSlownik/Views/TrainingView.swift`: entry point and selected-folder handoff.
- `MojSlownik/Views/ListeningPracticeView.swift` (new): question, answer, feedback and result flow.
- `MojSlownikTests/ListeningQuestionTests.swift` (new): mode mapping, legacy fallback, distractor uniqueness/fallback, spelling validation.
- `docs/architecture.md`: document the new practice flow and grade behavior.

## Reuse and constraints

Use existing `ReviewGrade`, `SpeechService`, `DailyStudyStore.recordQuizAnswer`, `FolderStore.words`, `SessionProgress`, Theme colors and error alert. Keep iOS 17 compatibility and all UI copy in Russian. Avoid microphone permission, network calls, dependencies, and new SRS behavior. Preserve existing SwiftData words; make the new grade optional so records already stored retain their schedules and can be classified from existing fields.

## Verification

- Run `xcodegen generate` after adding source files.
- Build `MojSlownik` for an installed iPhone simulator.
- Run the isolated `MojSlownikUnitTests` scheme.
- Manual checklist: folder filtering, 4-choice flow, Good text-entry flow, Easy audio dictation/replay, diacritic validation, result screen, and existing cards/quiz behavior. Do not use UI automation.

## Risks

- Existing records have no precise last-grade field; infer their initial tier from repetitions and ease factor. New card reviews record the exact latest grade.
- Simulator audio output may not fully validate speech quality; device playback remains a manual check.
