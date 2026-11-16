# Translation alternatives in Add Word

## Goal

When adding a word, show several translation candidates instead of a single machine
translation. The primary translation still fills the editable field as it does today
(Apple → Google → MyMemory). In parallel, the app fetches alternatives from the
keyless sources it already uses: Google `gtx` dictionary data and MyMemory `matches`.
It merges and deduplicates them and shows them as tappable chips under the
translation field. Tapping a chip puts its text into the editable field.

All new translation logic is language-pair agnostic. Language codes and expected
scripts come from one central language descriptor table. For the translation layer,
adding a language that uses an already-supported script (Latin or Cyrillic) means
adding one table entry. A language with a new script also needs a new `Script` case
with its Unicode ranges. Either way, the separate model work described under Risks
is still required. No `Word` model change, no language picker, no backend.

## Constraints

User request (verbatim):

> можно ли сделать Дополнительный перевод из бесплатных апи словарей? не всегда есть
> хороший стоковый перевод я подумал что можно показывать сразу несколько вариантов
> или брать более точный - как можно это сделать и имеет ли смысл? я планирую в
> будущем добавить бекенд синхронизацию

Binding user requirement, relayed by the coordinator. The plan must be language-pair
agnostic, because the user plans to support languages beyond pl↔ru in the future:

- parsers, merge and the script filter take the source and target language as
  parameters, with no hard-coded pl/ru;
- one central language descriptor holds the Google code, the MyMemory code, the
  Apple `Locale.Language` and the expected scripts, so adding a language means one
  table entry;
- the script filter is driven by the descriptor, not by "Cyrillic vs Latin" literals;
- tests include at least one pair that is not pl/ru;
- do NOT change the `Word` model in this task;
- keep scope minimal: no language picker UI.

Project and orchestrator constraints:

- iOS 17+, Swift 5.9, SwiftUI + SwiftData. No backend, accounts or API keys.
- Apple stays the primary translator when available. Alternatives are fetched in
  parallel, failures are tolerated, and they never block the primary result.
- No SwiftData changes: provider-specific data must not be stored, which keeps
  future backend sync clean. Existing words stay untouched.
- Parsing, merging and filtering are pure functions with XCTest coverage in
  `MojSlownikUnitTests`. Do not create, change or run UI/E2E tests.
- UI copy in Russian, code in English. Reuse Theme. Make the smallest complete change.
- Scope: `AddWordView` / `AddWordDraft`. Scanner quick-add stays as is (Decision
  3).

## Feasibility / does it make sense

Yes, for single words and short phrases. Machine translation picks one sense:
`zamek` becomes «замок», but «застёжка/молния» is also common. Dictionary-style
candidates fix this cheaply. Keyless sources an iOS client can call directly:

| Source | What it gives | Cost / limits | Verdict |
|---|---|---|---|
| Google `translate_a/single?client=gtx` with `dt=bd`, `dt=at` | `bd`: dictionary entries by part of speech; labels are in the `hl` language. `at`: alternatives for each segment. Good for common words in all major pairs; mostly empty for phrases. | Unofficial, undocumented format. Same endpoint and privacy profile as today. Throttles by IP, returning an HTML "Sorry…" page; this happened while drafting this plan. | **Use.** One request returns `t`, `bd` and `at`. |
| MyMemory `api.mymemory.translated.net/get` | `responseData.translatedText` plus a scored `matches` array of translation memory and MT results. Verified for `zamek` pl→ru: «замок», «Замок», «Замок PFP» (segment `Zamek PFP`). Noisy: partial segments and case duplicates; `quality` can be a string or a number. Quota errors come back as text starting with `MYMEMORY WARNING`, and `responseStatus` can be a non-200 number or a string. | 5,000 chars/day anonymous; 50,000 with `de=email`, which the app already sends. | **Use**, with filtering. |
| Wiktionary REST | en.wiktionary gives English glosses only. ru.wiktionary has no structured REST endpoint for definitions, so it would need scraping. | Free but fragile. | **Not now** (Decision 2). |
| Wiktextract / kaikki.org | Structured translations for many languages. | Dumps are hundreds of MB, so only practical behind a backend or as a bundled subset. | **Not now**; a good backend candidate. |
| Glosbe | Good examples. | No free API; its ToS forbid scraping. | **Reject.** |
| LibreTranslate public instances | One MT result, no alternatives. | The official instance needs a key; community instances are unreliable. | **Reject.** |
| DeepL Free / Yandex Dictionary | High quality. | Need keys, which are extractable from the app. Yandex Dictionary is deprecated for new keys. | **Reject on the client**; backend candidates. |

Recommendation: request `t`, `bd` and `at` from Google `gtx` and use MyMemory
`matches`. Merge and dedupe them, then show the primary translation plus up to 6
chips. When Apple is the primary translator, Google's own main translation also
becomes a candidate.

