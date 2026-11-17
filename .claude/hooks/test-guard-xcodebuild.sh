#!/bin/bash
# Tests guard-xcodebuild.sh. Cases are built from fragments so this file can be
# run (and written) without the guard itself reacting to the literal command text.
# Usage: bash .claude/hooks/test-guard-xcodebuild.sh
dir=$(cd "$(dirname "$0")" && pwd)
hook="$dir/guard-xcodebuild.sh"
x="xcode"; XB="${x}build"
T="te""st"
fail=0

check() { # expected_exit command
  local expected=$1 cmd=$2 actual
  actual=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$hook" >/dev/null 2>&1; echo $?)
  if [ "$actual" = "$expected" ]; then
    echo "ok   [$expected] $cmd"
  else
    echo "FAIL [expected $expected, got $actual] $cmd"; fail=1
  fi
}

check 2 "$XB -scheme MojSlownik $T"
check 0 "$XB -scheme MojSlownikUnitTests $T"
check 2 "$XB -scheme MojSlownikUnitTests $T -only-testing:MojSlownikUITests"
check 0 "$XB -scheme MojSlownikE2E $T -only-testing:MojSlownikUITests/QuizFlowTests"
check 0 "$XB -scheme MojSlownik build"
check 2 "$XB -scheme MojSlownik $T|tail -5"
check 2 "$XB -scheme MojSlownik $T;echo done"
check 2 "$XB -scheme MojSlownik $T&&echo ok"
check 2 "$XB -scheme MojSlownikE2E build && $XB -scheme MojSlownik $T"
check 2 "$XB -scheme MojSlownik build && $XB -scheme MojSlownikUnitTests $T"
check 2 "$XB $T"
check 0 "$XB -scheme MojSlownikE2E ${T}-without-building"
check 0 "$XB -scheme MojSlownikE2E $T -derivedDataPath /tmp/$T/dd"
check 0 "$XB -scheme MojSlownikE2E $T -resultBundlePath $T.xcresult"
check 2 "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer $XB -scheme MojSlownik $T"
check 2 "cd /tmp && $XB -scheme MojSlownik $T"
check 0 "echo 'run $XB -scheme MojSlownik $T later'"
check 0 "git commit -m 'docs: mention $XB $T'"

exit $fail
