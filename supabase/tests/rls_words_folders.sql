-- End-to-end RLS checks for public.words / public.folders, run as the real API roles.
-- Everything happens inside one transaction that is rolled back: no data is left behind.
--
-- Run against the linked Supabase project (Supabase MCP execute_sql, or psql as postgres)
-- and in CI against a plain Postgres with supabase/ci/auth_stub.sql loaded first:
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/rls_words_folders.sql
-- Any failed assertion raises an error; success ends with one "passed" row.

begin;

-- Fixtures (as the table owner): user A is anonymous, user B is a regular account.
insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', true),
    ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', false);

-- ---------------------------------------------------------------- user A (anonymous)
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":true}', true);
set local role authenticated;

insert into public.workspaces (id, term_language, translation_language, created_at)
values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now());
insert into public.folders (id, workspace_id, name, created_at)
values ('00000000-0000-4000-8000-0000000000f1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'A folder', now());
insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
values ('00000000-0000-4000-8000-0000000000d1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'kot', 'кот',
        'translation', now(), now());
insert into public.word_folders (workspace_id, word_id, folder_id, created_at)
values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', '00000000-0000-4000-8000-0000000000d1',
        '00000000-0000-4000-8000-0000000000f1', now());

do $$
begin
    assert (select count(*) from public.words) = 1, 'A must see its own word';
    assert (select count(*) from public.folders) = 1, 'A must see its own folder';
    assert (select count(*) from public.word_folders) = 1, 'A must see its own membership';
    assert (select user_id from public.words) = auth.uid(), 'user_id must default to auth.uid()';

    begin
        insert into public.words (user_id, id, workspace_id, term, translation, entered_side, created_at, due_date)
        values ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-0000000000d2',
                '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pies', 'пёс', 'translation', now(), now());
        raise exception 'FAIL: A inserted a word owned by B';
    exception when insufficient_privilege then null;
    end;

    begin
        insert into public.folders (user_id, id, workspace_id, name, created_at)
        values ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-0000000000f2',
                '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'x', now());
        raise exception 'FAIL: A inserted a folder owned by B';
    exception when insufficient_privilege then null;
    end;

    begin
        update public.words set user_id = '00000000-0000-4000-8000-00000000000b'
        where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: A moved its word to B';
    exception when insufficient_privilege then null;
    end;

    begin
        update public.folders set user_id = '00000000-0000-4000-8000-00000000000b'
        where id = '00000000-0000-4000-8000-0000000000f1';
        raise exception 'FAIL: A moved its folder to B';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- user B
reset role;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

do $$
declare
    affected integer;
