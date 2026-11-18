#!/usr/bin/env bash
# Fails if a server-side Supabase credential appears in the repository (tracked or untracked,
# not ignored). Only the publishable key (sb_publishable_…) may ship in the app.
# Usage: scripts/check-secrets.sh
set -euo pipefail

cd "$(dirname "$0")/.."

patterns=(
    'sb_secret_[A-Za-z0-9_-]{16,}'                                            # Supabase secret key
    'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'        # any full JWT (service_role, legacy anon)
    'postgres(ql)?://[^[:space:]/:@]+:[^[:space:]/@]+@'                      # connection string with a password
    '(SERVICE_ROLE|service_role)[A-Za-z_]*["'"'"']?[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9._-]{20,}'
)

args=()
for pattern in "${patterns[@]}"; do args+=(-e "$pattern"); done

if git grep --untracked -nIE "${args[@]}" -- . ':!scripts/check-secrets.sh'; then
    echo "error: possible Supabase secret above. Only sb_publishable_ keys may be committed." >&2
    exit 1
fi
echo "No Supabase secrets found."
