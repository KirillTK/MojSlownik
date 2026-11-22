# Language workspaces

Status: implementation plan drafted (analysis, design and backend design approved; plan awaits
critic → reviewer → user approval). Sections from «Implementation goal» onward are the plan;
the sections above it are the approved inputs and stay authoritative.
Base: c3b5bf4d599b8289592df1ba4d749e909228619d, clean tree.

## Goal

The user chooses the studied language and the translation language. Each pair is a workspace with
its own words, folders and practice scope. A mini wizard on first launch creates the first workspace;
a title menu switches between workspaces.

## Decisions

- Workspace identity = language pair (studied ← translation). One workspace per pair; the name is
  derived from the studied language. Cross-device merge keys on the pair, so no duplicates.
- v1 languages: Latin + Cyrillic scripts only (pl, ru, uk, en, de, fr, es, it, cs, pt).
- Wizard on first launch of a fresh install. Existing installs get the pl ← ru workspace with all
  current words and folders, no wizard. A signed-in user's server workspaces are pulled, not recreated.
- Switcher: native title menu (`toolbarTitleMenu`) on Словарь and Практика.

## Pitfalls found (analysis)

1. Local `Word` is ru/pl (`russian`/`polish`, `AppLanguage` with 2 cases and `.other`). Persisted
   properties cannot be renamed without a migration: keep them as storage of the translation/studied
   side, add optional `workspaceID` (+ language codes), route all access through neutral accessors.
   ~20 files touch `.polish/.russian`.
2. `LanguageDetector` is alphabet-based (Cyrillic → ru). Same-script pairs (en↔pl, uk↔ru, de↔en)
   need an explicit input-direction control in Add Word and scan.
3. `Word.init` lowercases both sides: wrong for German nouns (Haus). Case handling per language;
   comparison stays normalized.
4. Hardcoded Polish elsewhere: speech recognition `pl-PL`, TTS codes, OCR languages, listening
   practice checks `polish`, category keywords ru/pl only (other languages → Другое).
5. Sync: server `words` is already language-neutral; `folders` has no workspace. The wizard for a
   signed-in user must wait for the first pull; an offline-created workspace merges by pair key.
6. Existing users: silent migration to pl ← ru, no wizard; fixtures need a default workspace so
   existing E2E do not hit the wizard.
7. Workspace deletion vs the invariant "removing folders never deletes words": soft delete or no
   deletion in v1 (open).
8. Scope: daily ring/due counts per workspace; achievements stay global (proposed).
9. UI copy stays Russian whatever the translation language (stated in the wizard).
10. New E2E: wizard, switching, same-script direction toggle; new fixtures with unit tests.

## Design

Mockups: `.codex/plans/language-workspaces/mockups.html` (wizard directions A/B, title menu,
dictionary, add word with direction control, practice, manage sheet; light/dark).

## Design decisions (2026-11-20)

- Wizard: direction A (two steps: «Какой язык вы учите?» → «На какой язык переводить?»), shown as a
  full-screen cover on first launch and as a sheet from «Новый язык…».
- Title menu: workspace flag + studied language as the large title with a 24 pt `appSecondarySurface`
  circle holding a `chevron.down` glyph (native `toolbarTitleMenu` look); same menu on both tabs.
- Workspace deletion: soft delete (`deletedAt`); words/folders stay hidden and return when the pair is re-added.
- Dictionary, practice, same-script direction control and «Языки» sheet approved as in the mockups.

## Backend design (draft, for approval)

Requirement from the user: normalized tables. Current violations it fixes:
- `words.folder_ids uuid[]` — repeating group of foreign keys without referential integrity (1NF) →
  join table `word_folders`.
- `words.term_language/translation_language` would depend on the workspace, not the word (3NF) →
  languages live only in `workspaces`; `words.entered_language` → `entered_side` ('term'|'translation').

### Tables (all PK `(user_id, id)`, RLS `(select auth.uid()) = user_id`, WITH CHECK on insert/update,
no `anon`, no DELETE grant/policy (soft delete only), `private.set_server_updated_at` trigger,
keyset index `(user_id, updated_at, id)`)

```sql
create table public.workspaces (
    id uuid not null,                        -- deterministic: uuid v5(namespace, 'pl>ru')
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    term_language text not null check (term_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    translation_language text not null check (translation_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    sort_order integer not null default 0,
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    primary key (user_id, id),
    unique (user_id, term_language, translation_language),   -- one workspace per pair, incl. tombstones
    check (term_language <> translation_language)
);

alter table public.folders add column workspace_id uuid;         -- backfilled, then NOT NULL
alter table public.folders add foreign key (user_id, workspace_id) references public.workspaces (user_id, id);
alter table public.folders add unique (user_id, workspace_id, id);  -- target for word_folders FK

alter table public.words add column workspace_id uuid;           -- backfilled, then NOT NULL
alter table public.words add column entered_side text check (entered_side in ('term', 'translation'));
alter table public.words add foreign key (user_id, workspace_id) references public.workspaces (user_id, id);
alter table public.words add unique (user_id, workspace_id, id);

create table public.word_folders (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    workspace_id uuid not null,
    word_id uuid not null,
    folder_id uuid not null,
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,                  -- removing a membership = tombstone; re-adding clears it
    primary key (user_id, word_id, folder_id),
    -- composite FKs: same owner AND same workspace for word and folder
    foreign key (user_id, workspace_id, word_id) references public.words (user_id, workspace_id, id),
    foreign key (user_id, workspace_id, folder_id) references public.folders (user_id, workspace_id, id)
);
create index on public.word_folders (user_id, folder_id);       -- FK index / "words in folder"
-- (user_id, workspace_id, word_id) is covered by the PK prefix only partially → own index
create index on public.word_folders (user_id, workspace_id, word_id);
```

Language codes stay a domain check (atomic BCP 47 value) rather than a lookup table: the supported
list is a client capability, and a lookup table would need a migration per new language without
adding integrity the check lacks. Category stays `WordCategory.stableID` (same reasoning).
Folder-name uniqueness stays client-side (duplicate adoption on pull), as today: a server unique
index would make two offline devices fail on push.

### Key mechanics

- **Deterministic workspace id** = UUID v5 of the pair (`term>translation`). Two devices that create
  the same pair offline produce the same id, so the push is an idempotent upsert, not a conflict.
  The pair unique constraint is a safety net. Re-adding a soft-deleted pair clears `deleted_at`.
- **Sync order** (FKs): pull and push workspaces → folders → words → word_folders. Four cursors.
  `capabilityVersion` 1 → 2 clears cursors for a full re-pull.
- **Workspace tombstone** hides its words/folders in the app; it does not tombstone them on the server
  (no cascade of soft deletes), so reviving the pair restores everything.
- **Memberships**: conflicts become per membership (closes gap E). Locally `Word.folderIDs` stays the
  read model; a `syncedFolderIDs` snapshot on Word lets the push diff the set into upserts/tombstones
  (open: alternative is a local `FolderMembership` model).
- **First sign-in**: the wizard (fresh install) waits for the first pull when a session exists; if the
  server has workspaces, the wizard is skipped and the last-used one opens.
- **Validation**: `RemoteRecords` gets workspace and membership DTOs; a word/folder whose workspace
  is unknown locally is held (like content-invalid rows) until the workspace arrives.

### Migration (expand → contract, data-preserving)

> Superseded 2026-11-21: single migration, columns dropped, backup in private (see «Revision 2»).

1. **Expand** (one migration): create `workspaces`, `word_folders`; add nullable `workspace_id`,
   `entered_side`; backfill — one workspace per distinct `(user_id, term_language, translation_language)`
   of existing words (+ pl>ru for users with only folders), ids via `extensions.uuid_generate_v5`;
   `words.workspace_id`, `folders.workspace_id` (user's pl>ru); `entered_side` from `entered_language`;
   `word_folders` from `unnest(folder_ids)` joined to existing folders (dangling ids dropped).
   Then `set not null`. Old columns stay so installed builds keep syncing.
2. App release with capability 2 (reads/writes only the normalized shape).
3. **Contract** (separate migration, after every device runs the new build): drop
   `words.term_language`, `translation_language`, `entered_language`, `folder_ids` and the old pair index.
   Between 1 and 3 an old build's membership edits are not mirrored into `word_folders` (accepted
   window for a personal app; alternative is a temporary sync trigger).
- Tests in `supabase/tests`: RLS per table (other user cannot read/insert/move rows), composite FK
  rejects cross-workspace membership, pair uniqueness, backfill result on seeded data, no DELETE.
  Security advisors after applying.

## Backend decisions (2026-11-20)

- Local memberships: separate SwiftData model `FolderMembership` mirroring `word_folders`
  (own updatedAt/deletedAt/serverUpdatedAt); `Word.folderIDs` is migrated into it and no longer the source.
- Expand → contract without a compatibility trigger; all devices are updated before the contract migration.
  > Superseded 2026-11-21: single migration, columns dropped, backup in private (see «Revision 2»).
- Backend design approved; next: full implementation plan (planner → critic → reviewer → approval gate).

---

## Implementation goal

Ship language workspaces in four ordered, independently shippable PRs. After phase 4 the user picks
the studied and the translation language in a two-step wizard (fresh installs only), switches
workspaces from the title menu on Словарь and Практика, and manages them in the «Языки» sheet. Each
workspace has its own words, folders, practice scope and daily ring, synced through normalized
Supabase tables (`workspaces`, `folders`, `words`, `word_folders`). Existing users keep every word,
folder, membership and SRS value in the pl ← ru workspace without seeing the wizard.

## Constraints

User instructions (verbatim):
- «я хочу Дать возможность выбирать язык оригинальный и перевода - сделать как воркспейс - чтоб при
  первом логине - у тебя был мини визард, также ты мог переключаться между пресетами в которых свои
  слова, папки и тд. проанализируй вначале задачи и найди подводные камни - и потом я бы хотел
  утвердить дизайн(скрины) и потом можно проектировать бекенд»
- «таблицы должны быть нормализованы»

Task constraints (from the caller, binding):
- Ordered phases, each its own PR with clean build + green unit tests + green E2E for changed flows.
- SwiftData: never lose words; new properties optional/defaulted; `Word.russian`/`Word.polish` stay as
  storage; `Word.folderIDs` migrates into `FolderMembership` safely (legacy array kept).
- Deterministic workspace id = UUID v5 of the pair; existing installs get pl ← ru silently (no
  wizard); the wizard waits for the first pull when signed in.
- Supabase: new migration files only, RLS + WITH CHECK, no `anon`, rolled-back tests in
  supabase/tests, no SECURITY DEFINER in `public`, security advisors after applying.
- AGENTS.md invariants: logic in Stores/Services; only Backend/ imports Supabase; server rows
  validated in RemoteRecords before SwiftData; RemoteMergePolicy never hard-deletes words; soft delete
  + `isActive` filtering in memory; `updatedAt` on every changed row; no `#Predicate` for due/active;
  FolderLibraryStore injected once at the root; removing folders/memberships never deletes words;
  logs only enums/ints/bools/ASCII ids; UI copy Russian; DESIGN.md tokens only.

## Phases

| # | PR | User-visible change | Depends on |
|---|---|---|---|
| 1 | Local workspace foundation | none | — |
| 2 | Supabase normalization migration (single, with backup in `private`) + sync v2 + `FolderMembership` | none (sync keeps working on updated builds) | 1 |
| 3 | Language layer (10 languages, sides, case, speech/TTS/OCR codes) | none for pl ← ru | 1, 2 |
| 4 | Workspace UI (wizard, gate, title menu, «Языки», direction control, scoping UI) | yes | 1, 2, 3 |