Future backend: a sync backend could act as a translation proxy. It could hold keys
(DeepL, Yandex), host kaikki-derived dictionaries, cache results and avoid limits
on each device. The client seam is `TranslationAlternativesService.fetch`; a backend
would replace its body only.

## Acceptance criteria

- **AC-1:** After the existing 600 ms debounce, a gated input (AC-7) starts the
  primary translation and the alternatives fetch concurrently. The primary
  translation fills the field as soon as it arrives, whether or not alternatives are
  pending. It is not delayed.
- **AC-2:** When at least one alternative that differs from the primary arrives, a
  «Варианты» row appears below the translation field. It shows the primary
  translation first, then up to 6 alternatives. Google `bd` part-of-speech labels
  appear as small secondary text, in Russian because the request sends `hl=ru`.
- **AC-3:** Tapping a chip sets the editable field to the chip text. The chip whose
  normalized text equals the field shows as selected. Tapping the first chip
  restores the primary translation. Manual editing still works, and chips never
  trigger a new translation.
- **AC-4:** Candidates are deduped by normalized form: case-folded, trimmed, with
  inner whitespace collapsed. The first-seen spelling wins. A candidate is dropped
  if any of these hold:
  - it is empty;
  - it equals the source text;
  - it fails the descriptor-driven script filter (see `isValid`);
  - it is a MyMemory match whose `segment` does not equal the source text;
  - it is a MyMemory `translatedText` starting with `MYMEMORY WARNING`.

  Order: Google `t` → Google `bd` → Google `at` → MyMemory `translatedText` →
  MyMemory matches by descending `match`.
- **AC-5:** Each alternatives source fails silently. Failures include a network
  error, a non-200 HTTP status, rate-limit HTML, malformed JSON, a MyMemory
  `responseStatus` other than 200, or exceeding the dedicated session's 5-second
  resource timeout (`timeoutIntervalForResource = 5`). On failure, Add Word behaves
  as today: same primary translation and error label, no chips, no new error.
- **AC-6:** If the primary translation fails but alternatives arrive, the existing
  error label stays. Chips show without a primary chip, and tapping one fills the
  field, so Save becomes enabled.
- **AC-7:** Alternatives are fetched only if the trimmed source:
  - has no line break;
  - has at most 4 whitespace-separated words;
  - has at most 60 characters.

  Otherwise no extra request is made.
- **AC-8:** Changing the source text clears chips and cancels the in-flight
  alternatives request. This covers typing and a dictation committed with changed
  text. Dismissing Add Word (`onDisappear` → `cancelTranslation()`) does the same.
  A late response for an older revision, or after dismissal, never appears.
- **AC-9:** Starting dictation does not clear chips. Cancelling dictation, or
  finishing without changing the text, leaves the chips visible. This includes
  the case where the primary translation failed but chips are visible: no
  rescheduling, so the chips and the error label stay. An alternatives fetch that
  was pending when dictation began still delivers its chips.
- **AC-10:** Re-appearance (`resumeTranslationIfNeeded`) while alternatives are
  pending does not start another primary translation.
- **AC-11:** The primary MyMemory fallback (`MyMemoryTranslator.translate`) returns
  `TranslationError.badResponse` when `responseStatus` ≠ 200. It never returns a
  `MYMEMORY WARNING…` text as a translation.
- **AC-12:** Language-agnostic logic:
  - every URL builder, parser, merge and script filter gets its languages through a
    `TranslationPair` built from `TranslationLanguage` descriptors;
  - no new code compares against the `"pl"` / `"ru"` literals or `AppLanguage`
    cases;
  - unit tests exercise at least one pair that is not pl/ru through the same
    functions;
  - for a language whose script `Script` already covers (Latin/Cyrillic), the
    translation layer needs only a new `TranslationLanguage.all` entry. A new
    script also needs a new `Script` case with its ranges.
- **AC-13:** Saving persists only the source and the field text, as today. The
  `Word` and `WordFolder` schemas are unchanged.
- **AC-14:** The build has no warnings, and `MojSlownikUnitTests` passes.

## Changes by file

### Services

**New `MojSlownik/Services/TranslationLanguage.swift`** (the central descriptor)

