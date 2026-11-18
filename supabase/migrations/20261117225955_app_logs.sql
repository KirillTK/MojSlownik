-- Write-only diagnostics log from the app: errors and product events, never user content.
-- The client API (Services/AppLog.swift) only accepts fixed event names and typed values;
-- these CHECK constraints enforce the same shape server-side.
--
-- Security model:
-- * Signed-in users (`authenticated`) may INSERT rows for themselves only.
-- * Nobody using the API can read, change or delete logs: no SELECT/UPDATE/DELETE policies
--   or grants. Logs are read in the Supabase dashboard / SQL editor.
-- * `anon` has no privileges.

create table public.app_logs (
    id bigint generated always as identity primary key,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    received_at timestamptz not null default now(),
    occurred_at timestamptz not null,
    session_id uuid not null,
    level text not null check (level in ('info', 'warning', 'error')),
    event text not null check (event ~ '^[a-z][a-z0-9_]{0,31}(\.[a-z][a-z0-9_]{0,31}){1,2}$'),
    properties jsonb not null default '{}'::jsonb
        check (jsonb_typeof(properties) = 'object' and pg_column_size(properties) <= 2048),
    app_version text not null check (app_version ~ '^[0-9A-Za-z.()_ -]{1,32}$'),
    os_version text not null check (os_version ~ '^[0-9A-Za-z.()_ -]{1,32}$')
);

create index app_logs_user_id_occurred_at_idx on public.app_logs (user_id, occurred_at);
create index app_logs_event_occurred_at_idx on public.app_logs (event, occurred_at);

alter table public.app_logs enable row level security;

revoke all on table public.app_logs from anon, authenticated;
grant insert on table public.app_logs to authenticated;

create policy app_logs_insert_own on public.app_logs
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