Deviation from the suggested order: backend + sync v2 moves before the UI (was 4th). Reasons found in
the code: (a) the gate «wizard waits for the first pull» needs workspaces on the wire; (b) shipping the
UI on sync v1 would need a temporary «local-only non-pl workspaces» guard in `SwiftDataSyncStore`
because v1 hardcodes `term = polish (pl)`; (c) `FolderMembership` belongs with sync v2 (per-membership
conflicts), so phase 1 needs no v1↔membership bridge. Phase 3 has no visible change but edits phase-2 sync code (validation against `Language.all`,
removal of `AppLanguage` used by v1 sync), so the order is 1 → 2 → 3 → 4. There is no contract phase: the phase-2 migration drops the legacy
columns itself (Revision 2).

**Approve first: phase 1** (plus the refinements R1, R3–R8 below, which phase 2 needs). Phase 1 is the
foundation every other phase builds on and is invisible to the user.

## Backend design refinements (need approval; they do not change the approved model)

Found while planning against the code and the migrations; each is the smallest change that makes the
approved design work with the code and CI.

- **R1. `word_folders` keyset.** The table has no `id`, so the pull cursor is
  `(updated_at, word_id, folder_id)` and the keyset index is `(user_id, updated_at, word_id, folder_id)`.
  The approved `(user_id, folder_id)` index is replaced by `(user_id, workspace_id, folder_id)`: it
  covers the folder FK columns (FK index rule) and still serves «words in folder». The word FK index
  `(user_id, workspace_id, word_id)` stays as approved.
- **R2.** Removed in Revision 2 (no expand window: no defaults, no dual-write, no nullable legacy
  columns; the single migration drops them).
- **R3. UUID v5 source.** Namespace `a4f06f42-4f0b-43f6-bfb4-33545dcf1307`, name = UTF-8
  `"<term>><translation>"` (e.g. `pl>ru`). Server: `extensions.uuid_generate_v5` from `uuid-ossp`
  (pre-installed on Supabase; the migration runs `create extension if not exists "uuid-ossp" with
  schema extensions`; `supabase/ci/auth_stub.sql` adds `create schema if not exists extensions`).
  Pinned values: `pl>ru` = `0db61f29-e285-5e06-84f5-d85acfa1b5cc`, `de>ru` =
  `f03536f4-02a8-515b-924f-f39a95de6a18`, `uk>ru` = `be15f3c7-76f8-503d-82ac-31a7b330772a`,
  `en>pl` = `ffaa32bf-2636-5dbd-8e6a-ff2987c0cf6f`.
- **R4. Server-enforced determinism.** `workspaces` gets
  `check (id = extensions.uuid_generate_v5('a4f06f42-…'::uuid, term_language || '>' || translation_language))`
  (the function is IMMUTABLE), mirroring the client validator.
- **R5. Backfill without churn.** The backfill UPDATEs on `words`/`folders` run with their
  `*_set_server_updated_at` triggers disabled (inside the migration transaction), so server
  `updated_at` values stay equal to the devices' `serverUpdatedAt` and the capability-2 re-pull treats
  them as echoes instead of server updates. New tables get their triggers after the backfill INSERTs.
- **R6. Backfill test.** `scripts/test-db.sh` applies `supabase/ci/seeds/<migration file name>` (if it
  exists) right before that migration; `supabase/ci/seeds/<phase-2 migration>.sql` seeds legacy-shaped rows for two
  users, and `supabase/tests/workspaces_backfill.sql` asserts the result. Seeds are CI-only.
- **R7. Local membership identity.** `FolderMembership.id` = UUID v5 (namespace
  `4e7ef163-a08f-4bf2-90bd-abfdf88826c2`, name `"<wordID>/<folderID>"`, lowercase UUID text). It is
  client-only (held ids, acks, de-duplication); the server keeps the approved composite PK. Pinned:
  word `…00a1` + folder `…00f1` (both `00000000-0000-0000-0000-0000000000xx`) =
  `ac1d00f8-3a8d-50c2-9a32-97991e1d73be`.
- **R8. Phase order** as in the Phases table (backend before UI).

## Acceptance criteria

| AC | Observable result | Phase |
|---|---|---|
| AC-1 | Upgrading an existing install keeps every word (text, category, SRS, created/updated dates, sync state), folder and membership; the app opens straight into the dictionary with all words, titled «🇵🇱 Польский» (phase 4) — no wizard. | 1, 2, 4 |
| AC-2 | A fresh install (no data, no prior defaults), signed out, shows the two-step wizard as a full-screen cover; «Начать» creates the chosen pair and opens an empty dictionary titled with the studied language. | 4 |
| AC-3 | A fresh install with a restored session (also an expired one being refreshed) shows «Загружаем словарь…» until the first workspace pull ends; if the account has workspaces, no wizard appears and the first workspace (sort order) opens with its words; if it has none, or the pull fails, or 10 s pass (counted from the first loading frame), the wizard appears. The wizard never appears and then disappears because a stored session was being restored. A pull that brings workspaces while the wizard is open closes it. | 2 (auth mapping), 4 |
| AC-17 | On a newly linked device, words and folders of a workspace deleted on another device are stored hidden; re-adding that pair shows them with SRS and memberships. Membership tombstones of deleted folders/words never accumulate in held ids. | 2 |
| AC-4 | Tapping the title on Словарь or Практика opens the same menu: one row per active workspace («🇵🇱 Польский ← 🇷🇺», subtitle «248 слов»), a checkmark on the current one, then «Новый язык…» and «Управлять языками». | 4 |
| AC-5 | Switching scopes everything: list, search, category counts, folder picker (list/create/rename/reorder/delete), add/scan duplicate detection, Today ring and answer counts, flashcards/quiz/listening pools. The choice survives relaunch. | 1 (logic), 4 (UI) |
| AC-6 | The same folder name can exist in two workspaces; duplicates are rejected only within one workspace. | 1 |
| AC-7 | «Языки» sheet: swipe-delete with confirmation hides the workspace with its words and folders (nothing deleted); re-adding the same pair restores words, folders, memberships and SRS. The last active workspace cannot be deleted. «Править» reorders. | 4 |
| AC-8 | For a same-script pair (en ← pl, uk ← ru, …) Add Word shows the «Ввожу на» segmented control; the choice is remembered per workspace and decides which side the typed text is saved to. Different-script pairs (pl ← ru) keep today's layout and auto-detection. | 3 (logic), 4 (UI) |
| AC-9 | German terms keep their case («das Haus»); pl/ru/other languages keep today's lowercase storage; duplicate checks stay case-insensitive. | 3 |
| AC-10 | Pronounce, listening practice, dictation and OCR use the workspace's languages (term side for TTS/listening; input side for dictation; both languages for OCR). | 3, 4 |
| AC-11 | Achievements stay global: counts and unlocks are unchanged by switching or deleting workspaces. | 1 |
| AC-12 | Two signed-in devices converge on workspaces, folders, words and memberships; the same pair created offline on both becomes one workspace; concurrent membership edits on different folders both survive; a workspace delete propagates as hiding. No server or local hard delete of words. | 2 |
| AC-13 | The phase-2 migration preserves every server word, folder and membership: before the legacy columns are dropped, `public.words`/`public.folders` are copied to `private.words_backup_20261121`/`private.folders_backup_20261121` (no API access), and the operator holds a local `supabase db dump --data-only` file. A pre-phase-2 build's sync fails after the migration (accepted: all devices are updated; local data untouched). | 2 |
| AC-14 | Server: new tables have RLS scoped by `(select auth.uid()) = user_id` with WITH CHECK, no `anon` grants, no DELETE/TRUNCATE; composite FKs reject cross-workspace and cross-user memberships; pair uniqueness and id determinism are enforced; `scripts/test-db.sh` passes in CI; security advisors report nothing new. | 2 |
| AC-15 | UI copy stays Russian for any pair; logs carry only language codes, counts and booleans. | all |
| AC-16 | Each phase: zero-warning build, green `MojSlownikUnitTests`, green `MojSlownikE2E`. | all |

## Design spec (phase 4)

Approved mockups: `.codex/plans/language-workspaces/mockups.html` (wizard A, title menu, German
dictionary, same-script Add Word, «Языки»). Tokens from DESIGN.md/Theme.swift only; no new colours.

### Wizard (`Views/WorkspaceWizardView.swift`)
- Presentation: `.fullScreenCover` with `.interactiveDismissDisabled()` on first launch (no cancel);
  `.sheet` from «Новый язык…»/«Добавить язык» with a leading «Отмена» (`cancellationAction`).
- `NavigationStack`; step 2 is pushed (system back «Назад»). Background `appBackground`, side padding 20.
- Header per step: two progress capsules (height 4, spacing `AppSpacing.xs`, `appAccentStrong` for done
  steps, `appSecondarySurface` otherwise, accessibility hidden); kicker «Шаг 1 из 2»/«Шаг 2 из 2»
  (section header style); title `.title.weight(.heavy)`, wraps; body `.subheadline` `subtleText`.
  - Step 1: «Какой язык вы учите?» / «Для каждого языка будет свой словарь, свои папки и своя практика.»
  - Step 2: «На какой язык переводить?» / «Обычно это ваш родной язык. Интерфейс приложения останется на русском.»
- Language list: one `cardStyle(cornerRadius: AppRadius.card)` card, rows separated by `appBorder`
  dividers inset to the text. Row = `Button`, min height 56, HStack: flag `Text` (`.title2`,
  accessibility hidden), VStack(name `.body.weight(.semibold)` `appInk`; subtitle `.footnote`
  `subtleText`), Spacer, `checkmark` (`.body.weight(.bold)`, `appAccentStrong`) when selected.
  Selected row adds `.isSelected`; accessibility label «Польский, Polski» (name + endonym), the
  checkmark is not colour-only (glyph + trait). AX sizes: rows wrap, no truncation.
  - Step 1 order: pl, en, de, es, uk, fr, it, cs, pt, ru; preselected pl. Subtitle = endonym.
  - Step 2 order: ru, uk, en, pl, de, fr, es, it, cs, pt; preselected ru (none when the studied language
    is ru). The studied language row is disabled (opacity 0.45, subtitle «уже выбран как изучаемый»).
    A pair that already exists (active) shows subtitle «уже есть — откроется»; a soft-deleted pair shows
    «вернётся со словами».
  - Step 2 info line under the card: `info.circle` + `.footnote` `subtleText` «Пару можно добавить
    позже: «Новый язык…» в заголовке словаря.» (icon stacks above text at AX sizes).
- Bottom: `safeAreaInset(edge: .bottom)` `PrimaryButtonStyle()` (accent): step 1 «Далее»; step 2
  «Начать — 🇵🇱 ← 🇷🇺» (accessibility label «Начать: польский, перевод на русский»), disabled without a
  selection. One accent button per screen.
- Identifiers: `wizardLanguage-<code>` (step 1 rows), `wizardTranslation-<code>` (step 2 rows),
  `wizardNextButton`, `wizardStartButton`.
- Haptic: `.selection` on choosing a row (DESIGN §7 «choosing a chip»). No other animation.

### Waiting state (`WorkspaceGateView` inside `RootTabView`)
While the gate is `.loading`/`.waitingForAccount`: `appBackground`, centred `ProgressView` with label
«Загружаем словарь…» (`.subheadline`, `subtleText`), identifier `workspaceLoading`. No tab bar.
This is a new (minimal) visual: include it in the screenshot gate.

