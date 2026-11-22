# i18n: English + Russian UI, English comments

Base: `fc858ed` on `t3/language-workspaces` (clean tree). Mode: full. Revision 2: applies the
12 critic findings (see "Revision log" at the end).

## Goal

1. Translate every Russian code comment to English.
2. Move all user-facing copy out of the Swift sources into String Catalogs. English is the
   development (source) language, Russian is a full translation.
3. iOS chooses the UI language from the system language preferences. If none of the preferred
   languages is `en` or `ru`, the app shows English.
4. Domain data (dictionary words, persisted values, fixtures, test inputs) stays exactly as it is.

## Constraints (user instructions, verbatim)

> я хочу вычистить из кода комменты на русском - должны быть они на англ и сдеать i18 текст - без хардкода и поддерживаемые языки англ, русский - по дефолту берется язык системы и если нет конфига перевода - берешь англ

Project invariants that apply:
- SwiftData must not lose words, and persisted property values and keys must not change.
- Zero build warnings (`SWIFT_TREAT_WARNINGS_AS_ERRORS`).
- Logging never includes user text or copy.
- Read DESIGN.md before UI copy work.
- E2E tests use named fixtures only.
- Never run tests through the `MojSlownik` scheme.
- Run local tests on one simulator, limited to the affected E2E classes.

## Acceptance criteria

- AC-1: With the system language set to English, every screen, alert, menu, accessibility
  label/hint/value, error message and achievement shows English copy.
- AC-2: With the system language set to Russian, every screen shows Russian copy. The text
  matches today's copy character for character, except for the items in "Intentional Russian
  copy changes".
- AC-3: An unsupported language (German) shows English. Preferences `[de, ru]` show Russian,
  the first supported language.
- AC-4: Camera, microphone and speech-recognition permission prompts follow the same rule
  (`InfoPlist.xcstrings`).
- AC-5: Counts use correct plural forms. Russian uses one/few/many/other ("1 слово", "3 слова",
  "11 слов", "21 слово", "1 папка", "5 папок", "1 очко"). English uses one/other.
- AC-6: Dates in sync status and achievements use the app's UI language with the system region.
  No hardcoded `ru_RU` remains.
- AC-7: No comment in `MojSlownik/`, `MojSlownikTests/` or `MojSlownikUITests/` contains Cyrillic.
  No string literal in `MojSlownik/` contains Cyrillic outside marked data regions. A unit test
  enforces both rules.
- AC-8: The catalogs are complete and live:
  - every catalog entry has translated `en` and `ru` values with all plural categories, and
    format specifiers match across languages (unit test);
  - the key-extraction check (`scripts/check-localization.sh`) finds no key used in code that is
    missing from the catalog;
  - it also finds no catalog key that code never uses (dead key).
- AC-9: Existing words keep their category after upgrade. `Word.categoryRawValue` values and the
  `WordCategory` raw values are unchanged. Sync payloads (`stableID`, language codes) are unchanged.
- AC-10: Unit tests run in English (scheme pin). E2E chooses the language per launch: the default
  is Russian, and dedicated scenarios cover English, Russian, German → English, and `[de, ru]` →
  Russian.

## Design decisions (settled)

### Mechanism
- One `MojSlownik/Localizable.xcstrings` (sourceLanguage `en`) holds all app copy, and
  `MojSlownik/InfoPlist.xcstrings` holds the three usage descriptions. Both sit at the target root,
  so XcodeGen's `sources: - MojSlownik` picks them up (XcodeGen 2.45.4 supports `.xcstrings`).
- iOS language selection implements the fallback rule:
  - `CFBundleDevelopmentRegion` = `$(DEVELOPMENT_LANGUAGE)` = `en`;
  - add `CFBundleLocalizations: [en, ru]`;
  - leave `CFBundleAllowMixedLocalizations` unset, so the whole app, including system controls,
    uses one language;
  - there is no in-app picker: iOS Settings › Mój Słownik › Language appears once the app has two
    localizations.
- `CFBundleDisplayName` "Mój Słownik" is a brand name and is not localized.

### Key style: English source text as the key
- SwiftUI literals and `String(localized: "…")` use the English text as the key.
- Reasons:
  - The compiler extracts these keys into `.stringsdata`, which the key-extraction check compares
    with the catalog.
  - A failed lookup still shows readable English, which is the requested fallback.
  - About 450 strings need no separate key bookkeeping.
- Semantic keys are used only in two cases:
  - The language-name forms (`language.<code>.<form>`, below).
  - A collision, where two different Russian strings would share one English text. The rule:
    choose distinct English wording first. Otherwise use
    `String(localized: "area.purpose", defaultValue: "…", comment: "…")`.
- Every semantic key and every key with a placeholder gets a catalog `comment`.
- **No multi-argument plurals.** Every plural key has exactly one numeric argument. Sentences
  with two counts are split into single-argument keys and joined with `Text(verbatim:)` (the
  catalog test therefore never sees `%#@…@` substitutions, and it rejects them).

### How code gets strings
| Context | API |
|---|---|
| SwiftUI view literals (Text, Button, Label, Toggle, Picker, Section, navigationTitle, alert/confirmationDialog, TextField prompt, searchable prompt, accessibilityLabel/Hint/Value, accessibilityAction(named:)) | plain literal → `LocalizedStringKey` (automatic) |
| Ternaries in a `LocalizedStringKey` parameter position | allowed: the literals are typed by context (`title: isCapturing ? "Shot…" : "Freeze"`). The extraction check confirms both keys. |
| Ternaries / computed copy whose result is a `String` (stored in a `let`, returned from `-> String`, passed to a `String` parameter, interpolated) | each branch `String(localized: "…")`. A bare `cond ? "A" : "B"` typed as `String` is NOT localized. |
| Services/Stores/enums (errors, `ReviewGrade.title`, `AchievementCategory.title`, achievement title/detail, `WordCategory.title`, sync status, auth/speech errors, announcements) | `String(localized: "…")` returning `String` |
| Data in Text (word terms, folder names, endonyms, flags, "+5", joined already-localized parts) | `Text(verbatim:)` or `Text(stringVariable)` |
| Plurals | `"\(n) words"` → key `%lld words` with `plural` variations (en one/other; ru one/few/many/other) |