```swift
/// Writing system used to sanity-check provider candidates.
enum Script: Hashable, Sendable {
    case latin, cyrillic
    /// Unicode scalar ranges; extend when a new language needs a new script.
    var ranges: [ClosedRange<UInt32>] { … }   // latin: 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF; cyrillic: 0x400...0x4FF
    static func of(_ scalar: Unicode.Scalar) -> Script?   // nil for non-letters / unknown scripts
}

struct TranslationLanguage: Hashable, Sendable {
    let id: String               // stable app code, e.g. "pl"
    let googleCode: String       // gtx sl/tl
    let myMemoryCode: String     // langpair half
    let appleIdentifier: String  // Locale.Language(identifier:)
    let scripts: Set<Script>

    static let polish  = TranslationLanguage(id: "pl", googleCode: "pl", myMemoryCode: "pl", appleIdentifier: "pl", scripts: [.latin])
    static let russian = TranslationLanguage(id: "ru", googleCode: "ru", myMemoryCode: "ru", appleIdentifier: "ru", scripts: [.cyrillic])
    /// Supported languages: a language with an existing Script = one entry here;
    /// a new script also needs a Script case (+ AppLanguage/Word work, see plan Risks).
    static let all: [TranslationLanguage] = [.polish, .russian]
}

struct TranslationPair: Hashable, Sendable {
    let source: TranslationLanguage
    let target: TranslationLanguage
}

extension AppLanguage {
    var translationLanguage: TranslationLanguage {
        TranslationLanguage.all.first { $0.id == rawValue }!
    }
    /// Pair for translating text in this language into `other`.
    var translationPair: TranslationPair {
        TranslationPair(source: translationLanguage, target: other.translationLanguage)
    }
}
```

- The memberwise init stays internal, so tests can build descriptors such as German
  or English without shipping unused entries.
- The force-unwrap in `translationLanguage` is safe while `all` covers every
  `AppLanguage` case. A unit test asserts this.

**`MojSlownik/Services/GoogleWebTranslator.swift`**

- Extract
  `static func url(for text: String, pair: TranslationPair, dt: [String], interfaceLanguage: String? = nil) -> URL`.
  - Use `pair.source.googleCode` / `pair.target.googleCode`.
  - Repeat `URLQueryItem(name: "dt", …)` once for each entry in `dt`.
  - Add `hl` only when `interfaceLanguage` is non-nil.
  - Keep the `+` → `%2B` fix.
- `translate(_:from:to:)` builds a pair from its `AppLanguage` arguments
  (`TranslationPair(source: source.translationLanguage, target: target.translationLanguage)`)
  and calls `url(…, dt: ["t"])`. No behavior change.

**`MojSlownik/Services/MyMemoryTranslator.swift`**

- Extract
  `static func url(for text: String, pair: TranslationPair, contactEmail: String?) -> URL`
  with `langpair = "\(pair.source.myMemoryCode)|\(pair.target.myMemoryCode)"`.
- Extract the pure function
  `static func bestTranslation(from data: Data, sourceText: String, pair: TranslationPair) throws -> String`.
  `translate` calls it after the HTTP 200 check. It works as follows:
  - Decode with `MyMemoryPayload` (shared, see below). Map any decoding error
    (non-JSON, top level not an object) to `TranslationError.badResponse` with
    `do { … } catch { throw TranslationError.badResponse }`.
  - Throw `TranslationError.badResponse` if `responseStatus != 200`.
  - A nil `responseData` or `translatedText` contributes no main candidate.
  - Build the candidates, skipping any whose text starts with `MYMEMORY WARNING`
    (case-insensitive, after `unescape`).
  - Return the first candidate that passes `TranslationAlternatives.isValid(_:sourceText:pair:)`.
  - Otherwise throw `.emptyResult`.
- Remove the private `isValid` / `unescape`, which move to `TranslationAlternatives`.

  Behavior note: for pl→ru, today's filter only requires Cyrillic. The new filter
  also rejects candidates containing Latin letters (see `isValid`). This tightening
  is intended; it filters, for example, «Замок PFP».

**New `MojSlownik/Services/TranslationAlternatives.swift`**

```swift
struct TranslationAlternative: Equatable, Hashable, Sendable {
    let text: String
    let partOfSpeech: String?
}

/// Shared lenient MyMemory payload (used by MyMemoryTranslator and alternatives).
struct MyMemoryPayload: Decodable {
    struct ResponseData: Decodable { let translatedText: String? }
    struct Match: Decodable { let segment: String?; let translation: String; let match: Double? }
    let responseStatus: Int?        // Int or numeric String; missing/garbage → nil
    let responseData: ResponseData? // error responses may omit it or send null
    let matches: [Match]?
}

enum TranslationAlternatives {
    static let maxAlternatives = 6
    static let myMemoryWarningPrefix = "MYMEMORY WARNING"
    static func shouldFetch(_ text: String) -> Bool
    static func normalized(_ text: String) -> String
    static func unescape(_ text: String) -> String
    static func isValid(_ candidate: String, sourceText: String, pair: TranslationPair) -> Bool
    static func parseGoogle(_ data: Data) -> [TranslationAlternative]
    static func parseMyMemory(_ data: Data, sourceText: String) -> [TranslationAlternative]
    static func merge(primary: String?, groups: [[TranslationAlternative]],
                      sourceText: String, pair: TranslationPair) -> [TranslationAlternative]
}
```

