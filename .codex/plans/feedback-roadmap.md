# Roadmap from tester feedback (2026-11-28)

Umbrella plan. Each phase is its own branch (`feature/<slug>`) and PR, planned in detail with
`/ios-feature-flow` (UI phases also `/mobile-ios-design`) into its own plan file. This file records the
feedback, the binding decisions and the phase order; it is not an implementation plan.

## Feedback (summary)

1. Likes the palette: "yellow highlighter" association. Keep it.
2. Opens on an empty Dictionary: unclear what to do or what else the app has. Practice is easy to miss and
   should be the main screen. Wants the app to suggest what to do: a study plan, a word pool matching her
   level.
3. Does not want to type words in; expected content to be there already.
4. The only manual action worth doing is pointing the camera at text; wants faster access to it.

## Product direction

The app moves from "a personal dictionary I fill myself" to "an app that leads me": ready word sets by
level and topic, a daily plan, Today as the home screen. The own-dictionary and camera features stay.

## Decisions (user, 2026-11-28)

- D1 **Soft sign-in.** Sign-in is the first, prominent wizard step with a small "Continue without an
  account" link (App Store guideline 5.1.1(v)). Not mandatory.
- D2 **Fewer languages.** Studied: Polish, English, German. Translation: Russian, Ukrainian, English. Same-language pairs are not offered. The other languages are
  removed from pickers.
- D3 **Wizard is shown on first launch** and the plan parameters are editable later in Account.
- D4 **Daily load** is chosen in minutes and mapped to a new-words-per-day limit; due reviews are never cut.
- D5 **Camera** gets a recognisable icon and a text label, and faster entry points.
- D6 Word sets are organised by **level (CEFR) → topic**, ordered by frequency inside a level. Part of
  speech is a filter/attribute, plus a "Core verbs" set per level; not separate "top adjectives" decks.

Still binding (AGENTS.md, memory): never lose stored words; SwiftData additions optional/defaulted;
migrations as new files with RLS + DB tests; en+ru for every string; not in production, so breaking
changes and no old-client compatibility are fine.

## Resolved decisions (user, 2026-11-28)

- O1 Translation languages: **ru, uk, en**.
- O2 Plan settings (level, daily load, topics) are **per pair** (stored on `Workspace`, synced).
- O3 More new words than first proposed: daily load **5 / 10 / 20 / 30 min → 5 / 10 / 20 / 30 new
  words** (tunable later). Backlog rule accepted: no new words that day when due reviews exceed 3× the
  new-word limit.
- O4 Sources: see "Content sources" below.
- O5 Practice **merges into Today**; tabs become Today · Dictionary.
- Process: Phases 2–4 get a design approved by the user before `/ios-feature-flow`; small tasks are
  implemented directly with unit tests, `/code-review` and a PR, without local E2E (CI runs it).
  Tracking: [feedback-todo.md](feedback-todo.md).

## Content sources

