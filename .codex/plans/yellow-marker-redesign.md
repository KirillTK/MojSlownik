# Yellow «Маркер» redesign

Base: HEAD 52aa610 (translation alternatives + achievements merged). Mode: FULL.
Visual reference: `.codex/plans/yellow-redesign/mockups.html`, sections "A · «Маркер»" and
"A · новые экраны" only (tokens `.A` / `.dark .A`). Do not modify that folder.

## Goal

Redesign every screen in the approved «Маркер» language: warm paper, ink type, and
highlighter yellow used only as a fill. Apply what works in competitor apps without adding
features: one primary action per screen with a clear daily goal (Lingvist), large word
typography with one word per card (Vocabulary), short sessions with haptics and
micro-motion (Drops), visible word strength through a ring badge (Busuu), and bottom
sheets with friendly headings (Promova). Achievements move from a tab to an entry row on
Практика. There are no data, model, SRS, achievement-logic or translation changes.

## Constraints (user instructions)

- "я хочу сделать редизайн приложения — сделать его красивее, более modern, который следует всем best practice … Поменять цветовую палитру, не как у конкурентов — например жёлтый. Мы будем делать план по миграции." and, after the merge, "чтоб дизайнить и их" (the new translation-alternatives and achievements screens are in scope).
- Scope: visuals + layout + motion/haptics only. NO data/model/SRS/achievement logic/translation changes. Preserve stored words.
- iOS 17 minimum. Don't add opaque custom tab or navigation bars. Any `glassEffect` must be behind `#available(iOS 26, *)`. This plan uses none.
- Russian UI copy stays unchanged, except the new short labels listed under "New/changed copy".
- No E2E/UI automation, no snapshot tests. Do not run the UI-test scheme. Preserve existing UI tests and targets.
- No commit or push without authorization.
- Coordinator: apply `.claude/skills/mobile-ios-design/SKILL.md`. The Design spec follows §2–7, the phasing follows §1 (pilot + simulator screenshot gate in light/dark/AX text size), and the plan includes a §10 rubric check. While planning, the skill file and the mockup are not edited. During implementation the skill is trimmed per user decision 10. The mockup is never edited.

## Decisions (made by the user)

1. **Direction A «Маркер».** Paper bg #FAF8F2, ink #1C1B17 and highlighter yellow #FFD43B. Yellow is used as a FILL only: primary buttons, Today hero, selected chips, unlocked achievement tiles and word highlight. Soft yellow #FFF3BF is for surfaces. Ochre #8A6A00 is for accent-coloured text and icons on light backgrounds. Dark mode uses bg #141310, card #1F1E1A and ink #F4F1E8, and there #FFD43B may be used as text. Yellow is never a text or icon colour on light surfaces. Content on yellow is always ink.
2. **Scope:** visuals, layout, motion and haptics only. Preserve stored words.
3. **KnowledgeTierBadge** becomes a ring filled 1/4, 2/4, 3/4 or full, with a colour per tier: Не помню = error, Трудно = amber, Хорошо = ochre accent text, Легко = mastery green. The accessibility label text stays the same. The fill amount carries the level, so colour is not the only signal.
4. **Achievements:** the third tab is removed. RootTabView has two tabs (Словарь, Практика). A compact row on Практика shows points and streak and pushes AchievementsView. AchievementsView gets an ink hero card with points, "N из M получено · рекорд K дн.", unlocked badges as yellow tiles with ink icons, and locked badges as neutral fills with a lock. The 7-day strip is shown only if it can be derived without new logic. It cannot: see Design spec §Achievements.
5. **Achievement banner:** a dark ink strip with paper text, a yellow badge, a yellow "+N" pill and a light haptic when it appears. The store-driven timing and the reduce-motion branch stay as they are.

10. **DESIGN.md:** a repo-root `DESIGN.md` is the single source of truth for the design system (the design analogue of AGENTS.md). It contains:
    - purpose and how to use it
    - the colour roles table (token → role → light/dark hex) with verified contrast, plus the colour usage rules and forbidden pairs
    - typography
    - the spacing/radius scale
    - the components spec
    - the Iconography mapping table (approved)
    - motion (including the flashcard flip and Reduce Motion) and haptics
    - the accessibility checklist
    - what we borrow and what we don't copy from competitors
    - the change procedure: Theme.swift and DESIGN.md change in the same diff, and new visual decisions go to the user via a mockup

    AGENTS.md gets one line, "Before any UI/visual work read DESIGN.md". CLAUDE.md imports AGENTS.md, so it needs nothing more. `.claude/skills/mobile-ios-design/SKILL.md` keeps its process (§1) and review rubric (§10); its project-specific values are replaced with a pointer to DESIGN.md, and generic principles may stay brief. The docs/architecture.md "Presentation" section becomes a short summary plus a link, with no duplicated tokens. DESIGN.md is written in Phase 1 with Theme.swift. Its values match Theme exactly, and ThemeTests uses the DESIGN.md table. It is updated at the end of Phase 2 if anything changed at Gate 1. The docs-only parts need no build.

11. **Achievement catalog symbols are normalised** (user-approved, 2026-11-16). In `Services/Achievements.swift` only the `symbol:` string values change to outline SF Symbols; pairs get distinct outline names (e.g. 200 words → `books.vertical`, 50 words → `book`, 7-day streak → `calendar`). IDs, titles, details, criteria, points, ledger and unlock logic are unchanged. Unlocked badges add `.fill` via `symbolVariant`; locked badges render the outline name. This is the only allowed Services edit; AchievementEvaluator/Store tests must still pass unchanged. Verify each name exists on iOS 17.

12. **AddWord translation error = calm hint (variant A, `.codex/plans/yellow-redesign/options.html`).** When `draft.translationError != nil`, show under the translation field a single `subtleText` `.footnote` line with `info.circle`: "Автоперевод недоступен — впишите перевод вручную". No red, no `wifi.exclamationmark`. The service's `translationError` text is not shown visually; it is appended to the line's `accessibilityLabel` ("Автоперевод недоступен. <error>"). Translation field placeholder stays editable. Visual only, no store change.
13. **Scan result: long press on a word chip** (replaces the "Исправить слово" `Menu` under «Оригинал», ScannerView ~:323-332, which is removed). Each chip gets a native `.contextMenu` with: "Исправить слово…" (`pencil`) → sets the existing `selectedWord = SelectedWord(text: word)` (same AddWordView sheet flow as today); "Добавить в словарь" / "Убрать из словаря" / "Убрать из папки" (`plus` / `minus.circle`, calls existing `toggleSaved(word)`; only when translation is available, same rule as the tap); "Тема" submenu with the `WordCategory` options (same binding as the current chip `categoryMenu`, only when translation is available). The visible per-chip `categoryMenu` row is removed from the chip. Tap behaviour, retry-on-error, `scanWordChip-…` identifiers and accessibility label/hint stay. Add `.accessibilityAction(named: "Исправить слово")` (and named actions for add/remove) so VoiceOver has the same actions. Hint copy changes to: "Нажмите +, чтобы сохранить. Удерживайте слово, чтобы исправить или выбрать тему." View-only change; no draft/store logic changes.

Decision 11 symbol table (`Services/Achievements.swift`, `symbol:` strings only; every name already exists in SF Symbols for iOS 17 — `medal` is iOS 16+):

| Achievement id | Old | New |
|---|---|---|
| vocabulary.words.1 | text.badge.plus | text.badge.plus (unchanged) |
| vocabulary.words.50 | books.vertical | book |
| vocabulary.words.200 | books.vertical.fill | books.vertical |
| vocabulary.folders.3 | folder.fill | folder |
| vocabulary.categories.all | square.grid.3x3.fill | square.grid.3x3 |
| practice.answers.100 | checkmark.circle | checkmark.circle (unchanged) |
| practice.answers.500 | checkmark.seal.fill | checkmark.seal |
| practice.quiz.perfect | trophy.fill | trophy |
| practice.listening.50 | ear.fill | ear |
| streak.days.3 | flame | flame (unchanged) |
| streak.days.7 | flame.fill | medal |
| mastery.learned.10 | brain | brain (unchanged) |
| mastery.tier.25 | star.fill | star |
| mastery.interval.30 | calendar.badge.clock | calendar.badge.clock (unchanged) |
| meta.polyglot | crown.fill | crown |

Add a unit test in `MojSlownikTests/AchievementCatalogSymbolTests.swift` (or inside ThemeTests): no catalog symbol ends with `.fill`, and all catalog symbols are unique. Run `xcodegen generate` after adding it.

### Planner decisions (implementer must follow; challenge them at Gate 1 if needed)

- P1. Accent roles are split into separate tokens (see the token table). Every current `appAccent` usage is reassigned in the audit table below.
- P2. `appSuccess` becomes an alias of `appMastery` (green), so the success feedback colour is no longer the yellow accent.
- P3. Palette values live as `UIColor` constants (`enum Palette`), and `Color` statics wrap them, so unit tests can resolve light and dark values and check contrast.
- P4. Add and Scan move from the Словарь toolbar to a bottom-trailing FAB pair (from the mockup). The "Удалить папку" toolbar item stays.
- P5. AddWordView's "Сохранить" moves from the toolbar to a bottom yellow primary button via `safeAreaInset(edge: .bottom)`, which keeps it above the keyboard. The toolbar keeps only "Отмена". There is only one "Сохранить" button, so the UI-test query `buttons["Сохранить"]` still matches a single element.
- P6. Flashcard rating buttons keep a 2×2 grid (1 column at accessibility sizes). The mockup's interval subtitles ("1 д", "3 д") are NOT added because they need an SRS preview, which is new logic.
- P7. No 7-day streak strip. `AchievementLedger` stores only `lastStudyDay`, `currentStreakDays` and `longestStreakDays`. Days before the current streak are unknown, so a strip would show unknown days as missed and would need new calendar logic. The hero shows the streak as text instead.
- P8. Словарь uses yellow only for the selected chip and the Add FAB. Word rows get no highlighter treatment (see Open decision 1).
- P9. The haptic for the achievement banner lives in `AchievementTracker`, which is mounted once at the root. Putting it in `achievementBanner()` would not work: that modifier is hosted at root, AddWordView and ScanResultView, so the haptic would fire 2–3 times.
- P10. System navigation bars, large titles, `.searchable` and the TabView stay native. On the iOS 26 SDK (Xcode 27.2 is installed) they get Liquid Glass automatically. There are no `toolbarBackground` or `UINavigationBar.appearance` overrides.
- P11. The word-saved haptic has one source, WordListView's `words.count`. Every save flow is presented over WordListView, so per-sheet haptics are not needed and nothing double-fires.
- P12. The Design spec follows `.claude/skills/mobile-ios-design/SKILL.md` §2–7. The rubric mapping (§10) is under Design spec.

## Design spec