- `MyMemoryPayload` uses a custom `init(from:)`:
  1. Decode `responseStatus` **first**, with `decodeIfPresent(Int.self)`. On a type
     mismatch, fall back to `decodeIfPresent(String.self).flatMap(Int.init)`, and
     use nil if that fails.
  2. Decode `responseData` with `try? decodeIfPresent(ResponseData.self, …)`, so it
     can be absent, null or malformed.
  3. Decode `matches` with `try? decodeIfPresent([Match].self, …)`.

  A non-200 or error payload therefore always yields a status to check instead of
  failing to decode. Do not decode `quality`.
- `isValid`, driven by the descriptors:
  1. Reject the candidate if it is empty after trimming, or if
     `normalized(candidate) == normalized(sourceText)`.
  2. Classify each letter scalar with `Script.of`.
  3. Require at least one letter whose script is in `pair.target.scripts`.
  4. Reject any letter whose script is in `pair.source.scripts.subtracting(pair.target.scripts)`,
     meaning source-only scripts leaking into the output.
  5. Reject any letter with an unknown script (`nil`) or a script outside
     `source.scripts ∪ target.scripts`.
  6. Ignore digits, punctuation and symbols.

  Results:
  - pl→ru: needs Cyrillic, rejects Latin.
  - ru→pl: needs Latin, rejects Cyrillic (same as today).
  - Same-script pairs such as pl→en or de→en: needs Latin. Only the
    "equals source" check removes echoes.
- `parseGoogle` and `parseMyMemory` are format parsers and take no language. Their
  output is not language-specific; all language-dependent filtering happens in
  `merge` / `isValid` with the pair. This keeps one filtering point.
- `parseGoogle`. Parse with `JSONSerialization` and check every cast:
  - `root[0]`: join the string at index `[0]` of each segment into one `t`
    candidate.
  - `root[1]`, if it is an array (`bd`): each entry is `[pos: String, terms: [String], …]`.
    Emit each term with `partOfSpeech = pos`, or nil if `pos` is empty.
  - `root[5]`, if it is an array with exactly one segment (`at`): read element
    `[2]` of that segment, which is `[[altText, score, …], …]`, and emit each
    `altText` in order. Skip `at` for multi-segment input, because those
    alternatives are partial fragments.

  Output order is `t`, `bd`, `at`. Anything else, including HTML, returns `[]`.
- `parseMyMemory`:
  - Return `[]` if decoding fails or `responseStatus != 200`. A nil
    `responseData` or `translatedText` contributes no main candidate.
  - Otherwise output `translatedText` first, unless it starts with
    `myMemoryWarningPrefix` (case-insensitive).
  - Then the matches whose `normalized(segment) == normalized(sourceText)`, sorted
    by `match` descending, all passed through `unescape`.
- `merge`:
  1. Build `[primary] + groups.flatMap { $0 }`.
  2. Trim each text and drop candidates that fail `isValid`.
  3. Dedupe by `normalized`, keeping the first spelling. If the kept item has no
     part-of-speech label, adopt the first non-nil label among its duplicates.
  4. Remove the primary's normalized key.
  5. Cap at `maxAlternatives`.
- `shouldFetch`: return false if the trimmed text is empty, contains `\n` or `\r`,
  has more than 4 words, or has more than 60 characters.

**New `TranslationAlternativesService`** (same file)

```swift
enum TranslationAlternativesService {
    /// Google `hl`: language of part-of-speech labels. App UI copy is Russian.
    static let interfaceLanguage = "ru"
    /// Returns [googleCandidates, myMemoryCandidates]; never throws, [] per failed source.
    static func fetch(_ text: String, pair: TranslationPair) async -> [[TranslationAlternative]]
}
```

- Use a dedicated session:
  `private static let session: URLSession = { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 5; return URLSession(configuration: c) }()`.
  An ephemeral configuration keeps results out of the on-disk cache.
- Run the two requests with `async let`. For each request:
  - `try await session.data(from:)`, require HTTP 200, then parse;
  - catch every error and return `[]`.

  The URLs are:
  - Google: `GoogleWebTranslator.url(for: text, pair: pair, dt: ["t", "bd", "at"], interfaceLanguage: interfaceLanguage)`.
  - MyMemory: `MyMemoryTranslator.url(for: text, pair: pair, contactEmail: MyMemoryTranslator().contactEmail)`.
- Cancellation of the parent task cancels both `URLSession` tasks, and both
  results become `[]`.

`TranslationService.swift` (`Translator`) is unchanged.

**`MojSlownik/Services/AppleTranslator.swift`**

- Replace `Locale.Language(identifier: source.rawValue)` and the target equivalent
  with `Locale.Language(identifier: source.translationLanguage.appleIdentifier)`.
  This is a one-line change each, identical in behavior, and makes the descriptor
  the single source of codes.

