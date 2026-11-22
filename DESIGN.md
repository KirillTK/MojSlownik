# DESIGN.md — «Маркер»

## 1. Purpose and how to use it

This file is the single source of truth for the visual design of Mój Słownik: warm paper,
ink type, highlighter yellow used only as a fill. Read it before any UI or visual work.
Plan files in `.codex/plans/` are history; this file is current. Values here equal
`MojSlownik/Theme/Theme.swift` exactly (`ThemeTests` enforces the colour table).
Views use semantic tokens only: no hex, `Color.yellow`, `.white` or `.black` (the only exceptions are
camera-overlay colours in ScannerView and shadow colours of floating elements).

## 2. Colour

| Token | Role | Light | Dark |
|---|---|---|---|
| `appBackground` | page/paper | #FAF8F2 | #141310 |
| `cardBackground` | grouped cards, rating/option buttons | #FFFFFF | #1F1E1A |
| `appInk` | primary text/icons | #1C1B17 | #F4F1E8 |
| `subtleText` | secondary text/metadata | #6B675C | #A8A293 |
| `appBorder` | hairline dividers, card edge | #E7E2D5 | #2E2C26 |
| `appSecondarySurface` | neutral fill: unselected chips, category capsules, inputs, pronounce button | #F0ECE1 | #2A2823 |
| `appAccent` | accent fill only: primary button, Today hero, selected chip, unlocked tile, Add FAB, scan-photo selection | #FFD43B | #FFD43B |
| `appOnAccent` | on-accent: text/icons on appAccent | #1C1B17 | #1C1B17 |
| `appAccentText` | accent foreground: accent-coloured text/icons on paper/card | #8A6A00 | #FFD43B |
| `appAccentStrong` | control tint: TabView, progress fill, checkmarks | #1C1B17 | #FFD43B |
| `appAccentSoft` | soft yellow surface: mode-icon tiles, saved scan chips, replay button, language pill | #FFF3BF | #3A3318 |
| `appInverseSurface` | ink surface: CTA inside Today hero, Achievements hero, banner | #1C1B17 | #1C1B17 |
| `appOnInverse` | text on appInverseSurface (appAccent also allowed) | #F4F1E8 | #F4F1E8 |
| `appCardEdge` | 1 pt card edge stroke (not a shadow) | #E7E2D5 | #2E2C26 |
| `appRingTrack` | knowledge ring track (graphic) | #CDC5B0 | #46423A |
| `appInverseEdge` | 1 pt edge of inverse surfaces (hero, banner) | #1C1B17 | #3A372F |
| `appMastery` | Легко / success | #25704C | #8BD3A8 |
| `appMasterySurface` | correct-answer surface | #E3F1E8 | #1C3125 |
| `appError` | errors, Не помню | #B3261E | #FF8A80 |
| `appErrorSurface` | wrong-answer surface | #FCE8E6 | #3B1D1A |
| `appWarning` | warning text | #7C4C17 | #F4C787 |
| `appWarningSurface` | warning surface | #FBEFDB | #43311D |
| `appCaution` | amber, graphics only (Трудно ring arc), never text | #C77700 | #FFA94D |
| `appSuccess` | alias of `appMastery` (never the brand yellow) | — | — |

Dynamic pairs are defined as `Palette` `UIColor` constants; `Color` statics wrap them.

### Verified contrast (WCAG)

| Pair | Ratio | Use |
|---|---|---|
| ink #1C1B17 on yellow #FFD43B | 12.1 | on-accent text |
| yellow #FFD43B on paper #FAF8F2 | 1.34 | forbidden as text, tint or thin stroke |
| ochre #8A6A00 on paper / white / soft #FFF3BF | 4.77 / 5.07 / 4.54 | accent foreground |
| subtle #6B675C on paper | 5.32 | secondary text |
| dark: yellow on bg / card | 13.0 / 11.7 | dark accent foreground |
| dark: subtle #A8A293 on card | 6.56 | secondary text |
| error #B3261E on white | 6.54 | error text |
| mastery #25704C on paper / masterySurface / secondarySurface | 5.65 / 5.15 / 5.08 | success text |
| amber #C77700 on paper | 3.26 | ring graphic only, never text |

