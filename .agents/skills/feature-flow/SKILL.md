---
name: feature-flow
description: Plan, implement, verify, and review features in Mój Słownik with Codex subagents. Use when requested as $feature-flow or feature-flow; accepts free-form task context only. Excludes E2E and UI automation.
---

# Feature flow for Codex

Claude Code port: `.claude/skills/ios-feature-flow` — keep both in sync.

Adapted from the user's Claude feature-flow and agent roles for this native iOS project.
Invocation: `$feature-flow <context>`.
Treat everything after the skill name as free-form task context. Do not parse
ticket numbers, mode flags or a special plan-path argument.

## Context and planning

1. Read AGENTS.md and relevant source. Read docs/architecture.md only as needed.
   User instructions override workflow defaults. Reuse existing services and Theme;
   prefer the smallest complete change and observable acceptance criteria.
2. Record task, constraints, AC-1… criteria, relevant files, verification, risks and
   unresolved decisions in `.codex/plans/<slug>.md`. Derive the slug from the task description; no ticket number is needed.
   Do not store secrets or real user data in plans.
3. Delegate planning to `feature-planner`. Scale plan detail to task complexity.
4. Run a separate adversarial plan-critique pass before ordinary plan review.
   Challenge weak assumptions, missing failure states, data or async hazards,
   platform constraints, verification gaps, and acceptance criteria that cannot
   be observed. Record only concrete weaknesses with a scenario and correction.
   The critique is read-only and may use `feature-plan-reviewer` when no separate
   critic role is available.
5. Revise the plan for confirmed critique findings, then use
   `feature-plan-reviewer` against real source. Keep critique and review to at
   most two total passes unless the user requests another pass.
6. Resolve only material unanswered questions before finalizing the plan.
7. Present the reviewed plan to the user before implementation. Summarize the
   goal, acceptance criteria, files, approach, verification, risks and unresolved
   decisions. Link the plan file. Ask the user to approve or request changes.
8. Stop after presenting the plan. Do not delegate implementation, edit app or
   test files, run builds/tests, or otherwise execute the plan until the user
   explicitly approves it. The `$feature-flow` invocation itself is not approval.
   If the user requests changes, revise and review the plan, show the updated
   version, and wait for approval again. If the user declines, stop without
   implementation. Do not ask about E2E/browser testing.

## Delegation

Project agent definitions are `.codex/agents/feature-*.toml`. Use native custom
agent selection if exposed by the host. If only generic subagent tools are available,
read the relevant TOML and include its developer_instructions in the delegated task.
Never pretend a custom role was selected when the host cannot select it.
Pass every agent the task, plan, relevant paths, scope, base revision and constraints.
Give writers disjoint file ownership. Reviewers only read. Inspect their evidence.
If delegation is unavailable, execute the same steps sequentially and disclose it.
Models inherit the parent; do not use Claude model names or tools.

## Implementation

9. After approval, inspect git status and record the starting HEAD. Preserve existing changes;
   never stash, reset, discard or switch over unfinished work. No automatic fetch,
   commit, push or PR: these require user authorization.
10. `feature-implementer` implements model/services before SwiftUI. Preserve iOS 17
   support and existing SwiftData records. Resolve contradictions with real code
   before continuing rather than blindly implementing an invalid plan.
11. Do not create, update or run E2E, Playwright or XCUITest. Preserve existing
   MojSlownikUITests and its target. Add committed XCTest unit tests for new or changed nontrivial logic and
   regression tests for bug fixes. Run them using the isolated MojSlownikUnitTests
   scheme; do not substitute temporary assertions or build-only checks.

## Verification and review

12. Run xcodegen generate after adding source files or changing project.yml.
   Choose an installed iPhone simulator with xcrun simctl list devices available;
   run xcodebuild build using the project and scheme in AGENTS.md.
   Use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer if needed.
   Run xcodebuild test with scheme MojSlownikUnitTests only; never run the
   application scheme's tests, which include UI tests.
13. Run `feature-quality-reviewer` always; `feature-ui-reviewer` for SwiftUI;
   `feature-data-reviewer` for Word, SRS, persistence or translation data flows.
   Independent reviews may run concurrently within host limits. Include tracked
   diffs and new files, and distinguish pre-existing changes from this task.
14. Merge confirmed findings with severity, path:line, failing scenario and fix.
    Delegate fixes to the implementer; at most two rounds.
    Rerun affected checks; report unresolved issues instead of claiming success.
15. Provide a manual checklist for affected UI: ru/pl input, editable translation,
    save, flashcards and quiz. OCR needs a physical iPhone: line translation,
    word/chip selection and preserved scan result after dismissing AddWordView.
    Never claim manual checks were performed unless actually performed.

## Report

State what changed, verification commands and results, and remaining limitations.
No fabricated model attribution or automatic publication. Keep architecture updates
in docs/architecture.md and task history in plans, not in always-loaded instructions.