This section follows `.claude/skills/mobile-ios-design/SKILL.md` §2–7. The section numbers below refer to the skill. In Phase 1, the content of this Design spec (tokens, rules, typography, spacing/radii, components, iconography, motion, haptics) is transcribed into the repo-root `DESIGN.md`, which then becomes the source of truth. The plan stays the task history.

### Colour roles and tokens (skill §2, `Theme/Theme.swift`)

Views use only these semantic tokens. No hex, `Color.yellow`, `.white` or `.black` appear in views, except the existing camera-only `Color.black` / `Color.white.opacity` in ScannerView, which sit over a live camera or photo. Existing names keep their role and get new values. New names are marked NEW.

The brand colour is light, so the accent is split into three roles (skill §2):
- **accent fill** = `appAccent`
- **on-accent** = `appOnAccent` (ink, never white)
- **accent foreground** = `appAccentText` (ochre in light mode, yellow in dark mode)

`appAccentStrong` is the control and tint role.

| Token | Role | Light | Dark |
|---|---|---|---|
| `appBackground` | page/paper | #FAF8F2 | #141310 |
| `cardBackground` | grouped cards, rating/option buttons | #FFFFFF | #1F1E1A |
| `appInk` | primary text/icons | #1C1B17 | #F4F1E8 |
| `subtleText` | secondary text/metadata | #6B675C | #A8A293 |
| `appBorder` | hairline dividers, ring track, card edge | #E7E2D5 | #2E2C26 |
| `appSecondarySurface` | neutral fill: unselected chips, category capsules, inputs, pronounce button | #F0ECE1 | #2A2823 |
| `appAccent` | **accent fill only**: primary button, Today hero, selected chip, unlocked tile, Add FAB, scan-photo selection | #FFD43B | #FFD43B |
| `appOnAccent` | **on-accent**: text/icons on `appAccent` | #1C1B17 | #1C1B17 |
| `appAccentText` NEW | **accent foreground**: accent-coloured text/icons on paper/card | #8A6A00 | #FFD43B |
| `appAccentStrong` NEW | control tint: TabView, `.tint`, progress fill, checkmarks | #1C1B17 | #FFD43B |
| `appAccentSoft` NEW | soft yellow surface: mode-icon tiles, saved scan chips, replay button, language pill | #FFF3BF | #3A3318 |
| `appInverseSurface` NEW | ink surface: CTA inside Today hero, Achievements hero | #1C1B17 | #1C1B17 |
| `appOnInverse` NEW | text on `appInverseSurface` (yellow `appAccent` also allowed there) | #F4F1E8 | #F4F1E8 |
| `appCardEdge` NEW | 1 pt card edge stroke (mockup `cardShadow` hairline); not a shadow | #E7E2D5 | #2E2C26 |
| `appRingTrack` NEW | knowledge ring track (graphic, ≥ 1.5:1 vs card and paper) | #CDC5B0 (1.72 card / 1.62 paper) | #46423A (1.67 card / 1.86 bg) |
| `appInverseEdge` NEW | 1 pt edge of inverse surfaces (Achievements hero, banner); separates them from the dark bg | #1C1B17 (= surface, invisible) | #3A372F (1.56 vs bg) |
| `appMastery` | Легко / success | #25704C | #8BD3A8 |
| `appMasterySurface` NEW | correct-answer surface | #E3F1E8 | #1C3125 |
| `appSuccess` | alias → `appMastery` (was `appAccent`; skill §2: do not reuse the brand colour for success) | — | — |
| `appError` | errors, Не помню | #B3261E | #FF8A80 |
| `appErrorSurface` | wrong-answer surface | #FCE8E6 | #3B1D1A |
| `appWarning` | warning **text** | #7C4C17 (unchanged) | #F4C787 (unchanged) |
| `appWarningSurface` | warning surface | #FBEFDB (unchanged) | #43311D (unchanged) |
| `appCaution` NEW | amber, **graphics only** (Трудно ring arc); never text | #C77700 | #FFA94D |

**Verified WCAG contrast** (from the coordinator; ThemeTests re-asserts them):

| Pair | Ratio | Use |
|---|---|---|
| ink #1C1B17 on yellow #FFD43B | 12.1 | on-accent text, OK |
| yellow #FFD43B on paper #FAF8F2 | 1.34 | **forbidden** as text, tint or thin stroke |
| ochre #8A6A00 on paper / white / soft #FFF3BF | 4.77 / 5.07 / 4.54 | accent foreground, OK (AA body) |
| subtle #6B675C on paper | 5.32 | OK |
| dark: yellow on bg #141310 / card #1F1E1A | 13.0 / 11.7 | dark accent foreground, OK |
| dark: subtle #A8A293 on card | 6.56 | OK |
| error #B3261E on white | 6.54 | OK |
| mastery #25704C on paper / masterySurface / secondarySurface | 5.65 / 5.15 / 5.08 | OK |
| amber #C77700 on paper | 3.26 | ring graphic only (non-text ≥ 3:1); use `appWarning` for warning text |

The test computes all other pairs (on-inverse, surfaces, ochre on `appSecondarySurface`) instead of assuming them (skill §2 "check new pairs").

Implementation shape:
```swift
extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1)            // 0xRRGGBB
    convenience init(light: UIColor, dark: UIColor)              // dynamic provider
}
enum Palette { static let accent = UIColor(light: .init(hex: 0xFFD43B), dark: .init(hex: 0xFFD43B)) … }  // one per token
extension Color { static let appAccent = Color(uiColor: Palette.accent) … }
```
Remove the old `Color(light:dark:)` if nothing uses it afterwards.

**Colour usage rules** (transcribed into DESIGN.md):
1. `appAccent` is fill or background only. Never use it in `.foregroundStyle`, `.tint`, an SF Symbol colour or a thin stroke on light surfaces. The single exception is ScannerView's selection stroke over the camera photo.
2. Content on `appAccent` uses `appOnAccent`. Content on `appInverseSurface` uses `appOnInverse` or `appAccent`.
3. Accent-coloured text and icons use `appAccentText`. If ThemeTests shows ochre on `appSecondarySurface` < 4.5, use it there only for icons or large text (≥ 20 pt semibold).
4. Controls, progress fills, checkmarks and tab selection use `appAccentStrong`.
5. One accent. At most one `appAccent`-filled primary button is visible per screen state. Selected chips and the FAB are selection or floating actions, not competing primary buttons. Content text stays ink.
6. State is never colour-only:
   - ring: fill amount
   - answers: ✓/✕ icons and text
   - achievements: lock glyph and "Получено …"
   - selected chips: `.isSelected` trait and weight
7. `appCaution` is used only for the ring arc. Semantic colours keep their meaning everywhere.

### Typography (skill §3)

SF Pro uses text styles only. Custom sizes use `@ScaledMetric`. There are no fixed text point sizes.

| Use | Spec |
|---|---|
| Root screen titles | system large title (Словарь, Практика); pushed screens inline (unchanged) |
| Hero number ("12") | `@ScaledMetric(relativeTo: .largeTitle) var heroNumber: CGFloat = 40` → `.system(size: heroNumber, weight: .heavy)`, `.monospacedDigit()`, `.contentTransition(.numericText())` |
| Hero "из N" suffix | `.title3.weight(.semibold)`, opacity 0.75 |
| Flashcard word | `@ScaledMetric(relativeTo: .largeTitle) var cardWord: CGFloat = 38` → `.system(size: cardWord, weight: .heavy)`, `.multilineTextAlignment(.center)`, `.fixedSize(horizontal: false, vertical: true)`, `.minimumScaleFactor(0.7)` only as a last resort |
| Quiz/listening prompt | `.largeTitle.weight(.bold)` (was `.title`), wraps |
| Achievements points | `.largeTitle.weight(.heavy)`, `.monospacedDigit()`, `.contentTransition(.numericText())` |
| List word (Polish) | `.title3.weight(.bold)`, wraps |
| List translation / metadata | `.subheadline`, `subtleText` |
| Card/tile title | `.headline` |
| Section header ("РЕЖИМЫ") | `.footnote.weight(.bold)`, `.textCase(.uppercase)`, `.tracking(0.6)`, `subtleText` |
| Hero kicker ("СЕГОДНЯ") | as section header, colour `appOnAccent.opacity(0.75)` |
| Buttons | `.body.weight(.bold)` |
| Chips | `.subheadline.weight(.semibold)` |
| Counts (badges, progress "N из M", points) | `.monospacedDigit()` |

Hierarchy comes from weight and size. Metadata uses `subtleText`. There is no coloured body text.

### Layout, spacing, radii (skill §4)

```swift
enum AppSpacing { static let xxs: CGFloat = 4, xs = 8, s = 12, m = 16, l = 20, xl = 24, xxl = 32 }
enum AppRadius  { static let control: CGFloat = 12   // chips' tiles, icon tiles, inputs, option rows
                  static let button:  CGFloat = 16   // primary buttons, FAB
                  static let card:    CGFloat = 18   // grouped cards, mode tiles
                  static let hero:    CGFloat = 24   // Today hero, Achievements hero, prompt cards
                  static let flashcard: CGFloat = 28 }
```
- All shapes use `RoundedRectangle(cornerRadius:, style: .continuous)`. Chips use `Capsule()`.
- Screen side margin is 20 and section gap is 20. Every spacing value comes from `AppSpacing` (4-pt grid).
- `cardStyle(cornerRadius: AppRadius.card)` is `cardBackground` plus a 1 pt `appCardEdge` `strokeBorder`. It has no shadow. Shadows are used only for floating elements: the FAB and the banner (skill §4).
- Open lists over cards: the Словарь list stays a plain `List` with hairline separators (`appBorder`). Achievement rows stay inside one grouped card per category with hairline dividers. Cards are reserved for groups and hero blocks.
- Touch targets are ≥ 44×44 pt everywhere (chips, ring-free icon buttons, FAB, pronounce, menus).
- At accessibility sizes (`dynamicTypeSize.isAccessibilitySize`):
  - hero badges and the hero number line stack vertically (existing `AnyLayout`)
  - mode grid → 1 column
  - rating grid → 1 column
  - WordRow actions go under the word
  - the achievements row stacks vertically
  - the banner title wraps
  - scrolling chip rows stay horizontally scrollable and never clip

### Native structure and system chrome (skill §5)

- **Tabs:** `TabView` has 2 tabs (Словарь, Практика). Achievements is pushed from a Практика row, so no destination is both a tab and a row.
- **Bars:** system `NavigationStack` bars, large titles on root screens and inline on pushed screens. There are no `toolbarBackground` or appearance-proxy overrides. On the iOS 26 SDK (Xcode 27.2 is installed) bars get Liquid Glass automatically. This plan uses no `glassEffect`; if one is ever added, it goes behind `if #available(iOS 26, *)`. ScannerScreen keeps its system materials over the camera.
- **Sheets:**
  - FolderPicker sheet: `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`, since the content is short.
  - AddWordView stays `.large`, because it has a keyboard, alternatives and metadata. Its input and translation come first, then folder and category (unchanged order).
  - ScanResultView stays `.large`.