begin
    assert (select count(*) from public.words) = 0, 'B must not see A''s words';
    assert (select count(*) from public.folders) = 0, 'B must not see A''s folders';
    assert (select count(*) from public.workspaces) = 0, 'B must not see A''s workspaces';
    assert (select count(*) from public.word_folders) = 0, 'B must not see A''s memberships';

    update public.words set term = 'hacked' where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s word';

    update public.folders set name = 'hacked' where id = '00000000-0000-4000-8000-0000000000f1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s folder';

    -- Hard deletes are revoked for everyone (soft delete only).
    begin
        delete from public.words where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: B deleted A''s word';
    exception when insufficient_privilege then null;
    end;

    begin
        delete from public.folders where id = '00000000-0000-4000-8000-0000000000f1';
        raise exception 'FAIL: B deleted A''s folder';
    exception when insufficient_privilege then null;
    end;

    -- Same client-generated ids in another account: allowed, no cross-user collision.
    insert into public.workspaces (id, term_language, translation_language, created_at)
    values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now());
    insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
    values ('00000000-0000-4000-8000-0000000000d1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'dom', 'дом',
            'term', now(), now());
    assert (select count(*) from public.words) = 1, 'B must see only its own word';
    assert (select term from public.words) = 'dom', 'B must see its own copy of the id';

    -- Any language pair fits (not only ru/pl), with category as a stable id.
    insert into public.workspaces (id, term_language, translation_language, created_at)
    values (extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'de>en'), 'de', 'en', now());
    insert into public.words (id, workspace_id, term, translation, entered_side, category, created_at, due_date)
    values ('00000000-0000-4000-8000-0000000000d4',
            extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'de>en'),
            'Haus', 'house', 'term', 'home', now(), now());
    assert (select count(*) from public.words w join public.workspaces s
                on s.user_id = w.user_id and s.id = w.workspace_id
            where s.term_language = 'de' and s.translation_language = 'en') = 1,
           'a de/en word must be accepted';

    begin
        insert into public.workspaces (id, term_language, translation_language, created_at)
        values (extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'pl>pl'), 'pl', 'pl', now());
        raise exception 'FAIL: same term and translation language accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
        values (gen_random_uuid(), '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'a', 'b', 'both', now(), now());
        raise exception 'FAIL: entered_side outside term/translation accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.workspaces (id, term_language, translation_language, created_at)
        values (extensions.uuid_generate_v5('a4f06f42-4f0b-43f6-bfb4-33545dcf1307', 'Polish>ru'),
                'Polish', 'ru', now());
        raise exception 'FAIL: non-BCP 47 language code accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.words (id, workspace_id, term, translation, entered_side, category, created_at, due_date)
        values (gen_random_uuid(), '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'a', 'b', 'term',
                'Еда и напитки', now(), now());
        raise exception 'FAIL: localized category title accepted';
    exception when check_violation then null;
    end;

    -- Owner may soft-delete its own rows; hard delete is revoked.
    update public.words set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 1, 'B must be able to update its own word';
    begin
        delete from public.words where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: B hard-deleted its own word';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- anon (no session)
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
begin
    begin
        perform count(*) from public.words;
        raise exception 'FAIL: anon can read words';
    exception when insufficient_privilege then null;
    end;
    begin
        perform count(*) from public.folders;
        raise exception 'FAIL: anon can read folders';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.words (user_id, id, workspace_id, term, translation, entered_side, created_at, due_date)
        values ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-0000000000d3',
                '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'a', 'b', 'term', now(), now());
        raise exception 'FAIL: anon can insert words';
    exception when insufficient_privilege then null;
    end;
end $$;

-- ---------------------------------------------------------------- owner view + schema shape
reset role;

do $$
begin
    assert (select term from public.words
            where user_id = '00000000-0000-4000-8000-00000000000a'
              and id = '00000000-0000-4000-8000-0000000000d1') = 'kot',
           'A''s word must be untouched by B';
    assert (select name from public.folders
            where user_id = '00000000-0000-4000-8000-00000000000a') = 'A folder',
           'A''s folder must be untouched by B';

    assert (select bool_and(c.relrowsecurity) from pg_class c
            where c.oid in ('public.words'::regclass, 'public.folders'::regclass)),
           'RLS must be enabled on words and folders';

    assert (select count(*) from pg_policies
            where schemaname = 'public' and tablename in ('words', 'folders')) = 6,
           'words and folders must have exactly one policy each for select/insert/update';
    assert not exists (select 1 from pg_policies
                       where schemaname = 'public' and tablename in ('words', 'folders')
                         and (roles <> '{authenticated}'
                              or coalesce(qual, with_check) not like '%auth.uid()%user_id%')),
           'every policy must target authenticated and compare auth.uid() with user_id';
    assert not exists (select 1 from pg_policies
                       where schemaname = 'public' and tablename in ('words', 'folders')
                         and cmd in ('INSERT', 'UPDATE') and with_check is null),
           'INSERT and UPDATE policies must have WITH CHECK';

    assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.prosecdef),
           'no SECURITY DEFINER functions may live in schema public';
    assert col_description('public.words'::regclass,
                           (select attnum from pg_attribute where attrelid = 'public.words'::regclass
                            and attname = 'category')) like '%WordCategory.stableID%',
           'words.category documents the stable-id contract';
end $$;

select 'rls_words_folders: all assertions passed' as result;

rollback;
