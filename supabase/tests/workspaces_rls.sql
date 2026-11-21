-- RLS and shape checks for public.workspaces / public.word_folders and the normalized words/folders
-- (migration 20261121090000_language_workspaces), run as the real API roles. Needs a superuser owner
-- for the final cascade check. One transaction that is rolled back.
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/workspaces_rls.sql

begin;

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-0000000000a1', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-0000000000b1', 'authenticated', 'authenticated', false);

-- ---------------------------------------------------------------- user A
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

insert into public.workspaces (id, term_language, translation_language, created_at) values
    ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now()),
    ('f03536f4-02a8-515b-924f-f39a95de6a18', 'de', 'ru', now());
insert into public.folders (id, workspace_id, name, created_at) values
    ('00000000-0000-4000-8000-0000000a00f1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl folder', now()),
    ('00000000-0000-4000-8000-0000000a00f2', 'f03536f4-02a8-515b-924f-f39a95de6a18', 'de folder', now());
insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date) values
    ('00000000-0000-4000-8000-0000000a00d1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'kot', 'кот', 'term', now(), now());
insert into public.word_folders (workspace_id, word_id, folder_id, created_at)
values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', '00000000-0000-4000-8000-0000000a00d1',
        '00000000-0000-4000-8000-0000000a00f1', now());

do $$
declare
    stamp timestamptz;
    affected integer;
begin
    assert (select count(*) from public.workspaces) = 2, 'A sees its workspaces';
    assert (select count(*) from public.word_folders) = 1, 'A sees its membership';
    assert (select user_id from public.workspaces limit 1) = auth.uid(), 'user_id defaults to auth.uid()';

    -- Triggers assign updated_at on insert and bump it on update.
    select updated_at into stamp from public.workspaces where id = '0db61f29-e285-5e06-84f5-d85acfa1b5cc';
    assert stamp = date_trunc('milliseconds', stamp), 'workspace updated_at has ms precision';
    update public.workspaces set sort_order = 3 where id = '0db61f29-e285-5e06-84f5-d85acfa1b5cc';
    assert (select updated_at from public.workspaces where id = '0db61f29-e285-5e06-84f5-d85acfa1b5cc') > stamp,
           'workspace update bumps updated_at';
    select updated_at into stamp from public.word_folders;
    update public.word_folders set deleted_at = now();
    assert (select updated_at from public.word_folders) > stamp, 'membership update bumps updated_at';
    update public.word_folders set deleted_at = null;

    -- Second workspace for the same pair.
    begin
        insert into public.workspaces (id, term_language, translation_language, created_at)
        values (gen_random_uuid(), 'pl', 'ru', now());
        raise exception 'FAIL: pair duplicate with another id accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.workspaces (id, term_language, translation_language, created_at)
        values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now());
        raise exception 'FAIL: duplicate workspace accepted';
    exception when unique_violation then null;
    end;
    begin
        insert into public.workspaces (id, term_language, translation_language, created_at)
        values (extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'ru>ru'), 'ru', 'ru', now());
        raise exception 'FAIL: same-language workspace accepted';
    exception when check_violation then null;
    end;

    -- A membership across workspaces, or to a missing word/folder.
    begin
        insert into public.word_folders (workspace_id, word_id, folder_id, created_at)
        values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', '00000000-0000-4000-8000-0000000a00d1',
                '00000000-0000-4000-8000-0000000a00f2', now());
        raise exception 'FAIL: cross-workspace membership accepted';
    exception when foreign_key_violation then null;
    end;
    begin
        insert into public.word_folders (workspace_id, word_id, folder_id, created_at)
        values ('f03536f4-02a8-515b-924f-f39a95de6a18', '00000000-0000-4000-8000-0000000a00d1',
                '00000000-0000-4000-8000-0000000a00f2', now());
        raise exception 'FAIL: membership of a word from another workspace accepted';
    exception when foreign_key_violation then null;
    end;

    -- NOT NULL without defaults.
    begin
        insert into public.words (id, term, translation, entered_side, created_at, due_date)
        values (gen_random_uuid(), 'a', 'b', 'term', now(), now());
        raise exception 'FAIL: word without workspace_id accepted';
    exception when not_null_violation then null;
    end;
    begin
        insert into public.words (id, workspace_id, term, translation, created_at, due_date)
        values (gen_random_uuid(), '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'a', 'b', now(), now());
        raise exception 'FAIL: word without entered_side accepted';
    exception when not_null_violation then null;
    end;
    begin
        insert into public.folders (id, name, created_at) values (gen_random_uuid(), 'x', now());
        raise exception 'FAIL: folder without workspace_id accepted';
    exception when not_null_violation then null;
    end;
    -- A word in a workspace A does not own.
    begin
        insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
        values (gen_random_uuid(), extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'en>pl'),
                'a', 'b', 'term', now(), now());
        raise exception 'FAIL: word in an unknown workspace accepted';
    exception when foreign_key_violation then null;
    end;

    -- Ownership.
    begin
        insert into public.workspaces (user_id, id, term_language, translation_language, created_at)
        values ('00000000-0000-4000-8000-0000000000b1',
                extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'en>pl'), 'en', 'pl', now());
        raise exception 'FAIL: A inserted a workspace owned by B';
    exception when insufficient_privilege then null;
    end;
    begin
        update public.workspaces set user_id = '00000000-0000-4000-8000-0000000000b1';
        raise exception 'FAIL: A moved a workspace to B';
    exception when insufficient_privilege then null;
    end;
    begin
        update public.word_folders set user_id = '00000000-0000-4000-8000-0000000000b1';
        raise exception 'FAIL: A moved a membership to B';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.word_folders (user_id, workspace_id, word_id, folder_id, created_at)
        values ('00000000-0000-4000-8000-0000000000b1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc',
                '00000000-0000-4000-8000-0000000a00d1', '00000000-0000-4000-8000-0000000a00f1', now());
        raise exception 'FAIL: A inserted a membership owned by B';
    exception when insufficient_privilege then null;
    end;

    -- No hard deletes.
    begin
        delete from public.workspaces;
        raise exception 'FAIL: delete on workspaces allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from public.word_folders;
        raise exception 'FAIL: delete on word_folders allowed';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- user B