### Stores

**`MojSlownik/Stores/AddWordDraft.swift`**

New state and API:

- `private(set) var alternatives: [TranslationAlternative] = []` (merged, primary
  excluded).
- `private(set) var primaryTranslation: String?`.
- `private var awaitingAlternatives = false`: true after the primary has been
  handled while the alternatives fetch is still running.
- `var translationOptions: [TranslationAlternative]`:
  - empty if `alternatives` is empty;
  - otherwise `primaryTranslation` (if any) as a chip with
    `partOfSpeech: nil`, followed by `alternatives`.
- `func isSelected(_ option: TranslationAlternative) -> Bool`: normalized
  comparison with `translatedText`.
- `func select(_ option: TranslationAlternative)`: sets
  `translatedText = option.text`.
- Init parameter
  `alternatives: @escaping (String, TranslationPair) async -> [[TranslationAlternative]]`,
  defaulting to `{ await TranslationAlternativesService.fetch($0, pair: $1) }`.

Cancellation:

- Split the cancellation logic:
  - `private func cancelTask()`: `revision += 1`, cancel the task, `task = nil`,
    `isTranslating = false`, `awaitingAlternatives = false`.
  - `func cancelTranslation()` (public; used by `onDisappear` and scheduling):
    `cancelTask()`, then `alternatives = []` and `primaryTranslation = nil`
    (AC-8).
- `beginDictation()`:

  ```swift
  needsResume = translatedText.isEmpty && alternatives.isEmpty
  suspended = true
  if !awaitingAlternatives { cancelTask() }
  ```

  `alternatives.isEmpty` covers a failed primary with visible chips. A cancelled
  dictation must not reschedule, because rescheduling would clear the chips the user
  can still pick from. If the primary failed and alternatives are still pending,
  `alternatives` is empty, so `needsResume` is true. `endDictation` then reschedules
  both requests, as today.

  It no longer clears chips (AC-9). If only alternatives are pending, the task
  keeps running. It can write only `alternatives` / `task`, never
  `translatedText`, and its revision stays valid until the text actually changes.
  If the primary is still pending, the task is cancelled as today. Chips from an
  earlier completed fetch stay, because `cancelTask()` does not clear them.
- `commitDictation`, `endDictation` and `resumeTranslationIfNeeded`: unchanged.
  - A committed text goes through `setSource` → `scheduleTranslation` →
    `cancelTranslation()`, which clears the chips. Committing identical text
    restarts the request, as the existing test requires, and refetches chips.
  - `endDictation` with `needsResume` schedules the request again, as today. It is
    never set when chips are visible.
  - `resumeTranslationIfNeeded` keeps its `task == nil` guard. The task stays
    non-nil until alternatives finish, so there is no restart (AC-10).

`scheduleTranslation()`, inside the existing `Task`, after the debounce and the
revision guard:

1. `let pair = source.translationPair`.
2. `async let groups = TranslationAlternatives.shouldFetch(text) ? alternativesFetch(text, pair) : []`.
   Start this before the primary call.
3. Run the existing primary `do/catch`:
   - On success, set `translatedText` and `primaryTranslation`.
   - On error, set `translationError`.
   - In both branches, set `isTranslating = false` and
     `awaitingAlternatives = true`.
   - Do not `return` from the catch branch, and do not set `task = nil` yet.

   Keep the existing `guard !Task.isCancelled, revision == requestRevision`
   before each write. If the guard fails, return; `async let` is cancelled
   implicitly.
4. `let fetched = await groups`, then the same guard. Then set
   `alternatives = TranslationAlternatives.merge(primary: primaryTranslation, groups: fetched, sourceText: text, pair: pair)`,
   `awaitingAlternatives = false` and `task = nil`.

### Views

**`MojSlownik/Views/AddWordView.swift`**

- Add `@Environment(\.dynamicTypeSize) private var dynamicTypeSize`.
- In `translationCard`, after the error label and before the pronounce row, add
  `if !draft.translationOptions.isEmpty { alternativesRow }`.
- `alternativesRow`:
  - The caption `Text("Варианты")` (`.caption.weight(.semibold)`, `Color.subtleText`).
  - Then a `ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) }` of
    chips. When `dynamicTypeSize.isAccessibilitySize`, use
    `VStack(alignment: .leading, spacing: 8)` instead, with no scroll view.
