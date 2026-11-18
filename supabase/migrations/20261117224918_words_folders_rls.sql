-- Remote mirror of the local SwiftData models Word and WordFolder (future sync).
-- Local SwiftData stays the source of truth; nothing in the app reads or writes these yet.
--
-- Security model:
-- * RLS is enabled in the same migration that creates the tables.
-- * Every policy is scoped to the row owner: (select auth.uid()) = user_id. The role check
--   alone is not enough: anonymous sign-ins also get the `authenticated` role.
-- * INSERT and UPDATE use WITH CHECK, so a client can neither create nor move rows into
--   another user's account.
-- * `anon` (no session) has no table privileges at all.
-- * Primary keys are (user_id, id): a client-generated id never collides across users.

create table public.folders (
    id uuid not null,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name text not null check (char_length(btrim(name)) between 1 and 200),
    sort_order integer not null default 0,
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    primary key (user_id, id)
);

create table public.words (
    id uuid not null,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    russian text not null check (char_length(btrim(russian)) between 1 and 500),
    polish text not null check (char_length(btrim(polish)) between 1 and 500),
    source_language_code text not null check (source_language_code in ('ru', 'pl')),
    category text not null default 'Другое' check (char_length(category) <= 100),
    folder_ids uuid[] not null default '{}' check (cardinality(folder_ids) <= 500),
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    ease_factor double precision not null default 2.5 check (ease_factor >= 1.3),
    interval_days double precision not null default 0 check (interval_days >= 0),
    repetitions integer not null default 0 check (repetitions >= 0),
    due_date timestamptz not null,
    last_review_grade text check (last_review_grade in ('again', 'hard', 'good', 'easy')),
    knowledge_tier integer check (knowledge_tier between 0 and 3),
    consecutive_soft_misses integer not null default 0 check (consecutive_soft_misses >= 0),
    primary key (user_id, id)
);

-- Delta sync pulls "changed since cursor" per user.
create index folders_user_id_updated_at_idx on public.folders (user_id, updated_at);
create index words_user_id_updated_at_idx on public.words (user_id, updated_at);

alter table public.folders enable row level security;
alter table public.words enable row level security;

revoke all on table public.folders, public.words from anon;
grant select, insert, update, delete on table public.folders, public.words to authenticated;

create policy folders_select_own on public.folders
    for select to authenticated
    using ((select auth.uid()) = user_id);
create policy folders_insert_own on public.folders
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy folders_update_own on public.folders
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy folders_delete_own on public.folders
    for delete to authenticated
    using ((select auth.uid()) = user_id);

create policy words_select_own on public.words
    for select to authenticated
    using ((select auth.uid()) = user_id);
create policy words_insert_own on public.words
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy words_update_own on public.words
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy words_delete_own on public.words
    for delete to authenticated
    using ((select auth.uid()) = user_id);
