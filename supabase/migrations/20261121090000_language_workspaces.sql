-- Language workspaces: normalizes the sync schema.
--
-- * public.workspaces (new): one row per (user, term_language, translation_language) pair. The
--   languages live only here; words and folders point at a workspace (3NF).
-- * public.words: term_language, translation_language, entered_language and folder_ids are replaced
--   by workspace_id and entered_side ('term' | 'translation').
-- * public.folders: gets workspace_id.
-- * public.word_folders (new): word <-> folder memberships, replacing the words.folder_ids array
--   (1NF, referential integrity). A removed membership is a tombstone (deleted_at).
--
-- Single migration (no expand/contract window): existing rows are backfilled, the new columns are
-- NOT NULL without defaults, and the legacy columns are dropped. Pre-migration app builds cannot
-- sync afterwards (accepted: every device is updated). The data of the dropped columns survives in
-- private.words_backup_20261121 and private.folders_backup_20261121 (full copies, taken first) until a
-- later migration drops them after the data was confirmed.
--
-- Security model (unchanged: RLS scoped by (select auth.uid()) = user_id, WITH CHECK on
-- INSERT/UPDATE, no anon grants, no hard deletes):
-- * The new tables enable RLS in the migration that creates them; every policy compares
--   (select auth.uid()) with user_id.
-- * Composite foreign keys (user_id, workspace_id[, word_id | folder_id]) keep every row, and every
--   membership, inside one owner and one workspace.
-- * The backup tables are in schema `private` (no API usage), have every privilege revoked from API
--   roles and RLS enabled without policies.
-- * No SECURITY DEFINER functions.

begin;

-- 1. Backup of the shape that is about to change.
create table private.words_backup_20261121 as table public.words;
create table private.folders_backup_20261121 as table public.folders;
revoke all on table private.words_backup_20261121, private.folders_backup_20261121
    from public, anon, authenticated;
alter table private.words_backup_20261121 enable row level security;
alter table private.folders_backup_20261121 enable row level security;
comment on table private.words_backup_20261121 is
    'Backup before 20261121 language workspaces migration; dropped by a later migration after the user confirms the data.';
comment on table private.folders_backup_20261121 is
    'Backup before 20261121 language workspaces migration; dropped by a later migration after the user confirms the data.';

-- 2. uuid v5 for deterministic workspace ids (pre-installed on Supabase).
create extension if not exists "uuid-ossp" with schema extensions;

-- 3. Workspaces. id = uuid v5 (namespace a4f06f42-4f0b-43f6-bfb4-33545dcf1307) of 'term>translation',
-- so two devices creating the same pair offline produce the same row.
create table public.workspaces (
    id uuid not null,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    term_language text not null check (term_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    translation_language text not null check (translation_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    sort_order integer not null default 0,
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    primary key (user_id, id),
    constraint workspaces_pair_key unique (user_id, term_language, translation_language),
    constraint workspaces_distinct_languages check (term_language <> translation_language),
    constraint workspaces_id_is_pair_uuid check (
        id = extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307'::uuid,
                                         term_language || '>' || translation_language))
);

-- 4. Backfill workspaces: every pair that has words, plus pl>ru for users who have folders
-- (folders had no language; the app treated them as pl>ru).
insert into public.workspaces (id, user_id, term_language, translation_language, sort_order,
                               created_at, updated_at)
select extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307'::uuid,
                                   p.term_language || '>' || p.translation_language),
       p.user_id, p.term_language, p.translation_language,
       (row_number() over (partition by p.user_id
                           order by p.created_at, p.term_language, p.translation_language) - 1)::integer,
       p.created_at,
       date_trunc('milliseconds', pg_catalog.clock_timestamp())
from (
    select user_id, term_language, translation_language, min(created_at) as created_at
    from (
        select user_id, term_language, translation_language, created_at from public.words
        union all
        select user_id, 'pl', 'ru', created_at from public.folders
    ) as pairs
    group by user_id, term_language, translation_language
) as p
on conflict do nothing;

-- 5. New columns (nullable until backfilled).
alter table public.folders add column workspace_id uuid;
alter table public.words
    add column workspace_id uuid,
    add column entered_side text check (entered_side in ('term', 'translation'));

-- 6. Backfill words and folders without bumping updated_at (R5): the devices' stored server stamps
-- stay equal to the server's, so the post-migration re-pull sees echoes, not server updates.
alter table public.words disable trigger words_set_server_updated_at;
alter table public.folders disable trigger folders_set_server_updated_at;

update public.words
set workspace_id = extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307'::uuid,
                                               term_language || '>' || translation_language),
    entered_side = case when entered_language = term_language then 'term' else 'translation' end;
update public.folders
set workspace_id = extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307'::uuid, 'pl>ru');

alter table public.words enable trigger words_set_server_updated_at;
alter table public.folders enable trigger folders_set_server_updated_at;

