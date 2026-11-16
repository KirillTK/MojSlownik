@AGENTS.md

## Claude Code

- Feature workflow: `/ios-feature-flow [--lite] <context>` (`.claude/skills/ios-feature-flow`),
  agents in `.claude/agents/feature-*.md`. The personal `/feature-flow` is a
  web/Playwright pipeline — do not use it in this repo.
- `.claude/hooks/guard-xcodebuild.sh` blocks any `xcodebuild … test` except the `MojSlownikUnitTests` scheme.
