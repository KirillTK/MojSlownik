#!/bin/bash
# Prints a build destination for the newest installed iOS (>= 17) runtime's
# last iPhone simulator, e.g. "platform=iOS Simulator,id=<UDID>". Exits 1 if none exists.
# Used by CI; reusable locally:  DEST=$(.github/scripts/pick-simulator.sh)
set -euo pipefail
UDID=$(xcrun simctl list devices available -j \
  | jq -r '[.devices | to_entries[]
            | select(.key | test("iOS-(1[7-9]|[2-9][0-9])"))
            | .key as $rt
            | .value[] | select(.name | startswith("iPhone"))
            | . + {ver: ($rt | capture("iOS-(?<v>[0-9]+(-[0-9]+)*)").v
                             | split("-") | map(tonumber))}]
           | sort_by(.ver)
           # Prefer plain numbered models ("iPhone 17", "iPhone 17 Pro"): unusual form factors
           # have failed to launch UI-test runner clones.
           | (map(select(.name | test("^iPhone [0-9]+( Pro)?$"))) | last) // last
           | .udid')
if [ -z "$UDID" ] || [ "$UDID" = "null" ]; then
  echo "No iPhone simulator available" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "Using simulator $UDID" >&2
echo "platform=iOS Simulator,id=$UDID"