- Rules for interpolated literals:
  - `Text("Delete folder “\(name)”?")` becomes key `Delete folder “%@”?`.
  - Data-only interpolations such as `"\(flag) \(name)"` use `Text(verbatim:)`.
  - A literal `%` in a key is written `%%`.

### String-typed view helpers: retyping table
These helpers currently take `String` and render it with `Text(title)`, which never localizes.

| Helper | Callers | New signature / caller change |
|---|---|---|
| `TrainingView.sectionHeader(_ title: String, color:)` :63 | :79 "Сегодня", :166 "Режимы" | `_ title: LocalizedStringKey` |
| `TrainingView.answerBadge(count:title: String, icon:)` :133 | :95 "Верных", :96 "Ошибок" | `title: LocalizedStringKey` |
| `TrainingView.ModeTile(title:subtitle: String)` :255 | :171-189 (subtitle ternary at :179) | both `LocalizedStringKey`; the :189 subtitle becomes literal `"Listen and write \(adverb)"` |
| `ScannerView.compactControl(title:accessibilityTitle: String, …)` :190 | :156-168 (nested ternaries) | both `LocalizedStringKey`; the ternary literals stay inline (contextual typing) |
| `AccountView.signInButton(_:title: String, …)` :93 | :67, :70 | `title: LocalizedStringKey` |
| `WorkspaceManagerView.infoLine(_ text: String)` :127 | :45 literal | `_ text: LocalizedStringKey` |
| `WorkspaceWizardView` step page `title`, `message`, `footnote` (:117-143) and its `infoLine(_:)` :259 | :30-59 literals | `LocalizedStringKey` (`footnote: LocalizedStringKey?`); `subtitle: (Language) -> String` stays `String` (data: endonym) |
| `WordListView.categoryFilter(_:title: String, count:)` :221 | :206 "Все темы", :211 `category.rawValue` | **stays `String`** (one caller passes the computed `category.title`); callers pass `String(localized: "All topics")` and `category.title`; body `Text(title)`; a11y `.accessibilityLabel(String(localized: "\(title), words: \(count)"))` (ru "%1$@, слов: %2$lld", no plural, copy unchanged) |
| `WordListView` `EmptyStateView(title:message: String)` :247-254 | :44-52 literals | `LocalizedStringKey` |
| `ErrorAlert.errorAlert(title: String, error:)` | all callers literals | `title: LocalizedStringKey` |
| `ScannerView` nested literal :426 `.accessibilityLabel("\(word), \(translation ?? draft.wordErrors[word] ?? "Перевод загружается")")` | n/a | hoist: `let status = translation ?? draft.wordErrors[word] ?? String(localized: "Loading translation")`; `.accessibilityLabel(Text(verbatim: "\(word), \(status)"))` |
| `ScannerView` :427-429 accessibilityHint nested ternary | n/a | literals in `LocalizedStringKey` context are fine; keep one expression |
| `ScannerView` :122-125 `-> String` instruction helper; `:474-475` `-> String` | n/a | `String(localized:)` per return |

These helpers stay `String` because they receive already-localized or data strings:
`AccountView.calmNote` (`sync.statusText`), `FolderPicker.errorLabel` (store errors),
`PronounceButton.text`, `ScannerView` word-chip helpers, and the `QuizView`/`ListeningPracticeView`
option helpers.

### Language names: localized grammatical forms
Remove `nameRU`, `prepositionalRU`, `genitiveRU`, `adverbRU` and `neuterRU` from `Language`
(none are persisted or Codable). Add in `Services/Language.swift`:

```swift
/// Localized UI forms of a language name (Localizable.xcstrings, `language.<code>.<form>`).
struct LanguageNames: Equatable {
    let name: String            // titles, rows, labels: "Polish" / "Польский"
    let inline: String          // nominative mid-sentence: "Polish" / "польский"
    let inputOption: String     // segment after "I'm typing in": "Polish" / "Польском"
    let genitive: String        // same-alphabet note: "Polish" / "польского"
    let adverb: String          // "in Polish" / "по-польски"
    let wordPlaceholder: String // "Polish word" / "Польское слово"
    static func of(_ code: String) -> LanguageNames   // switch over the 10 codes, literal keys
}
extension Language {
    var names: LanguageNames { .of(code) }
    var localizedName: String { names.name }
}
```

- Each value is `String(localized: "language.pl.name", defaultValue: "Polish", comment: "…")`, and
  so on: 60 entries. The `default:` case returns the code in every field.
- Russian values must equal today's derived strings:

| code | name | inline | inputOption | genitive | adverb | wordPlaceholder |
|---|---|---|---|---|---|---|
| pl | Польский | польский | Польском | польского | по-польски | Польское слово |
| ru | Русский | русский | Русском | русского | по-русски | Русское слово |
| uk | Украинский | украинский | Украинском | украинского | по-украински | Украинское слово |
| en | Английский | английский | Английском | английского | по-английски | Английское слово |
| de | Немецкий | немецкий | Немецком | немецкого | по-немецки | Немецкое слово |
| fr | Французский | французский | Французском | французского | по-французски | Французское слово |
| es | Испанский | испанский | Испанском | испанского | по-испански | Испанское слово |
| it | Итальянский | итальянский | Итальянском | итальянского | по-итальянски | Итальянское слово |
| cs | Чешский | чешский | Чешском | чешского | по-чешски | Чешское слово |
| pt | Португальский | португальский | Португальском | португальского | по-португальски | Португальское слово |

- English: `name` = `inline` = `inputOption` = `genitive` = Polish / Russian / Ukrainian /
  English / German / French / Spanish / Italian / Czech / Portuguese; `adverb` = "in <Name>";
  `wordPlaceholder` = "<Name> word".
- `endonym` stays a stored literal (data). The wizard and
  `WorkspaceLabels.accessibilityName` compare `endonym == localizedName`.

### Shared helpers
- `Services/AppLocale.swift` (new):

```swift
enum AppLocale {
    /// The UI language iOS resolved for this app (en or ru) combined with the system region.
    static var current: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents = .init(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return Locale(components: components)
    }
}
```

- Plurals replace `RussianPlural` (delete the file). Add to `WorkspaceLabels`:
  - `static func wordCount(_ n: Int) -> String { String(localized: "\(n) words") }`
  - `folderCount(_:)` → `"\(n) folders"`