Text pairs must reach 4.5:1, graphics 3:1 (ring track and inverse edge 1.5:1), in both appearances.
Ochre on `appSecondarySurface` is below 4.5: icons and large text only.

### Colour usage rules

1. `appAccent` is fill or background only. Never `.foregroundStyle`, `.tint`, an SF Symbol colour or a thin stroke on light surfaces. Single exception: ScannerView's selection stroke over the camera photo.
2. Content on `appAccent` uses `appOnAccent`. Content on `appInverseSurface` uses `appOnInverse` or `appAccent`.
3. Accent-coloured text and icons use `appAccentText`.
4. Controls, progress fills, checkmarks and tab selection use `appAccentStrong`.
5. One accent. At most one `appAccent` primary button per screen state; selected chips and the FAB are selection/floating actions. Content text stays ink.
6. State is never colour-only: ring fill amount, ✓/✕ icons and text, lock glyph and "Получено", `.isSelected` trait and weight.
7. `appCaution` only for the ring arc. Semantic colours keep their meaning everywhere; success is `appMastery`, never the brand yellow.

Forbidden pairs: `appAccent` as text/icon on paper or card; `appInk` or `subtleText` on `appAccent` in dark mode (use `appOnAccent`); `appCaution` as text.

## 3. Typography

SF Pro, text styles only. Custom sizes use `@ScaledMetric`. No fixed text point sizes.

| Use | Spec |
|---|---|
| Root screen titles | system large title; pushed screens inline; the workspace screens (Словарь) use an inline title because the large-title menu shows no chevron on iOS 26 |
| Hero number | `@ScaledMetric(relativeTo: .largeTitle)` 40, heavy, `.monospacedDigit()`, `.contentTransition(.numericText())` |
| Hero "из N" suffix | `.title3.weight(.semibold)`, opacity 0.75 |
| Flashcard word | `@ScaledMetric(relativeTo: .largeTitle)` 38, heavy, centered, wraps |
| Quiz/listening prompt | `.largeTitle.weight(.bold)`, wraps |
| Achievements points | `.largeTitle.weight(.heavy)`, monospaced digits, numericText |
| List word (Polish) | `.title3.weight(.bold)`, wraps |
| List translation / metadata | `.subheadline`, `subtleText` |
| Card/tile title | `.headline` |
| Section header | `.footnote.weight(.bold)`, uppercase, tracking 0.6, `subtleText` |
| Hero kicker | section header, `appOnAccent.opacity(0.75)` |
| Buttons | `.body.weight(.bold)` |
| Chips | `.subheadline.weight(.semibold)`; selected chip `.bold` |
| Counts | `.monospacedDigit()` |

Hierarchy comes from weight and size; metadata uses `subtleText`; no coloured body text.

## 4. Spacing and radii

`AppSpacing` (4-pt grid): xxs 4, xs 8, s 12, m 16, l 20, xl 24, xxl 32.
`AppRadius`: control 12 (icon tiles, inputs, option rows), button 16 (primary buttons, FAB),
card 18 (grouped cards, mode tiles), hero 24 (Today/Achievements hero, prompt cards), flashcard 28.

- Shapes use `RoundedRectangle(style: .continuous)`; chips use `Capsule()`.
- Side margin 20, section gap 20.
- `cardStyle` = `cardBackground` + 1 pt `appCardEdge` stroke, no shadow. Shadows only for floating elements (FAB, banner).
- Open lists (Словарь) keep hairline `appBorder` separators; cards are for groups and hero blocks.
- Touch targets are at least 44x44 pt.
- At accessibility sizes: hero badges stack, mode grid and rating grid become one column, WordRow actions go under the word, chip rows scroll horizontally.

## 5. Components

