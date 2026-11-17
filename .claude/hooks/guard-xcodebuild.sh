#!/bin/bash
# PreToolUse(Bash): guard test runs. A command that runs an xcodebuild test action
# (test / test-without-building) is allowed only when every -scheme value is
# MojSlownikUnitTests (without MojSlownikUITests references) or MojSlownikE2E.
# The MojSlownik app scheme's tests, and tests without an explicit scheme, are blocked.
# Chained commands are evaluated as a whole (conservative).
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *xcodebuild*) ;; *) exit 0 ;; esac
# xcodebuild must be invoked at a command position (after ; & | ( or line start,
# or right after a quote opening a `bash -c '…'` body), optionally behind VAR=value
# assignments, wrappers (env/time/nohup/sudo/command/exec), xcrun or a path prefix.
# Best effort: this is an accident guard, not a security boundary.
invoke='(^|[;&|(]|-c[[:space:]]+["'"'"'])[[:space:]]*(((env|time|nohup|sudo|command|exec)([[:space:]]+-[^[:space:]]+)*|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)[[:space:]]+)*(xcrun[[:space:]]+|[^[:space:]]*/)?xcodebuild[[:space:]]'
echo "$cmd" | grep -qE "$invoke" || exit 0
# test action in xcodebuild's action position, also glued to shell operators:
# "test|tail", "test;echo", "test&&..." (paths like /tmp/test/dd or test.xcresult do not match)
echo "$cmd" | grep -qE 'xcodebuild([^|;&]*[[:space:]])(test|test-without-building)([[:space:]|;&"'"'"']|$)' || exit 0
schemes=$(echo "$cmd" | grep -oE -- '-scheme[[:space:]=]+["'"'"']?[A-Za-z0-9_]+' \
          | sed -E 's/^-scheme[[:space:]=]+["'"'"']?//')
block() {
  echo "Blocked: test only with -scheme MojSlownikUnitTests or -scheme MojSlownikE2E; the MojSlownik app scheme's tests are not allowed (AGENTS.md)." >&2
  exit 2
}
[ -z "$schemes" ] && block
for s in $schemes; do
  case "$s" in
    MojSlownikE2E) ;;
    MojSlownikUnitTests) echo "$cmd" | grep -q 'MojSlownikUITests' && block ;;
    *) block ;;
  esac
done
exit 0