### Test language
- **Unit tests:** pin the `MojSlownikUnitTests` scheme test action to English (`language: en`,
  `region: US` in project.yml). If XcodeGen ignores these, use
  `commandLineArguments: {"-AppleLanguages (en)": true, "-AppleLocale en_US": true}`. A runtime
  test asserts the host really runs in English.
- **Russian lookups in unit tests:** always pass both the ru bundle and the ru locale. The
  `locale` argument decides the plural category:
  `String(localized: "\(n) words", bundle: ruBundle, locale: Locale(identifier: "ru_RU"))`, where
  `ruBundle = Bundle(path: Bundle.main.path(forResource: "ru", ofType: "lproj")!)!`. The helper lives
  in `MojSlownikTests/LocalizationTestSupport.swift`.
- **E2E:** `E2ETestCase.launch(_:prefill:auth:sync:language:)` with
  `language: UILanguage = .russian`. `UILanguage` maps to launch arguments:

| case | `-AppleLanguages` | `-AppleLocale` |
|---|---|---|
| `russian` | `(ru)` | `ru_RU` |
| `english` | `(en)` | `en_US` |
| `german` | `(de)` | `de_DE` |
| `germanThenRussian` | `(de, ru)` | `de_DE` |

### Key-extraction check (replaces "commit the synced catalog")
CLI `xcodebuild` does not sync the catalog. The compiler does emit `*.stringsdata` (JSON) for
every Swift file when `SWIFT_EMIT_LOC_STRINGS=YES`. New `scripts/check-localization.sh
<DerivedDataPath>` works as follows:
- It runs embedded `python3 -I`.
- It collects the keys of table `Localizable` from every
  `<DerivedData>/Build/Intermediates.noindex/MojSlownik.build/**/MojSlownik.build/**/*.stringsdata`
  of the app target. It ignores test targets and packages.
- It loads `MojSlownik/Localizable.xcstrings` and prints two lists:
  - **missing**: keys in code that are not in the catalog;
  - **dead**: keys in the catalog that are not in code.
- It exits 1 if either list is non-empty, or if no `.stringsdata` was found (this guards against a
  wrong path or extraction being off).
- If the `.stringsdata` layout differs from the expected one, the fallback is
  `xcodebuild -exportLocalizations -localizationPath <scratch> -exportLanguage ru` with the same
  comparison on the exported `.xcloc/Localized Contents/ru.xliff` trans-unit ids.

The check runs in every step after the build. It is also added to CI (`Build & unit tests` job,
after "Build app", `scripts/check-localization.sh DerivedData`), added in step 1 with the Cyrillic-key filter above. "No stale" in AC-8 means
"no dead keys" from this check. The catalog test does not rely on `extractionState`, and the
implementer leaves that field absent.

## Data that must NOT be localized (categories)

1. **Persisted category raw values:** `WordCategory` `rawValue`s ("Еда и напитки", …, "Другое") and
   the `Word.categoryRawValue = "Другое"` default. They are stored in SwiftData. The UI moves
   from `.rawValue` to the new `.title`; `id` stays `rawValue`.
2. **Category detection vocabulary:** the `WordCategory.vocabulary` keyword sets.
3. **Language endonyms** in the `Language` static declarations, plus flags.
4. **Debug fixtures and stubs:** `UITestFixtures.swift` (words, «Урок 1», «Lektion 1»),
   `UITestLaunchConfiguration.swift` (stub translations, `partOfSpeech: "существительное"`),
   `UITestSyncRemote.swift` (remote words, folder «Из облака»).
5. **User content:** terms, translations, folder names, provider translations and parts of speech.
6. **Server/DB:** `supabase/` SQL holds only Cyrillic data values (seeds, test rows, the applied
   migration default `'Другое'`). Do not touch it. `scripts/` and `.github/` contain no Cyrillic.
7. **Test inputs and expectations** in `MojSlownikTests/` and `MojSlownikUITests/`.
8. **Translation-provider payloads:** codes and URLs only.

### Data regions for the hygiene test (by region, not by file)
Mark each data literal region in `MojSlownik/` with English marker comments:
`// l10n:data-begin <reason>` … `// l10n:data-end`, or a trailing `// l10n:data` on a single line.
Only these regions:

| File | Region |
|---|---|
| `Services/WordCategory.swift` | the `case … = "…"` declarations (persisted raw values); the `vocabulary` static. `title` is NOT inside a region. |
| `Models/Word.swift` | the `categoryRawValue` default line |
| `Services/Language.swift` | the ten `static let <language> = Language(…)` declarations (endonyms) |
| `Services/UITestFixtures.swift` | the seed word/folder data blocks and `syncedWords` pairs |
| `Services/UITestLaunchConfiguration.swift` | the stub translation dictionaries and the alternatives stub |
| `Services/UITestSyncRemote.swift` | the remote record builders/states containing words and «Из облака» |

The test fails on Cyrillic outside a region, on unbalanced or nested markers, and on a region
with no Cyrillic in it (stale marker).

## Intentional Russian copy changes

1. `WorkspaceWizardView` step-2 message "Обычно это ваш родной язык. Интерфейс приложения
   останется на русском." is no longer true. New copy:
   - en "Usually your native language. The app interface follows your iPhone's language."
   - ru "Обычно это ваш родной язык. Язык интерфейса берётся из настроек iPhone."
2. Points get real plural forms (ru one "%lld очко", few "%lld очка", many/other "%lld очков"; en
   "%lld point"/"%lld points"). Today they always read "очков":
   - `TrainingView.swift:216` "\(points) очков · Серия: \(streak) дн.";
   - `AchievementsView.swift:40` "\(store.totalPoints) очков";
   - `AchievementBanner.swift:35` "…, плюс \(points) очков".

   Only counts ending in 1–4 change (for example "1 очко", "3 очка"). No E2E asserts "очков"
   (grep of `MojSlownikUITests` is clean).
3. Nothing else changes in Russian. Splitting into single-argument keys keeps the rendered
   Russian text identical (see the achievements keys below).

