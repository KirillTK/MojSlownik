# TODO: guided learning (tester feedback 2026-11-28)

Tracker for the work from [feedback-roadmap.md](feedback-roadmap.md) (feedback, decisions, phase
details). Tasks are done in separate chats; this file is the shared context. Update it in the same chat
that changes a task's state (tick boxes, add branch/PR/plan links, note new decisions).

**Starting a new chat:** "Read .codex/plans/feedback-todo.md and feedback-roadmap.md, take task <N>."

## Process

- **Small tasks** (Phase 0, Phase 1, content scripts): implement directly, no `/ios-feature-flow`.
  Write unit tests where logic changes, build with zero warnings, run unit tests locally, run
  `/code-review`, open a PR. **Do not run E2E locally**: CI runs the full suite on the PR; watch it.
- **Large tasks** (Phases 2, 3, 4): first design with `/mobile-ios-design` (HTML mockups, then the user
  approves), then `/ios-feature-flow <link to this task + approved design>`. Its plan goes into
  `.codex/plans/<slug>.md` and is linked below.
- Branches `feature/<slug>` / `fix/<slug>` from `main` (after `feature/fsrs-review-log` is merged).
- Every new string: en + ru. Never lose stored words.

Status: `[ ]` todo · `[~]` in progress · `[x]` done.

## Phase 0 — Camera access (small) · branch `feature/camera-access` · [~] PR open

- [x] Scan button: `camera.viewfinder` icon + visible "Scan" / «Сканировать» label (44 pt, VoiceOver)
- [x] Home Screen quick action "Scan text" → opens the scanner (unit test for routing; E2E via
      `UITEST_QUICK_ACTION`). Dynamic item: appears after the first launch; skipped while a sheet is open
- [x] Count taps from scan to saved word: scan button → tap a line → tap word chip (saves) → Done =
      4 taps for one word, +1 per extra word. Already minimal; no change
- [x] /code-review (done, fixes applied) → PR → CI green (awaiting merge)
- Manual: camera/OCR on a device; long-press icon → "Scan text" on a device. PR: #17

## Phase 1 — Narrow languages (small) · branch `feature/narrow-languages` (stacked on #17) · [~]

- [x] Selectable studied languages: pl, en, de. Translation: ru, uk, en. No same-language pairs
      (`Language.studyOrder` / `translationOrder`; en ← en stays disabled in the wizard)
- [x] Sync validation still accepts every existing code; legacy workspaces load and keep their words
      (`Language.all` / `LanguageCodes.supported` unchanged, so no provider mapping is removed)
- [x] Legacy pairs cannot be created anew: the wizard is the only create path (the workspace manager
      opens it too). A soft-deleted legacy pair keeps its languages listed so its words can come back
      (`WorkspaceWizardChoices.studyLanguages` / `translationLanguages(for:)`)
- [~] Unit tests + E2E picker check (CI) → /code-review (done, fixes applied) → PR → CI green
- PR: #18 (base: feature/camera-access)

## Phase 2 — Onboarding wizard and study plan (large) · branch `feature/onboarding-plan`

- [ ] Design (`/mobile-ios-design`): wizard steps sign-in (skippable) → studied → translation → level →
      daily load → topics; Account "Study plan"; "Set up your plan" card. **User approval**
- [ ] `/ios-feature-flow` plan: (link)
- [ ] Implementation: plan fields on Workspace + migration/RLS/DB test; gate with sign-in step; daily
      new-word limit + backlog rule; Account section
- [ ] PR → CI green. PR:

## Phase 3 — Today home screen (large) · branch `feature/today-screen`

- [ ] Design: tabs Today · Dictionary (Practice merges into Today), one Start button, progress, camera
      card, achievements, plan card; Dictionary empty state. **User approval**
- [ ] `/ios-feature-flow` plan: (link)
- [ ] Implementation + E2E fixtures (empty, due words, no plan)
- [ ] PR → CI green. PR:

## Phase 4 — Word-set catalog (large) · branch `feature/word-catalog`

- [ ] Design: new-word card with "I already know this", topic folders, topic picker. **User approval**
- [ ] `/ios-feature-flow` plan: (link)
- [ ] Implementation: bundled JSON per pair, planner service, `catalogEntryID` (+ migration), topic
      folders, `scripts/check-catalog.sh` in CI
- [ ] PR → CI green. PR:

## Content track (parallel, starts now)

- [ ] Agree on the catalog JSON format (draft in roadmap Phase 4) before generating data
- [ ] pl → ru, A1 (~300–500 entries, topics, examples): generate, user reviews translations
- [ ] pl → uk, pl → en A1 (same entries, new translations)
- [ ] Polish A2; then English and German pairs (A1 from Goethe / Cambridge reference lists)
- Sources: see roadmap › Content sources.

## Phase 5 — Later

- [ ] App Intent "Scan text" + Control Center / Lock Screen control (iOS 18, `#available`), Action button
- [ ] Placement mini-test for "I don't know my level"
- [ ] More levels/pairs; topic picker after onboarding

## Decision log

- 2026-11-28: soft sign-in; studied pl/en/de; translation ru/uk/en; plan settings per pair; daily load
  5/10/20/30 min → 5/10/20/30 new words; no new words when due > 3× limit; Practice merges into Today;
  large tasks need design approval first; small tasks skip local E2E.
