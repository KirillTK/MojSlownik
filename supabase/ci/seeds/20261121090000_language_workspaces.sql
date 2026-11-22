-- CI-only seed: legacy-shaped rows (before 20261121090000_language_workspaces) so that
-- supabase/tests/workspaces_backfill.sql and workspaces_backup.sql can check the backfill.
-- Applied by scripts/test-db.sh right before that migration; never apply this to Supabase.
--
-- User C: words pl>ru (one Russian-entered, one tombstone) and de>ru, folders (one live, one deleted);
--         folder_ids mix a live folder, a deleted folder and a dangling id.
-- User D: folders only, no words.

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated', false);

insert into public.folders (id, user_id, name, sort_order, created_at, deleted_at) values
    ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-00000000000c', 'C live', 0,
     '2026-01-01 10:00:00+00', null),
    ('00000000-0000-4000-8000-0000000000c2', '00000000-0000-4000-8000-00000000000c', 'C deleted', 1,
     '2026-01-02 10:00:00+00', '2026-03-01 10:00:00+00'),
    ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-00000000000d', 'D folder', 0,
     '2026-01-05 10:00:00+00', null);

insert into public.words (id, user_id, term, term_language, translation, translation_language,
                          entered_language, folder_ids, created_at, due_date, deleted_at) values
    ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-00000000000c', 'kot', 'pl',
     'кот', 'ru', 'ru',
     '{00000000-0000-4000-8000-0000000000c1,00000000-0000-4000-8000-0000000000c2,00000000-0000-4000-8000-0000000000ff}',
     '2026-01-10 10:00:00+00', '2026-01-10 10:00:00+00', null),
    ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-00000000000c', 'pies', 'pl',
     'пёс', 'ru', 'pl', '{00000000-0000-4000-8000-0000000000c1}',
     '2026-01-11 10:00:00+00', '2026-01-11 10:00:00+00', '2026-02-01 10:00:00+00'),
    ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-00000000000c', 'Haus', 'de',
     'дом', 'ru', 'de', '{00000000-0000-4000-8000-0000000000c1}',
     '2026-02-01 10:00:00+00', '2026-02-01 10:00:00+00', null);

-- Server stamps before the migration (the R5 check compares them afterwards).
create schema ci;
create table ci.seed_snapshot as
    select 'word'::text as kind, user_id, id, updated_at from public.words
    union all
    select 'folder', user_id, id, updated_at from public.folders;