| Component | Spec |
|---|---|
| Primary button | `PrimaryButtonStyle(kind:)`: full width, min height 50, radius button, `.body.bold`. `.accent`: yellow + `appOnAccent`; `.inverse` (inside the yellow hero only): ink + yellow; `.ink` (Apple sign-in): `appInverseSurface` + `appOnInverse` + 1 pt `appInverseEdge`; `.card` (Google sign-in): `cardBackground` + `appInk` + 1 pt `appCardEdge`; `.ink`/`.card` disabled: opacity 0.5. Disabled `.accent`: `appSecondarySurface` + `subtleText`. Pressed: scale 0.97 + opacity 0.9 (opacity only with Reduce Motion) |
| Secondary actions | No custom secondary button; text actions are system `Button` with `appAccentText` tint |
| Chip | `chipStyle(isSelected:)`: padding 14, visible capsule min height 36, 44 pt hit frame. Selected yellow + `appOnAccent`, else `appSecondarySurface` + `appInk`. Callers set no colours on the label |
| Progress bar | `MarkerProgressBar(value:track:fill:height:)`: capsule, value clamped 0…1, `.snappy` change (none with Reduce Motion), hidden from accessibility; callers supply label/value |
| Card | `cardStyle()` |
| Today hero | yellow fill, radius hero, content `appOnAccent`: kicker, big "N из M", status line (`appOnAccent` 0.75), progress, inverse CTA, ✓/✕ badges, "Ответов" caption |
| Mode tile | `cardStyle()`, min height 96, 36 pt `appAccentSoft` icon tile with ink glyph; disabled dims only icon tile and title |
| Achievements entry row | card, 40 pt soft tile with ink `trophy`, points and streak subtitle, "N из M", chevron |
| List row | line 1: Polish word (`.title3.bold`, at least 160 pt), ring, pronounce; line 2: translation, category capsule, folder menu |
| Knowledge ring | `@ScaledMetric` 22, line width 0.2x size, `appRingTrack` track, arc filled 25/50/75/100 % for tiers 0–3 in error / `appCaution` / `appAccentText` / `appMastery`; labels unchanged |
| Achievement tile | unlocked: yellow + `appOnAccent` filled glyph; locked: `appSecondarySurface` + `subtleText` outline glyph + `lock`; radius 0.32x size, default 40 |
| Banner | always `appInverseSurface` in both themes, radius 20, 1 pt `appInverseEdge`, `appOnInverse` text, yellow badge and "+N" pill, shadow black 0.25 r15 y6 |
| Rating buttons | `cardBackground` + `appBorder`, radius control, min height 50; only Не помню is red text and Легко a yellow fill; 2x2 grid, one column at AX |
| Search field | native `.searchable` |
| Floating add/scan | bottom-trailing pair; add = yellow, scan = card; size scaled, capped at 72 |
| Pronounce button | 44 pt circle, `appSecondarySurface`, ink `speaker.wave.2` |
| Flip card | one `Button` with two faces; the pronounce button is a sibling overlay |
| Workspace title menu | `.workspaceTitleMenu(words:)`: inline title «🇵🇱 Польский» (flag + studied language; «🇩🇪 Немецкий ← 🇷🇺» when two workspaces study the same language) with the system `toolbarTitleMenu` chevron. Menu: inline `Picker` «Язык» (each option «🇵🇱 Польский ← 🇷🇺» and the word count on a second line of the same `Text`; the system checkmark marks the active one), `Divider`, «Новый язык…» (`plus`), «Управлять языками» (`gearshape`). Switching dismisses sheets built for the previous pair |
| Language wizard | two-step `NavigationStack` (full-screen cover on first launch, sheet with «Отмена» from «Новый язык…»): two progress capsules (4 pt, `appAccentStrong` / `appSecondarySurface`), section-style kicker «Шаг N из 2», `.title.heavy` title, `.subheadline` `subtleText` body, one `cardStyle` card of rows (min 56 pt, flag `.title2`, name `.body.semibold`, endonym/status `.footnote` `subtleText`, `checkmark` `appAccentStrong` + `.isSelected`; the studied language is disabled at 0.45 on step 2), one `PrimaryButtonStyle` accent button in a bottom inset («Далее» / «Начать — 🇩🇪 ← 🇷🇺»), step 2 info line (`info.circle` footnote, stacks at AX). Back is a custom «Назад» toolbar button |
| Loading gate | `appBackground`, centred `ProgressView` and «Загружаем словарь…» (`.subheadline` `subtleText`), no tab bar; shown while the session is restored or the first pull runs (10 s limit) |
| Languages sheet | `.sheet` + inline «Языки»; leading «Править» (reads «Готово» `.bold` while editing), trailing «Готово» (`appAccentText`, hidden while editing). Inset-grouped `List` on `appBackground`, rows on `cardBackground`: flag `.title2`, «Польский ← Русский» `.body.semibold`, «248 слов · 4 папки» `.footnote` `subtleText` `.monospacedDigit()`, `checkmark` `appAccentStrong` on the active row. Delete through `.onDelete` + `confirmationDialog` (`.deleteDisabled` for the only workspace), reorder through `.onMove`. «Добавить язык» (`plus`, `appAccentText`, min 44 pt) opens the wizard sheet; calm `info.circle` footnote below |
| Input-side control | Same-script pairs only, above the Add Word card: section header «Ввожу на» and a segmented `Picker` («🇺🇦 Украинском» / «🇷🇺 Русском»), plus a calm `info.circle` footnote under the card; remembered per workspace |
| Account sheet | `.sheet` + inline "Аккаунт", "Готово" (`appAccentText`). Signed out: 64 pt `appAccentSoft` tile, `.title3.bold` title, Apple (`PrimaryButtonStyle(kind: .ink)`, `apple.logo`) and Google (`.card`, official multicolour `GoogleLogo` asset at body size, never tinted) buttons, no yellow; failure is the calm `info.circle` footnote; a successful sign-in closes the sheet. Signed in: card with email and provider (`subtleText`), then the sync card, then "Выйти" text button. Sync card (`cardStyle`, `AppSpacing.m` padding, hidden when the build has no sync): "Синхронизация" header (`.subheadline.weight(.semibold)`, `appInk`, one line, scales down to 0.6), a `.footnote` `subtleText` status line («Синхронизировано: сегодня, 12:14», date without year) with a small `ProgressView` while a cycle runs (label «Идёт синхронизация»), and the «Синхронизировать сейчас» text button (`appAccentText`, min height 44, disabled while a cycle runs). A failed cycle and the paused state use the calm `info.circle` footnote (no red; the icon stacks above the text at accessibility sizes). Paused (data linked to another account): explanation plus the «Объединить словари» text button, which opens a `confirmationDialog` «Объединить словари?» (message: both directions, nothing is deleted; actions «Объединить» / «Отмена»); no manual sync while paused. A manual sync announces its result to VoiceOver |