reset role;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

insert into public.workspaces (id, term_language, translation_language, created_at)
values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now());

do $$
declare
    affected integer;
begin
    assert (select count(*) from public.workspaces) = 1, 'B sees only its own workspace';
    assert (select count(*) from public.word_folders) = 0, 'B sees none of A''s memberships';
    update public.workspaces set sort_order = 9 where id = 'f03536f4-02a8-515b-924f-f39a95de6a18';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s workspace';
    update public.word_folders set deleted_at = now();
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s memberships';
    begin
        insert into public.word_folders (workspace_id, word_id, folder_id, created_at)
        values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', '00000000-0000-4000-8000-0000000a00d1',
                '00000000-0000-4000-8000-0000000a00f1', now());
        raise exception 'FAIL: membership referencing A''s word accepted';
    exception when foreign_key_violation then null;
    end;
end $$;

-- ---------------------------------------------------------------- anon
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
do $$
begin
    begin
        perform count(*) from public.workspaces;
        raise exception 'FAIL: anon can read workspaces';
    exception when insufficient_privilege then null;
    end;
    begin
        perform count(*) from public.word_folders;
        raise exception 'FAIL: anon can read word_folders';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- owner: shape
reset role;
do $$
declare
    tbl text;
    privilege text;
    api_role text;
begin
    assert extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'pl>ru')
           = '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pinned pl>ru v5 id';
    assert extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'en>pl')
           = 'ffaa32bf-2636-5dbd-8e6a-ff2987c0cf6f', 'pinned en>pl v5 id';

    assert not exists (select 1 from information_schema.columns
                       where table_schema = 'public' and table_name = 'words'
                         and column_name in ('term_language', 'translation_language', 'entered_language',
                                             'folder_ids')),
           'legacy word columns must be gone';

    foreach tbl in array array['public.workspaces', 'public.word_folders'] loop
        assert (select relrowsecurity from pg_class where oid = tbl::regclass), 'RLS on ' || tbl;
        assert not has_table_privilege('anon', tbl, 'select'), 'anon has no access to ' || tbl;
        foreach api_role in array array['authenticated', 'anon'] loop
            foreach privilege in array array['DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
                assert not has_table_privilege(api_role, tbl, privilege),
                       format('%s must not have %s on %s', api_role, privilege, tbl);
            end loop;
        end loop;
    end loop;

    assert (select count(*) from pg_policies where schemaname = 'public'
            and tablename in ('workspaces', 'word_folders')) = 6, 'select/insert/update policy per table';
    assert not exists (select 1 from pg_policies
                       where schemaname = 'public' and tablename in ('workspaces', 'word_folders')
                         and (roles <> '{authenticated}'
                              or coalesce(qual, with_check) not like '%auth.uid()%user_id%')),
           'policies compare auth.uid() with user_id';
    assert not exists (select 1 from pg_policies
                       where schemaname = 'public' and tablename in ('workspaces', 'word_folders')
                         and cmd in ('INSERT', 'UPDATE') and with_check is null), 'WITH CHECK present';
    assert (select count(*) from pg_trigger
            where tgname in ('workspaces_set_server_updated_at', 'word_folders_set_server_updated_at')
              and not tgisinternal) = 2, 'timestamp triggers';
    assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.prosecdef), 'no SECURITY DEFINER in public';
end $$;

-- Deleting an auth user cascades through all rows (as owner).
delete from auth.users where id = '00000000-0000-4000-8000-0000000000a1';
do $$
begin
    assert not exists (select 1 from public.workspaces where user_id = '00000000-0000-4000-8000-0000000000a1');
    assert not exists (select 1 from public.word_folders where user_id = '00000000-0000-4000-8000-0000000000a1');
    assert not exists (select 1 from public.words where user_id = '00000000-0000-4000-8000-0000000000a1');
end $$;

select 'workspaces_rls: all assertions passed' as result;

rollback;