-- 7. No defaults: a client must always say which workspace and side. A null here aborts the migration.
alter table public.folders alter column workspace_id set not null;
alter table public.words alter column workspace_id set not null;
alter table public.words alter column entered_side set not null;

-- 8. Constraints. The unique constraints are the targets of the membership foreign keys; their
-- (user_id, workspace_id) prefix also serves the workspace foreign keys.
alter table public.folders
    add constraint folders_workspace_fk foreign key (user_id, workspace_id)
        references public.workspaces (user_id, id),
    add constraint folders_user_workspace_id_key unique (user_id, workspace_id, id);
alter table public.words
    add constraint words_workspace_fk foreign key (user_id, workspace_id)
        references public.workspaces (user_id, id),
    add constraint words_user_workspace_id_key unique (user_id, workspace_id, id);

-- 9. Memberships. Composite foreign keys: the word and the folder must belong to the same owner
-- and the same workspace. No id column: the pull cursor is (updated_at, word_id, folder_id).
create table public.word_folders (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    workspace_id uuid not null,
    word_id uuid not null,
    folder_id uuid not null,
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    primary key (user_id, word_id, folder_id),
    constraint word_folders_word_fk foreign key (user_id, workspace_id, word_id)
        references public.words (user_id, workspace_id, id),
    constraint word_folders_folder_fk foreign key (user_id, workspace_id, folder_id)
        references public.folders (user_id, workspace_id, id)
);

-- Dangling and deleted folder ids are dropped. Tombstoned words keep their live memberships; the
-- app tombstones them when it applies the word tombstone.
insert into public.word_folders (user_id, workspace_id, word_id, folder_id, created_at, updated_at)
select distinct w.user_id, w.workspace_id, w.id, f.id,
       greatest(w.created_at, f.created_at),
       date_trunc('milliseconds', pg_catalog.clock_timestamp())
from public.words w
cross join lateral unnest(w.folder_ids) as m (folder_id)
join public.folders f
    on f.user_id = w.user_id and f.id = m.folder_id
   and f.workspace_id = w.workspace_id and f.deleted_at is null
on conflict do nothing;

-- 9a. Drop the legacy shape; all of it is in the backup, workspaces, entered_side and word_folders.
drop index public.words_user_id_language_pair_idx;
alter table public.words
    drop constraint words_entered_language_in_pair,
    drop constraint words_distinct_languages,
    drop column term_language,
    drop column translation_language,
    drop column entered_language,
    drop column folder_ids;

-- 10. Indexes: keyset pulls per user, and the foreign-key columns of memberships.
create index workspaces_user_id_updated_at_id_idx on public.workspaces (user_id, updated_at, id);
create index word_folders_user_id_updated_at_keyset_idx
    on public.word_folders (user_id, updated_at, word_id, folder_id);
create index word_folders_user_workspace_word_idx on public.word_folders (user_id, workspace_id, word_id);
create index word_folders_user_workspace_folder_idx on public.word_folders (user_id, workspace_id, folder_id);

-- 11. Server-assigned updated_at (see 20261119105315_sync_server_timestamps).
create trigger workspaces_set_server_updated_at
    before insert or update on public.workspaces
    for each row execute function private.set_server_updated_at();
create trigger word_folders_set_server_updated_at
    before insert or update on public.word_folders
    for each row execute function private.set_server_updated_at();

-- 12. RLS, grants (no anon, no delete) and policies.
alter table public.workspaces enable row level security;
alter table public.word_folders enable row level security;

revoke all on table public.workspaces, public.word_folders from anon;
grant select, insert, update on table public.workspaces, public.word_folders to authenticated;
revoke delete, truncate, references, trigger on table public.workspaces, public.word_folders
    from authenticated, anon;

create policy workspaces_select_own on public.workspaces
    for select to authenticated
    using ((select auth.uid()) = user_id);
create policy workspaces_insert_own on public.workspaces
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy workspaces_update_own on public.workspaces
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy word_folders_select_own on public.word_folders
    for select to authenticated
    using ((select auth.uid()) = user_id);
create policy word_folders_insert_own on public.word_folders
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy word_folders_update_own on public.word_folders
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

-- 13. Documentation.
comment on column public.workspaces.id is
    'Deterministic: uuid v5 (namespace a4f06f42-4f0b-43f6-bfb4-33545dcf1307) of term_language || ''>'' || translation_language.';
comment on column public.words.workspace_id is
    'Workspace (language pair) of the word; term_language/translation_language live only in public.workspaces.';
comment on column public.words.entered_side is
    'Side the user typed: term (studied language) or translation.';
comment on table public.word_folders is
    'Word <-> folder membership; removing one is a tombstone (deleted_at), re-adding clears it.';
comment on column public.workspaces.updated_at is
    'Server-assigned (trigger private.set_server_updated_at), ms precision, strictly increasing per row; sync cursor.';
comment on column public.word_folders.updated_at is
    'Server-assigned (trigger private.set_server_updated_at), ms precision, strictly increasing per row; sync cursor.';

commit;