### Patterns

- **Recoverable service errors (e.g. auto-translation failed):** a calm `subtleText` `.footnote` line with `info.circle` under the field ("Автоперевод недоступен — впишите перевод вручную"). No red: the user can continue manually. The raw service message goes only into the accessibility label. Red `appError` is reserved for failed saves/destructive problems (system alert via `errorAlert`).
- **Secondary actions on chips/cards (e.g. scan word chips):** tap does the primary action; long press opens a native `.contextMenu` (edit, add/remove, topic submenu). Every context-menu action is also exposed as a named `accessibilityAction`, and the screen hint mentions the long press ("Удерживайте слово, чтобы исправить или выбрать тему").
- **Empty states:** 64 pt `appAccentSoft` tile with an ink outline symbol, `.title3.bold` title, `subtleText` body, optional `appAccentText` text action. Root-screen empty states fill the available height and stay clear of floating buttons.

## 6. Iconography

SF Symbols only, outline names. Weight `.fontWeight(.medium)` on standalone images; `Label` icons follow
their text style. Sizes come from text styles or `@ScaledMetric`. Default monochrome rendering; palette
only for the scanner's selected-block checkmark. Filled variants are for state only: selected tab,
unlocked achievement glyph (`symbolVariant(.fill)`), answer result and scanner checkmarks.
Mode and achievements icons sit on `appAccentSoft` tiles with an ink glyph.

