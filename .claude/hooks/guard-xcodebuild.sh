#!/bin/bash
# PreToolUse(Bash): block running UI/E2E tests. Only the MojSlownikUnitTests scheme may be tested.
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *xcodebuild*) ;; *) exit 0 ;; esac
if echo "$cmd" | grep -qE '(^|[[:space:]])(test|test-without-building)([[:space:]]|$)'; then
  if ! echo "$cmd" | grep -qE -- '-scheme[[:space:]]+MojSlownikUnitTests([[:space:]]|$)' \
     || echo "$cmd" | grep -q 'MojSlownikUITests'; then
    echo "Blocked: only 'xcodebuild -scheme MojSlownikUnitTests test' is allowed; UI/E2E tests must never run (AGENTS.md)." >&2
    exit 2
  fi
fi
exit 0