### Achievements and streak keys (single-argument)
| Site | Composition (`Text(verbatim:)` joins already-localized parts) | en | ru |
|---|---|---|---|
| `TrainingView.swift:216` | `"\(points) · \(streak)"` | "%lld points" (plural) · "Streak: %lld days" (plural) | "%lld очко/очка/очков" · "Серия: %lld дн." (all categories "Серия: %lld дн.") |
| `AchievementsView.swift:40` | single key | "%lld points" (shared) | as above |
| `AchievementsView.swift:46` | `"\(unlocked) · \(record)"` | "%1$lld of %2$lld unlocked" (not a plural) · "best streak %lld days" (plural) | "%1$lld из %2$lld получено" · "рекорд %lld дн." (all categories) |
| `AchievementsView.swift:53` | single key | "Streak: %lld days" (shared) | "Серия: %lld дн." |
| `AchievementBanner.swift:35` | `"\(unlocked), \(plus)"` | "Achievement unlocked: %@" · "plus %lld points" (plural) | "Достижение получено: %@" · "плюс %lld очко/очка/очков" |
| `AchievementBanner.swift:21` | `Text(verbatim: "+\(points)")` | — | — |
| `AchievementStore.swift:160` announcement | key "Achievement unlocked: %@" (shared) | | "Достижение получено: %@" |

`TrainingView.swift:222` "\(unlocked) из \(total)" becomes "%1$lld of %2$lld" / "%1$lld из %2$lld"
(not a plural). The same pattern applies in `SessionProgress` and ListeningPractice "\(score) из …".

## English glossary (use consistently)

| Russian | English |
|---|---|
| Словарь | Dictionary |
| Практика | Practice |
| Карточки | Flashcards |
| Викторина | Quiz |
| На слух | Listening |
| Достижения | Achievements |
| Папка | Folder |
| Тема | Topic |
| Категория | Category |
| Аккаунт | Account |
| Языки | Languages |
| Новый язык… | New language… |
| Управлять языками | Manage languages |
| Ввожу на | I'm typing in |
| Готово | Done |
| Отмена | Cancel |
| Закрыть | Close |
| Править | Edit |
| Удалить | Delete |
| Убрать | Remove |
| Сохранить | Save |
| Создать | Create |
| Сканирование | Scanning |
| Синхронизация | Sync |
| Не помню / Трудно / Хорошо / Легко | Again / Hard / Good / Easy |
| Достижение получено | Achievement unlocked |
| Все темы | All topics |
| Перевод загружается | Loading translation |

English uses “…” quotes where Russian uses «…»; the ellipsis character "…" is kept.

## Changes by file

Four sequential steps. Each step leaves the build, unit tests and its affected E2E classes
green, so each one can be a separate implementer run. All steps edit `Localizable.xcstrings`,
so do not run them in parallel. Keep catalog keys sorted. Catalog entry shape:

```json
{ "sourceLanguage" : "en", "version" : "1.0", "strings" : {
  "Account" : { "localizations" : {
    "en" : { "stringUnit" : { "state" : "translated", "value" : "Account" } },
    "ru" : { "stringUnit" : { "state" : "translated", "value" : "Аккаунт" } } } },
  "%lld words" : { "comment" : "…", "localizations" : {
    "en" : { "variations" : { "plural" : {
      "one" : { "stringUnit" : { "state" : "translated", "value" : "%lld word" } },
      "other" : { "stringUnit" : { "state" : "translated", "value" : "%lld words" } } } } },
    "ru" : { "variations" : { "plural" : {
      "one" : {…"%lld слово"}, "few" : {…"%lld слова"}, "many" : {…"%lld слов"}, "other" : {…"%lld слова"} } } } } }
} }
```

Every entry has an explicit `en` and `ru`. Leave `extractionState` absent.

Every step ends with:
1. `xcodegen generate`;
2. a build with `-derivedDataPath <scratch>/DD`;
3. `scripts/check-localization.sh <scratch>/DD`, which must report zero missing and zero dead keys.
   Keys containing Cyrillic (`[\u0400-\u04FF]`) are excluded from "missing": they are not-yet-converted
   Russian literals, caught by SourceHygieneTests in step 4. The script prints their count as info.
   By the end of step 3 that count must be 0;
4. unit tests;
5. the step's E2E classes on one simulator.

### Step 1: infrastructure, language layer, E2E language parameter
Owns:
- **Project and scripts:** `project.yml`, `MojSlownik/Info.plist` (regenerated by xcodegen,
  committed), `scripts/check-localization.sh` (new), `.github/workflows/ci.yml` (one step).
- **Catalogs:** `MojSlownik/Localizable.xcstrings` (new), `MojSlownik/InfoPlist.xcstrings` (new).
- **Services:** `Services/AppLocale.swift` (new), `Services/Language.swift`,
  `Services/WorkspaceLabels.swift`, `Services/RussianPlural.swift` (delete).
- **View call sites:** only the lines that break when the RU fields go:
  - `Views/AddWordView.swift` 143-152, 228, 338;
  - `Views/TrainingView.swift` 189;
  - `Views/ListeningPracticeView.swift` 214;
  - `Views/WorkspaceWizardView.swift` 30, 85, 93, 226;
  - `Views/WorkspaceManagerView.swift` 103;
  - `Views/Components/WorkspaceTitleMenu.swift` 29.
- **E2E:** `MojSlownikUITests/E2ETestCase.swift`.
- **Tests:** `MojSlownikTests/LocalizationTestSupport.swift` (new),
  `LocalizationCatalogTests.swift` (new), `LocalizationRuntimeTests.swift` (new),
  `AppLocaleTests.swift` (new), `LanguageTests.swift`, `WorkspaceLabelsTests.swift`.

Changes:
- `project.yml`:
  - `options.developmentLanguage: en`.
  - Project `settings.base`: `LOCALIZATION_PREFERS_STRING_CATALOGS: YES`,
    `SWIFT_EMIT_LOC_STRINGS: YES`.
  - App `info.properties`: English usage descriptions:
    - camera: "The camera is used to scan words and add them to your dictionary."
    - microphone: "The microphone is used to dictate Polish words to add to your dictionary."
    - speech: "Speech recognition is used to enter Polish words by voice. Speech may be processed
      on Apple servers."
  - Also in `info.properties`: `CFBundleLocalizations: [en, ru]`.
  - `schemes.MojSlownikUnitTests.test`: `language: en`, `region: US`.
- `InfoPlist.xcstrings`: keys `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` and
  `NSSpeechRecognitionUsageDescription`. `en` uses the texts above; `ru` uses today's project.yml
  texts verbatim.
