---
name: ios-feature-flow
description: Plan, critique, implement, verify and review a Mój Słownik feature with project subagents. Run as /ios-feature-flow [--lite] <free-form task context>, or /ios-feature-flow <path-to-plan.md> to resume an approved plan. Excludes E2E and UI automation.
argument-hint: "[--lite] <task / extra context> | <plan.md>"
disable-model-invocation: true
---

# Mój Słownik feature flow (Claude Code)

Claude port of `.agents/skills/feature-flow/SKILL.md` (Codex). Keep the two in sync
when the process changes. Named `ios-feature-flow` because the personal
`~/.claude/skills/feature-flow` (web/Playwright pipeline) would shadow a project
skill with the same name.

You are the orchestrator: delegate planning, coding and review to the
`feature-*` subagents in `.claude/agents/`, pass results between them, and own
every conversation with the user. Subagents cannot ask the user anything.

Input: $ARGUMENTS

## 0. Parse input

- `--lite` → lite mode (table below). Without it, if the task is clearly a
  one-file change with no model/SRS/translation impact, suggest `--lite` in one
  line and continue in full mode.
- An existing `.md` path → resume: re-read the plan. If it contains
  `## Approval` with a recorded approval, go to step 5; otherwise go to step 4.
- Everything else is free-form task context; no ticket numbers or other flags.
  User instructions are binding unless they conflict with AGENTS.md safety rules;
  raise such a conflict as the first question.

| | Full | Lite |
|---|---|---|
| Plan | full | Goal, AC, Changes, Verification, Risks |
| Critique + review | critic, then plan-reviewer (max 2 passes total) | plan-reviewer once |
| Code reviewers | quality + ui (SwiftUI) + data (Word/SRS/persistence/translation) | quality only |
| Fix rounds | 2 | 1 |

## 1. Plan

1. Slug: kebab-case from the task. Plan path: `.codex/plans/<slug>.md` (shared
   with Codex history). No secrets or real user data in plans.
2. Record `git rev-parse HEAD` and `git status --porcelain` as the base; pass both
   to every agent so pre-existing changes are not attributed to this task.
3. Run `feature-planner` with: task text verbatim, mode, plan path, base.

## 2. Critique and review (read-only agents)

1. Full mode: run `feature-plan-critic` on the plan. Confirmed weaknesses (each
   with scenario + correction) go back to `feature-planner` for one revision.
2. Run `feature-plan-reviewer` against the real source. `needs-changes` →
   planner revises. Critique + review together: at most 2 passes unless the user
   asks for more; leftovers become open questions.

## 3. Open questions

Ask only material, unresolved decisions with `AskUserQuestion` (recommended option
first, one decision per question). Never ask about E2E or browser testing.
Record answers in the plan under `## Decisions`.

## 4. Approval gate — STOP

Present: goal, AC-1…, files, approach, verification, risks, open decisions, and a
link to the plan file. Ask with `AskUserQuestion`: `Approve` / `Request changes` /
`Stop`. The `/ios-feature-flow` invocation itself is not approval.

- Until the user approves: no implementer, no edits to app or test files, no
  builds or tests.
- Request changes → revise (planner + one plan-reviewer pass), present again.
- Stop → end without implementation; the user can resume later with the plan path.
- Approve → append `## Approval` (date, "approved by user") to the plan.

## 5. Implement

1. Re-check `git status`. Preserve existing changes: never stash, reset, discard
   or switch branches. No fetch, commit, push or PR unless the user authorizes it.
2. Run `feature-implementer` with plan, base and the list of files it owns.
   Order: model/services → stores → SwiftUI. It adds committed XCTest unit tests
   for changed nontrivial logic and regression tests for bug fixes.
3. If the implementer reports that real code contradicts the plan, stop and
   resolve it (ask the user if it changes scope) instead of forcing the plan.

## 6. Verify

Run yourself, not via the implementer's word:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=$(xcrun simctl list devices available | grep -m1 -oE 'iPhone [0-9A-Za-z ]+ \(' | sed 's/ ($//')
# after adding files or editing project.yml:
xcodegen generate
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination "platform=iOS Simulator,name=$SIM" build 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownikUnitTests \
  -destination "platform=iOS Simulator,name=$SIM" test 2>&1 | grep -E 'error:|failed|Executed|TEST (SUCCEEDED|FAILED)'
```

Build must have zero warnings in touched files. Never run the `MojSlownik` scheme's
tests (they include UI tests); a project hook blocks it. If `xcodegen` is missing,
report it instead of editing the generated project by hand.

## 7. Review and fix

1. Launch applicable reviewers in parallel in one message: `feature-quality-reviewer`
   always; full mode adds `feature-ui-reviewer` for SwiftUI and
   `feature-data-reviewer` for Word/SRS/persistence/translation. Give each the plan,
   base and the list of task files (tracked diff + new files).
2. Spot-check high-severity findings in the code yourself; drop unconfirmed ones.
3. Confirmed findings (severity, path:line, scenario, fix) → `feature-implementer`.
   Rerun step 6. At most 2 rounds (lite: 1); report anything left unresolved.

## 8. Report

- What changed (files), verification commands and real results, unresolved issues.
- Manual checklist for affected areas: ru/pl input, editable translation, save,
  flashcards (ratings update dueDate), quiz. OCR needs a physical iPhone: line
  translation, word/chip selection, scan result kept after dismissing AddWordView.
  Never claim a manual check that was not performed.
- Update `docs/architecture.md` if architecture changed; task history stays in the plan.
