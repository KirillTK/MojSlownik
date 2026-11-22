---
name: mobile-ios-design
description: iOS/SwiftUI visual and UX design rules for Mój Słownik — palette roles, typography, layout, components, motion, haptics, accessibility, and how to present and approve a design (HTML mockups, then simulator screenshots). Use when designing, restyling, planning or reviewing any screen or component.
---

# Mobile iOS design (Mój Słownik)

Use this skill for design exploration, design specs inside `/ios-feature-flow` plans,
and UI review. It sets the process and review bar; `DESIGN.md` and `Theme/Theme.swift` hold the values.
English + Russian UI copy (String Catalogs), iOS 17+, SwiftUI only, no third-party UI kits.

## 1. Process: how a design gets approved

1. **Explore visually, not in prose.** Draw 2–3 directions as an HTML mockup on the
   same real screens (Словарь, Практика, a practice card, plus any screen the task touches),
   with a light/dark toggle. Use real copy and data shapes from the source, not lorem ipsum.
   Save under `.codex/plans/<slug>/mockups.html` next to the plan and show it inline.
2. **One decision per question.** Ask the user to pick a direction; recommended first.
3. **Spec in the plan.** Turn the chosen direction into a `## Design spec` and update `DESIGN.md`
   (tokens, type scale, spacing, radii, colour rules, components) together with `Theme.swift`.
   The user approves the text plan.
4. **Pilot, then gate.** Implement tokens plus 2 representative screens. Capture simulator
   screenshots (light, dark, accessibility text size) and get the user's approval before rollout:
   ```sh
   UDID=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
   xcrun simctl ui $UDID appearance dark   # or light
   xcrun simctl ui $UDID content_size extra-extra-extra-large  # reset: large
   xcrun simctl io $UDID screenshot /path/in/scratchpad/screen-dark.png
   ```
5. **Roll out** the remaining screens with no new visual decisions; anything new goes back to the user.

## 2. Colour

Values, tokens, components, icons, motion and haptics: see `DESIGN.md`.

- Views use semantic tokens only; no hex or system colours in views. Every token has light and dark values.
- If the brand colour is light, split it into accent fill, on-accent (never white) and accent foreground; never use the fill as text, tint or thin stroke on light surfaces.
- Contrast: body text >= 4.5:1, large text and essential icons >= 3:1, both appearances. Check new pairs.
- State is never colour-only.

## 3. Typography

See `DESIGN.md`. Text styles only, `@ScaledMetric` for custom sizes, long words wrap, changing numbers use `.monospacedDigit()`.

## 4. Layout and spacing

See `DESIGN.md`. Use the spacing/radius scale, touch targets >= 44 pt, and switch rows to vertical layouts at accessibility sizes.

## 5. Native structure and system chrome

See `DESIGN.md`. Keep system bars and materials (no opaque custom bars); `glassEffect` only behind `#available(iOS 26, *)`; no destination as both tab and row.

## 6. Components

See `DESIGN.md` (Components). Put a component in `Views/Components/` only when two or more screens use it.

## 7. Motion and haptics

See `DESIGN.md`. Every animation has a Reduce Motion branch; haptics via `.sensoryFeedback`, never on scroll or every tap.

## 8. Accessibility checklist

See `DESIGN.md` (Accessibility checklist).

## 9. Competitors

See `DESIGN.md` for what to borrow and what not to copy.

## 10. Review rubric (for plans and diffs)

Report a finding when: a raw colour or font size appears in a view; the accent fill is used
as text/tint on a light surface; contrast is unchecked for a new pair; a row clips at AX sizes;
a control is < 44 pt or gesture-only; an animation lacks a Reduce Motion branch; state is
colour-only; a screen has two competing primary actions; a destination is duplicated in the tab bar;
behaviour (data, SRS, translation, achievements logic) changed in a "visual" task.