- `Language.swift`:
  - `LanguageNames` as designed above, with `// l10n:data` markers on the static declarations;
  - drop the RU fields and the private init's RU parameters;
  - translate the comments (the "Wi-Fi роутер" example becomes "a Latin brand name inside
    Cyrillic text").
- `WorkspaceLabels.swift`: use `localizedName`, add `wordCount` and `folderCount`, and write the
  comments in English.
- Call sites: these exact en/ru pairs go into the catalog.
  - AddWordView:
    - header "I'm typing in" / "Ввожу на";
    - segment `Text(verbatim: "\(flag) \(names.inputOption)")` with accessibilityLabel
      `localizedName`;
    - note "%1$@ and %2$@ use the same alphabet, so choose the input language manually. Your
      choice is remembered." / "У %1$@ и %2$@ один алфавит, поэтому язык ввода выбирается вручную.
      Выбор запоминается." (genitive forms);
    - "Dictate %@" / "Продиктовать %@" and "Speak %@…" / "Говорите %@…" (adverb).
  - TrainingView :189 subtitle: "Listen and write %@" / "Слушать и писать %@" (adverb).
    `ModeTile.subtitle` stays `String` until step 3, so pass `String(localized:)` here.
  - ListeningPracticeView :214 `TextField(names.wordPlaceholder, …)`.
  - Wizard:
    - "Start: %1$@, translated into %2$@" / "Начать: %1$@, перевод на %2$@" (inline forms);
    - rows `Text(verbatim: language.localizedName)`;
    - subtitles compare `endonym == localizedName`.
  - Manager :103 `Text(verbatim: "\(WorkspaceLabels.wordCount(n)) · \(WorkspaceLabels.folderCount(m))")`.
  - Title menu :29 `Text(verbatim: "\(menuLabel)\n\(wordCount)")`.
- `E2ETestCase`:
  - add `UILanguage` and the `language:` parameter (default `.russian`), which appends the launch
    arguments from the table above;
  - move `openTitleMenu(_:)` here from WorkspaceFlowTests (same body) and delete the private copy;
  - leave everything else unchanged.
- `ci.yml`: add the "Check localization keys" step after "Build app" in `Build & unit tests`.
- Affected E2E: `WorkspaceFlowTests` and `AddWordFlowTests`.

### Step 2: services, stores, models and their comments
Owns:
- **Copy changes:** `Services/Achievements.swift`, `SRSEngine.swift`, `WordCategory.swift`,
  `TranslationService.swift`, `ScannedTextTokenizer.swift`, `DataRepositories.swift`,
  `WorkspaceCatalog.swift`, `FolderStore.swift`, `SpeechRecognitionService.swift`,
  `Stores/SyncStore.swift`, `AuthStore.swift`, `AchievementStore.swift`.
- **Comments only:** `Services/AppleTranslator.swift`, `GoogleWebTranslator.swift`,
  `MyMemoryTranslator.swift`, `Stores/DailyStudyStore.swift`, `Theme/Theme.swift`.
- **Comments plus data-region markers only:** `Models/Word.swift`, `Services/UITestFixtures.swift`,
  `UITestLaunchConfiguration.swift`, `UITestSyncRemote.swift`.

Tests to update. These assertions break because the host is English:

| File and line | Old expectation | New expectation |
|---|---|---|
| `WorkspaceCatalogTests.swift:90` | "Нельзя удалить единственный язык" | "You can't delete the only language" |
| `WorkspaceScopingTests.swift:196` | "Выберите язык словаря" | "Choose a dictionary language" |
| `SwiftDataVocabularyRepositoryTests.swift:41` | "Слово больше не существует" | "The word no longer exists" |
| `ScanWordStoreTests.swift:176` | "Слово больше не существует" | "The word no longer exists" |
| `SyncStoreTests.swift:350-367` | Russian status texts | see Verification |
| `AuthStoreTests.swift:205` | "Не удалось войти. Попробуйте ещё раз." | "Couldn't sign in. Try again." |
| `WordCategoryTests` | — | raw values pinned in Russian, plus English `title` |

Also update any other copy assertion that fails. Run
`grep -rnP 'localizedDescription|errorMessage|statusText|\.title\b' MojSlownikTests` and check
each Cyrillic expectation.

Changes:
- **`String(localized:)` everywhere in owned files:**
  - every `errorDescription`, `ReviewGrade.title` and `AchievementCategory.title`;
  - achievement `title`/`detail` (16 entries; the Polyglot detail is one full sentence: "Earn
    “Librarian”, “Practice week”, “Connoisseur” and “Flawless”");
  - the `AuthStore` error and the `SpeechRecognitionService` messages;
  - the `AchievementStore` announcement (key "Achievement unlocked: %@").
- **`WordCategory`:**
  - add `var title: String` (switch, `String(localized:)`): Food & drinks / Home / Travel / Nature
    / People / Work & study / Health / Other;
  - raw values and `vocabulary` stay unchanged, inside data regions;
  - add a comment that the raw values are persisted and must never change.
- **`SyncStore`:**
  - `text(for:now:calendar:locale:)` and `whenText(_:now:calendar:locale:)` take
    `locale: Locale = AppLocale.current`, and `ru_RU` is dropped;
  - keys: "Synced: %@" / "Синхронизировано: %@", "today, %@" / "сегодня, %@", "yesterday, %@" /
    "вчера, %@";
  - older dates use `.day().month(.abbreviated)` in `locale`.
- **`SpeechRecognitionService` `.unavailable`:** translate faithfully ("Polish speech recognition
  is unavailable right now. Try again later."). See Open decision 2.
- **Comments:** translate every Russian comment in owned files at the same density.
  - Cyrillic examples in comments become English/Latin: the GoogleWebTranslator response shape
    becomes `[[["translation","original",...], ...], ...]`, and the UITestSyncRemote example
    `дом`/`кот` becomes the Polish sides `dom`/`kot`.
  - Theme «Маркер» becomes "Marker".
- **Affected E2E:** `SyncFlowTests` and `AccountFlowTests` (status texts), `FlashcardsFlowTests`
  (grade titles).

### Step 3: all views
Owns every file in `MojSlownik/Views/` and `MojSlownik/Views/Components/` (remaining copy and
comments), and `MojSlownikTests/KnowledgeTierBadgeTests.swift`.
- Apply the "How code gets strings" table and the **String-typed view helpers: retyping table**
  above, every row.
- Category UI uses `category.title`:
  - "Topic: %@" / "Тема: %@";
  - "Word category %1$@: %2$@" / "Категория слова %1$@: %2$@";
  - "Automatically: %@" / "Автоматически: %@".
- `KnowledgeTierBadge`:
  - level names via `String(localized:)` reusing the `ReviewGrade` English keys;
  - "Knowledge level of the word %1$@: %2$@" / "Уровень знания слова %1$@: %2$@";
  - "Knowledge level: %@" / "Уровень знания: %@".
- Points and streak keys: as in the achievements table. AchievementsView date: "Unlocked %@" /
  "Получено %@" with `.locale(AppLocale.current)`.
- RootTabView: tab labels "Dictionary"/"Practice", and "Loading dictionary…".
- WorkspaceWizardView: apply the intentional message change.
- Translate the Russian comments in WordListView, ScannerView, QuizView, AchievementsView,
  WorkspaceWizardView, WorkspaceManagerView and WorkspaceTitleMenu.
- Affected E2E: all existing classes (copy changes everywhere). Run them one class at a time on
  one simulator; the full suite also runs in CI.

### Step 4: E2E localization scenarios, hygiene guard, docs
Owns:
- **Tests:** `MojSlownikUITests/LocalizationFlowTests.swift` (new),
  `MojSlownikTests/SourceHygieneTests.swift` (new).
- **Test comments to translate:** `MojSlownikTests/SRSEngineTests.swift` ("Легко" → "Easy"),
  `MojSlownikUITests/WorkspaceFlowTests.swift:108` and `SyncFlowTests.swift:40`.
- **E2E helper:** the banner predicate in `E2ETestCase.dismissAchievementBannerIfPresent`
  becomes `label BEGINSWITH 'Достижение получено' OR label BEGINSWITH 'Achievement unlocked'`.
- **Docs:** `AGENTS.md`, `DESIGN.md`, `docs/architecture.md`,
  `.claude/skills/mobile-ios-design/SKILL.md`.

Doc changes:
- **AGENTS.md:**
  - replace "UI copy is Russian; …" with "UI copy is localized: English source strings and a
    Russian translation in String Catalogs (Localizable.xcstrings, InfoPlist.xcstrings); iOS
    picks the system language and falls back to English. Code, comments, file names and
    project instructions are English.";
  - the "No hardcoded UI copy … write both en and ru in the same change" invariant was already
    added by the orchestrator at the user's request (2026-11-22); keep it, do not duplicate;
  - add `scripts/check-localization.sh <DerivedData>` to Verification.
- **DESIGN.md:**
  - §8 becomes "VoiceOver: localized labels (en/ru)…";
  - add a "Copy" note in §5 Patterns: copy quoted in this file is the Russian localization;
    English source strings live in the catalog; English uses “…” and Russian «…»; every new
    string gets both languages.
- **docs/architecture.md:**
  - add a `## Localization` section covering catalogs, key style, `LanguageNames`, `AppLocale`,
    single-argument plurals, data regions, the extraction check and test language setup;
  - in Tests and CI, add `LocalizationFlowTests`, the unit-test language pin and the E2E
    `language:` default.
- **mobile-ios-design SKILL.md:** line 10 "Russian UI copy" becomes "English + Russian UI copy
  (String Catalogs)".
- **README.md:** stays Russian; it is user documentation.
- **Affected E2E:** `LocalizationFlowTests`.

## Reuse

- `WorkspaceLabels` stays the single place for workspace labels and gains the plural helpers.
  `Language`/`LanguagePair` stay the descriptors.
- Existing components (`ErrorAlert`, `EmptyStateView`, `ModeTile`, `SessionProgress`,
  `FolderPicker`) are kept; only their copy parameters are retyped. No new UI components and no
  Theme changes.
- The `E2ETestCase` helpers and the fixtures `basicVocabulary` and `multiWorkspace` are reused.
  No new fixtures.

## Data compatibility

- **SwiftData:** no schema change, and no persisted property is added, renamed or changed in
  value. `Word.categoryRawValue` keeps the Russian raw values, so `WordCategory(rawValue:)`
  resolves exactly as before. `LegacySchemaMigrationTests` is untouched.
- **Sync:** words send `category.stableID`, workspaces store only codes, and folder names are user
  data. No change.
- **UserDefaults:** achievements are keyed by id, plus active workspace and input sides. Nothing is
  keyed by copy.
- **Logging:** no copy is logged.
- **Language change:** a system language change relaunches the app, and
  `AchievementCatalog.all` resolves strings again.

## Verification

### Unit tests
- **`LocalizationCatalogTests`** (new). It reads both source catalogs through a
  `#filePath`-relative URL; the simulator can read host files. It checks:
  - `sourceLanguage == "en"`;
  - every key has `en` and `ru`, either a `stringUnit` with `state == "translated"` or `plural`
    variations (en: one+other; ru: one+few+many+other), each translated;
  - format specifiers match between the en and ru values and every variation. Specifiers are
    normalized to a type list by position: `%@`, `%lld`, `%1$@`, `%2$lld`, `%%` ignored;
  - plural keys have exactly one numeric specifier, and any `%#@` or `substitutions` fails the
    test;
  - `InfoPlist.xcstrings` has exactly the three usage-description keys.
  Dead and missing keys are the extraction script's job, not this test's.
- **`LocalizationRuntimeTests`** (new):
  - the host runs in English: `Bundle.main.preferredLocalizations.first == "en"`;
  - `Bundle.main.localizations ⊇ {en, ru}` and `developmentLocalization == "en"`;
  - `Bundle.preferredLocalizations(from: ["en","ru"], forPreferences:)`: `["ru-RU"]` → `ru`,
    `["de","ru"]` → `ru`, `["de"]` → `en`. If the last case returns no development fallback
    through this API, keep only the `developmentLocalization` assertion; the E2E German launch
    covers the behavior.
  - **ru plural matrix** (bundle and locale `ru_RU`):

    | n | `%lld words` |
    |---|---|
    | 0 | "0 слов" |
    | 1 | "1 слово" |
    | 3 | "3 слова" |
    | 5 | "5 слов" |
    | 11 | "11 слов" |
    | 12 | "12 слов" |
    | 21 | "21 слово" |
    | 248 | "248 слов" |

    `%lld folders` 1/4/5 → "1 папка"/"4 папки"/"5 папок". `%lld points` 1/3/5/11 →
    "1 очко"/"3 очка"/"5 очков"/"11 очков".
  - **en plurals** (main bundle, `en_US`): `wordCount(1) == "1 word"`, `wordCount(5) == "5 words"`,
    `folderCount(1) == "1 folder"`.
  - **Table-driven ru language names:** all 10 × 6 forms from the table above, looked up as
    `String(localized: "language.<code>.<form>", bundle: ru, locale: ru_RU)` and compared to the
    expected strings, which the test declares as a literal table.
  - **en `LanguageNames.of(code)`** for all 10 codes: `name == inline == inputOption == genitive
    == <English name>`, `adverb == "in <English name>"`, `wordPlaceholder == "<English name> word"`.
- **`AppLocaleTests`** (new): the language is `en` in the host, and the region equals
  `Locale.autoupdatingCurrent.region`.
- **`LanguageTests`**: the adverbRU/neuterRU tests are replaced by the en `LanguageNames` asserts
  above.
- **`WorkspaceLabelsTests`**: English expectations ("🇵🇱 Polish", "🇩🇪 German ← 🇷🇺",
  "German ← Russian", "Polish, Polski", and "English" for `.english`). The plural block moves to
  the runtime tests.
- **`SyncStoreTests`**: no literal time strings. Each expectation is built from the same format
  style the code uses:

  ```swift
  let locale = Locale(identifier: "en_GB")
  let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                             calendar: calendar, timeZone: calendar.timeZone))
  XCTAssertEqual(SyncStore.text(for: .synced(date), now: now, calendar: calendar, locale: locale),
                 "Synced: today, \(time)")
  ```

  - The yesterday case and the older-date case work the same way; the older case builds the
    day with `.day().month(.abbreviated)`.
  - One ru-locale case checks only that the day part equals the same FormatStyle with `ru_RU`, so
    the locale is proven to be honored.
  - Never hardcode a space before AM/PM; `en_GB` gives a 24-hour clock anyway.
- **Step-2 table above**: `WorkspaceCatalogTests:90`, `WorkspaceScopingTests:196`,
  `SwiftDataVocabularyRepositoryTests:41`, `ScanWordStoreTests:176`, `AuthStoreTests:205`,
  `WordCategoryTests`.
- **`KnowledgeTierBadgeTests`**: "Again", "Hard", "Good", "Easy"; "Knowledge level of the word
  miasto: Good"; "Knowledge level: Good".
- **`SourceHygieneTests`** (new, step 4) is a small Swift lexer over `MojSlownik/`,
  `MojSlownikTests/` and `MojSlownikUITests/`. It handles:
  - `"…"` with `\"` escapes;
  - `"""…"""`;
  - raw strings `#"…"#` / `##"…"##`;
  - string interpolation `\( … )` with balanced parentheses and **nested string literals**
    inside it (`"\(a ?? "Перевод")"`), recursively;
  - `//` and `///` comments, and nested `/* /* */ */`;
  - `//` inside a string (URLs such as `"https://x/?q=кот"`) is not a comment.

  Rules:
  - (a) no Cyrillic in any comment in all three directories;
  - (b) no Cyrillic in string literals in `MojSlownik/**/*.swift` outside `l10n:data` regions;
  - (c) markers are balanced, not nested, and every region contains Cyrillic.

  Lexer self-tests with inline samples cover: a nested literal in an interpolation, a URL with
  `//` and Cyrillic, a raw string containing `"`, a multi-line string containing `//`, a nested
  block comment, and an escaped quote. Each must produce the expected comment and literal spans.
  Failure messages list `file:line`.

### E2E (MojSlownikUITests, fixtures `basicVocabulary`, `multiWorkspace`)
`LocalizationFlowTests` (new; the CI `dictionary` shard picks it up automatically):
- `testEnglishLaunchShowsEnglishCopy`: launch `.multiWorkspace` with `.english`, then
  `waitForDictionary`.
  - Tab buttons "Dictionary" and "Practice" exist.
  - `openTitleMenu("🇵🇱 Polish")` shows "Manage languages". Tap it.
  - The navigation bar is "Languages", and elements with label CONTAINS "5 words · 1 folder"
    and "2 words · 1 folder" exist.
  - Close the sheet and open Practice; "Flashcards" exists.
- `testRussianLaunchShowsRussianCopy`: `.multiWorkspace` with `.russian`. Check "Словарь",
  "Практика", "🇵🇱 Польский", "Управлять языками", "Языки", "5 слов · 1 папка" and
  "2 слова · 1 папка".
- `testUnsupportedSystemLanguageFallsBackToEnglish`: `.basicVocabulary` with `.german`. Check the
  tabs "Dictionary" and "Practice" and the title "🇵🇱 Polish".
- `testFirstSupportedPreferredLanguageWins`: `.multiWorkspace` with `.germanThenRussian`
  (`-AppleLanguages (de, ru)`, `-AppleLocale de_DE`). Check the tab "Словарь" and title
  "🇵🇱 Польский", then the Languages sheet shows "5 слов · 1 папка".
- Existing classes keep running in Russian through the default parameter.

### Build and commands (every step)
1. `xcodegen generate`.
2. Build (zero warnings) with `-onlyUsePackageVersionsFromResolvedFile -derivedDataPath <scratch>/DD`.
3. `scripts/check-localization.sh <scratch>/DD`: 0 missing, 0 dead.
4. Step 1 only: confirm that `<scratch>/DD/Build/Products/Debug-iphonesimulator/MojSlownik.app`
   has `en.lproj` and `ru.lproj` with `Localizable.strings`/`.stringsdict` and
   `InfoPlist.strings`, and that `plutil -p ru.lproj/InfoPlist.strings` shows the Russian texts.
   A missing `ru` in the pbxproj `knownRegions` is acceptable if `ru.lproj` is present; record
   it in the PR.
5. Unit tests: `MojSlownikUnitTests`, `-parallel-testing-enabled NO`, one simulator.
6. The step's E2E classes, `-only-testing:MojSlownikUITests/<Class>`, one simulator. The full
   suite runs in CI.
7. Reviewer greps:
   - `grep -rnE '(title|text|message|subtitle|accessibilityTitle|footnote): String' MojSlownik/Views`
     and `grep -rnE 'func \w+\(_ \w+: String' MojSlownik/Views`: each hit must be in the "stays
     String" list (data or already-localized input);
   - `grep -rnE 'Text\([a-zA-Z.]+ \?' MojSlownik/Views`;
   - `grep -rn 'RussianPlural\|nameRU\|adverbRU\|neuterRU\|ru_RU' MojSlownik`, which must be empty;
   - `grep -rnP '[\x{0400}-\x{04FF}]' MojSlownik --include='*.swift'`: only lines inside
     `l10n:data` regions.

### Manual checks (not automatable)
- A physical iPhone in English, Russian and German: walk Dictionary, Add word, Scanner (camera),
  Practice modes, Achievements, Account, the wizard and the Languages sheet. Each run shows one
  language; German shows English.
- Camera, microphone and speech permission prompts in en and ru (fresh install each time).
- Settings › Mój Słownik › Language lists English/Russian, and switching relaunches in that
  language.
- VoiceOver spot checks in English: labels, hints, announcements and the banner.
- Largest Dynamic Type in both languages: mode tiles, chips, the segmented control and achievement
  stats wrap acceptably.

## Risks

- **Silent non-localization**: `Text(stringVar)` or a `String` ternary compiles but shows the
  English literal in a Russian UI. Mitigations:
  - the retyping table;
  - reviewer greps;
  - the extraction check: a literal that never becomes a key is not caught by it, but its
    English text then appears in the Russian E2E runs and breaks Russian assertions;
  - the manual ru pass.
- **Contextual typing of ternary literals** in `LocalizedStringKey` parameters (`compactControl`):
  if the compiler does not extract these, the check reports them as dead catalog keys. The
  fix is then `String(localized:)` branches plus a `String` parameter rendered with `Text(_:)`.
- **`.stringsdata` location** depends on the Xcode version. The script fails loudly when it
  finds no files, and the `-exportLocalizations` fallback is documented.
- **System controls turn Russian** in Russian E2E (swipe Delete, search Cancel, Back), where
  they were English before. The WorkspaceFlowTests predicates already accept both. Any other
  English system-label match gets the same `OR`.
- **XcodeGen may ignore the scheme `language`/`region` keys**: use the documented fallback; the
  runtime test fails loudly.
- **Large diff, merge conflicts**: one catalog touched in every step. Run steps sequentially and
  keep keys sorted.
- **Plural fixes** change some Russian point counts ("1 очко"). No E2E depends on them.

## Open decisions

1. **Unit-test language:** English chosen (source language). Russian is verified through
   explicit ru bundle + `ru_RU` locale lookups. The alternative, pinning to Russian, leaves
   English untested at runtime.
2. **Copy that hardcodes "Polish"** ("Прослушайте и выберите польское слово", "Введите
   перевод на польский", "Распознавание польской речи…", the microphone/speech usage
   descriptions): translate faithfully (default), or make it follow the workspace language with
   `LanguageNames` in a follow-up.
3. **Wizard step-2 message:** confirm the proposed en/ru wording (a change is required).
4. **Points plural fix** (intentional change 2): accept the corrected Russian forms (default), or
   keep "очков" for every number.
5. **In-app language picker:** none; iOS per-app language covers it.
6. **English glossary:** confirm the terms, especially Again/Hard/Good/Easy and Topic vs Category.
7. **DESIGN.md quoted copy:** keep it in Russian with a note (default), or add English
   equivalents.

## Decisions (user, 2026-11-22)

- Copy that hardcodes "Polish": translate it faithfully. Following the workspace language is a later task.
- Points plural fix: accepted ("1 очко", "3 очка", "5 очков"; en "1 point"/"5 points").
- Wizard step-2 message: proposed en/ru wording accepted.
- English glossary: accepted as listed.
- Defaults kept: unit tests pinned to English; no in-app language picker; DESIGN.md quoted copy stays Russian with a note.
- Reviewer fix (orchestrator): check-localization.sh ignores Cyrillic keys for "missing" until step 3 ends; see "Every step ends with".

- User (2026-11-22): AGENTS.md rule added now: new/changed copy always gets en and ru in the same change.

## Revision log (rev 2, critic findings)

1. String-typed helpers: added the retyping table (TrainingView :63/:133/ModeTile,
   ScannerView.compactControl :190 and nested literal :426, AccountView.signInButton :93,
   WorkspaceManagerView.infoLine :127, the wizard page/infoLine, WordListView.categoryFilter :221,
   EmptyStateView, ErrorAlert) and the reviewer greps. Deviation: `categoryFilter` stays `String`
   because one caller passes the computed `category.title`; its literal caller wraps
   `String(localized:)`.
2. Replaced the catalog-sync assumption with `scripts/check-localization.sh` (`.stringsdata` vs
   catalog, missing and dead keys; `-exportLocalizations` fallback). It runs every step and in
   CI. AC-8 "no stale" now relies on this check.
3. The E2E `language:` parameter (default Russian) and the `openTitleMenu` move are in step 1.
   Each step lists its E2E classes.
4. Every ru lookup passes bundle and `locale: ru_RU`. The full matrix 0/1/3/5/11/12/21/248 plus
   folders 1/4/5 and points.
5. Added `testFirstSupportedPreferredLanguageWins` (`(de, ru)`, `de_DE`): Russian UI and
   "5 слов · 1 папка".
6. Multi-argument plurals are split into single-argument keys. The catalog test rejects `%#@`
   and substitutions.
7. AchievementsView :40/:46/:53, TrainingView :216/:222 and Banner :35 are listed with exact
   keys. The points plural is recorded as intentional change 2 and Open decision 4.
8. SyncStore expectations are built from the same FormatStyle with `en_GB`, with no hardcoded
   AM/PM spacing.
9. The hygiene allowlist uses `l10n:data` regions, not files; `WordCategory.title` is excluded.
   Added lexer cases for nested interpolation literals and URLs.
10. Table-driven test of all 10×6 ru language-name forms.
11. Named the breaking assertions: WorkspaceCatalogTests:90, WorkspaceScopingTests:196,
    SwiftDataVocabularyRepositoryTests:41, ScanWordStoreTests:176 (plus AuthStoreTests:205,
    SyncStoreTests).
12. Collapsed to 4 steps: infrastructure + language layer + E2E parameter; services/stores;
    all views; E2E scenarios + hygiene + docs.

## Approval

2026-11-22: approved by user.