- **Destructive actions:** unchanged (swipe delete `role: .destructive`, folder confirmation dialog).
- **SF Symbols:** every icon is an SF Symbol, using the default monochrome rendering. The only palette rendering is the scanner checkmark (ink glyph on a yellow disc). Weight follows the text style.

### Components (skill §6)

All components go in `Views/Components/` only when used by ≥ 2 screens; otherwise they are private in the screen.

| Component | Where | Spec |
|---|---|---|
| **Primary button** | new `Views/Components/PrimaryButtonStyle.swift` (Training, AddWord, Scanner, Flashcards, Quiz, Listening) | `struct PrimaryButtonStyle: ButtonStyle { enum Kind { case accent, inverse }; var kind: Kind = .accent }`. Full width, `minHeight: 50`, `AppRadius.button`, `.body.weight(.bold)`, centered multiline. `.accent`: `appAccent` + `appOnAccent`. `.inverse` (only inside the yellow hero): `appInverseSurface` + `appAccent`. Disabled (`@Environment(\.isEnabled)`): `.accent` → `appSecondarySurface` + `subtleText`; `.inverse` → `appOnAccent.opacity(0.12)` + `appOnAccent.opacity(0.5)`. Pressed: scale 0.97 + opacity 0.9, `.snappy(duration: 0.2)`; Reduce Motion → opacity only |
| **Secondary actions** | — | No custom secondary button: the Flashcards reveal button is removed (user decision 7). Text-only secondary actions use system `Button` with the `appAccentText` tint (colour rule 4) |
| **Chip** | new `Views/Components/ChipStyle.swift` (WordListView, FolderPicker compact used on Словарь + Практика) | `func chipStyle(isSelected: Bool) -> some View`: horizontal padding 14, visible `Capsule` minHeight 36, outer `frame(minHeight: 44)` + `contentShape(Rectangle())`. Selected: `appAccent`/`appOnAccent`, `.semibold`; unselected: `appSecondarySurface`/`appInk`. chipStyle sets `.foregroundStyle` itself. Callers must REMOVE explicit colours on the label's text and icons (e.g. FolderPicker:37/46/55), or those colours would put `appInk` (1.26:1 in dark) on yellow. AddWordView alternative chips keep their two-line `RoundedRectangle(AppRadius.control)` layout with the same fills (already conforming) |
| **Progress bar** | new `Views/Components/MarkerProgressBar.swift` (Training, SessionProgress, Achievements) | `MarkerProgressBar(value: Double, track: Color = .appSecondarySurface, fill: Color = .appAccentStrong, height: CGFloat = 8)`: capsule track and fill, value clamped to 0…1, `.snappy(duration: 0.3)` on change, Reduce Motion → no animation. `accessibilityHidden(true)`; callers keep their existing label/value |
| **Card** | `Theme.cardStyle` | see Layout |
| **Today hero** | TrainingView, private | `appAccent` fill, `AppRadius.hero`, padding 16, content `appOnAccent`. Order: kicker "Сегодня" → big line (`Text("\(completed)")` hero number + `Text(" из \(total)")` suffix joined with `+`, so it is still read as "N из M"; or the existing "Добавьте первое слово"/"Нет повторений" in `.title2.bold`) → existing remaining-status line (TrainingView:66-69; replace its explicit `subtleText` with `appOnAccent.opacity(0.75)`, 6.24:1) → `MarkerProgressBar(track: appOnAccent.opacity(0.12), fill: appOnAccent)` with the existing a11y label/value → CTA `PrimaryButtonStyle(kind: .inverse)` (existing titles, hint, disabled rule) → badges row (`appOnAccent.opacity(0.12)` capsules with ✓/✕ icons and the existing "Верных: N"/"Ошибок: N") → existing "Ответов: N" caption (TrainingView:80-82; `subtleText` → `appOnAccent.opacity(0.75)`) |
| **Mode tile** | TrainingView, private | `cardStyle()`, padding 14, minHeight 96, 36 pt (`@ScaledMetric`) `AppRadius.control` icon tile in `appAccentSoft` with an `appInk` glyph, `.headline` title, `.subheadline` `subtleText` subtitle. Disabled: dim ONLY the icon tile and title (`.opacity(0.45)`). The subtitle ("Нужно минимум 4 слова") stays full-strength `subtleText` so the reason stays readable. Use a private `TileButtonStyle` that renders the label unchanged, so the system does not dim the whole label. Verify in the empty/1-word screenshot. `LazyVGrid` 2 columns (1 at AX); На слух is full width with an HStack layout |
| **Achievements entry row** | TrainingView, private | `cardStyle()` HStack: 40 pt `appAccentSoft` tile + ink `trophy`; "Достижения" `.headline`; subtitle "\(totalPoints) очков · Серия: \(streak) дн." `subtleText`; trailing "\(unlocked) из \(total)" `subtleText` monospaced + chevron. `.accessibilityElement(children: .combine)`. Pushes `AchievementsView` |
| **List row** | WordListView `WordRow` | Two lines.<br>**Line 1:** `HStack(alignment: .center, spacing: 12)` with the Polish word (`.title3.bold`, `.layoutPriority(1)`, `frame(minWidth: 160, alignment: .leading)`, wraps), then Spacer, the ring, and PronounceButton.<br>**Line 2:** `HStack(spacing: 8)` with the Russian translation (`subtleText`, `.layoutPriority(1)`, wraps), then Spacer, the category capsule (`tag` + name, `.caption.weight(.medium)`, `subtleText` on `appSecondarySurface`, `maxWidth: 120`, tail truncation, 44 pt target), and the folder menu icon button (44 pt).<br>Wrap line 2's trailing pair in `ViewThatFits(in: .horizontal) { HStack { … }; VStack(alignment: .trailing) { … } }`. At AX sizes, line 2 becomes a VStack: translation, then category + folder on their own row (leading). The word is never squeezed below ~160 pt |
| **Knowledge ring badge** | `KnowledgeTierBadge` (List, Scanner, Flashcards, Quiz, Listening) | `@ScaledMetric(relativeTo: .body) var size: CGFloat = 22`; line width `size * 0.2`; track `Circle().stroke(appRingTrack)`; arc `Circle().trim(from: 0, to: presentation.fillFraction).stroke(color, StrokeStyle(lineWidth:, lineCap: .butt)).rotationEffect(.degrees(-90))`; no capsule. Colours: error / `appCaution` / `appAccentText` / `appMastery`. Trim animates `.snappy`, Reduce Motion → none. A11y unchanged |
| **Achievement tile** | `AchievementBadge` (Achievements, banner) | unlocked: `appAccent` fill + `appOnAccent` glyph; locked: `appSecondarySurface` + `subtleText` glyph (opacity 0.8) + `lock` bottom-trailing in `subtleText`. The glyph uses `.symbolVariant(isUnlocked ? .fill : .none)` (see Iconography). Radius `size * 0.32`, default size 40 (`@ScaledMetric` base) |
| **Toast/banner** | `AchievementBanner` | floating; ALWAYS `appInverseSurface` background in both themes (user decision 6), radius 20, 1 pt `appInverseEdge` `strokeBorder` (invisible in light, visible in dark); caption "Достижение получено" `appOnInverse.opacity(0.7)`, title `appOnInverse` wraps; `AchievementBadge(size: 36, isUnlocked: true)`; "+N" pill `appAccent` capsule + `appOnAccent` `.subheadline.bold`; shadow `.black.opacity(0.25)`, radius 15, y 6. Dismiss by tap, swipe and VoiceOver action, plus the store announcement (all existing) |
| **Rating buttons** | FlashcardsView, private | `cardBackground` + 1 pt `appBorder` stroke, `AppRadius.control`, `.body.weight(.semibold)`, minHeight 50. Semantic colour for the extremes only: Не помню `appError` text; Трудно, Хорошо `appInk`; Легко `appAccent` fill + `appOnAccent`, no stroke. 2×2 grid, 1 column at AX |
| **Search field** | WordListView | native `.searchable(text:prompt: "Найти слово")`, unchanged |
| **Floating add/scan** | WordListView, private | The overlay attaches to the OUTER `VStack` of WordListView (WordListView:31, the view carrying `.background`/`.navigationTitle`), not the List, so it also shows with 0 words. The empty state tells users to tap «плюс». Layout: `.bottomTrailing`, `HStack(spacing: 12)`, padding trailing 20 / bottom 16, `.ignoresSafeArea(.keyboard)`.<br>Size: `@ScaledMetric(relativeTo: .title2) private var fabScaled: CGFloat = 56`; `fabSize = min(fabScaled, 72)`; scan = `fabSize - 4`.<br>Scan: `AppRadius.button`, `cardBackground`, `appInk` `text.viewfinder`, shadow `.black.opacity(0.12)` r8 y4.<br>Add: `AppRadius.button`, `appAccent` + `appOnAccent` `plus` `.title2.weight(.semibold)`, shadow `.black.opacity(0.18)` r10 y6.<br>Labels "Сканировать текст"/"Добавить слово" are kept. The List gets `.contentMargins(.bottom, fabSize + 16 + AppSpacing.m, for: .scrollContent)`, derived from the same value with no fixed 88 |
| **Pronounce button** | `PronounceButton` | 44 pt `Circle`, `appSecondarySurface` fill, `appInk` `speaker.wave.2`, `.fontWeight(.medium)` |
| **Flashcard (flip)** | FlashcardsView, private | See Motion and Changes §14. The card is one `Button` (identifier `flashcard`) whose label is a `ZStack` of two faces. PronounceButton is a sibling `.overlay(alignment: .topTrailing)` on the Button, outside its label |

### Motion (skill §7)

Every animation is 0.2–0.35 s `.snappy`/`.smooth`, never blocks the next action, and has a Reduce Motion branch:

