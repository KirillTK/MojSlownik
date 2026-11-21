#!/usr/bin/env bash
# Applies supabase/migrations to an empty Postgres with the CI auth stub and runs the RLS tests.
# Usage: scripts/test-db.sh <psql connection URL to an EMPTY database>
# Files in supabase/ci/seeds with a migration's file name are applied right before that migration.
# CI passes a throwaway service container. Never point this at the Supabase project:
# the stub creates roles and an auth schema that Supabase already owns.
set -euo pipefail

url="${1:?usage: scripts/test-db.sh <postgres URL of an empty database>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
# Supabase sessions run in UTC; the app sends zone-less UTC timestamps.
export PGTZ=UTC
psql_cmd=(psql "$url" -X -q -v ON_ERROR_STOP=1)

"${psql_cmd[@]}" -f "$root/supabase/ci/auth_stub.sql"
for migration in "$root"/supabase/migrations/*.sql; do
    # CI-only legacy-shaped rows applied right before the migration they exercise (never on Supabase).
    seed="$root/supabase/ci/seeds/$(basename "$migration")"
    if [ -f "$seed" ]; then
        echo "Seeding $(basename "$seed")"
        "${psql_cmd[@]}" -f "$seed"
    fi
    echo "Applying $(basename "$migration")"
    "${psql_cmd[@]}" -f "$migration"
done
for test in "$root"/supabase/tests/*.sql; do
    echo "Running $(basename "$test")"
    "${psql_cmd[@]}" -f "$test"
done