### Title menu (`Views/Components/WorkspaceTitleMenu.swift`, used by WordListView and TrainingView)
- `.navigationTitle(title)` + `.navigationBarTitleDisplayMode(.large)` + `.toolbarTitleMenu { … }`.
  Title = «🇵🇱 Польский» (flag + studied language name). If another active workspace has the same
  studied language, title = «🇩🇪 Немецкий ← 🇷🇺».
- Menu content: `Picker` (`.inline` style, label «Язык») over active workspaces in sort order; each
  option label `Text("🇵🇱 Польский ← 🇷🇺")` + `Text("248 слов")` (subtitle; Russian plural via
  `RussianPlural`); system checkmark marks the current one. Then `Divider`, `Button("Новый язык…",
  systemImage: "plus")`, `Button("Управлять языками", systemImage: "gearshape")`.
- Word counts come from the screen's `@Query` words (active, grouped by `effectiveWorkspaceID`).
- The chevron in a 24 pt `appSecondarySurface` circle is the system rendering we rely on; the pilot
  screenshot gate verifies it on the iOS 17 simulator and the newest simulator (Risk K1).
- Tab labels «Словарь»/«Практика» do not change.

### «Языки» sheet (`Views/WorkspaceManagerView.swift`)
- `.sheet`, `NavigationStack`, inline title «Языки». Leading: «Править» (enters edit mode; reads
  «Готово» `.bold` while editing). Trailing: «Готово» (`appAccentText`, closes; hidden while editing).
- `List` (`.insetGrouped`, `scrollContentBackground(.hidden)` on `appBackground`, rows on
  `cardBackground`). Row: flag `.title2` (hidden from VO), VStack(«Польский ← Русский»
  `.body.weight(.semibold)`; «248 слов · 4 папки» `.footnote` `subtleText` `.monospacedDigit()`),
  Spacer, `checkmark` `appAccentStrong` for the active one (+ `.isSelected`). Tap selects (sheet stays).
  Delete via `ForEach(...).onDelete` (rev. 1 — F9): the handler does not delete, it stores the
  workspace and presents the confirmation; this gives both the swipe «Удалить» and the edit-mode delete
  control (not gesture-only). `.deleteDisabled(isOnlyActive)` on the row of the only active workspace.
  Edit mode `.onMove` → reorder.
- Delete confirmation: `confirmationDialog` «Удалить «Немецкий ← Русский»?», message «Слова и папки
  скроются. Если добавить эту пару снова, всё вернётся.», actions «Удалить» (destructive) / «Отмена».
- Below the list: `Button("Добавить язык", systemImage: "plus")` (`appAccentText`, min height 44) →
  wizard sheet; then the `info.circle` footnote «Удалённый язык скрывается вместе со словами и папками.
  Если добавить ту же пару снова, всё вернётся.»
- Identifiers: `workspaceRow-<term>-<translation>`, `addWorkspaceButton`, `manageWorkspacesDone`.

### Direction control (AddWordView, same-script pairs only)
- Above the input card: section header «Ввожу на» and `Picker(.segmented)` with two options
  «🇺🇦 Украинском» / «🇷🇺 Русском» (term first; `prepositional` names), identifier `inputSideControl`.
- The «Слово» pill shows the chosen side's flag + name; the translation card header reads «Перевод» with
  the other side's flag. Info line (calm pattern) under the card: «У украинского и русского один
  алфавит, поэтому язык ввода выбирается вручную. Выбор запоминается.» (`genitive` names).
- Different-script pairs: no control, no info line; layout identical to today.

### DESIGN.md / Theme
- No Theme.swift change. DESIGN.md: add Components rows «Workspace title menu», «Language wizard»,
  «Languages sheet», «Input-side control», «Loading gate»; Icons rows `gearshape` (manage languages),
  `plus` (new language), `checkmark` (selected language row).
- Pilot gate (mobile-ios-design §4): implement wizard + dictionary title menu first, capture light, dark
  and AX5 screenshots (iOS 17 simulator and newest simulator), get approval, then roll out «Языки»,
  Практика and Add Word without new visual decisions.

## Data model and SwiftData migration

### Models (all additions optional or defaulted; no renames/removals)
- **New `Models/Workspace.swift`** `@Model final class Workspace`: `id: UUID = UUID()` (always
  `WorkspaceID.make`), `termLanguageCode: String = "pl"`, `translationLanguageCode: String = "ru"`,
  `sortOrder: Int = 0`, `createdAt: Date = .now`, `updatedAt: Date? = nil`, `deletedAt: Date? = nil`,
  `serverUpdatedAt: Date? = nil`. Extension: `isActive`, `lastModifiedAt`, `isSyncDirty`,
  `markDeleted(now:)` (same shape as WordFolder).
- **Word** (phase 1): `+ workspaceID: UUID? = nil`. Storage mapping documented on the model:
  `polish` = term (studied side), `russian` = translation side, `sourceLanguageCode` = language code of
  the entered side. Accessors: `term`, `translation` (get/set the stored properties), `text(on: WordSide)`,
  `effectiveWorkspaceID` (`workspaceID ?? WorkspaceID.legacy`), `enteredSide(in pair)`.
  Phase 2: `+ legacyFolderIDsMigrated: Bool = false`; `folderIDs` becomes frozen legacy storage (never
  written after phase 2, read only by the migration).
- **WordFolder** (phase 1): `+ workspaceID: UUID? = nil`, `effectiveWorkspaceID`.
- **New `Models/FolderMembership.swift`** (phase 2): `id: UUID = UUID()` (always
  `MembershipID.make(wordID:folderID:)`), `wordID: UUID = UUID()`, `folderID: UUID = UUID()`,
  `workspaceID: UUID = WorkspaceID.legacy`, `createdAt: Date = .now`, `updatedAt: Date? = nil`,
  `deletedAt: Date? = nil`, `serverUpdatedAt: Date? = nil`; same sync helpers.
- **New `Models/AppSchema.swift`**: `enum AppSchema { static let models: [any PersistentModel.Type] }`
  = `[Word, WordFolder, Workspace]` (phase 1) `+ FolderMembership` (phase 2). Every
  `ModelContainer(for: …)` in app and tests switches to `ModelContainer(for: Schema(AppSchema.models), …)`.

### Launch migration

`Services/WorkspaceBackfill.swift`, run in `AppResources.init` right after `WordIdentityBackfill.run`;
own context, autosave off, one save, rollback on failure, logs only via `os.Logger` like
WordIdentityBackfill.
0. **Workspace de-duplication (phase 1, rev. 1 — F5).** SwiftData on iOS 17 has no unique constraint,
   so several `Workspace` rows may share an `id`. Keep the row with the latest `lastModifiedAt` (ties:
   the active one, then the earliest `createdAt`) and delete the others (workspace rows hold only
   language codes and order, never user text; words/folders are untouched). `WorkspaceCatalog.ensure`
   and `SwiftDataSyncStore.applyWorkspaces` always look an id up in any state before inserting, so
   no code path inserts a second row with an existing id.
1. **Existing-install workspace (phase 1, rev. 1 — F3).** One-time marker `workspace.backfill.v1`
   (Bool in the app's `UserDefaults`, written only after this backfill saved successfully on the first
   launch of any phase ≥ 1 build). When the marker is absent: if any `Word` or `WordFolder` row exists
   (any state) and no `Workspace` with id `WorkspaceID.legacy` exists (any state), insert pl>ru
   (`WorkspaceID.legacy`, sortOrder 0, createdAt = earliest word/folder `createdAt`, `updatedAt =
   createdAt`, `serverUpdatedAt = nil`); then write the marker. Defaults keys (`sync.v1`,
   `achievements.v1`, …) are never used to infer an existing install: a fresh install with a restored
   session writes `sync.v1` itself. When the marker is present, step 1 does nothing.
   Independently of the marker: if any Word/WordFolder has `workspaceID == nil` and no Workspace with id
   `WorkspaceID.legacy` exists in any state, insert it as above; a tombstoned one is never revived here.
   **Phases 1–3 only (removed in phase 4): no-active-workspace fallback (F5).** If no active workspace
   exists and no `Workspace` row with `WorkspaceID.legacy` exists in any state, insert pl>ru (as above).
   A row with that id is never inserted twice and never revived here (a tombstone needs the phase-4 UI;
   all devices run the same phase, rev. 2). An existing install updated straight from c3b5bf4 to phase 4
   with zero rows gets the wizard, which is correct (empty dictionary).
2. **Assign workspace (phase 1).** Every Word/WordFolder with `workspaceID == nil` gets
   `WorkspaceID.legacy`. `updatedAt` and `serverUpdatedAt` are not touched: the server backfill makes the
   same assignment, so these rows stay clean.
3. **Legacy memberships (phase 2).** For each Word with `legacyFolderIDsMigrated == false` (with a uuid;
   words without one are skipped until `WordIdentityBackfill` gives them one): for each id in `folderIDs`
   (deduplicated, order kept) whose WordFolder exists and is active in the word's workspace, upsert a
   `FolderMembership` (`id = MembershipID.make`, `createdAt = updatedAt = word.lastModifiedAt`,
   `serverUpdatedAt = nil`, active) unless one with that id already exists in any state; then set
   `legacyFolderIDsMigrated = true` (same save; word `updatedAt` untouched). Ids of missing or deleted
   folders are left in the legacy array (never deleted) and not migrated — the server backfill drops
   the same dangling ids.
4. **Membership de-duplication (phase 2).** If several FolderMembership rows share an `id`, keep the one
   with the latest `lastModifiedAt` and delete the others (membership rows only; never words or folders).

### Migration tests
- `LegacySchemaMigrationTests`: add `LegacySchemaV3` = frozen copy of the persisted schema at c3b5bf4
  (Word with `serverUpdatedAt`, WordFolder with `serverUpdatedAt`). Phase 1 test: write a V3 SQLite store
  in a temp dir (3 words incl. one tombstone and one in two folders, 2 folders incl. one tombstone),
  open it with `AppSchema.models`, run `WorkspaceBackfill`; assert word count, texts, SRS fields,
  `updatedAt`, `serverUpdatedAt` unchanged, every row has `workspaceID == WorkspaceID.legacy`, one pl>ru
  workspace exists. Phase 2 adds `LegacySchemaV4` (= phase-1 shape) and tests: V3→current and
  V4→current migrate memberships, keep `folderIDs` untouched, set the flag, skip dangling ids, and a
  second run creates nothing.

## Changes by file

### Phase 1 — Local workspace foundation (no UI change)

Model and services
- `Models/Workspace.swift` (new), `Models/AppSchema.swift` (new), `Models/Word.swift`,
  `Models/WordFolder.swift`: as in «Data model».
- `Services/DeterministicUUID.swift` (new): `extension UUID { static func v5(namespace: UUID, name:
  String) -> UUID }` (CryptoKit `Insecure.SHA1` over namespace bytes + UTF-8 name; version 5, RFC 4122
  variant). `enum WorkspaceID { static let namespace; static func make(term: String, translation:
  String) -> UUID; static let legacy = make(term: "pl", translation: "ru") }`.
- `Services/WordSide.swift` (new): `enum WordSide: String { case term, translation }` and
  `struct WordEntry: Equatable { term, translation, enteredSide }` with
  `static func legacy(source: String, translation: String) -> WordEntry` (phase-1 adapter:
  `LanguageDetector.detect(source) == .russian` → entered side `.translation`, i.e. term = translation
  text; otherwise `.term`). Removed in phase 3.
