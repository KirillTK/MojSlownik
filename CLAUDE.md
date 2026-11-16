@AGENTS.md

## Claude Code

- Feature workflow: `/ios-feature-flow [--lite] <context>` (`.claude/skills/ios-feature-flow`).
  It mirrors the Codex `$feature-flow`; agents are `.claude/agents/feature-*.md`, plans stay in `.codex/plans/`.
  The personal `/feature-flow` is a web/Playwright pipeline — do not use it in this repo.
- `.claude/hooks/guard-xcodebuild.sh` blocks any `xcodebuild … test` except the `MojSlownikUnitTests` scheme.
- Pick the simulator from `xcrun simctl list devices available`; `iPhone 16` may not be installed.
- Filter xcodebuild output (`| grep -E 'error:|warning:|SUCCEEDED|FAILED|Executed'`) instead of reading full logs.