| Where | Animation | Reduce Motion |
|---|---|---|
| Flashcard reveal (flip) | `withAnimation(.snappy(duration: 0.35)) { isFlipped.toggle() }`. Card label `ZStack { front; back }`: front `.rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)`, back `.rotation3DEffect(.degrees(isFlipped ? 0 : -180), axis: (0, 1, 0), perspective: 0.5)`, so the back face is never mirrored. Face visibility comes from a private `FaceVisibility: ViewModifier, Animatable` (`animatableData` = the face's current angle; opacity 1 when \|angle\| < 90°, else 0), so the swap happens exactly at the edge-on midpoint. The hidden face gets `.accessibilityHidden(true)`. No haptic | no rotation: `withAnimation(.easeInOut(duration: 0.2))` crossfade of face opacities |
| Flashcard next card | container `.id(currentIndex)` + `.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))`. In `apply`, only `currentIndex += 1` is wrapped in `withAnimation(.snappy(duration: 0.3))`; `isFlipped = false` stays outside | transition `.opacity`, no `withAnimation` |
| Hero/Achievements counts | `.contentTransition(.numericText())` with `.animation(.snappy, value:)` | animation `nil` |
| Progress bars, ring trim | `.snappy(duration: 0.3)` on value | `nil` |
| Primary button press | scale 0.97 | opacity only |
| Answer feedback (quiz/listening) | feedback view inserted with `.transition(.opacity.combined(with: .scale(scale: 0.98)))`, `.smooth(duration: 0.25)` | `.opacity` |
| Banner | existing `.move(edge: .top)+opacity` / reduce-motion `.opacity` (unchanged) | existing |

No list-row animations are triggered under the finger. Swipe actions stay system.

### Haptics (skill §7, `.sensoryFeedback`, iOS 17)

| Event | Modifier |
|---|---|
| Choosing a category chip (Словарь) | `.sensoryFeedback(.selection, trigger: selectedCategory)` |
| Choosing a translation alternative (AddWord) | view-local `@State private var selectionTick = 0`, incremented in the chip action → `.sensoryFeedback(.selection, trigger: selectionTick)` (no store API change) |
| Flashcard rating | `.sensoryFeedback(.selection, trigger: reviewedCount)` |
| Quiz answer | `.sensoryFeedback(trigger: selectedAnswer) { _, new in new == nil ? nil : (new == currentQuestion?.correctAnswer ? .success : .error) }` |
| Listening answer | `.sensoryFeedback(trigger: answerIsCorrect) { _, new in new.map { $0 ? .success : .error } }` |
| Word saved (AddWord bottom Save, scan quick-add, nested AddWord) | one source in WordListView, which stays mounted under all these sheets: `.sensoryFeedback(trigger: words.count) { old, new in new > old ? .impact(weight: .light) : nil }`. No per-sheet haptics, so nothing double-fires |
| Achievement unlocked (banner) | in `AchievementTracker` (mounted once): `.sensoryFeedback(trigger: store.currentAnnouncement?.id) { _, new in new == nil ? nil : .impact(weight: .light) }` |

There are no haptics on scroll, card flip/reveal, navigation or generic taps.

### Iconography (user decision 9)

**Style:**
- SF Symbols only, using OUTLINE (non-`.fill`) names.
- Weight: `.fontWeight(.medium)` on standalone `Image`s. `Label` icons follow their text style.
- Size: from the surrounding text style (`.font(.body)`, `.title3`, …), or from a `@ScaledMetric` for the large result icons. No fixed sizes.
- Rendering: default monochrome. `.symbolRenderingMode(.palette)` is used only for the scanner's selected-block checkmark.
- Filled variants are for state only:
  - selected tab (the system fills tab symbols automatically)
  - unlocked achievement glyph (`.symbolVariant(.fill)`)
  - per-answer result `checkmark.circle.fill`/`xmark.circle.fill`
  - scanner saved-word and selected-block `checkmark.circle.fill`
- Icons for modes and the achievements row sit on `appAccentSoft` tiles with an `appInk` glyph.

**Purpose → symbol** (all exist in SF Symbols 5 / iOS 17, and most are already in this codebase):

| Purpose | Symbol |
|---|---|
| Tab Словарь | `character.book.closed` |
| Tab Практика | `rectangle.stack` |
| Add word | `plus` |
| Scan text | `text.viewfinder` |
| Folder (none / member) | `folder.badge.plus` / `folder` |
| Create folder | `folder.badge.plus` |
| Remove from folders / delete folder | `folder.badge.minus` |
| Dictate (idle) | `mic` |
| Dictating (recording) | `waveform` with `.symbolEffect(.variableColor.iterative, isActive: speech.state == .listening && !reduceMotion)` (iOS 17 API) |
| Mic unavailable | `mic.slash` |
| Pronounce / replay | `speaker.wave.2` |
| Category | `tag` |
| Flashcards | `rectangle.on.rectangle` |
| Quiz | `checklist` |
| Listening | `ear` |
| Achievements | `trophy` |
| Streak | `flame` |
| Locked | `lock` |
| Correct / wrong (badges) | `checkmark` / `xmark` |
| Correct / wrong (answer state) | `checkmark.circle.fill` / `xmark.circle.fill` (state, filled) |
| Session result | `flag.checkered` (perfect score: `trophy`) |
| Overflow menu (only if a future row needs one) | `ellipsis.circle` |
| Navigation affordance | `chevron.right` |
| Menu affordance | `chevron.down` |
| Close camera | `xmark` |
| Retry | `arrow.clockwise` |
| Edit / rename | `pencil` |
| Delete | `trash` |
| Network error | `wifi.exclamationmark` |
| Inline error | `exclamationmark.circle` |
| Search empty state | `magnifyingglass` |
| Camera unavailable | `camera` |
| Translate selection | `text.magnifyingglass` |

**Per-file audit** (`grep -rn "systemName:\|systemImage:\|symbol:" MojSlownik/Views`, at base):

| File:line | Old | New |
|---|---|---|
| RootTabView:7 | `book.closed.fill` | `character.book.closed` |
| RootTabView:10 | `rectangle.on.rectangle.angled` | `rectangle.stack` |
| RootTabView:13 | `trophy.fill` (tab) | removed with the tab |
| WordListView:36, 45, 67, 87, 275 | `character.book.closed`, `magnifyingglass`, `trash`, `folder.badge.minus` ×2 | unchanged |
| WordListView:94 | `camera.viewfinder` (toolbar) | `text.viewfinder` (scan FAB) |
| WordListView:102 | `plus` (toolbar) | `plus` (add FAB) |
| WordListView:256 | `chevron.down` | category capsule: `tag` + name + `chevron.down` (`.caption2`) |
| WordListView:290 | `folder.badge.plus` / `folder.fill` | `folder.badge.plus` / `folder` (shape difference conveys membership; the a11y label is unchanged) |
| TrainingView:136 (mode icons via `icon:`) | `rectangle.on.rectangle.angled`, `checklist`, `ear`, `trophy` | `rectangle.on.rectangle`, `checklist`, `ear`; achievements row `trophy` |
| TrainingView:147 | `chevron.right` | unchanged |
| TrainingView hero badges | `checkmark`, `xmark` | unchanged |
| AddWordView:158 | `mic.fill` / `stop.fill` | `mic` / `waveform` + variableColor effect (Reduce Motion: static `waveform`); the a11y labels "Продиктовать по-польски"/"Остановить запись" are unchanged |
| AddWordView:192, 276 | `wifi.exclamationmark`, `mic.slash` | unchanged |
| ScannerView:85 | `xmark` | unchanged |
| ScannerView:142 | `text.magnifyingglass` | unchanged |
| ScannerView:160, 306 | `text.viewfinder` | unchanged |
| ScannerView:210 | `camera.on.rectangle` | `camera` |
| ScannerView:328 | `pencil` | unchanged |
| ScannerView:396 | `checkmark.circle.fill` / `plus.circle` | unchanged (state) |
| ScannerView:406 | `arrow.clockwise` | unchanged |
| ScannerView:466 | `chevron.down` | `tag` + name + `chevron.down` (same capsule as WordListView) |
| ScannerView:516 | `wifi.exclamationmark` | unchanged |
| ScannerView:595 | `checkmark.circle.fill` | unchanged, palette ink-on-yellow |
| FlashcardsView:194 | `checkmark.circle.fill` (completed) | `flag.checkered` on an `appAccentSoft` tile |
| FlashcardsView:204, 223 | `checklist`, `rectangle.on.rectangle.slash` | unchanged |
| QuizView:98, 102 | `checkmark.circle.fill`, `xmark.circle.fill` | unchanged (state) |
| QuizView:173 | `trophy.fill` / `flag.checkered` | `trophy` / `flag.checkered` |
| QuizView:217, 222 | `checkmark`, `xmark` | unchanged |
| ListeningPracticeView:133 | `speaker.wave.2.fill` | `speaker.wave.2` |
| ListeningPracticeView:159, 163 | `checkmark.circle.fill`, `xmark.circle.fill` | unchanged (state) |
| ListeningPracticeView:300 | `trophy.fill` / `flag.checkered` | `trophy` / `flag.checkered` |
| ListeningPracticeView:344, 349 | `checkmark`, `xmark` | unchanged |
| AchievementsView:35 | `trophy.fill` (old header) | removed (the hero has no trophy) |
| AchievementsView:53 | `flame` | `flame` (in the hero, `appAccent` on ink) |
| AchievementBadge:10 | catalog `symbol` | same name + `.symbolVariant(isUnlocked ? .fill : .none)`, `.fontWeight(.medium)` |
| AchievementBadge:17 | `lock.fill` | `lock` |
| PronounceButton:11 | `speaker.wave.2.fill` | `speaker.wave.2` |
| FolderPicker:36, 53, 94, 109, 217, 236, 243, 252 | `folder`, `chevron.down`, `trash`, `folder.badge.plus`, `checkmark`, `pencil`, `trash`, `exclamationmark.circle` | unchanged names; add `.fontWeight(.medium)` |

Services/Achievements.swift catalog symbols are normalised to outline names (Decision 11); only `symbol:` strings change. Unlocked badges add `.fill` via `symbolVariant`; locked badges render the outline name.

### New or changed copy (Russian)

- "Режимы": a new section header above the mode tiles.
- AchievementsView hero subtitle: "\(unlocked) из \(total) получено · рекорд \(longest) дн.". This merges the existing "N из M получено" and "Рекорд: N дн.".
- Practice achievements row subtitle: "\(points) очков · Серия: \(streak) дн.". It replaces "N из M · P очков".

Removed: the tab label "Достижения" (the navigation title stays). No other copy changes.

### Design rubric check (skill §10)

| Rubric finding | How the plan prevents it |
|---|---|
| Raw colour or font size in a view | Every colour is a Theme token. Custom sizes, including the four former `.system(size: 40/44)` result icons, use `@ScaledMetric` with text styles. The only remaining literals are the camera-overlay `Color.black`/`.white` in ScannerView (existing, over a photo) and the shadow colours on the FAB and banner. The AC-2 grep and review cover the rest. |
| Accent fill used as text/tint on a light surface | Role split (`appAccent` / `appOnAccent` / `appAccentText` / `appAccentStrong`), the per-line audit table, and the AC-2 grep `appAccent([^A-Za-z]\|$)` with every hit reviewed. ThemeTests asserts yellow on paper is < 3. Forbidden pairs (`subtleText`/`appInk` on yellow) are removed: hero status line and caption, FolderPicker chip. |
| Contrast unchecked for a new pair | The verified ratios table. `ThemeTests` asserts every text pair ≥ 4.5 and graphics ≥ 3 in light and dark, the ring track and inverse edge ≥ 1.5, and ochre on `appSecondarySurface` in [3, 4.5). |
| Row clips at AX sizes | AX layout rules. WordRow is two lines with the word kept at ≥ 160 pt and a `ViewThatFits` fallback. Gate screenshots at `accessibility-extra-large`, plus a manual AX5 spot check. Long words wrap. |
| Control < 44 pt or gesture-only | Chips keep a 44 pt outer frame. FAB is 52–72, pronounce 44, category capsule and folder menu 44, rating/option/primary 50. The flashcard reveal is the card `Button` (not a gesture), with its hint. The banner keeps its "Скрыть" accessibility action and the `.isButton` trait. |
| Animation without a Reduce Motion branch | The Motion table gives every animation a branch: the flip falls back to a crossfade, and the `waveform` effect is inactive. |
| State colour-only | Ring fill amount, ✓/✕ icons with text, lock glyph and "Получено", folder `folder` vs `folder.badge.plus` shapes, `.isSelected` traits. |
| Two competing primary actions | One `appAccent` primary per state:<br>- Практика has only the hero; its CTA is `.inverse`.<br>- AddWord has only the bottom Save; the toolbar Save is removed.<br>- In Listening, Проверить is disabled (grey) once Дальше appears.<br>- Flashcards has no reveal button; Легко is a rating choice, not a CTA.<br>Selection chips (including a yellow folder chip) and the FAB are not primary buttons. |
| Destination duplicated in the tab bar | The Achievements tab is removed. It is reachable only via the Практика row. |
| Behaviour changed in a visual task | No model, store, SRS, translation or achievement-logic edits, and the Services catalog symbols are untouched. Only additive view-level code: `Presentation.fillFraction`, Theme tokens, view-local haptic triggers and flip state rendering (the existing `isFlipped`). AC-14 covers this. |

## Acceptance criteria

- AC-1: `Theme.swift` defines every token in the table with the stated light/dark values (including `appInverseEdge`, `appRingTrack`, and light `appMastery` #25704C), plus `Palette` UIColor constants, `AppRadius`/`AppSpacing` and `UIColor(hex:)`. `appSuccess == appMastery`.
- AC-2: `grep -rnE "appAccent([^A-Za-z]|$)" MojSlownik` is run, and every hit is reviewed against colour rule 1. The only allowed uses are as fill/background, plus the ScannerView photo-overlay stroke. No `.foregroundStyle`, `.tint` or SF Symbol colour on a light surface uses `appAccent`.
- AC-3: The app has exactly two tabs, «Словарь» (`character.book.closed`) and «Практика» (`rectangle.stack`), with selection tinted `appAccentStrong`. The achievement tracker, banner and AppleTranslationHost still mount at the root.
- AC-4: Практика shows, top to bottom:
  - the compact FolderPicker
  - the yellow Today hero with "N из M", the status line and caption in `appOnAccent.opacity(0.75)`, progress, the ink CTA (existing titles), and the correct/error badges and "Ответов" caption
  - the "Режимы" header and the 2-column mode tiles (На слух full width; a disabled tile dims only its icon tile and title)
  - the achievements row ("Достижения", "P очков · Серия: S дн.", chevron), which pushes AchievementsView
  - the "Слов в выбранном наборе" footnote

  Exactly one yellow primary action (the hero) is visible. Selection chips such as a selected folder chip may also be yellow; they are not counted. The CTA disabled rules and accessibility hints are unchanged.
- AC-5: Словарь shows the native search, folder and category chips (capsules; the selected chip is yellow with `appOnAccent` text and icons in both themes), and two-line rows:
  - line 1: Polish word, ring, pronounce
  - line 2: translation, then the category capsule and folder menu

  The word is never narrower than about 160 pt. Add and Scan are a bottom-trailing FAB pair whose size is capped at 72 pt. The list bottom margin is derived from that size, so the FAB never covers the last row, and the FAB is hidden behind the keyboard. The swipe-to-delete and folder-deletion toolbar still work.
- AC-5a: With 0 words, the FAB pair is visible over the «Словарь пуст» empty state.
- AC-6: KnowledgeTierBadge is a ring whose fill is 25/50/75/100 % for tiers 0–3, coloured error / caution / accentText / mastery, on an `appRingTrack` track. The VoiceOver label strings are unchanged.
- AC-7: Flashcards show a card (`cardBackground`, radius 28) with a language label and the ring inside, and PronounceButton as a sibling overlay at top-trailing (when Polish is the large text). Rating buttons follow the spec: only Не помню is red text and Легко a yellow fill; Трудно and Хорошо are ink. There is a selection haptic on rating. Card change is animated, or not animated under Reduce Motion. `dueDate` still updates after rating.
- AC-7a (flip):
  - Tapping the card (identifier `flashcard`) flips it around Y in about 0.35 s. The front shows the prompt word. The back shows the word small and the translation large, not mirrored. Tapping again flips back.
  - There is no separate "Показать/Скрыть перевод" button. VoiceOver hears the shown text with the hint "Показать перевод"/"Скрыть перевод" and the `.isButton` trait. The hidden face is not read.
  - Tapping PronounceButton speaks without flipping.
  - Reduce Motion gives a crossfade with no rotation.
  - There is no haptic on flip.
  - Rating buttons appear only after reveal.
- AC-8: Quiz and На слух use card-style prompts, a correct answer on `appMasterySurface` with a green check, a wrong answer on `appErrorSurface`, success/error haptics, a feedback transition with a Reduce Motion branch, and the yellow primary for Проверить/Дальше/results. The answer flow and timing are unchanged.
- AC-9: AddWordView has a bottom yellow "Сохранить" (same disabled rule), and the toolbar keeps only "Отмена" (in `appAccentText`). The language pill is `appAccentSoft` with ink text. The alternative chips keep a yellow fill with ink when selected. The mic button shows `mic`, and `waveform` (animated unless Reduce Motion) while recording. In ScanResultView, saved chips use an `appAccentSoft` surface and the "+" icons use `appAccentText`. Scanner block selection draws a yellow highlight with an ink checkmark on a yellow circle. The scan result still remains after AddWordView is dismissed.
- AC-10: AchievementsView shows:
  - the ink hero: yellow points, the merged subtitle, `flame` + "Серия: N дн." in `appOnInverse`, a progress bar with a yellow fill on a 12 % paper track, and a 1 pt `appInverseEdge` edge visible in dark mode
  - uppercase section headers with done/total
  - unlocked yellow tiles with filled glyphs, and locked neutral tiles with `lock`
  - `MarkerProgressBar` for in-progress items

  It has no NavigationStack of its own and is only pushed from Практика.
- AC-11: The achievement banner is ALWAYS a dark ink strip in both themes: `appInverseSurface` background, `appOnInverse` text, a yellow badge and a yellow "+N" pill. In dark mode it adds a 1 pt `appInverseEdge` edge and keeps its shadow. A single light haptic fires on each new announcement. There is still a reduce-motion opacity transition, and tap/swipe/VoiceOver dismissal still work.
- AC-12: FolderPicker's compact variant is a chip whose icon, title and chevron use `appOnAccent` when selected and `appInk` otherwise (no explicit `appInk` overriding the chip). Its sheet uses `.presentationDetents([.medium, .large])` with a visible drag indicator. CategoryMenu, ErrorAlert and SessionProgress (now `MarkerProgressBar`) follow the tokens.
- AC-13: Every text pair listed under Verification meets WCAG AA in both appearances (unit test). Controls stay ≥ 44 pt. Layouts work at `accessibility-extra-large` with no clipped or overlapping text. Every animation has a Reduce Motion branch.
- AC-14: Existing SwiftData words, folders and achievements (UserDefaults `achievements.v1`) load unchanged after the update. No model, store or service logic is changed beyond the `KnowledgeTierBadge.Presentation.fillFraction` and Theme additions.
- AC-15: The build has no warnings. `MojSlownikUnitTests` passes. `docs/architecture.md` reflects the two tabs and the new components. Its "Presentation" section is a short summary that links to DESIGN.md, with no token values.
- AC-16: A light impact haptic fires once per newly saved word (AddWord, scan quick-add, nested AddWord). Its single source is WordListView's `words.count`. It does not fire on launch or on delete.
- AC-17: Every item in the Design rubric check (skill §10) holds for the final diff.
- AC-18 (icons): every `systemName:`/`systemImage:` in `MojSlownik/Views` matches the Iconography mapping and per-file audit. No `.fill` names remain outside the listed state uses. Standalone icons use `.fontWeight(.medium)`, with sizes from text styles or `@ScaledMetric`.
- AC-19 (text buttons): text-only buttons and toolbar items ("Показать все слова", "Создать папку", "Повторить перевод предложения", "Исправить слово", "Отмена", "Готово", "Удалить папку") render in `appAccentText` (ochre in light, yellow in dark), not ink.
- AC-20 (DESIGN.md):
  - The repo-root `DESIGN.md` exists with every section listed in user decision 10.
  - Its token table, `Theme.swift` (`Palette`) and `ThemeTests` agree exactly; `testDesignDocTokenTableMatchesPalette` passes.
  - AGENTS.md contains the line "Before any UI/visual work read DESIGN.md".
  - `.claude/skills/mobile-ios-design/SKILL.md` keeps §1 and §10 and points to DESIGN.md instead of repeating project values.
  - docs/architecture.md links to DESIGN.md.

## Changes by file

### Accent usage audit (every current `appAccent`/`appSuccess` hit → new role)

Screen-level `.tint` follows colour rule 4. Screens and sheets get `.tint(.appAccentText)`, so text buttons and toolbar items read as actions. Non-text controls set `appAccentStrong` explicitly.

| File:line (at base) | Current | New |
|---|---|---|
| RootTabView:15 | `.tint(.appAccent)` | TabView `.tint(.appAccentStrong)` (tab selection) |
| WordListView (NavigationStack) | inherits tint | `.tint(.appAccentText)` on the NavigationStack content ("Показать все слова", "Удалить папку") |
| TrainingView (NavigationStack) | inherits tint | `.tint(.appAccentText)` (back buttons of pushed screens) |
| TrainingView:66-69 | status line `subtleText` | `appOnAccent.opacity(0.75)` (6.24:1) |
| TrainingView:72 | progress tint | `MarkerProgressBar` in the hero (ink fill on a 12 % ink track) |
| TrainingView:76 | correct badge fg accent | hero badge, `appOnAccent` |
| TrainingView:80-82 | "Ответов" caption `subtleText` | `appOnAccent.opacity(0.75)` |
| TrainingView:138 | mode icon fg | `appInk` on an `appAccentSoft` tile |
| TrainingView:168-169 | CTA accent fill | `PrimaryButtonStyle(kind: .inverse)` |
| WordListView:185-186 | selected chip fill | `chipStyle(isSelected:)` (conforms) |
| WordListView:261 | category menu text accent | `subtleText` on an `appSecondarySurface` capsule |
| KnowledgeTierBadge:14 | track `appBorder` | `appRingTrack` |
| KnowledgeTierBadge:60 | `.accent → .appAccent` | `.accent → .appAccentText` |
| PronounceButton:13 | icon accent | `appInk` |
| SessionProgress:30 | progress tint | `MarkerProgressBar()` defaults |
| FolderPicker:37, 46, 55 | folder icon accent / title `appInk` / chevron accent | compact: no explicit colours; chipStyle supplies `appOnAccent` (selected) or `appInk`. Non-compact form row: icon `appInk`, chevron `subtleText` |
| FolderPicker:205 | sheet tint | `.tint(.appAccentText)` ("Создать папку", "Сохранить", "Готово") |
| FolderPicker:217 | checkmark | explicit `appAccentStrong` |
| AddWordView:53, 111 | tint | `.tint(.appAccentText)` |
| AddWordView:129-130 | lang pill accent 12 % + accent text | `appAccentSoft` bg + `appInk` text |
| AddWordView:244-255 | selected alt chip | unchanged (conforms) |
| FlashcardsView:39 | tint | `.tint(.appAccentText)` |
| FlashcardsView:98 | language label accent | `subtleText`, `.caption.weight(.bold)`, uppercase |
| FlashcardsView:110 | reveal label accent | removed (the card is the reveal button; user decision 7) |
| FlashcardsView:159-170 | grade tint/surface | rating-button spec |
| FlashcardsView:194-197 | completed icon `appSuccess`, `.system(size: 40)` | `flag.checkered`, `appInk` on an `appAccentSoft` tile, `@ScaledMetric` size |
| FlashcardsView:212-213 | borderedProminent accent | `PrimaryButtonStyle()` |
| QuizView:36 | tint | `.tint(.appAccentText)` |
| QuizView:99 | `appSuccess` check | unchanged (now green `appMastery`) |
| QuizView:173-175 | result icon accent, `.system(size: 40)` | `appInk` on `appAccentSoft`, `@ScaledMetric` |
| QuizView:205-206 | accent button | `PrimaryButtonStyle()` |
| QuizView:217-221 | result badge `appSuccess` | unchanged (now green; must be ≥ 4.5 on its surface, covered by mastery tests) |
| QuizView:126-131 | correct option `appSecondarySurface` | `appMasterySurface` |
| ListeningPracticeView:39 | tint | `.tint(.appAccentText)` |
| ListeningPracticeView:110-111, 217-218, 332-333 | accent buttons | `PrimaryButtonStyle()` |
| ListeningPracticeView:135 | replay fg accent | `appInk` on an `appAccentSoft` circle |
| ListeningPracticeView:160, 229 | `appSuccess` | unchanged (green) |
| ListeningPracticeView:300-302 | result icon accent, `.system(size: 40)` | `appInk` on `appAccentSoft`, `@ScaledMetric` |
| ListeningPracticeView:344-348 | result badge `appSuccess` | unchanged (green) |
| ListeningPracticeView:184-190, 240 | correct surfaces `appSecondarySurface` | `appMasterySurface` |
| ScannerView:148-149 | borderedProminent accent | `PrimaryButtonStyle()` |
| ScannerView:210-212 | unavailable icon accent, `.system(size: 44)` | `camera`, `appAccentText`, `@ScaledMetric` 44 |
| ScannerView:268 | screen tint | `.tint(.appAccentText)` ("Готово", "Исправить слово", "Повторить перевод предложения") |
| ScannerView:397 | `isSaved ? appSuccess : appAccent` | `isSaved ? appMastery : appAccentText` |
| ScannerView:408 | "Повторить" accent | `appAccentText` |
| ScannerView:446-451 | saved bg `appSecondarySurface`, stroke accent 0.3 | saved bg `appAccentSoft`, stroke `appAccent.opacity(0.6)` (decorative edge on its own soft-yellow fill, not text) |
| ScannerView:470 | category menu text accent | `subtleText` |
| ScannerView:587-597 | photo overlay | fill `appAccent.opacity(0.3)`, stroke `appAccent` (allowed exception); checkmark `symbolRenderingMode(.palette)` `.foregroundStyle(Color.appOnAccent, Color.appAccent)`, remove the white circle bg |
| AchievementsView:35-37, 50, 112, 124, 127 | various | see step 17 |
| AchievementBanner:22 | "+N" accent text | yellow pill, ink text |
| AchievementBadge:12 | accent glyph | tile spec |
| Services/SRSEngine.swift:17-22 | `ReviewGrade.color` (`.appAccent`, `.red`…) | **leave untouched**: grep shows no callers; Services are out of scope |

Phasing follows skill §1:
- **Gate 0:** the user approves this text plan, including its Design spec. The mockup direction is already chosen.
- **Phase 1** is the pilot: tokens plus two representative screens (Словарь, Практика).
- **Gate 1** is a simulator-screenshot approval in light, dark and an accessibility text size.
- **Phase 2** is the rollout, with no new visual decisions. Anything not covered by the Design spec goes back to the user before it is implemented.

### Phase 1 (pilot), then STOP at Gate 1

1. **`MojSlownik/Theme/Theme.swift`**: rewrite per the token table (including `appInverseEdge`, `appRingTrack`, light `appMastery` #25704C), P3, `AppRadius`/`AppSpacing` and the updated `cardStyle`. Update the header comment to "«Маркер»: warm paper, ink, highlighter-yellow fills".
1a. **`DESIGN.md`** (new, repo root; docs-only, written together with Theme.swift). Sections, in order:
    1. Purpose and how to use it: read it before any UI work; the plan files are history, DESIGN.md is current.
    2. Colour roles table, in the exact `` | `token` | role | #light | #dark | `` format parsed by ThemeTests, with alias rows using `—`. Then the verified-contrast table, the 7 colour usage rules and the forbidden pairs.
    3. Typography table.
    4. Spacing and radius scale (`AppSpacing`/`AppRadius` values).
    5. Components (primary button, chip, progress bar, card, Today hero, mode tile, achievements row, list row, ring, achievement tile, banner, rating buttons, search, FAB, pronounce, flip card).
    6. Iconography: style rules plus the purpose → symbol table. The per-file audit stays in the plan only.
    7. Motion table (including the flip and Reduce Motion fallbacks) and haptics table.
    8. Accessibility checklist (from skill §8, specialised: 44 pt, AX5, VoiceOver labels, no colour-only state, Increase Contrast).
    9. Competitors: what we borrow and what we don't copy (from skill §9 and the mockup table).
    10. Change procedure: change Theme.swift, DESIGN.md and ThemeTests in the same diff; new visual decisions go to the user via an HTML mockup and approval before code; at the end, review with the skill §10 rubric.

    Keep it free of task history and per-line audits.
1b. **`AGENTS.md`**: add one line in "Architecture and reading map": "Before any UI/visual work read [DESIGN.md](DESIGN.md)." Change nothing else. CLAUDE.md is unchanged, because it imports AGENTS.md.
1c. **`.claude/skills/mobile-ios-design/SKILL.md`**:
    - Keep the frontmatter, §1 (process) and §10 (review rubric) verbatim, apart from pointing §1.3 "Spec in the plan" to "update DESIGN.md".
    - Replace the project-specific values in §2–7 (yellow/ochre examples, radius numbers, component specifics) with a short pointer: "Values, tokens, components, icons, motion and haptics: see DESIGN.md."
    - Keep 1–3 generic principle bullets per section: role split, contrast thresholds, Dynamic Type, 44 pt, Reduce Motion, `.sensoryFeedback`.
    - Keep §8 and §9 brief, or point them to DESIGN.md.
2. **`MojSlownik/Views/Components/PrimaryButtonStyle.swift`** (new: `.accent`/`.inverse`), **`ChipStyle.swift`** (new) and **`MarkerProgressBar.swift`** (new), per the Components spec.
3. **`MojSlownik/Views/RootTabView.swift`**: delete the `NavigationStack { AchievementsView() }` tab. The tab icons become `character.book.closed` / `rectangle.stack`, and the TabView tint becomes `appAccentStrong`. Keep the tracker, banner and translation host. The Preview is unchanged.
4. **`MojSlownik/Views/TrainingView.swift`**:
   - Rebuild it as described in AC-4. `todayPanel` merges with `practiceButton`, which moves into the hero. Hero status line and caption: `appOnAccent.opacity(0.75)`.
   - `modes` becomes `modeGrid` with the "Режимы" header. Icons: `rectangle.on.rectangle`, `checklist`, `ear`. Disabled tiles dim only the icon tile and title, via the private `TileButtonStyle`.
   - The achievements `NavigationLink` moves out of `modes` into a private `achievementsRow`: a `cardStyle()` HStack with a 40 pt `appAccentSoft` tile and an ink `trophy`, the title "Достижения", the subtitle "\(achievements.totalPoints) очков · Серия: \(achievements.currentStreak(now: now)) дн.", trailing `subtleText` "\(unlockedCount) из \(catalog.count)", and `chevron.right`. Its accessibility is combined. In AX sizes it becomes a VStack.
   - `.tint(.appAccentText)` on the NavigationStack.
   - Keep the `TimelineView` and the `refreshClock` logic as they are.
5. **`MojSlownik/Views/WordListView.swift`**:
   - Category chips use `chipStyle` plus a selection haptic.
   - Remove the two toolbar buttons (scan/add). Attach the FAB overlay to the outer `VStack` (line 31), so it shows with 0 words. Use a capped scaled size and a derived list bottom margin (Components table).
   - Add the single word-saved haptic: `.sensoryFeedback(trigger: words.count) { old, new in new > old ? .impact(weight: .light) : nil }`.
   - `.tint(.appAccentText)` on the NavigationStack content.
   - `WordRow`: replace the current HStack/VStack with the two-line layout from the Components table:
     - line 1: word (min ~160 pt), ring, PronounceButton
     - line 2: translation, then the category capsule (`tag`) and the folder menu (`folder.badge.plus`/`folder`), with a `ViewThatFits` fallback

     Remove the "badge above word" HStack and the fixed `width: 180`. Category and folder menus keep their existing menu contents, actions and accessibility labels and hints.
   - At AX sizes: word, translation, then [ring, pronounce, category, folder] wrapping onto rows as needed (VStack of HStacks).
   - Keep `.tint(.red)` on swipe delete.
6. **`MojSlownik/Views/Components/KnowledgeTierBadge.swift`**: ring per the spec, with the `appRingTrack` track. Add `var fillFraction: Double { Double(filledMarks) / 4 }` to `Presentation`. `IndicatorColor` maps `.warning → .appCaution` and `.accent → .appAccentText`. Case names stay, so the existing tests still compile.
7. **`MojSlownik/Views/Components/FolderPicker.swift`**: the compact variant uses `chipStyle(isSelected: selectedFolderID != nil)`. REMOVE the explicit `foregroundStyle` on its folder icon (37), title (46) and chevron (55) in the compact branch, so the chip supplies `appOnAccent`/`appInk`. The non-compact form row uses icon `appInk` and chevron `subtleText`. The sheet gets `.tint(.appAccentText)` and the checkmark gets `appAccentStrong`. Add `.fontWeight(.medium)` to icons. Sheet detents are Phase 2.
8. **`MojSlownik/Views/Components/PronounceButton.swift`**: circle per the spec, `speaker.wave.2`.
9. **Contrast-safety sweep (mechanical, all remaining files):** apply only the audit-table colour/tint substitutions in AddWordView, ScannerView, FlashcardsView, QuizView, ListeningPracticeView, AchievementsView, AchievementBanner, AchievementBadge and SessionProgress, so nothing shows yellow text or ink-on-yellow between the gates. No layout or icon changes yet. AchievementBadge (tile, `lock`, `symbolVariant`) and AchievementBanner (always ink, `appInverseEdge`) get their full spec here because they are small and visible in the pilot. Add the AchievementTracker banner haptic here as well.
10. **`MojSlownikTests/KnowledgeTierBadgeTests.swift`** and **`MojSlownikTests/ThemeTests.swift`** (new): see Verification. The ThemeTests expected values come from the DESIGN.md table.
11. Run `xcodegen generate`, build, run the unit tests, run the AC-2 grep review, then capture the Gate 1 screenshots.

**Gate 1:** present the screenshots and wait for explicit user approval before Phase 2. Apply any token or spacing feedback in Theme.swift, DESIGN.md and ThemeTests together.

### Phase 2 (rollout), after approval

12. **`AddWordView.swift`**:
    - Remove the toolbar "Сохранить" and add `.safeAreaInset(edge: .bottom) { Button("Сохранить") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(<same condition>).padding(.horizontal, 20).padding(.vertical, 12).background(Color.appBackground) }`.
    - Screen tint `appAccentText`.
    - Field labels ("Слово"/translation header) in `.footnote.bold` `subtleText`.
    - Source text field in `.title2.weight(.bold)`.
    - Input and translation cards share one `cardStyle()`.
    - Language pill per the audit.
    - Category picker in `cardStyle(cornerRadius: AppRadius.control)`.
    - Alternatives selection haptic (view-local `selectionTick`).
    - Mic button: `mic` / `waveform` with `.symbolEffect(.variableColor.iterative, isActive: speech.state == .listening && !reduceMotion)` (add `@Environment(\.accessibilityReduceMotion)`). Keep the 44 pt frame, the a11y labels and the disabled rule.
13. **`ScannerView.swift`** (ScannerScreen + ScanResultView):
    - Audit substitutions.
    - Screen tint `appAccentText`.
    - Primary "Перевести выбранное" uses `PrimaryButtonStyle()`.
    - Camera control bar keeps its materials (over the camera).
    - Word chips: `cardBackground`, or `appAccentSoft` when saved, radius `AppRadius.button`.
    - Category capsule: `tag` + name + `chevron.down`.
    - No haptic here: the save haptic comes from WordListView.
    - `unavailableView`: `camera` icon in `appAccentText`, `@ScaledMetric` size.
    - The `scanWordChip-…` / `scanInlineWord-…` / `scanTranslationText` / `scanOriginalText` identifiers are kept.
14. **`FlashcardsView.swift`** (user decision 7):
    - Card: one `Button` (identifier `flashcard`, unchanged action `isFlipped.toggle()` inside the Motion-table animation). Its label is a `ZStack` of two faces, `frame(maxWidth: .infinity, minHeight: 300)`, background `cardBackground`, `AppRadius.flashcard`, 1 pt `appCardEdge` stroke, no shadow. Each face has padding 24.
    - Front face: language label (`frontLanguage.displayName`, `.caption.bold` uppercase `subtleText`, top-leading), ring (top-leading under the label, or in the label row; non-interactive), and the prompt word (`@ScaledMetric` 38 heavy, centered, wraps).
    - Back face (counter-rotated per the Motion table): language label (`frontLanguage.other.displayName`), ring, the word small (`.headline` `subtleText`), a hairline divider (`appBorder`, 1 pt, 80 % width), and the translation large (`@ScaledMetric` 38 heavy).
    - The Motion-table flip uses the `FaceVisibility` animatable modifier. Under Reduce Motion it is a crossfade only. No haptic on flip.
    - Accessibility:
      - button label = visible large text, or "word — translation" on the back
      - `.accessibilityHint(isFlipped ? "Скрыть перевод" : "Показать перевод")`
      - `.accessibilityAddTraits(.isButton)`
      - hidden face `.accessibilityHidden(true)`
      - the `flashcard` identifier is unchanged
    - PronounceButton: a sibling `.overlay(alignment: .topTrailing) { if shownLanguage == .polish { PronounceButton(text: shownText, language: .polish).padding(12) } }` applied to the card Button, NOT inside its label. The existing `shownLanguage`/`shownText` semantics are kept.
    - REMOVE the separate reveal label/button ("Показать перевод/Скрыть перевод"). The existing hint text "Вспомните перевод, затем откройте ответ." stays under the card while it is unrevealed.
    - Rating buttons appear after reveal, per the spec. The "Хорошо" title is kept.
    - The next-card transition is `.id(currentIndex)`. Completed view: `flag.checkered` tile and `@ScaledMetric` icon. "К практике" uses `PrimaryButtonStyle()`.
15. **`QuizView.swift`**: prompt card `cardStyle(cornerRadius: AppRadius.hero)` with the ring top-trailing, the prompt in `.largeTitle.bold` and PronounceButton. Options are `cardBackground` + `appBorder` 1 pt, `AppRadius.control`, minHeight 56. The answer feedback uses the Motion-table transition. Answer surfaces use mastery/error, plus haptics. The result view uses an `appAccentSoft` icon tile (`trophy`/`flag.checkered`, `@ScaledMetric`) and the primary button. Screen tint `appAccentText`.
16. **`ListeningPracticeView.swift`**:
    - Prompt card: same treatment as Quiz.
    - Replay button: a `@ScaledMetric` 64 pt `appAccentSoft` circle with an ink `speaker.wave.2`, plus the "Повторить" caption. Keep its accessibility label.
    - Text field: `cardBackground` with a 1 pt `appBorder` stroke at `AppRadius.control`, and an `appAccentStrong` 2 pt stroke while focused.
    - Primary buttons, feedback surfaces (`appMasterySurface`/`appErrorSurface`), haptics and the result view (`trophy`/`flag.checkered`, `@ScaledMetric`) follow the spec.
    - Screen tint `appAccentText`.
    - Keep the `listeningAnswer` identifier.
17. **`AchievementsView.swift`**:
    - Update the doc comment: "Pushed from Практика; owns no NavigationStack."
    - Remove the old `trophy.fill` header icon.
    - Hero: `appInverseSurface`, `AppRadius.hero`, padding 16, and a 1 pt `appInverseEdge` stroke (visible in dark mode). It contains:
      - the points `Text("\(totalPoints) очков")` in `.largeTitle.heavy` `appAccent` with `.contentTransition(.numericText())`
      - the merged subtitle in `appOnInverse.opacity(0.75)`
      - `MarkerProgressBar(track: appOnInverse.opacity(0.12), fill: appAccent)`
      - `Label("Серия: N дн.", systemImage: "flame")` with a yellow icon and `appOnInverse` text
    - Sections: an uppercase header plus done/total, rows inside `cardStyle()`. Row: badge 40, `.headline` title, `subtleText` detail. The unlocked date is `.caption` `subtleText`. In-progress rows show `MarkerProgressBar(height: 4)` and "N из M". Trailing points are `appInk` bold when unlocked and `subtleText` otherwise.
    - The accessibility combine is kept.
18. **`AchievementBanner.swift`**, **`AchievementBadge.swift`**: finalize per the spec if Phase 1 left anything. **`AchievementBannerModifier.swift`**: no change. **`AchievementTracker.swift`**: banner haptic (done in Phase 1).
19. **`FolderPicker.swift`**: sheet `.presentationDetents([.medium, .large])` + `.presentationDragIndicator(.visible)`. The non-compact form row is `cardStyle(cornerRadius: AppRadius.control)`.
20. **`CategoryMenu.swift`**: no structural change (the label comes from callers). Callers are styled as described above.
21. **`SessionProgress.swift`**: replace `ProgressView` with `MarkerProgressBar()`. Keep the texts and the accessibility element.
22. **`ErrorAlert.swift`**: no change. The system alert's OK button follows the presenting tint (`appAccentText`) or the system default. Either is acceptable.
23. **`docs/architecture.md`** (docs-only):
    - Navigation row: "Dictionary and Training tabs; Achievements is pushed from Training".
    - Reusable Views: add PrimaryButtonStyle, chipStyle and MarkerProgressBar. Mention the KnowledgeTierBadge ring and the AchievementBanner by name only.
    - Replace "Presentation" with a 3–5 line summary plus a link: «Маркер» paper/ink/yellow-fill language; practice is hero-led with one primary action; flashcards flip; see [DESIGN.md](../DESIGN.md) for tokens, components, icons, motion and haptics. No hex values, token tables or rules are duplicated.
    - Remove the Lilac Studio text and the "explicit reveal button" sentence.
24. **`DESIGN.md`** (end of Phase 2): reconcile it with any Gate 1 / Phase 2 changes. The token table must still match Theme.swift and ThemeTests (re-run `MojSlownikUnitTests` if the table changed). Then run the final skill §10 rubric review against the diff.

## Reuse

- `cardStyle`, the existing semantic tokens, `FolderPicker`, `CategoryMenu`, `PronounceButton`, `SessionProgress` and `errorAlert`.
- Existing store APIs: `DailyStudyStore.progress/answerTotals`, `AchievementStore.totalPoints/unlockedCount/catalog/currentStreak()/ledger.longestStreakDays/progress(for:vocabulary:)`, and `KnowledgeProgressService.tier(for:)`.
- iOS 17 `sensoryFeedback`, `contentMargins`, `ScaledMetric` and `presentationDetents`. There is no UIKit appearance proxy and no third-party code.

## Data compatibility

No changes to `Word`, `WordFolder`, SwiftData schema, `AchievementStore` storage (`achievements.v1`), `DailyStudyStore` or the translation stack. Existing records render with new styling only. Removing the Achievements tab does not touch the stored unlocks. They remain reachable from Практика.

## Verification

Unit tests (`MojSlownikUnitTests` scheme):
- `KnowledgeTierBadgeTests`: add `testRingFillFractionGrowsWithTier`, asserting that `(0...3).map { presentation(for:$0).fillFraction } == [0.25, 0.5, 0.75, 1.0]` and that the out-of-range clamps match.
- `ThemeTests` (new):
  - `UIColor(hex:)` resolves 0xFFD43B to the right RGBA.
  - A private WCAG contrast helper (plus an alpha-composite helper) is defined in the test file only. It resolves `Palette` colours with `resolvedColor(with: UITraitCollection(userInterfaceStyle: .light/.dark))`.
  - In both appearances it asserts ≥ 4.5 for:
    - ink/background, ink/card
    - subtle/background, subtle/card, subtle/secondarySurface
    - accentText/background, accentText/card, accentText/accentSoft
    - onAccent/accent, `onAccent@0.75` composited over accent (≈ 6.24)
    - onInverse/inverse, accent/inverse
    - error/errorSurface, warning/warningSurface
    - mastery/background, mastery/masterySurface, mastery/secondarySurface
  - It asserts ≥ 3.0 (non-text) for caution/card, caution/background, error/card, accentText/card and mastery/card.
  - It asserts ≥ 1.5 for ringTrack/card and ringTrack/background (both appearances), and for inverseEdge/background (dark).
  - It asserts that ochre on `appSecondarySurface` (light) is ≥ 3 and < 4.5. This pins colour rule 3: icons and large text only.
  - It asserts that `appInk` (dark) on `appAccent` is < 3. This documents why `appOnAccent` is mandatory on yellow.
  - It also asserts that `appAccent` against background is < 3 in light mode. This documents why yellow is fill-only.
  - It pins the coordinator-verified ratios within ±0.05: 12.1 (ink/yellow), 1.34 (yellow/paper), 4.77 / 5.07 / 4.54 (ochre on paper / white / soft), 5.32 (subtle/paper), 13.0 / 11.7 (dark yellow on bg / card), 6.56 (dark subtle/card), 6.54 (error/white), 5.65 / 5.15 / 5.08 (mastery #25704C on paper / masterySurface / secondarySurface) and 3.26 (amber/paper, asserted ≥ 3 and < 4.5, so amber stays graphics-only).
  - `testDesignDocTokenTableMatchesPalette`:
    - Locates the repo-root `DESIGN.md` via `URL(fileURLWithPath: #filePath)` (take the file URL, delete the last two path components — `ThemeTests.swift` and `MojSlownikTests` — then append `DESIGN.md`); the simulator can read the host filesystem.
    - Parses each token-table row of the form `` | `appX` | role | #RRGGBB | #RRGGBB | ``. Alias rows use `—` and are skipped.
    - Asserts that each hex equals the resolved light/dark `Palette` value. The test keeps its own `[String: UIColor]` map, so no app API is added.
    - Fails (does not skip) if the file is missing, so DESIGN.md, Theme.swift and the tests cannot drift.

No snapshot or UI tests.

Commands (choose the device with `xcrun simctl list devices available`; iPhone 17 is installed, iPhone 16 is not; set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if CommandLineTools is active):
```sh
xcodegen generate
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination 'platform=iOS Simulator,name=iPhone 17' build | grep -E 'error:|warning:|SUCCEEDED|FAILED'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests -destination 'platform=iOS Simulator,name=iPhone 17' test | grep -E 'error:|warning:|Executed|SUCCEEDED|FAILED'
grep -rnE "appAccent([^A-Za-z]|$)" MojSlownik          # AC-2: review every hit against colour rule 1
grep -rnE "systemName:|systemImage:" MojSlownik/Views | grep "\.fill"   # AC-18: only the listed state uses remain
```

Gate 1 screenshots (skill §1.4; simulator; no app code changes for seeding; save outside the repo in the session scratchpad, `$SHOTS`):
```sh
SHOTS=<session scratchpad>/yellow-marker-gate1; mkdir -p "$SHOTS"
UDID=<iPhone 17 udid from: xcrun simctl list devices available>
xcrun simctl boot "$UDID"; open -a Simulator
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik -destination "id=$UDID" -derivedDataPath build/dd build | grep -E 'error:|SUCCEEDED|FAILED'
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/MojSlownik.app
xcrun simctl status_bar "$UDID" override --time 9:41 --batteryLevel 100 --cellularBars 4
xcrun simctl launch "$UDID" com.kirill.personal.mojslownik
# Seed by hand once: add ~6 words (mix Russian/Polish), assign 2 categories and 1 folder,
# then run one Flashcards session rating Не помню / Трудно / Хорошо / Легко so all ring tiers appear.
for mode in light dark; do
  xcrun simctl ui "$UDID" appearance $mode
  for size in large accessibility-extra-large; do   # optionally also extra-extra-extra-large
    xcrun simctl ui "$UDID" content_size $size
    # navigate to Словарь, then Практика (and push Достижения once) and capture each:
    xcrun simctl io "$UDID" screenshot "$SHOTS/p1-<screen>-$mode-$size.png"
  done
done
xcrun simctl ui "$UDID" content_size large; xcrun simctl ui "$UDID" appearance light
```
Screens for Gate 1:
- Словарь in light, dark and AX-XL.
- Практика in light, dark and AX-XL.
- Практика with an empty dictionary (CTA disabled), light only.
- The achievements banner, if one can be triggered naturally (e.g. "first word"), light and dark. It is ink in both, with a visible edge in dark.
- Gate 1 checklist (dark mode especially):
  - Ring track visible on cards and rows.
  - `appInverseEdge` visible around the banner.
  - The selected folder chip shows ink text and icon on yellow.
  - Hero status line and caption are readable on yellow.
  - The disabled Викторина tile (fewer than 4 words) keeps its subtitle readable.
  - With 0 words, the FAB is visible over «Словарь пуст».
  - Text buttons ("Показать все слова", "Удалить папку") are ochre in light and yellow in dark.
  - The tab selection is ink in light and yellow in dark. If the tab bar picks up the screens' `appAccentText` tint instead of the TabView's `appAccentStrong`, note it for the user; both pass contrast.
  - New outline icons on the tabs, rows, FAB and mode tiles.

Show the PNGs inline to the user. They are not committed. Phase 2 sign-off repeats this for AddWord (with alternatives), ScanResult (via the `UITEST_PREFILL` environment launch: `SIMCTL_CHILD_UITEST_PREFILL="Dzień dobry" xcrun simctl launch …`), Flashcards (front, revealed after the flip, mid-flip not required, completed; plus Reduce Motion on), Quiz (answered), На слух (answered) and Достижения.

Manual checks (AGENTS.md):
- Add Russian and Polish words, and edit/save translations through the bottom Save.
- Complete flashcards: tap the card to flip it and flip it back, tap pronounce without flipping, and rate (ratings update dueDate and the ring changes tier). Then complete a quiz.
- Dictation: the mic icon becomes an animated `waveform` while recording, and stays static with Reduce Motion on.
- Run listening practice.
- Push and pop Достижения from Практика.
- Achievement banner appearance, haptic (device), and tap/swipe dismissal.
- VoiceOver on the ring, the hero, the FAB, the achievements row and the flashcard (hint "Показать перевод"/"Скрыть перевод"; the hidden face is not read).
- Reduce Motion on: no slide, scale or rotation animations; the flashcard crossfades.
- Increase Contrast on: pairs stay readable (skill §8).
- AX5 (`accessibility-extra-extra-extra-large`) spot check on Словарь, Практика and Flashcards: no clipping.
- Save haptic: fires once per saved word and not at app launch.
- On a physical iPhone: haptics; scan a line, check its translation, select a word in the text and in the chips, and confirm the scan result remains after dismissing AddWordView.

Report honestly any checks that can't be done (haptics and OCR need a device).

## Risks

- **Low-contrast yellow slips through:** the AC-2 grep and ThemeTests guard it. Reviewers should also look for `.accentColor` and `Color.accentColor` (none at base).
- **iOS 26 Liquid Glass + FAB:** the floating glass tab bar and a bottom-placed search field (if the system moves `.searchable` to the bottom on iPhone) may overlap the FAB. Check this in the Gate 1 screenshots. Fallback: move the FAB into `safeAreaInset(edge: .bottom, alignment: .trailing)` of the List instead of an overlay.
- **Bottom Save + keyboard in a sheet** reduces visible space at large Dynamic Type. The `ScrollView` above it scrolls. Verify in the AX-XL screenshot.
- **Yellow Today hero in dark mode** is very bright on #141310. The user confirmed it stays (decision 8).
- **Flip implementation:** a 3D rotation plus the face-visibility switch can show both faces or a mirrored frame if the opacity is not tied to the animated angle. That is why the animatable `FaceVisibility` modifier is specified. Also verify that the overlay PronounceButton's hit area does not trigger the card's flip. It is a sibling, so it shouldn't.
- **Tab tint inheritance:** setting `.tint(.appAccentText)` inside tab content may or may not override the tab-bar selection colour on iOS 17 vs iOS 26. Both options pass contrast. Check it in the Gate 1 screenshots.
- **Estimated tokens** (`appRingTrack`, `appInverseEdge`, `appMasterySurface`) were checked by the plan reviewer/coordinator (ratios in the token table; mastery text on `appMasterySurface` 5.15 light / 7.91 dark). ThemeTests asserts their thresholds. If a test fails, adjust the hex in Theme and DESIGN.md together.
- **DESIGN.md parsing test** depends on the simulator reading the host repo path via `#filePath`. This works for local simulator runs, but would fail on a device or in a sandboxed CI. There is no CI today.
- **Achievements discoverability** drops without a tab. The row sits below the modes and may be below the fold at AX sizes.
- **Removing the toolbar Add/Scan buttons** changes muscle memory. The labels are kept for VoiceOver and the existing UI tests don't use them.
- **Transition on `.id(currentIndex)`** could replay when the same word is re-appended for "Не помню". The index changes, so this is fine, but verify that there is no flicker on a single-word session.
- **Banner haptic from AchievementTracker** fires only while the root is mounted. It always is, including under sheets.
- **Save haptic via `words.count`** could fire if `@Query` populates after the first render (0 → N at launch), and an in-place re-save cannot trigger it. Verify on the simulator at launch. If it fires at launch, gate it with a view-local `@State didLoad` set in `.onAppear` and ignore changes before that.
- **Hero CTA thumb reach:** the primary CTA sits in the upper-middle of Практика, while skill §4 prefers the bottom half. The user confirmed it stays inside the hero (decision 8).

## Open decisions

None (Decisions 12–13 added 2026-11-16 after screen mockup review). Resolved: dark-mode hero (stays yellow), CTA position (in hero), word-list highlighter (none), rating interval hints (out), banner style (always ink), flashcard reveal (card flip), iconography (outline mapping), achievement catalog symbols (normalised, Decision 11).

## Approval

2026-11-16 — approved by user ("делай сразу все разом"). Modification: Gate 1 is skipped; Phase 1 and Phase 2 are implemented in one pass. Simulator screenshots (light, dark, accessibility text size) are captured at the end for the user's review instead of as an intermediate gate.

2026-11-16 — user reviewed all screen mockups (final.html, remaining.html, icons.html, options.html) and chose variant A (error hint) and the long-press chip menu; all screens are migrated in one pass.