- `Services/WorkspaceCatalog.swift` (new, `@MainActor enum`, the FolderStore pattern): `workspaces(in:)`
  (active, sorted by sortOrder, createdAt, id), `ensure(term:translation:context:now:) -> Workspace`
  (insert, or revive a tombstone: `deletedAt = nil`, `updatedAt = now`; idempotent for active),
  `delete(id:container:now:)` (soft; refuses the last active one with `StoreError.lastWorkspace`
  «Нельзя удалить единственный язык»), `reorder(ids:container:now:)`, `wordCount/folderCount`
  helpers for the sheet. Never touches words or folders on delete (they hide by scope).
- `Services/WorkspaceBackfill.swift` (new): «Launch migration» steps 1–2.
- `Services/WorkspaceScope.swift` (new): `static func words(_ words: [Word], workspaceID: UUID?) ->
  [Word]` (active + `effectiveWorkspaceID == id`; `nil` id → `[]`), same for folders.
- `Services/DataRepositories.swift`: `WorkspaceRecord {id, termCode, translationCode, sortOrder}`;
  `WorkspaceRepository` protocol (`workspaces()`, `ensure(term:translation:) -> UUID`,
  `delete(id:)`, `reorder(ids:)`); `FolderRepository` methods take `workspaceID: UUID`
  (`folders(in:)`, `createFolder(name:workspaceID:)`, `reorderFolders(ids:workspaceID:)`; rename/delete
  by id unchanged); `VocabularyRepository`: `addWord(_ entry: WordEntry, category:, folderID:,
  workspace: WorkspaceContext)`, `toggleScannedWord(_ entry:, category:, folderID:, workspace:)`,
  `changeCategory(_:entry:workspace:)`; others unchanged. `struct WorkspaceContext: Equatable
  { id; termCode; translationCode }`. `RepositoryError.noWorkspace` («Выберите язык словаря»).
- `Services/SwiftDataRepositories.swift`: `SwiftDataWorkspaceRepository`; folder/vocabulary repositories
  pass the workspace through.