- Chip: a `Button { draft.select(option) }` whose label is a
  `VStack(alignment: .leading, spacing: 2)`:
  - `Text(option.text)` (`.subheadline.weight(.medium)`);
  - an optional `Text(pos)` (`.caption2`).

  Styling:
  - padding: 12 horizontal, 8 vertical; `.frame(minHeight: 44)`;
  - shape: `RoundedRectangle(cornerRadius: 14)`;
  - selected: `Color.appAccent` fill with `Color.appOnAccent` text (including
    the part-of-speech text);
  - otherwise: `Color.appSecondarySurface` fill, `Color.appInk` text and a
    `Color.subtleText` part-of-speech label.

  Modifiers: `.disabled(speech.isBusy)`,
  `.accessibilityLabel(option.text + (option.partOfSpeech.map { ", \($0)" } ?? ""))`,
  and `.accessibilityAddTraits(draft.isSelected(option) ? .isSelected : [])`.
- Footnote copy: «Речь может обрабатываться на серверах Apple. Введённый и распознанный
  текст отправляется сервисам перевода (Google, MyMemory).»

### Docs

**`docs/architecture.md`**

- Translation row: add `TranslationLanguage.swift` (descriptor table) and
  `TranslationAlternatives.swift`.
- Adding flow and Non-obvious Constraints: alternatives are fetched in parallel, are
  gated, are silent on failure and are not persisted. They send text to Google and
  MyMemory even when Apple translates. The script filter comes from the descriptors.
- Update the MyMemory constraint line: it now rejects a non-200 `responseStatus`
  and warning texts, and the script rule now also rejects source-script letters.
- Unit Tests paragraph: mention alternatives parsing, merging and the language
  descriptors.

Run `xcodegen generate` after adding the files.

## Reuse

- The URL building, `+` escaping and contact email in `GoogleWebTranslator` and
  `MyMemoryTranslator`, through the extracted static helpers.
- The MyMemory `unescape` / validity logic: moved and generalized, not duplicated.
- `AddWordDraft`'s revision and cancellation pattern; `LanguageDetector`;
  `AppLanguage.other`.
- Theme: `appAccent`, `appOnAccent`, `appSecondarySurface`, `appInk`, `subtleText`.
- The continuation stub pattern from `AddWordDraftTests`.

## Data compatibility

- No SwiftData changes. `Word` / `WordFolder` are untouched, so no migration is
  needed.
- Alternatives exist only in memory in `AddWordDraft`.
- Only the user-chosen translation string is saved. It is provider-neutral, which
  keeps it ready for sync.

## Privacy, rate limits, offline

- **Privacy:** on iOS 18 with offline Apple translation, text currently may never
  leave the device. Now every gated input is also sent to Google and MyMemory. The
  footnote is updated; automatic loading is confirmed (Decision 1).
- **Rate limits:** the debounce and gate keep this to about one Google and one
  MyMemory call per settled word.
  - MyMemory quota exhaustion is detected (`responseStatus`, `MYMEMORY WARNING`) and
    is silent for alternatives. It is a `badResponse` for the primary fallback, as
    today with HTTP errors.
  - If Apple fails, Google is hit twice per word: once for the primary translation
    and once for alternatives.
- **Offline:** requests fail fast or hit the 5-second resource timeout. No chips
  appear, and the primary translation is unchanged.

## Verification

### Unit tests

New `MojSlownikTests/TranslationAlternativesTests.swift`, with inline JSON fixtures.
Define these helpers at the top of the file:

- `pl_ru = TranslationPair(source: .polish, target: .russian)` and
  `ru_pl = TranslationPair(source: .russian, target: .polish)`;
- the test-only descriptors `german` (`de`, `[.latin]`) and `english` (`en`,
  `[.latin]`);
- `de_ru` and `pl_en`.

1. `testParseGoogleReadsTranslationDictionaryAndAlternatives`. Use the **captured
   real** `zamek` pl→ru response (see the required step below), trimmed. Assert the
   `t` → `bd` (with Russian `pos`) → `at` order.
2. `testParseGoogleSkipsMultiSegmentAlternativesAndHandlesNullDictionary`.
3. `testParseGoogleReturnsEmptyForHtmlAndMalformedInput`. Inputs: the "Sorry…" HTML,
   `{}`, `[]`, `[null]`.
4. `testParseMyMemoryKeepsExactSegmentMatchesSortedByScore`. Use the real `zamek`
   shape, with `quality` both `"0"` and `74`. Include a `Zamek PFP` segment, which
   is excluded, and an `&#39;` entity, which is unescaped.
5. `testParseMyMemoryRejectsNon200StatusAsIntOrString`. Use `responseStatus: 429`
   and `responseStatus: "403"`; both return `[]`. `"200"` as a string is accepted.
6. `testParseMyMemoryDropsQuotaWarningText`. `translatedText` is
   `"MYMEMORY WARNING: YOU USED ALL AVAILABLE FREE TRANSLATIONS…"` with
   status 200 and valid matches. The warning is dropped and the matches are kept.
