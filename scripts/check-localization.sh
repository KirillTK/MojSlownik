#!/usr/bin/env bash
# Compares the string keys the compiler extracted from the app target (*.stringsdata, emitted
# because SWIFT_EMIT_LOC_STRINGS=YES) with MojSlownik/Localizable.xcstrings.
#   missing: key used in code, absent from the catalog   -> failure
#   dead:    key in the catalog that code never uses     -> failure
# Keys that contain Cyrillic are not-yet-converted Russian literals: they are excluded from
# "missing" and only counted (SourceHygieneTests rejects them once the conversion is done).
# Usage: scripts/check-localization.sh <DerivedDataPath>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <DerivedDataPath>" >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 -I - "$1" "$repo/MojSlownik/Localizable.xcstrings" <<'PY'
import glob
import json
import re
import sys

derived, catalog_path = sys.argv[1], sys.argv[2]

# <DerivedData>/Build/Intermediates.noindex/MojSlownik.build/<config>/MojSlownik.build/Objects-normal/<arch>/*.stringsdata
# (the inner MojSlownik.build is the app target; test targets and packages live elsewhere).
pattern = f"{derived}/Build/Intermediates.noindex/MojSlownik.build/*/MojSlownik.build/Objects-normal/*/*.stringsdata"
files = sorted(glob.glob(pattern))
if not files:
    print(f"error: no .stringsdata files match {pattern}", file=sys.stderr)
    print("       build the MojSlownik scheme first, or adapt the path (fallback: xcodebuild -exportLocalizations)",
          file=sys.stderr)
    sys.exit(1)

used = {}
for path in files:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    for entry in data.get("tables", {}).get("Localizable", []):
        used.setdefault(entry["key"], f'{data.get("source", path)}:{entry.get("location", {}).get("startingLine", "?")}')

with open(catalog_path, encoding="utf-8") as handle:
    catalog = set(json.load(handle)["strings"].keys())

cyrillic = re.compile("[Ѐ-ӿ]")
pending = sorted(key for key in used if cyrillic.search(key))
missing = sorted(key for key in used if key not in catalog and not cyrillic.search(key))
dead = sorted(key for key in catalog if key not in used)

print(f"info: {len(files)} stringsdata files, {len(used)} keys used in code, {len(catalog)} catalog keys")
print(f"info: {len(pending)} Cyrillic keys not converted yet (excluded from missing)")
if missing:
    print(f"error: {len(missing)} key(s) used in code are missing from Localizable.xcstrings:")
    for key in missing:
        print(f"  {key!r}  ({used[key]})")
if dead:
    print(f"error: {len(dead)} catalog key(s) are never used in code (dead):")
    for key in dead:
        print(f"  {key!r}")
print(f"summary: missing={len(missing)} dead={len(dead)} pending-cyrillic={len(pending)}")
sys.exit(1 if missing or dead else 0)
PY
