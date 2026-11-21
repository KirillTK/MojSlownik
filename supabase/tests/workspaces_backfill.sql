-- CI-only: checks the backfill of 20261121090000_language_workspaces on the rows seeded by
-- supabase/ci/seeds/20261121090000_language_workspaces.sql (needs that seed and ci.seed_snapshot).
-- Runs as the table owner. One transaction that is rolled back.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/workspaces_backfill.sql

begin;

do $$
declare
    c constant uuid := '00000000-0000-4000-8000-00000000000c';
    d constant uuid := '00000000-0000-4000-8000-00000000000d';
    plru constant uuid := '0db61f29-e285-5e06-84f5-d85acfa1b5cc';
    deru constant uuid := 'f03536f4-02a8-515b-924f-f39a95de6a18';
begin
    -- Workspaces: C has pl>ru (sort 0) and de>ru (sort 1); D only pl>ru (folders only).
    assert (select count(*) from public.workspaces where user_id = c) = 2, 'C must have two workspaces';
    assert (select sort_order from public.workspaces where user_id = c and id = plru) = 0, 'C pl>ru sort 0';
    assert (select sort_order from public.workspaces where user_id = c and id = deru) = 1, 'C de>ru sort 1';
    assert (select term_language || '>' || translation_language from public.workspaces
            where user_id = c and id = deru) = 'de>ru', 'de>ru languages';
    assert (select count(*) from public.workspaces where user_id = d) = 1, 'D must have one workspace';
    assert (select id from public.workspaces where user_id = d) = plru, 'D has pl>ru';
    assert (select created_at from public.workspaces where user_id = c and id = plru)
           = timestamptz '2026-01-01 10:00:00+00', 'created_at is the earliest row of the pair';
    assert not exists (select 1 from public.workspaces where deleted_at is not null
                       and user_id in (c, d)), 'no workspace is a tombstone';
    assert not exists (select 1 from public.workspaces
                       where updated_at <> date_trunc('milliseconds', updated_at)), 'ms precision';

    -- Words and folders point at the expected workspace.
    assert (select workspace_id from public.words where id = '00000000-0000-4000-8000-0000000000e1') = plru;
    assert (select workspace_id from public.words where id = '00000000-0000-4000-8000-0000000000e2') = plru;
    assert (select workspace_id from public.words where id = '00000000-0000-4000-8000-0000000000e3') = deru;
    assert (select count(*) from public.folders where workspace_id = plru and user_id in (c, d)) = 3,
           'every folder is in pl>ru';

    -- entered_side from entered_language.
    assert (select entered_side from public.words where id = '00000000-0000-4000-8000-0000000000e1')
           = 'translation', 'Russian-entered word';
    assert (select entered_side from public.words where id = '00000000-0000-4000-8000-0000000000e2') = 'term';
    assert (select entered_side from public.words where id = '00000000-0000-4000-8000-0000000000e3') = 'term';

    -- Memberships: only the live folder of the same workspace; deleted, dangling and cross-workspace dropped.
    assert (select count(*) from public.word_folders where user_id in (c, d)) = 2,
           'exactly the live-folder memberships';
    assert exists (select 1 from public.word_folders
                   where word_id = '00000000-0000-4000-8000-0000000000e1'
                     and folder_id = '00000000-0000-4000-8000-0000000000c1' and deleted_at is null);
    assert exists (select 1 from public.word_folders
                   where word_id = '00000000-0000-4000-8000-0000000000e2'
                     and folder_id = '00000000-0000-4000-8000-0000000000c1' and deleted_at is null);
    assert not exists (select 1 from public.word_folders
                       where word_id = '00000000-0000-4000-8000-0000000000e3'), 'de word not in a pl>ru folder';
    assert not exists (select 1 from public.word_folders
                       where folder_id = '00000000-0000-4000-8000-0000000000c2'), 'deleted folder dropped';

    -- R5: the backfill did not touch updated_at of words and folders.
    assert (select count(*) from ci.seed_snapshot) = 6, 'snapshot has all seeded words and folders';
    assert not exists (
        select 1 from ci.seed_snapshot s
        left join public.words w on s.kind = 'word' and w.user_id = s.user_id and w.id = s.id
        left join public.folders f on s.kind = 'folder' and f.user_id = s.user_id and f.id = s.id
        where coalesce(w.updated_at, f.updated_at) is distinct from s.updated_at),
        'backfill must not bump updated_at of words/folders';
end $$;

select 'workspaces_backfill: all assertions passed' as result;

rollback;