7. `testParseMyMemoryReturnsEmptyOnMalformedJSON`.
8. `testIsValidUsesDescriptorScripts`:
   - pl→ru: «замок» ok; «Замок PFP» and `zamek` rejected.
   - ru→pl: `zamek` ok; «замок» rejected.
   - pl→en: `castle` ok; `zamek` rejected because it equals the source.
   - de→ru: «замок» ok; `Schloss` rejected.
   - Digits and punctuation are ignored: «замок-2» is ok for pl→ru.
9. `testMergeDedupesCaseInsensitivelyExcludesPrimaryAndSourceAndCaps` (pl→ru):
   checks dedupe, first spelling kept, the primary excluded, invalid items dropped,
   the cap of 6, and part-of-speech adoption.
10. `testMergeWorksForNonPolishRussianPair` (de→ru and pl→en): the same pure
    `merge` call with a mixed-script group, filtered according to each pair's
    descriptor.
11. `testMergeWithoutPrimaryKeepsAllValidCandidates`.
12. `testShouldFetchGate`: `"kot"`, `"dzień dobry"`, 4 words, 5 words, 61
    characters, `"a\nb"`, `"   "`.
13. `testGoogleURLUsesDescriptorCodesAndInterfaceLanguage`. For a de→ru pair,
    `GoogleWebTranslator.url(…, dt: ["t","bd","at"], interfaceLanguage: "ru")` has
    `sl=de`, `tl=ru`, three `dt` items, `hl=ru`, and `+` encoded as `%2B`. With
    `dt: ["t"]` and no interface language, the query matches today's primary URL
    exactly.
14. `testMyMemoryURLUsesDescriptorCodes`: `langpair=de|ru`, and `de` is present.
15. `testEveryAppLanguageHasDescriptor`: `AppLanguage.allCases` maps through
    `translationLanguage` without trapping, and `translationPair.target` equals
    `other.translationLanguage`.

New `MojSlownikTests/MyMemoryTranslatorTests.swift`, covering the primary-path fix:

16. `testBestTranslationThrowsOnNon200ResponseStatus`: `429` and `"403"` throw
    `badResponse`.
17. `testBestTranslationSkipsQuotaWarningAndUsesValidMatch`.
18. `testBestTranslationPrefersValidMainResponse` (regression for today's
    behavior).
18a. `testBestTranslationMapsErrorPayloadsToBadResponse`. Cases:
    - `{"responseStatus":"403","responseData":null,"responseDetails":"…"}`;
    - `{"responseStatus":429}` with no `responseData`;
    - a non-JSON body;
    - a top-level array.

    All four throw `TranslationError.badResponse`, not a `DecodingError`.
    `parseMyMemory` returns `[]` for the same inputs.

`AddWordDraftTests` changes:

19. Add a `makeDraft(translate:alternatives:)` helper. Every **existing** test passes
    `alternatives: { _, _ in [] }`, so no test touches the network.
20. Add an `AlternativesStub`, a continuation-based stub that records
    `(text, pair)`.
21. `testAlternativesDoNotDelayPrimaryAndAppearAfterward`. Resume the primary
    first: the field is set and the options are empty. Resume the alternatives: the
    options are `[primary] + merged`.
22. `testSelectingAlternativeUpdatesTranslationWithoutRetranslating`: after
    `select`, `isSelected` is true for that chip only and the translate call count
    is unchanged.
23. `testStaleAlternativesAreIgnoredAfterSourceChange`: `kot` → `pies`; a late `kot`
    response is ignored.
24. `testPrimaryFailureStillShowsAlternatives`.
25. `testLongInputSkipsAlternativesFetch`: a 5-word source makes zero alternatives
    calls.
26. `testDismissClearsAlternativesAndRejectsLateResponse`.
    1. Chips are visible from an earlier completed fetch; `cancelTranslation()`
       clears the options.
    2. A second scenario: a fetch is pending, `cancelTranslation()` is called, then
       the stub resumes. The options stay empty.
27. `testDictationClearsVisibleAlternativesOnlyWhenTextChanges`. With chips visible:
    - `beginDictation()` keeps the chips;
    - `endDictation()` without a commit (cancelled dictation) keeps them;
    - `beginDictation()` + `commitDictation("pies")` clears them, and a new
      alternatives request for `pies` is recorded.
27a. `testFailedPrimaryWithVisibleChipsSurvivesCancelledDictation`. The primary
    fails and the alternatives resolve, so chips are visible and the field is empty.
    Then `beginDictation()` and `endDictation()` with no commit. Expect: the
    translate call count stays at 1, the alternatives call count stays at 1, the
    chips stay unchanged, and `translationError` is still set.
28. `testPendingAlternativesSurviveCancelledDictation`. Resolve the primary while
    alternatives are pending. Then `beginDictation()`, `endDictation()`, and resume
    the alternatives stub. The chips appear, and the translate call count is 1.