- `Services/FolderStore.swift`: every fetch of folders filters `effectiveWorkspaceID == workspaceID`
  (create: new folder gets `workspaceID`, sortOrder per workspace; name validation per workspace;
  reorder validates against the workspace's active folders); `requireFolder(_:in:workspaceID:)` also
  checks the workspace; `words(_:in:)` unchanged in phase 1.
- `Services/ScanWordStore.swift`: take `WordEntry` + `WorkspaceContext`; candidate words =
  `WorkspaceScope.words`; new words get `workspaceID`, `sourceLanguageCode` = code of the entered side;
  `Word.matches(_ entry: WordEntry)` (normalized term and translation; replaces
  `matches(source:translation:language:)`).
- `Services/SwiftDataSyncStore.swift` (sync v1 kept): pulled inserts get `workspaceID =
  WorkspaceID.legacy`; adoption candidates only words/folders whose `effectiveWorkspaceID ==
  WorkspaceID.legacy`; `pendingWords`/`pendingFolders` skip rows of other workspaces (none exist in
  phase 1; guard only). Uses `term`/`translation` accessors.
- `Services/LoggingRepositories.swift`: wrap the new signatures; add `LoggingWorkspaceRepository`
  (storage failures as today).
- `Services/AppLog.swift`: events `workspace.created`, `workspace.switched`, `workspace.deleted`,
  `workspace.restored`; key `termLanguage = "term_language"` (values: language codes as `.name`).
- `Services/UITestFixtures.swift`: every fixture calls `WorkspaceCatalog.ensure(term:"pl",
  translation:"ru")` and sets `workspaceID` on its words/folders.

Stores
- `Stores/WorkspaceStore.swift` (new, `@MainActor @Observable`): `struct Option {id, termCode,
  translationCode, sortOrder}`, `options`, `activeID`, `active`, `context: WorkspaceContext?`,
  `load()` (reads options; active = persisted id if active, else first option; persists it),
  `select(id:)` (logs `workspace.switched` with codes), `create(term:translation:) -> UUID` (ensure +
  select; logs created/restored), `delete(id:)` (if active, selects the first remaining), `reorder(ids:)`;
  `onActiveChange: ((WorkspaceContext?) -> Void)?`; `changeSignal?.notify()` after writes.
  Active id persisted by `UserDefaultsActiveWorkspaceRepository` (new, in
  `Services/ProgressRepositories.swift`), key `workspace.active.v1` (UUID string).
- `Stores/FolderLibraryStore.swift`: `workspaceID: UUID?` (set by AppResources wiring); `load()` lists
  that workspace's folders (empty when nil); create passes it.
- `Stores/VocabularyStore.swift`: `workspace: WorkspaceContext?`; writes that need it throw
  `RepositoryError.noWorkspace` when nil; API `add(_ entry: WordEntry, …)`,
  `toggleScanned(_ entry:, …)`, `changeCategory(_:entry:)`; log `.language` = entered language code.
- `MojSlownikApp.swift`: `AppResources` builds the container from `AppSchema`, runs
  `WorkspaceBackfill.run(container:defaults:)`, creates `WorkspaceStore`, wires
  `onActiveChange = { folders.workspaceID = $0?.id; vocabulary.workspace = $0; try? folders.load() }`,
  calls `workspaces.load()`; injects `.environment(workspaces)`. `uiTest()`: after `fixture.seed`, call
  `workspaces.load()`. `preview` seeds pl>ru via `WorkspaceCatalog.ensure`.

Views (reads only; no visual change)
- `WordListView`, `TrainingView`, `FlashcardsView`, `QuizView`, `ListeningPracticeView`,
  `ScannerView` (`ScanResultView`): `@Environment(WorkspaceStore.self)`; the active-word list becomes
  `WorkspaceScope.words(stored…, workspaceID: workspaces.activeID)`; writes build `WordEntry.legacy`.
  `AddWordView`: builds `WordEntry.legacy`. `AchievementTracker`/`AchievementsView`: unchanged (global).

### Phase 2 — Supabase normalization migration, sync v2, FolderMembership (no UI change)

Database
- `supabase/migrations/20261121090000_language_workspaces.sql` (new; timestamp = creation time, must
  sort after 20261119105315). One migration does everything (Revision 2). Contents in «Supabase
  migrations».
- `supabase/ci/auth_stub.sql`: `create schema if not exists extensions;`.
- `supabase/ci/seeds/20261121090000_language_workspaces.sql` (new, R6).
- `scripts/test-db.sh`: before each migration, apply `supabase/ci/seeds/$(basename "$migration")` if it
  exists.
- `supabase/tests/workspaces_rls.sql`, `supabase/tests/workspaces_backfill.sql`,
  `supabase/tests/workspaces_backup.sql` (new).
- Rewrites of existing tests (moved from the removed phase 5; every test runs after all migrations):
  `supabase/tests/rls_words_folders.sql` — each user first inserts its pl>ru workspace
  (`'0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now()`); word inserts drop `term_language`,
  `translation_language`, `entered_language`, `folder_ids` and add `workspace_id`, `entered_side`; folder
  inserts add `workspace_id`; the `folder_ids` usage becomes a `word_folders` row; RLS assertions
  unchanged. `supabase/tests/sync_server_timestamps.sql` — same insert changes; timestamp assertions
  unchanged.
- Later, separate PR after the user confirms the migrated data:
  `supabase/migrations/<ts>_drop_language_workspaces_backup.sql` (`drop table
  private.words_backup_20261121, private.folders_backup_20261121`); it also deletes
  `supabase/tests/workspaces_backup.sql` in the same PR.

Model and services
- `Models/FolderMembership.swift` (new), `Models/Word.swift` (`legacyFolderIDsMigrated`),
  `Models/AppSchema.swift`.
- `Services/DeterministicUUID.swift`: `enum MembershipID { static func make(wordID:folderID:) }`.
- `Services/WorkspaceBackfill.swift`: steps 3–4.
- `Services/LanguageCodes.swift` (new, rev. 1 — F2): supported v1 code list and `preservesCase`;
  used by `RemoteRecordValidator`, `SwiftDataSyncStore` (stored text form) and later by `Language`.
- `Services/ScanWordStore.swift` / `Services/SwiftDataSyncStore.swift` (rev. 1 — F1): word soft delete
  (local and pulled) tombstones the word's active memberships; `applyWorkspaces` materializes remote
  tombstones (`.insertTombstone`); membership reference check per «Known sets».
- `Services/MembershipIndex.swift` (new): `struct MembershipIndex { init(_ memberships:
  [FolderMembership]) ; func folderIDs(of wordID: UUID) -> Set<UUID>; func wordIDs(in folderID: UUID)
  -> Set<UUID> }` (active memberships only).
- `Services/FolderStore.swift`: memberships read/write `FolderMembership` instead of `Word.folderIDs`:
  `setMembership` upserts (create, or revive with `deletedAt = nil`) / tombstones by id, sets the
  membership's `updatedAt`, no longer bumps `word.updatedAt`; `removeFromAllFolders` tombstones all
  active memberships of the word; `delete(id:)` tombstones the folder's active memberships;
  `words(_:in:memberships:)` takes a `MembershipIndex`. Rollback patterns as today.
- `Services/ScanWordStore.swift`: folder toggles/adds through the same membership helpers (legacy
  duplicate words: the toggle tombstones the folder membership of every matching duplicate, as today).
- `Services/SyncRemote.swift`: `SyncCursor` gains `secondaryID: UUID?` (Codable, optional; used only by
  memberships: `id` = word_id, `secondaryID` = folder_id; `overlapping` resets both to nil UUID);
  protocol adds `fetchWorkspaces`, `upsertWorkspaces`, `fetchMemberships(ownerID:after:limit:)`,
  `upsertMemberships(_:) -> [RemoteMembershipAck]`; `RemoteMembershipAck {wordID, folderID, updatedAt}`.
- `Services/SyncState.swift`: `+ workspacesCursor`, `membershipsCursor` (decodeIfPresent); key stays
  `sync.v1`.
- `Services/SyncEngine.swift`: `capabilityVersion = 2`; cycle = pull workspaces → pull folders → pull
  words → pull memberships → push workspaces → push folders → push words → push memberships;
  `onWorkspacesPulled` callback (called once per cycle after the workspace pull finishes);
  `SyncReport.workspacesChanged`, `membershipsChanged`; membership pull hold ids = `MembershipID`.
- `Services/SwiftDataSyncStore.swift`: `SyncKind` + `.workspaces`, `.memberships`;
  `applyWorkspaces` (RemoteMergePolicy; insert/update/softDelete/acknowledge; no adoption — ids are
  deterministic); `applyFolders` adoption key = workspace + name key, inserts set `workspaceID`;
  `applyWords` adoption key = workspace + normalized term + translation (`syncPairKey` gains the
  workspace), inserts/updates take `workspaceID`, `enteredSide` → `sourceLanguageCode` (code of that side
  from the local workspace), no `folderIDs` handling; word adoption re-keys the adopted word's
  memberships (`wordID`, recomputed `id`, `serverUpdatedAt = nil`); folder adoption re-keys memberships
  the same way; `applyMemberships` (merge by `MembershipID`, insert/update/softDelete/acknowledge);
  pulled folder tombstone tombstones that folder's active local memberships (they push);
  `pendingWorkspaces`, `pendingMemberships` (only rows whose word and folder are known locally);
  `pendingWords` payload v2 (see «Sync changes»); `markPushed` for all four kinds (memberships by
  `MembershipID`); `prepareLink` covers workspaces and memberships; `knownWorkspaceIDs`,
  `knownWordIDs`; `reason(for:)` adds `unknown_workspace`, `unknown_reference`, `invalid_side`.
- `Backend/RemoteRecords.swift`: `RemoteWorkspaceRecord/Upsert`, `RemoteMembershipRecord/Upsert`,
  `RemoteWordRecord` v2 (adds `workspace_id`, `entered_side`; select drops `term_language`,
  `translation_language`, `entered_language`, `folder_ids`), `RemoteWordUpsert` v2 (adds `workspace_id`,
  `entered_side`; no `term_language`/`translation_language`/`entered_language`/`folder_ids` — the columns
  no longer exist), `RemoteFolderRecord/Upsert` add `workspace_id`; validators (see «Sync changes»);
  `RemoteRecordDecoder.workspaces/memberships`.
- `Backend/RemoteMergePolicy.swift`: `decide` overloads and `localRecordState` for Workspace and
  FolderMembership (same rule; never hard-deletes).
- `Backend/SupabaseSyncRemote.swift`: tables `workspaces`, `word_folders`; membership keyset filter
  `updated_at.gt."T",and(updated_at.eq."T",word_id.gt.W),and(updated_at.eq."T",word_id.eq.W,folder_id.gt.F)`
  ordered by `updated_at, word_id, folder_id`; membership upsert `onConflict: "user_id,word_id,folder_id"`
  selecting `word_id,folder_id,updated_at`; others as today.
- `Services/UITestSyncRemote.swift`: in-memory workspaces and memberships (same paging/stamping), seeds
  for existing states rewritten to v2 rows; new state `remoteWorkspaces` (phase 4).
- `Services/UITestFixtures.swift`: `foldersOrdered` and any membership seed create `FolderMembership`
  rows instead of `folderIDs`.

Stores and views
- `Stores/SyncStore.swift`: after a cycle with `workspacesChanged` → `workspaces.load()`; with
  `foldersChanged`/`membershipsChanged` → `folders.load()`; exposes
  `private(set) var workspacePullFinished = false` (set by `onWorkspacesPulled`, reset on account change).
  Init gains `workspaces: WorkspaceStore`.
- Views using memberships (`WordListView` row folder menu and folder filter, `TrainingView`,
  `FlashcardsView`, `QuizView`, `ListeningPracticeView`, `ScanResultView`): add
  `@Query private var storedMemberships: [FolderMembership]`, build `MembershipIndex`, and replace every
  `word.folderIDs` read with it.
- docs/architecture.md: Sync (four tables, order, cursors, v2 wire mapping), Study Folders
  (FolderMembership), Backend Readiness (gap E closed, workspaces).

### Phase 3 — Language layer (no visible change for pl ← ru)
- `Services/Language.swift` (replaces `Services/TranslationLanguage.swift`; keeps `Script`):
  `struct Language: Hashable, Sendable, Identifiable` with `code`, `nameRU`, `prepositionalRU`,
  `genitiveRU`, `endonym`, `flag`, `speechCode`, `ocrCode`, `googleCode`, `myMemoryCode`,
  `appleIdentifier: String?`, `scripts`, `preservesCase`; `static let all` (table below),
  `studyOrder`, `translationOrder`, `init?(code:)`, `func storedForm(_ text:) -> String` (trim; lowercase
  unless `preservesCase`). `struct LanguagePair: Hashable { term; translation; isSameScript;
  language(of: WordSide); func detectSide(_ text:) -> WordSide? }` (different-script pairs: the first
  letter scalar whose script belongs to exactly one side; nil for same-script pairs or no letters).
  `TranslationPair` keeps its name with `Language` members.

  | code | nameRU | prepositional | genitive | endonym | flag | speech | OCR | Apple | case |
  |---|---|---|---|---|---|---|---|---|---|
  | pl | Польский | польском | польского | Polski | 🇵🇱 | pl-PL | pl-PL | pl | lower |
  | ru | Русский | русском | русского | Русский | 🇷🇺 | ru-RU | ru-RU | ru | lower |
  | uk | Украинский | украинском | украинского | Українська | 🇺🇦 | uk-UA | uk-UA | uk | lower |
  | en | Английский | английском | английского | English | 🇬🇧 | en-GB | en-US | en | lower |
  | de | Немецкий | немецком | немецкого | Deutsch | 🇩🇪 | de-DE | de-DE | de | keep |
  | fr | Французский | французском | французского | Français | 🇫🇷 | fr-FR | fr-FR | fr | lower |
  | es | Испанский | испанском | испанского | Español | 🇪🇸 | es-ES | es-ES | es | lower |
  | it | Итальянский | итальянском | итальянского | Italiano | 🇮🇹 | it-IT | it-IT | it | lower |
  | cs | Чешский | чешском | чешского | Čeština | 🇨🇿 | cs-CZ | cs-CZ | nil | lower |
  | pt | Португальский | португальском | португальского | Português | 🇵🇹 | pt-PT | pt-BR | pt | lower |

  Scripts: cyrillic for ru/uk, latin for the rest. google/myMemory codes = `code`.
- `Services/LanguageDetector.swift`: remove `AppLanguage`; keep `LanguageDetector.side(of:in:)` wrapper
  over `LanguagePair.detectSide`. `Services/WordSide.swift`: remove `WordEntry.legacy`; add
  `WordEntry.make(input:translation:side:)` (input text goes to `side`).
- `Models/Word.swift`: new init `init(entry: WordEntry, pair: LanguagePair, workspaceID:, createdAt:,
  category:)` storing `pair.term.storedForm(entry.term)` / `pair.translation.storedForm(…)` and
  `sourceLanguageCode = pair.language(of: entry.enteredSide).code`; old init removed (tests/fixtures
  migrate). `text(in: AppLanguage)` → `text(on: WordSide)`.
- `Stores/WorkspaceStore.swift`: `WorkspaceContext` carries `pair: LanguagePair`; options expose `pair`.
  Per-workspace input side: `inputSide(for:)`/`setInputSide(_:for:)` persisted in
  `UserDefaultsInputSideRepository` (key `workspace.inputSide.v1`, `[uuidString: "term"|"translation"]`),
  default `.term`.
- Translation: `TranslationService`, `Translator.translate(_:from: Language, to: Language)`,
  `GoogleWebTranslator`, `MyMemoryTranslator`, `AppleTranslator` (skip Apple when `appleIdentifier ==
  nil`), `TranslationAlternatives` — `AppLanguage` → `Language`; log values are codes.
- `Stores/AddWordDraft.swift`: init takes `pair: LanguagePair` and `inputSide: WordSide?` (nil =
  auto-detect); `setInputSide(_:)` re-schedules translation; the side used = `inputSide ??
  pair.detectSide(text) ?? .term`; translates to the other side; exposes `resolvedSide`.
- `Stores/ScanResultDraft.swift`: takes `pair`; per word side = `pair.detectSide(word) ?? .term`
  (same-script pairs: scanned text is the studied language — Open decision O3).
- `Services/SpeechService.swift`: `speak(_:language: Language)` uses `speechCode`.
  `Services/SpeechRecognitionService.swift`: `start(locale:onRecognized:)` (caller passes the code).
- `Services/ScannedTextTokenizer.swift` and `Views/ScannerView.swift` (`DataScannerRepresentable`):
  recognition languages = `[pair.term.ocrCode, pair.translation.ocrCode]` filtered by the supported
  list; empty → automatic (as today).
- `Services/ListeningQuestion.swift`: `word.polish` → `word.term`, `russian` → `translation`.
- `Services/WordCategory.swift`: `detect(term:translation:)` (same keyword sets; other languages fall
  to `.other`).
- `Services/SwiftDataSyncStore.swift`, `Backend/RemoteRecords.swift`: language validation against
  `Language.all` (unsupported code → `unsupportedLanguage`, held); pulled text stored with
  `storedForm` of its side's language.
- `Services/UITestLaunchConfiguration.swift`: stub keyed by target code; adds `de` (`"дом": "das Haus"`,
  `"учить": "lernen"`), `en` (`"dom": "house"`), `pl` (`"house": "dom"`) entries.
- Views: `PronounceButton(language: Language)`; `WordListView`, `KnowledgeTierBadge`, `FlashcardsView`
  (`frontSide: WordSide`), `QuizView` (`promptSide`), `ListeningPracticeView` (TTS = term language),
  `AddWordView` (pill shows the resolved side's language; dictation locale = term language for
  different-script pairs, input side language for same-script pairs), `ScanResultView`: all through
  `term`/`translation`/`WordSide` and the active `LanguagePair`. Visual output for pl ← ru identical.

### Phase 4 — Workspace UI
- `Services/WorkspaceGate.swift` (new, pure): `enum WorkspaceGatePhase { loading, waitingForAccount,
  needsSetup, ready }` and `static func phase(hasActiveWorkspace:, auth: AuthStore.Status-like enum,
  syncAvailable:, linkedToCurrentAccount:, workspacePullFinished:, syncFailed:, timedOut:)`:
  active → ready; auth unknown/restoring and not timed out → loading; signed in + sync available +
  linked + pull not finished + not failed + not timed out → waitingForAccount; else needsSetup.
  `timedOut` covers `loading` and `waitingForAccount` together (rev. 1 — F4).
- Restoring an expired stored session (rev. 1 — F4). Today
  `SupabaseAuthBackend.account(for:session:)` returns nil for `.initialSession` with an expired session,
  so AuthStore reports `signedOut` and then `signedIn` after the SDK refresh — the gate would show the
  wizard and then yank it. Change: `AuthBackend.accountUpdates()` yields `AuthUpdate` (new enum in
  `Services/Auth.swift`: `.account(AuthAccount?)`, `.restoring`); `SupabaseAuthBackend` maps
  `.initialSession` + expired session to `.restoring` (still no custom token code); `StaticAuthBackend`
  gains `restoringThenSignedIn`/`restoringThenSignedOut` behaviours for tests. `AuthStore` keeps
  `.unknown` on `.restoring` and falls back to `.signedOut` if no further update arrives within 10 s
  (the account sheet never spins forever offline); sync semantics unchanged (`.unknown` runs no cycle).
- `Services/WorkspaceBackfill.swift`: remove the phase-1 «no active workspace → create pl>ru» step.
- `Services/RussianPlural.swift` (new): `format(_ n: Int, one:, few:, many:) -> String`
  («1 слово», «3 слова», «11 слов», «21 слово»; «1 папка», «4 папки», «5 папок»).
- `Views/RootTabView.swift`: `WorkspaceGateView` wrapper: computes the gate phase from
  WorkspaceStore/AuthStore/SyncStore, starts one 10 s timer (`@State timedOut`) when it first enters
  `loading` or `waitingForAccount` (not restarted between them); shows the waiting state, the wizard cover (`needsSetup`, bound to the phase so a
  pull that brings workspaces closes it), or the TabView.
- `Views/WorkspaceWizardView.swift`, `Views/WorkspaceManagerView.swift` (new),
  `Views/Components/WorkspaceTitleMenu.swift` (new, a `ViewModifier` `.workspaceTitleMenu(words:)`
  that sets title + title menu and owns the wizard/manager sheet presentation).
- `Views/WordListView.swift`, `Views/TrainingView.swift`: replace `.navigationTitle("Словарь"/"Практика")`
  with `.workspaceTitleMenu(words: storedWords)`; reset `selectedFolderID`/`selectedCategory`/search on
  workspace change (`.onChange(of: workspaces.activeID)`).
- `Views/AddWordView.swift`: direction control + info line for same-script pairs (Design spec).
- `Services/UITestFixtures.swift`: new fixtures `freshInstall`, `multiWorkspace`, `sameScriptWorkspace`
  (see «E2E»). `Services/UITestSyncRemote.swift`: state `remoteWorkspaces`.
- `MojSlownikUITests/E2ETestCase.swift`: mirror new fixture/sync names; helper `waitForDictionary()`
  (waits for `addWordButton` hittable) replacing `app.navigationBars["Словарь"]` waits in
  `AccountFlowTests`/`SyncFlowTests`.
- `DESIGN.md` (Components/Icons rows), `docs/architecture.md` (Data Flows: workspaces, gate;
  Non-obvious Constraints: language detection per pair).

## Sync changes (phase 2)

- **Wire v2.** Workspace: `id, user_id, term_language, translation_language, sort_order, created_at,
  updated_at, deleted_at`. Folder: + `workspace_id`. Word: `id, user_id, workspace_id, term,
  translation, entered_side, category, created_at, updated_at, deleted_at, ease_factor, interval_days,
  repetitions, due_date, last_review_grade, knowledge_tier, consecutive_soft_misses`. Membership:
  `user_id, workspace_id, word_id, folder_id, created_at, updated_at, deleted_at`. Every upsert row
  encodes every key (explicit nulls), as today.
- **Mapping.** `term` ↔ `Word.polish`, `translation` ↔ `Word.russian` (storage names), `entered_side` ↔
  `sourceLanguageCode` (code of that side in the word's workspace; an unknown code pushes `term`).
- **Supported languages (rev. 1 — F2).** Phase 2 already validates against the full v1 list
  `pl, ru, uk, en, de, fr, es, it, cs, pt` (`Services/LanguageCodes.swift`: `static let supported`,
  `static func preservesCase(_ code:) -> Bool` = `code == "de"`). Phase 3's `Language.all` must equal
  this list (`LanguageTests` asserts it). Pulled text is stored with the per-language case rule from
  phase 2 on, so a German row pulled by a phase-2 build is never lowercased and pushed back. Rule for
  the future: any later widening of the supported list or of a validator bumps
  `SyncEngine.capabilityVersion`, so rows held by an older build are re-pulled.
- **Known sets (rev. 1 — F1).** Built per cycle, after the preceding pull step finished:
  `knownWorkspaceIDs` = ids of all local `Workspace` rows in any state, after all workspace pages
  of this cycle were applied (incl. materialized tombstones, see Merge); `knownFolderIDs` /
  `knownWordIDs` = ids of all local folders / words (uuid) in any state after their pull step;
  rows skipped (held) this cycle are not in the sets. A folder/word is «in» a workspace by its
  `effectiveWorkspaceID`.
- **Validation** (`RemoteRecordValidator`): workspace — id ≠ nil UUID, owner, codes match the BCP 47
  shape and differ, `id == WorkspaceID.make(term, translation)` (else `invalidID`), codes in the
  supported list (else `unsupportedLanguage` → held), timestamps; folder/word — `workspace_id` in
  `knownWorkspaceIDs` else `unknownWorkspace` (held); word — `entered_side ∈ {term, translation}` else
  `invalidSide`; membership — ids ≠ nil, owner, timestamps; then references: word in `knownWordIDs` and
  folder in `knownFolderIDs`, both with `effectiveWorkspaceID == workspace_id`. A membership failing the
  reference check is **skipped without holding** when it is a tombstone (`deleted_at` set; reason
  `orphan_tombstone`, counted, cursor moves on — nothing to apply, so it can never fill `heldIDs`),
  and held by `MembershipID` (`unknown_reference`) when it is active. Outgoing rows pass the same
  validators.
- **Merge.** `RemoteMergePolicy` for all four kinds; no hard deletes. Workspace ids are deterministic, so
  there is no workspace adoption; a remote workspace tombstone hides it locally (if it was active, the
  WorkspaceStore reload selects the first remaining; none → wizard in phase 4). Word/folder adoption is
  scoped to the workspace. Memberships merge per (word, folder) — gap E closed.
- **Workspace tombstones are materialized (rev. 1 — F1).** Rule 1 of `RemoteMergePolicy` («no local
  row + remote tombstone → keepLocal») stays for words, folders and memberships. Documented exception
  for workspaces only: a new decision `.insertTombstone(at:)`, returned only by the
  `decide(local:remote: ValidatedRemoteWorkspace)` overload when there is no local row and the remote
  row is deleted; `applyWorkspaces` inserts it as a soft-deleted `Workspace` (`deletedAt`, `updatedAt`
  and `serverUpdatedAt` = remote values; clean, never pushed). Justification in the code comment:
  the row holds only language codes and order (no user text), and without it every word and folder of
  a workspace deleted on another device would be held forever on a newly linked device, so re-adding
  the pair could never bring them back. With it, such words/folders/memberships are applied normally
  (hidden by scope); re-adding the pair (`WorkspaceCatalog.ensure` revives the tombstone, dirty) shows
  them and pushes the revival.
- **Word deletion tombstones its memberships (rev. 1 — F1).** Local soft delete of a word
  (`ScanWordStore.delete`, scan toggle-off) and a pulled word tombstone (`applyWords` `.softDelete`/
  `.update` with `deletedAt`) tombstone that word's active memberships (`markDeleted(now:)`, dirty, they
  push), mirroring folder deletion. Words themselves are never deleted.
- **Rejected/held references (rev. 1 — F10).** `pendingMemberships(excluding:)` skips (keeps dirty, not
  counted as invalid) every membership whose `wordID` or `folderID` is in `SyncState.heldIDs` or in the
  engine's session-rejected ids (`SyncEngine.rejectedIDs` = ids of `rejected` row versions, any
  version), or whose word/folder row is not yet synced (`serverUpdatedAt == nil` or sentinel) after the
  word/folder push of this cycle — the FK would reject it.
