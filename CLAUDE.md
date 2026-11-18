@AGENTS.md

## Claude Code

- Skills: see the Skills table in AGENTS.md. `/ios-feature-flow` agents live in
  `.claude/agents/feature-*.md`. The personal `/feature-flow` is a web/Playwright
  pipeline — do not use it in this repo.
- `.claude/hooks/guard-xcodebuild.sh` allows `xcodebuild … test` only for the
  `MojSlownikUnitTests` and `MojSlownikE2E` schemes; testing through the `MojSlownik`
  app scheme stays blocked (`bash .claude/hooks/test-guard-xcodebuild.sh` checks the hook).