29. `testResumeDuringPendingAlternativesDoesNotRestart`. The primary fails and
    alternatives are pending. Call `resumeTranslationIfNeeded()` twice: the
    translate call count stays at 1. Resume the alternatives: the options appear.

### Required implementer step

Before writing test 1, capture one real Google response:

```sh
curl -s 'https://translate.googleapis.com/translate_a/single?client=gtx&sl=pl&tl=ru&hl=ru&dt=t&dt=bd&dt=at&q=zamek'
```

Trim it to the fields used and paste it as the fixture. Adjust `parseGoogle`
indexes if the live shape differs from the one described above. If Google
throttles (HTML "Sorry…"), retry from another network or later. Report it if no
real response could be captured, and do not invent one silently.

### Build and run

```sh
xcodegen generate
xcrun simctl list devices available
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' build | grep -E 'error:|warning:|SUCCEEDED|FAILED'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests \
  -destination 'platform=iOS Simulator,name=<installed iPhone>' test | grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'
```

### Manual checks

In the simulator, Apple translation is skipped:

- **`zamek`:** the chips have Russian part-of-speech labels. Pick «застёжка» and
  save; the Dictionary shows the chosen text.
- **`кот`:** the chips are Polish only, and their labels are Russian.
- **Fast typing (`kot` → `pies`):** no stale chips appear.
- **6-word sentence:** no chips; translation works as before.
- **Offline:** no chips and no new error.
- **Accessibility XXL text:** the chips stack vertically.
- **Dictation:** start dictation with chips visible and cancel it; the chips
  remain. Dictate a different word; the chips refresh.
- **Regressions:** dictation, folders/categories, the scanner's correction menu
  opening `AddWordView`, flashcards and quiz.
- **Physical iOS 18 device with Apple packs:** the Apple result is the primary chip,
  and Google `t` appears when it differs. If no device is available, report that.

## Risks

- **Google's undocumented format:** the `bd` / `at` indexes may change. Parsing is
  defensive, so the worst case is no chips. Capturing a real response is a required
  step.
- **Google throttling:** the extra call raises the chance of throttling, which can
  also affect the primary fallback. Mitigated by the debounce and the gate. A
  possible follow-up: reuse the alternatives response as the primary when Apple
  fails.
- **MyMemory noise:** crowd entries can be wrong. Mitigated by the segment, script
  and quota filters and the cap; the user still chooses.
- **Tighter primary MyMemory filter:** for pl→ru it now rejects candidates with Latin
  letters, such as brand names. The fallback may then pick a lower-ranked candidate
  or fail with `emptyResult`. Tests 17 and 18 cover the intended cases.
- **Privacy:** text now reaches Google and MyMemory on devices where Apple translates
  offline (see Privacy).
- **`AddWordDraft` task lifetime:** the task now lives until alternatives finish
  (up to 5 s), and dictation may leave it running. Revision guards cover every
  write. Tests 26–29, including 27a, cover dismissal, dictation, resume and stale responses.
- **Future multi-language support:** this plan makes only the translation layer
  language-agnostic. These parts are still pl/ru-specific and need separate work:
  - `Word.russian` / `Word.polish` (stored lowercased), `Word.sourceLanguageCode`
    and `WordCategory.detect(russian:polish:)`;
  - `AppLanguage` (`other`, `displayName`, `flag`, `speechCode`);
  - `LanguageDetector` (Cyrillic means Russian);
  - quiz, flashcard and listening code that reads `russian` / `polish`.

  Generalizing `Word` into, for example, `term` / `translation` plus language codes
  needs a SwiftData migration that preserves existing words. Do it as its own task,
  ideally together with the backend sync schema design, so the stored format is
  settled once. Adding a language later means a new `TranslationLanguage.all`
  entry, an `AppLanguage` case and that migration.
- **Layout:** chips beyond the visible width are reached by horizontal scroll;
  accessibility text sizes switch to a vertical list.

## Decisions

The user answered these on 2026-11-16:

1. **Chips load automatically.** No «Показать варианты» button. The privacy footnote
   update stays.
2. **No Wiktionary or kaikki source now.** It may be added later through the
   backend.
3. **No alternatives on the scanner's quick-add cards.** `ScanResultDraft` and
   `ScanResultView` are unchanged.
4. **`Word` is unchanged.** Neither the chosen alternative nor the part of speech is
   stored.
5. **Limits confirmed:** up to 6 alternative chips; fetch only when the input is at
   most 4 words and at most 60 characters.
6. **Part-of-speech labels in Russian:** Google gets `hl=ru` through the constant
   `TranslationAlternativesService.interfaceLanguage`, matching the UI. If a UI
   language setting appears later, it replaces the constant.

## Open decisions

None.

## Approval

2026-11-16 — approved by user.