- **Cursors.** Four in `SyncState`; capability 1 → 2 clears all cursors and held ids (full re-pull).
  `SyncEngine.persist` copies all four cursors (`workspacesCursor`, `foldersCursor`, `wordsCursor`,
  `membershipsCursor`) plus capability, held ids and last sync time onto the fresh state (rev. 1 —
  F10). `SyncEngine.later` compares `(updatedAtMillis, id, secondaryID)`: equal millis and equal `id`
  fall through to `secondaryID` (uuid text order, nil < any), so membership cursors never move
  backwards.
  Pulled rows equal to local ones become echoes; migrated local memberships (`serverUpdatedAt = nil`)
  push once as idempotent upserts.
- **Gate hook.** `SyncEngine.onWorkspacesPulled` → `SyncStore.workspacePullFinished = true` →
  `WorkspaceStore.load()` (phase 4 gate input).
- **Linking.** `prepareLink` also resets workspaces and memberships (same sentinel rule).
- **Logging.** Unchanged events; new skip reasons are ASCII names.

## Supabase migrations and tests (phase 2)

`supabase/migrations/20261121090000_language_workspaces.sql` (one transaction), in order:
1. Header comment with the security model (as in earlier migrations), the backup tables and the note
   that pre-phase-2 builds cannot sync after it (accepted, 2026-11-21).
1a. Backup (Revision 2): `create table private.words_backup_20261121 as table public.words;`
    `create table private.folders_backup_20261121 as table public.folders;` (full copies incl. the
    legacy columns and tombstones); `revoke all on table private.words_backup_20261121,
    private.folders_backup_20261121 from public, anon, authenticated;` `alter table … enable row level
    security;` on both (no policies: defence in depth; schema `private` already has no API usage);
    comment «Backup before 20261121 language workspaces migration; dropped by a later migration after
    the user confirms the data».
2. `create extension if not exists "uuid-ossp" with schema extensions;`
3. `create table public.workspaces` exactly as approved, plus R4 check
   `workspaces_id_is_pair_uuid`, constraint names `workspaces_pair_key` (unique),
   `workspaces_distinct_languages`.
4. Backfill workspaces: one row per user for each distinct `(term_language, translation_language)` of
   their words, plus `('pl','ru')` for users who have folders; `id =
   extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', term || '>' || translation)`,
   `created_at` = min `created_at` of those rows, `sort_order` = `row_number() - 1` per user ordered by
   created_at, term, translation; `on conflict do nothing`.
5. `alter table public.folders add column workspace_id uuid;` `alter table public.words add column
   workspace_id uuid, add column entered_side text check (entered_side in ('term','translation'));`
6. Disable `words_set_server_updated_at` and `folders_set_server_updated_at`; backfill
   `words.workspace_id` (v5 of the row's pair), `words.entered_side` (`'term'` when entered_language =
   term_language else `'translation'`), `folders.workspace_id` (pl>ru id); re-enable both triggers (R5).
7. NOT NULL, no defaults: `alter column workspace_id set not null` on `words` and `folders`;
   `alter column entered_side set not null` (the backfill sets every row; any null aborts the migration).
8. Constraints: `folders_workspace_fk (user_id, workspace_id) → workspaces (user_id, id)`,
   `folders_user_workspace_id_key unique (user_id, workspace_id, id)`; same for words
   (`words_workspace_fk`, `words_user_workspace_id_key`).
9. `create table public.word_folders` as approved (FK names `word_folders_word_fk`,
   `word_folders_folder_fk`); backfill from `unnest(words.folder_ids)` joined to the same user's active
   folders in the word's workspace (`created_at = greatest(w.created_at, f.created_at)`, `deleted_at`
   null), `on conflict do nothing`; dangling/deleted folder ids dropped.
9a. Drop the legacy shape (Revision 2): `drop index public.words_user_id_language_pair_idx;`
    `alter table public.words drop constraint words_entered_language_in_pair, drop constraint
    words_distinct_languages, drop column term_language, drop column translation_language, drop column
    entered_language, drop column folder_ids;` (all values are in the backup, `workspaces`,
    `entered_side` and `word_folders` by now).
