-- review_logs: an append-only log of every practice answer (word, time, grade, mode, elapsed days,
-- interval and FSRS memory before/after). Input for a future on-device FSRS optimizer.
--
-- Security model:
-- * Signed-in users (`authenticated`) may SELECT their own rows and INSERT rows for themselves
--   only (RLS scoped by (select auth.uid()) = user_id, WITH CHECK on INSERT).
-- * No UPDATE/DELETE grants or policies: the log is immutable through the API. Rows disappear
--   only with the account (on delete cascade from auth.users).
-- * `anon` has no privileges. user_id defaults to auth.uid(). updated_at is server-assigned
--   (trigger, like words) and cannot be sent: INSERT is granted per column without it.
-- * No foreign keys to words/workspaces: entries outlive soft-deleted words and may arrive before
--   the word row. No SECURITY DEFINER functions.
--
-- Growth: about 250 bytes per row, roughly 9 MB per year at heavy use (a few thousand answers a day).

begin;

create table public.review_logs (
    id uuid not null,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    workspace_id uuid not null,
    word_id uuid not null,
    reviewed_at timestamptz not null
        constraint review_logs_reviewed_at_plausible check (reviewed_at >= '2020-01-01T00:00:00Z'),
    rating text not null
        constraint review_logs_rating_known check (rating in ('again', 'hard', 'good', 'easy')),
    mode text not null
        constraint review_logs_mode_known check (mode in ('flashcards', 'quiz', 'listening')),
    affects_schedule boolean not null,
    elapsed_days double precision not null
        constraint review_logs_elapsed_days_range check (elapsed_days >= 0 and elapsed_days <= 36500),
    interval_days_before double precision not null
        constraint review_logs_interval_before_range check (interval_days_before >= 0 and interval_days_before <= 36500),
    interval_days_after double precision not null
        constraint review_logs_interval_after_range check (interval_days_after >= 0 and interval_days_after <= 36500),
    due_before timestamptz not null
        constraint review_logs_due_before_plausible check (due_before >= '2020-01-01T00:00:00Z'),
    due_after timestamptz not null
        constraint review_logs_due_after_plausible check (due_after >= '2020-01-01T00:00:00Z'),
    state_before smallint not null
        constraint review_logs_state_before_range check (state_before between 0 and 3),
    state_after smallint not null
        constraint review_logs_state_after_range check (state_after between 0 and 3),
    stability_before double precision not null
        constraint review_logs_stability_before_range check (stability_before >= 0 and stability_before <= 36500),
    stability_after double precision not null
        constraint review_logs_stability_after_range check (stability_after >= 0 and stability_after <= 36500),
    difficulty_before double precision not null
        constraint review_logs_difficulty_before_range check (difficulty_before >= 0 and difficulty_before <= 10),
    difficulty_after double precision not null
        constraint review_logs_difficulty_after_range check (difficulty_after >= 0 and difficulty_after <= 10),
    last_reviewed_before timestamptz,
    updated_at timestamptz not null default now(),
    primary key (user_id, id)
);

comment on table public.review_logs is 'Append-only log of practice answers; immutable through the API.';
comment on column public.review_logs.affects_schedule is
    'False for answers that left the schedule alone (word not due, typed soft miss).';

create trigger review_logs_set_server_updated_at
    before insert or update on public.review_logs
    for each row execute function private.set_server_updated_at();

-- Keyset pull (future optimizer backfill): where user_id = $1 and (updated_at, id) after the cursor.
-- The primary key (user_id, id) already covers the user_id foreign key.
create index review_logs_user_id_updated_at_id_idx on public.review_logs (user_id, updated_at, id);

alter table public.review_logs enable row level security;

revoke all on table public.review_logs from anon, authenticated;
grant select on table public.review_logs to authenticated;
grant insert (id, user_id, workspace_id, word_id, reviewed_at, rating, mode, affects_schedule,
              elapsed_days, interval_days_before, interval_days_after, due_before, due_after,
              state_before, state_after, stability_before, stability_after,
              difficulty_before, difficulty_after, last_reviewed_before)
    on table public.review_logs to authenticated;

create policy review_logs_select_own on public.review_logs
    for select to authenticated
    using ((select auth.uid()) = user_id);

create policy review_logs_insert_own on public.review_logs
    for insert to authenticated
    with check ((select auth.uid()) = user_id);

commit;