| Purpose | Symbol |
|---|---|
| Tab Словарь / Практика | `character.book.closed` / `rectangle.stack` |
| Add word / Scan text | `plus` / `text.viewfinder` |
| Scan chip add / remove (chip + menu) | `plus.circle` / `minus.circle` |
| Switch camera | `camera.rotate` |
| Recoverable service error hint | `info.circle` |
| Secret achievement | `questionmark` |
| Flashcards empty state | `rectangle.on.rectangle.slash` |
| Folder (none / member) | `folder.badge.plus` / `folder` |
| Remove from folders / delete folder | `folder.badge.minus` |
| Dictate idle / recording / unavailable | `mic` / `waveform` (variableColor unless Reduce Motion) / `mic.slash` |
| Pronounce / replay | `speaker.wave.2` |
| Category | `tag` |
| Flashcards / Quiz / Listening | `rectangle.on.rectangle` / `checklist` / `ear` |
| Achievements / Streak / Locked | `trophy` / `flame` / `lock` |
| Correct / wrong badges | `checkmark` / `xmark` |
| Correct / wrong answer state | `checkmark.circle.fill` / `xmark.circle.fill` |
| Session result | `flag.checkered` (perfect: `trophy`) |
| Navigation / menu affordance | `chevron.right` / `chevron.down` |
| Close camera / retry / edit / delete | `xmark` / `arrow.clockwise` / `pencil` / `trash` |
| Account / Sign in with Apple | `person.crop.circle` / `apple.logo` |
| Network error / inline error | `wifi.exclamationmark` / `exclamationmark.circle` |
| Manage languages / new language / selected language row | `gearshape` / `plus` / `checkmark` |
| Search empty / camera unavailable / translate selection | `magnifyingglass` / `camera` / `text.magnifyingglass` |

Achievement catalog symbols are outline names (no `.fill`, unique); unlocked badges add `.fill` via `symbolVariant`.

## 7. Motion and haptics

Every animation is 0.2–0.35 s `.snappy`/`.smooth`, never blocks the next action, and has a Reduce Motion branch.

| Where | Animation | Reduce Motion |
|---|---|---|
| Flashcard flip | `.snappy(duration: 0.35)` Y rotation, back face counter-rotated, face visibility switches at the edge-on midpoint | opacity crossfade |
| Next flashcard | move + opacity transition on card id | opacity |
| Counts | `.contentTransition(.numericText())` | none |
| Progress bars, ring trim | `.snappy(duration: 0.3)` | none |
| Primary button press | scale 0.97 | opacity only |
| Answer feedback | opacity + scale 0.98, `.smooth(duration: 0.25)` | opacity |
| Banner | top move + opacity | opacity |

No animation under the finger in lists.

| Event | Haptic (`.sensoryFeedback`) |
|---|---|
| Choosing a category chip / translation alternative | `.selection` |
| Flashcard rating | `.selection` |
| Quiz / listening answer | `.success` / `.error` |
| Word saved (single source: WordListView `words.count`) | light impact |
| Achievement banner (in `AchievementTracker`, mounted once) | light impact |

No haptics on scroll, flip, navigation or generic taps.

## 8. Accessibility checklist

- Dynamic Type up to AX5 without clipping; long words wrap.
- VoiceOver: Russian labels, decorative images hidden, grouped rows combined, custom controls with `.isButton`/`.isSelected` traits and named actions.
- Light and dark both designed; Increase Contrast keeps pairs readable.
- No colour-only state; touch targets at least 44 pt; reveal and answer actions are buttons, not tap gestures.
- Reduce Motion branch for every animation.

## 9. Competitors: borrow and do not copy

Borrow: one clear daily goal and next action (Lingvist), one large word per card (Vocabulary), short sessions with haptics (Drops),
visible word strength via ring (Busuu), friendly headings and bottom sheets (Promova).
Do not copy their palettes, illustrations, mascots, upsell screens, streak pressure or layouts one-to-one.

## 10. Change procedure

1. Change `Theme.swift`, this file and `ThemeTests` in the same diff.
2. New visual decisions go to the user via an HTML mockup and approval before code.
3. Finish with the review rubric in `.claude/skills/mobile-ios-design/SKILL.md` (§10).