- **Frequency order (pl, de, en):** Leipzig Corpora Collection word lists, CC BY 4.0
  (linked from https://en.wiktionary.org/wiki/Wiktionary:Frequency_lists/Polish). Needs an attribution
  line (Account › About). Avoid hermitdave/FrequencyWords for bundled data: content is CC BY-SA 4.0
  (share-alike would apply to our catalog).
- **Level reference, not copied verbatim:** German: Goethe-Institut A1 word lists
  (Start Deutsch 1, Fit in Deutsch 1), A2/B1 likewise. English: English Vocabulary Profile
  (englishprofile.org), Cambridge A2 Key / B1 Preliminary vocabulary lists. Polish: no open CEFR list
  found; assign levels by frequency band + topic, generated and reviewed by the user.
- Entries (translations, examples) are our own: generated, then reviewed.

## Phases

### Phase 0 — Camera access (small) `feature/camera-access`

- Floating scan button: `camera.viewfinder` instead of `text.viewfinder`, with a visible label
  ("Scan" / «Сканировать»); keep the 44 pt target and VoiceOver label.
- Home Screen quick action "Scan text" (`UIApplicationShortcutItem`) that opens the scanner.
- Count steps from scan to saved word; trim obvious extra taps if any (separate item if non-trivial).
- Tests: E2E for the quick-action launch path if it can be driven by a launch argument; unit test for the
  shortcut routing. Manual: camera/OCR on device.

### Phase 1 — Narrow languages (small/medium) `feature/narrow-languages`

- Split "selectable" from "known": pickers (wizard, workspace manager) offer only D2 pairs; sync validation
  (`LanguageCodes.supported`, Backend/RemoteRecords.swift) keeps accepting every existing code so a legacy
  workspace (e.g. fr→ru) still loads and its words are never dropped.
- Legacy workspaces stay usable read/practice; they cannot be created anew.
- Remove now-unused provider mappings only if no stored workspace can reference them (otherwise keep).
- Tests: unit (selectable list, legacy pair still validates), E2E wizard picker.

### Phase 2 — Wizard and study plan settings (large) `feature/onboarding-plan`

- Wizard steps: 1 sign-in (soft, D1) → 2 studied language → 3 translation language → 4 level
  (From zero / A1 / A2 / B1) → 5 daily load (5 / 10 / 20 / 30 min) → 6 topics (optional, skippable).
  If sign-in pulls an existing workspace with a plan, skip the remaining steps (extends WorkspaceGate).
- Model: optional `level`, `dailyMinutes`, `topics` on `Workspace` (per O2) + migration on `workspaces`
  with RLS/DB tests; RemoteRecords validation.
- Existing workspaces without a plan: Today/Practice shows a "Set up your plan" card, no forced wizard.
- Account → "Study plan" section to edit level, load, topics; changes apply from the next local day.
- Daily new-word limit (O3: 5/10/20/30 min → 5/10/20/30) enforced in the practice queue for words never reviewed (works before the
  catalog exists; the catalog later feeds the same queue).
- Tests: unit (gate phases incl. sign-in step, minutes→limit, backlog rule, plan validation), DB test,
  E2E wizard with/without account via fixtures (`UITEST_FIXTURE`, signed-in fixture; no real OAuth).

### Phase 3 — Today home screen (medium/large, design first) `feature/today-screen`

- `/mobile-ios-design`: HTML mockups → approval → simulator screenshots.
- Tabs: Today · Dictionary (O5). Today shows: due reviews and new words for today with one Start button,
  daily progress (marker bar), a large "Point the camera at text" card, streak/achievements entry,
  the plan card from Phase 2 when no plan is set.
- Empty dictionary no longer a dead end: the Dictionary empty state points to Today and the camera.
- Tests: E2E Today flows with fixtures (empty, due words, plan not set), unit for any new summary logic.

### Phase 4 — Word-set catalog engine (large) `feature/word-catalog`

- Format: bundled JSON per pair, e.g. `Resources/Catalog/pl-ru.json`; entry = stable `id`, `term`,
  `translation`, optional `example`, `level`, `topic`, `partOfSpeech`, `rank`. Domain data, not localized
  (`// l10n:data` rules apply to any Swift fixtures).
- The catalog is **not** copied into SwiftData. A planner service (Services/Catalog/) picks the next
  entries by level → topic preference → rank, up to the daily limit, and creates real `Word`s through
  VocabularyStore with an optional synced `catalogEntryID` (no re-introducing; migration + RLS test).
- Introduced words go into auto folders per topic (e.g. "A1 · Food"); removing the folder never deletes
  words.
- New card actions: learn it / "I already know this" (marks it known so it is not scheduled as new).
- `scripts/check-catalog.sh` in CI: valid JSON, unique ids, allowed levels/topics, no empty fields.
- Tests: unit (planner selection, limit, no duplicates, known-word path, catalogEntryID sync validation),
  E2E: a fixture with a small catalog → Today offers new words → practice adds them.

### Parallel track — Content (starts now, independent of code)

- Frequency sources per "Content sources"; build pl-ru A1 (~300–500 entries) with topics and examples, user review.
- Then pl-uk and pl-en A1, A2 for Polish, then English and German pairs.

### Phase 5 — Later

- App Intent "Scan text" + Control Center / Lock Screen control (iOS 18 behind `#available`), Action button.
- Placement mini-test for "I don't know my level".
- More levels/pairs; topic picker after onboarding.

## Order

0 → 1 → 2 → 3 → 4, content in parallel from day one. Phases 0 and 1 are independent and quick; 3 can start
its design work while 2 is in implementation. Start new branches from `main` after
`feature/fsrs-review-log` is merged.