10. Indexes: `workspaces_user_id_updated_at_id_idx (user_id, updated_at, id)`;
    `word_folders_user_id_updated_at_keyset_idx (user_id, updated_at, word_id, folder_id)`;
    `word_folders_user_workspace_word_idx (user_id, workspace_id, word_id)`;
    `word_folders_user_workspace_folder_idx (user_id, workspace_id, folder_id)` (R1).
    (Folder/word FKs to workspaces are covered by the new unique constraints' prefix.)
11. Triggers `workspaces_set_server_updated_at`, `word_folders_set_server_updated_at` → existing
    `private.set_server_updated_at()`.
12. RLS on both new tables; `revoke all … from anon`; `grant select, insert, update … to authenticated`;
    `revoke delete, truncate, references, trigger … from authenticated, anon`; policies
    `*_select_own`, `*_insert_own` (WITH CHECK), `*_update_own` (USING + WITH CHECK), all
    `(select auth.uid()) = user_id`; no delete policy.
13. Comments on `workspaces.id` (deterministic v5), `words.workspace_id`, `words.entered_side`,
    `word_folders` and the new `updated_at` columns.

Tests (each `begin; … rollback;`, ends with one «passed» row, run by `scripts/test-db.sh`; `workspaces_rls.sql` also runs on the linked project via MCP
`execute_sql`. `workspaces_backfill.sql` and `workspaces_backup.sql` are CI-only (they need the CI seed);
on the real project the row-count comparison in Verification 5c replaces them):
- `supabase/tests/workspaces_rls.sql`: users A/B; A inserts a workspace (computed v5 id), folder, word,
  membership; A sees them, B sees none; B cannot update A's rows (0 rows); A cannot insert rows owned by
  B or move rows to B (`insufficient_privilege`); `anon` has no privileges on the new tables
  (`has_table_privilege`); `delete` as authenticated fails (`insufficient_privilege`); second workspace
  with the same pair but another id fails (`check_violation` via R4) and with a matching id fails
  (`unique_violation`); `term_language = translation_language` fails; membership whose folder is in
  another workspace fails (`foreign_key_violation`); membership referencing B's word fails; a word
  insert without `workspace_id` or `entered_side` fails (`not_null_violation`); a word in a workspace
  A does not own fails (`foreign_key_violation`); the columns `term_language`, `translation_language`,
  `entered_language`, `folder_ids` no longer exist on `public.words` (`information_schema.columns`); `uuid_generate_v5(ns,'pl>ru') =
  '0db61f29-e285-5e06-84f5-d85acfa1b5cc'`; triggers assign `updated_at` on insert and bump it on update
  for both new tables; deleting an auth user with all rows succeeds (cascade, NO ACTION FKs) — as owner.
- `supabase/ci/seeds/20261121090000_language_workspaces.sql`: users C (words pl/ru incl. a
  tombstone, folder_ids with one live folder, one deleted folder and one dangling id; two folders) and D
  (folders only, no words); a word of C with `term_language = 'de'`. The seed also saves every seeded
word/folder `(id, updated_at)` into the CI-only table `ci.seed_snapshot` (schema `ci`, created only by
the seed) so the R5 check does not depend on the backup tables.
- `supabase/tests/workspaces_backfill.sql` (as owner): C has workspaces pl>ru and de>ru with the pinned
  ids and sort orders 0/1; D has pl>ru only; every word/folder has the expected `workspace_id`;
  `entered_side` matches; `word_folders` has exactly the live-folder memberships; word/folder
  `updated_at` unchanged by the backfill (R5, compared with `ci.seed_snapshot`); `entered_side` of C's Russian-entered word is
  `'translation'`.
- `supabase/tests/workspaces_backup.sql` (Revision 2): as owner, `private.words_backup_20261121` and
  `private.folders_backup_20261121` exist, their row counts equal the seeded counts (all of C's and
  D's rows, tombstones included), the word backup still has `term_language`, `translation_language`,
  `entered_language`, `folder_ids` with the seeded values; `has_schema_privilege('anon'|'authenticated',
  'private', 'usage')` and `has_table_privilege(…, 'select')` are false; as `authenticated`, `select`
  from the backup raises `insufficient_privilege`.
- After applying to Supabase: run security and performance advisors (MCP `get_advisors`), compare row
  counts (`words`/`folders` vs their backups; `sum(cardinality(folder_ids))` from the word backup vs
  `word_folders`, minus dangling/deleted-folder ids).

## Unit tests

Phase 1
- `DeterministicUUIDTests` (new): pinned v5 values (R3), version/variant bits, `WorkspaceID.legacy`.
- `WorkspaceCatalogTests` (new): ensure is idempotent; revive clears `deletedAt` and bumps `updatedAt`;
  delete is soft and refuses the last active; reorder; ordering rule.
- `WorkspaceBackfillTests` (new): existing data → pl>ru + assignment without touching
  `updatedAt`/`serverUpdatedAt`; fresh (no rows) → no inferred workspace (phase 1 asserts only the
  temporary fallback insert); tombstoned pl>ru stays tombstoned; second run is a no-op.
  Rev. 1: (F3) marker absent + only `sync.v1`/`achievements.v1` in defaults + no rows → no workspace
  inferred, marker written; marker present + rows with nil `workspaceID` → assignment still runs but no
  inference; failed save → marker not written. (F5) two Workspace rows with the legacy id → one remains
  (latest modified); the phases 1–3 fallback never inserts a second legacy row and never revives a
  tombstone; `WorkspaceCatalog.ensure` never inserts a duplicate id.
- `WorkspaceScopeTests` (new, rev. 1 — F10): active filter, `effectiveWorkspaceID` fallback for nil
  `workspaceID`, nil scope id → `[]`, folders likewise.
- `WorkspaceStoreTests` (new): load picks persisted id, falls back to first; select persists and logs;
  create selects; deleting the active selects another; `onActiveChange` fires.
- `FolderStoreTests`/`FolderLibraryStoreTests`/`FolderRepositoryContractTests`: same name allowed in two
  workspaces, rejected within one; reorder per workspace; options scoped.
- `ScanWordStoreTests`, `VocabularyStoreTests`, `AddWordDraftTests` (signature only): duplicates matched
  per workspace; `noWorkspace` error; `WordEntry.legacy` mapping.
- `SwiftDataSyncStoreTests`: v1 pulled rows get the legacy workspace; adoption ignores other
  workspaces.
- `LegacySchemaMigrationTests`: V3 → current (see «Migration tests»).
- `UITestSupportTests`: fixtures seed exactly one pl>ru workspace and assign it.
- `AppLogTests`: new events/keys pass the server pattern.

Phase 2
- `MembershipIDTests` (in DeterministicUUIDTests): pinned value (R7).
- `MembershipIndexTests` (new, rev. 1 — F10): tombstones excluded, both directions, empty input.
- Rev. 1 sync cases:
  - `SwiftDataSyncStoreTests`/`SyncEngineTests` (F1): link to an account whose de>ru workspace is
    deleted and still has words, a folder and memberships → workspace stored as a clean tombstone, words
    and folder stored (hidden), nothing held; `WorkspaceStore.create(term: "de", translation: "ru")` →
    the words appear in scope with SRS and memberships, and the next push sends the workspace with
    `deleted_at = null`.
  - (F1) membership tombstones referencing unknown (never synced or deleted) words/folders: skipped with
    reason `orphan_tombstone`, `heldIDs.count` unchanged across 3 cycles; active orphan → held.
  - (F1) local word delete and pulled word tombstone tombstone its memberships; word row stays.
  - `RemoteMergePolicyTests` (F1): workspace overload returns `.insertTombstone` for no local + remote
    deleted; word/folder/membership overloads still return `.keepLocal`.
  - `SyncEngineTests` (F2): a de>ru workspace with a German word validates and applies in phase 2
    (not held, case kept); `LanguageCodes.supported` pinned.
  - `SyncEngineTests` (F10): `persist` keeps all four cursors when the link is unchanged; `later` with
    equal millis/id compares `secondaryID`; `pendingMemberships` skips memberships whose word/folder is
    held, session-rejected or unsynced, and sends them once the word is acknowledged.
  - `AuthStoreTests` (F4): `.restoring` keeps `.unknown`; a following account → `.signedIn` without an
    intermediate `.signedOut`; no update within 10 s → `.signedOut`.
  - `SupabaseAdapterTests` (F4): `account(for:)` maps `.initialSession` + expired session to
    `.restoring`, valid session to the account, nil session to `.account(nil)`.
- `WorkspaceBackfillTests`: legacy memberships migrate (flag, dangling skipped, folderIDs untouched,
  idempotent, de-duplication).
- `FolderStoreTests`: membership upsert/revive/tombstone; folder delete tombstones memberships; words
  never deleted; word `updatedAt` unchanged by membership edits.
- `RemoteRecordValidatorTests`: workspace id determinism, unsupported language, unknown workspace,
  invalid side, membership unknown reference, owner mismatch → untrusted.
- `RemoteMergePolicyTests`: workspace and membership states.
- `SwiftDataSyncStoreTests`: apply/push for four kinds; scoped adoption; membership re-key on word and
  folder adoption; pulled folder tombstone; prepareLink for new kinds; word payload has exactly the v2 keys (no legacy columns).
- `SyncEngineTests`: order of calls, four cursors, capability 2 reset, held membership ids,
  `onWorkspacesPulled` called once, membership FK rejection isolated per row.
- `SupabaseAdapterTests`: membership keyset filter string, select columns, upsert conflict targets,
  decoding of v2 rows with PostgREST's decoder.
- `SyncStateRepositoryTests`: old `sync.v1` JSON decodes with nil new cursors; `secondaryID` round trip.
- `SyncStoreTests`: workspaces/folders reload after pull; `workspacePullFinished`.
- `LegacySchemaMigrationTests`: V3 and V4 → current.

Phase 3
- `LanguageTests` (new): table integrity (unique codes, distinct flags, non-empty RU forms),
  `storedForm` (de keeps case), `detectSide` (pl/ru by script; nil for en/pl and uk/ru).
- `WordTests`: init per pair and side; case rules; `matches` case-insensitive.
- `AddWordDraftTests`: explicit input side, `setInputSide` re-translates, auto-detect for
  different-script pairs.
- `ScanResultDraftTests`, `ListeningQuestionTests`, `WordCategoryTests`, `SpeechRecognitionServiceTests`
  (locale passed through), `TranslatorLoggingTests`, `MyMemoryTranslatorTests`,
  `TranslationAlternativesTests` (Language-based pairs), `ScannedTextTokenizerTests` (language list).
- `WorkspaceStoreTests`: input side persistence per workspace.

Phase 4
- `WorkspaceGateTests` (new): every phase transition incl. timeout, failure, mismatch, signed out;
  rev. 1 (F4): restoring → `loading` (never `needsSetup`), restoring + timed out → `needsSetup`,
  restoring → signed in → `waitingForAccount` → `ready`.
- `RussianPluralTests` (new): 0, 1, 2, 5, 11, 12, 21, 22, 25, 111.
- `UITestSupportTests`: new fixture names pinned and contents (`freshInstall` empty without
  workspace; `multiWorkspace`; `sameScriptWorkspace`); new sync state `remoteWorkspaces`.

## E2E scenarios and fixtures

Fixtures (DEBUG, `Services/UITestFixtures.swift`, mirrored in `E2ETestCase`):
- All existing fixtures: seed the pl>ru workspace (phase 1) — they never hit the wizard.
- `freshInstall` (phase 4): nothing, not even a workspace.
- `multiWorkspace` (phase 4): pl>ru active with `basicVocabulary` words and folder «Урок 1» (kot, dom);
  de>ru with «das Haus»/«дом» and «lernen»/«учить» and folder «Lektion 1» (das Haus); sortOrder pl 0, de 1.
- `sameScriptWorkspace` (phase 4): en>pl active, no words (ASCII typing works for both sides).
- Sync state `remoteWorkspaces` (phase 4, rev. 1 — F6): server has de>ru at sort 0 with «das Haus»/«дом»
  and pl>ru at sort 1 with the cloud words of `remoteVocabulary`, so the opened workspace proves the pull
  (a local default would be pl>ru).

Scenarios
- Phase 1: no new flows; the whole existing suite must stay green (fixtures now seed a workspace).
- Phase 2: update `SyncFlowTests` sources only (server model v2); all five scenarios stay; add
  `testFolderMembershipFromAccountAppears` (remote membership puts a cloud word in the cloud folder;
  folder filter shows it).
- Phase 3: existing suite green; `AddWordFlowTests.testAddPolishWordManually` asserts
  `inputSideControl` does not exist.
- Phase 4 — new `MojSlownikUITests/WorkspaceFlowTests.swift` (dictionary shard):
  1. `testFreshInstallWizardCreatesWorkspace`: `freshInstall` → `wizardLanguage-de` → Далее → `wizardTranslation-ru`
     selected → `wizardStartButton` → nav bar «🇩🇪 Немецкий», «Словарь пуст».
  2. `testExistingDataSkipsWizard`: `basicVocabulary` → no `wizardStartButton`, nav bar «🇵🇱 Польский», «kot».
  3. `testSwitchingScopesDictionaryFoldersAndPractice`: `multiWorkspace` → tap title → choose
     «🇩🇪 Немецкий ← 🇷🇺» → «das Haus» visible, «kot» absent; folder picker lists only «Lektion 1»;
     Практика title is «🇩🇪 Немецкий» and shows «Слов в выбранном наборе: 2»; switching back via the
     Практика menu restores «kot» on Словарь. (Persistence across relaunch is a unit test: UI-test
     launches wipe defaults.)
  4. `testDeleteAndRestoreWorkspace`: `multiWorkspace` → menu → «Управлять языками» → «Править» →
     delete control of `workspaceRow-de-ru` → «Удалить» → confirm → «Готово» (edit) → Готово → menu lacks German → «Новый язык…» → de → ru →
     Начать → «das Haus» visible again.
  5. `testSameScriptDirectionControl`: `sameScriptWorkspace` → add word → `inputSideControl` exists →
     choose «🇵🇱 Польском» → type «dom» → translation field «house» → save → list shows «house» and «dom».
  6. `testSignedInFreshInstallOpensAccountWorkspace`: `freshInstall` + `signedIn` + `remoteWorkspaces`
     → `workspaceLoading` may appear → nav bar «🇩🇪 Немецкий» with «das Haus»; `wizardStartButton`
     never appears; the title menu also lists «🇵🇱 Польский ← 🇷🇺».
  7. `testSignedInFreshInstallWithFailedPullShowsWizard` (rev. 1 — F6): `freshInstall` + `signedIn` +
     `failsOnce` → wizard appears (`wizardLanguage-pl` exists) without waiting for the timeout.
  8. `testSignedInFreshInstallWithEmptyAccountShowsWizard` (rev. 1 — F6): `freshInstall` + `signedIn` +
     `empty` → wizard appears after the first pull.
- Phase 4 — update `AccountFlowTests`/`SyncFlowTests` waits to `waitForDictionary()`.
- Manual only: camera/OCR with de and uk pairs, dictation in en/de/uk, TTS voices, Apple Translation on
  a physical iOS 18 device for a new pair, two-device sync on phase-2+ builds.

## Verification

Per phase (Done = all of these):
1. `xcodegen generate` (new files every phase).
2. Build, zero warnings:
   `xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=<device>' -onlyUsePackageVersionsFromResolvedFile build | grep -E 'error:|warning:|SUCCEEDED|FAILED'`
3. Unit: `-scheme MojSlownikUnitTests … test` (never the app scheme).
4. E2E: `-scheme MojSlownikE2E … test` (phase 4: `WorkspaceFlowTests` plus the full suite).
5. Phase 2 only: `scripts/test-db.sh <empty Postgres URL>`; `bash scripts/check-secrets.sh`. Rollout
   after the user approves the PR, in this order:
   a. The operator runs `supabase db dump --data-only -f <path outside the repo, e.g.
      ~/Backups/mojslownik-20261121-data.sql>` against the linked project and keeps the file locally
      (never committed, never inside the repo tree).
   b. Apply the migration (it creates the `private.*_backup_20261121` copies first).
   c. Security/performance advisors and the row-count comparison against the backups.
   d. Install the phase-2 build on every device (pre-phase-2 builds show «Не удалось синхронизировать»
      until updated; their local data is untouched).
   e. After the user confirms the data, a separate PR drops the backup tables.
6. Phase 4 only: pilot screenshot gate (light, dark, AX5; iOS 17 and newest simulator) before rollout;
   final screenshots of wizard, both title menus, «Языки», Add Word en ← pl.
7. Manual list reported (camera/OCR, dictation, TTS, Apple Translation, two-device sync, upgrade of the
   real on-device store from the App build at c3b5bf4 → phase 1/2 builds with a backup first).

## Risks

- **K1 Title menu rendering.** `toolbarTitleMenu` with a large title may render differently on iOS 17
  (chevron placement/circle). Mitigation: pilot gate on the iOS 17 simulator; fallback (needs user
  approval at the gate) = inline display mode on both root screens, or a custom large-title header
  `Menu` with the 24 pt circle. Open decision O1.
- **K2 Store migration on the real device.** Adding an entity + properties relies on SwiftData lightweight
  migration (no VersionedSchema in the app). Mitigation: V3/V4 frozen-schema tests on disk; manual
  backup (sync to account) before installing phase 1/2 builds; backfill never edits text/SRS.
- **K3 Destructive server migration (rev. 2).** The phase-2 migration drops `term_language`,
  `translation_language`, `entered_language`, `folder_ids`. Mitigation: in-database copies in
  `private` taken in the same transaction, the operator's local data-only dump, backfill DB tests on
  seeded legacy rows, the row-count comparison; local SwiftData on every device stays the source of
  truth and is not touched by the migration. Pre-phase-2 builds cannot sync afterwards (accepted).
- **K4 Remote workspace tombstone on first link.** An existing device linking to an account where pl>ru was
  deleted elsewhere hides its pl>ru words (tombstone wins over an unsynced row). Nothing is lost;
  re-adding the pair restores. Documented in architecture.md.
- **K5 Held rows never revisited.** A membership held because its folder was held is not re-pulled until
  a capability bump (same as today's held words).
- **K6 Full re-pull.** Capability 2 re-downloads everything once and pushes every migrated membership once;
  fine for a personal dictionary (pages of 500).
- **K7 Same-script ambiguity in scan** (Open decision O3) and the alphabet heuristic for different-script
  pairs (mixed-script text picks the first letter's script).
- **K8 Provider coverage.** Apple Translation lacks Czech (skipped); Vision OCR may not support pl/cs/pt-PT
  (automatic fallback); offline speech recognition not available for every locale (existing error copy).
- **K9 Scope size.** ~40 files across four PRs; each PR stays independently green; phases 2 and 3 can run
  in parallel branches after phase 1.
- **K10 Accessibility of flags.** Emoji flags in the navigation title are read by VoiceOver
  («флаг: Польша»); menu/sheet rows hide flags and use spoken labels; the title itself cannot.

## Revision 1 (critic findings, 2026-11-20)

| # | Finding | Where addressed |
|---|---|---|
| F1 HIGH | Remote tombstones never materialized → words of a workspace deleted elsewhere held forever; orphan membership tombstones fill `heldIDs` | Sync changes: «Known sets», «Workspace tombstones are materialized», «Word deletion tombstones its memberships»; Phase 2 files; AC-17; sync tests |
| F2 MED | Phase 2 validated pl/ru only, phase 3 widened without capability bump | Sync changes «Supported languages» (full list + case rule in phase 2; future widening bumps capability); `Services/LanguageCodes.swift`; tests |
| F3 MED | Existing install inferred from defaults keys a fresh signed-in install writes itself | Launch migration step 1 (marker `workspace.backfill.v1`, no defaults inference); WorkspaceBackfillTests |
| F4 MED | Expired restored session reported as signed out; `.loading` had no timeout | Phase 4 gate + `AuthUpdate.restoring` (Auth.swift, SupabaseAuthBackend, AuthStore 10 s fallback); one timer for loading+waiting; AC-3; tests. Lands in phase 2 (no UI effect) so phase 4 can rely on it. |
| F5 MED | Fallback insert could duplicate the legacy id / revive a server deletion | Launch migration steps 0–1 (dedupe by id, never insert an existing id, never revive a tombstone; the read-only fallback was removed in Revision 2); tests |
| F6 MED | E2E gaps for the gate | E2E scenarios 6 (de>ru at sort 0), 7 (failsOnce), 8 (empty account) |
| F7 LOW | `entered_side` stale for old-build rows | Superseded by Revision 2: `entered_side` is backfilled from `entered_language` in the single phase-2 migration (no old-build writes afterwards) |
| F8 LOW | Phase 5 test rewrites missing | Moved to phase 2 «Rewrites of existing tests» (Revision 2) |
| F9 LOW | Delete was gesture-only | «Языки» sheet: `.onDelete` + confirmation + `.deleteDisabled`; E2E scenario 4 uses edit mode |
| F10 LOW | persist/later/new cursors, scope/index tests, pendingMemberships | Sync changes «Cursors», «Rejected/held references»; WorkspaceScopeTests, MembershipIndexTests, SyncEngineTests |

Files added to the change lists by this revision: `Services/LanguageCodes.swift` (phase 2),
`Services/Auth.swift`, `Backend/SupabaseAuthBackend.swift`, `Stores/AuthStore.swift` (phase 2, F4).

## Revision 2 (user decision, 2026-11-21)

User: «да, удаляем колонки в одной миграции с бэкапом в private». The app is not in production, so
there is no expand/contract compatibility window.

| Change | Where |
|---|---|
| One phase-2 migration creates `workspaces`/`word_folders`, backfills (`workspace_id`, `entered_side` from `entered_language`, `folder_ids` → `word_folders`), sets NOT NULL without defaults and drops the legacy columns, constraints and pair index | «Supabase migrations and tests» steps 1a, 7, 9a, 13; Phase 2 files |
| Backup: `private.words_backup_20261121`, `private.folders_backup_20261121` (no grants, RLS on), dropped by a later migration after the user confirms; operator's local `supabase db dump --data-only` outside the repo | Migration step 1a; Verification 5; `workspaces_backup.sql` test |
| R2 removed (defaults, dual-write, nullable legacy columns); sync v2 sends only the normalized shape | Refinements; Phase 2 `RemoteWordUpsert`; Sync changes «Wire v2» |
| Phase 5 removed; its test rewrites (`rls_words_folders.sql`, `sync_server_timestamps.sql`) moved to phase 2; F7 recompute folded into the migration backfill | Phases table; Phase 2 files; Revision 1 rows F7/F8 |
| Mixed-build/mixed-phase handling removed: old K3, O7, the phases 1–3 «tombstoned pl>ru read-only fallback» (`isFallbackToDeleted`), the expand-window manual check | Launch migration step 1; tests; Risks; Open decisions; E2E manual list |
| Pre-phase-2 builds fail to sync after the migration (accepted: all devices are updated) | AC-13; K3; Verification 5d |
| Approved sections keep their text with a «Superseded 2026-11-21» note | «Migration (expand → contract…)», «Backend decisions» |

Kept: R1, R3–R8.

## Open decisions

- **O1** Fallback if the native large-title menu does not match the approved look on iOS 17: inline title
  (recommended, fully native) or a custom header `Menu`. Decided at the pilot gate with screenshots.
- **O2** Sign-in link on wizard step 1 («У меня есть аккаунт — войти») for reinstalls without a restored
  Keychain session. Not in the approved mockups; recommended to skip in v1 (a later pull merges by pair).
- **O3** Same-script pairs in Scan: treat scanned text as the studied language (recommended, no UI) or add
  the «Ввожу на» control to the scan result screen (new design).
- **O4** Case preservation: only German keeps case (recommended); alternative: keep case for every new
  language and lowercase only pl/ru/uk.
- **O5** «Last used workspace» after a fresh-install pull: first by sort order (planned; no server
  column). Alternative: sync a per-account `last_used_at` (schema change).
- **O6** Approval of refinements R1, R3–R8 (they adjust indexes, id derivation, tests and phase order of
  the approved backend design without changing its normalized model; R2 was removed in Revision 2).

## Approval

- 2026-11-21: approved by user — phases 1–4, refinements R1 and R3–R8, open decisions O1–O5 as
  recommended (O1 inline title fallback, O2 no sign-in link, O3 scan = studied language, O4 case kept
  for German only, O5 first workspace by sort order). Stops: pilot UI screenshots (phase 4) and before
  applying the migration to the real Supabase project.
