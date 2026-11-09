---
name: feature-flow
description: Plan, implement, verify, and review features in Mój Słownik with Codex subagents. Use when requested as $feature-flow or feature-flow; accepts free-form task context only. Excludes E2E and UI automation.
---

# Feature flow for Codex

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
3. Delegate planning to `feature-planner`, then use `feature-plan-reviewer`
   against real source, at most two passes. Scale plan detail to task complexity.
4. Ask only material unresolved questions. Existing authorization is sufficient;
   do not repeat approval requests or ask about E2E/browser testing.

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

5. Inspect git status and record the starting HEAD. Preserve existing changes;
   never stash, reset, discard or switch over unfinished work. No automatic fetch,
   commit, push or PR: these require user authorization.
6. `feature-implementer` implements model/services before SwiftUI. Preserve iOS 17
   support and existing SwiftData records. Resolve contradictions with real code
   before continuing rather than blindly implementing an invalid plan.
7. Do not create, update or run E2E, Playwright or XCUITest. Preserve existing
   MojSlownikUITests and its target. Add committed XCTest unit tests for new or changed nontrivial logic and
   regression tests for bug fixes. Run them using the isolated MojSlownikUnitTests
   scheme; do not substitute temporary assertions or build-only checks.

## Verification and review

8. Run xcodegen generate after adding source files or changing project.yml.
   Choose an installed iPhone simulator with xcrun simctl list devices available;
   run xcodebuild build using the project and scheme in AGENTS.md.
   Use DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer if needed.
   Run xcodebuild test with scheme MojSlownikUnitTests only; never run the
   application scheme's tests, which include UI tests.
9. Run `feature-quality-reviewer` always; `feature-ui-reviewer` for SwiftUI;
   `feature-data-reviewer` for Word, SRS, persistence or translation data flows.
   Independent reviews may run concurrently within host limits. Include tracked
   diffs and new files, and distinguish pre-existing changes from this task.
10. Merge confirmed findings with severity, path:line, failing scenario and fix.
    Delegate fixes to the implementer; at most two rounds.
    Rerun affected checks; report unresolved issues instead of claiming success.
11. Provide a manual checklist for affected UI: ru/pl input, editable translation,
    save, flashcards and quiz. OCR needs a physical iPhone: line translation,
    word/chip selection and preserved scan result after dismissing AddWordView.
    Never claim manual checks were performed unless actually performed.

## Report

State what changed, verification commands and results, and remaining limitations.
No fabricated model attribution or automatic publication. Keep architecture updates
in docs/architecture.md and task history in plans, not in always-loaded instructions.
