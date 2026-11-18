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

insert into public.folders (id, name, created_at)
values ('00000000-0000-4000-8000-0000000000f1', 'A folder', now());
insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                          created_at, due_date, folder_ids)
values ('00000000-0000-4000-8000-0000000000d1', 'kot', 'pl', 'кот', 'ru', 'ru', now(), now(),
        '{00000000-0000-4000-8000-0000000000f1}');

do $$
begin
    assert (select count(*) from public.words) = 1, 'A must see its own word';
    assert (select count(*) from public.folders) = 1, 'A must see its own folder';
    assert (select user_id from public.words) = auth.uid(), 'user_id must default to auth.uid()';

    begin
        insert into public.words (user_id, id, term, term_language, translation, translation_language,
                                  entered_language, created_at, due_date)
        values ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-0000000000d2',
                'pies', 'pl', 'пёс', 'ru', 'ru', now(), now());
        raise exception 'FAIL: A inserted a word owned by B';
    exception when insufficient_privilege then null;
    end;

    begin
        insert into public.folders (user_id, id, name, created_at)
        values ('00000000-0000-4000-8000-00000000000b', '00000000-0000-4000-8000-0000000000f2', 'x', now());
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

    update public.words set term = 'hacked' where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s word';

    update public.folders set name = 'hacked' where id = '00000000-0000-4000-8000-0000000000f1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not update A''s folder';

    delete from public.words where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not delete A''s word';

    delete from public.folders where id = '00000000-0000-4000-8000-0000000000f1';
    get diagnostics affected = row_count;
    assert affected = 0, 'B must not delete A''s folder';

    -- Same client-generated id in another account: allowed, no cross-user collision.
    insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                              created_at, due_date)
    values ('00000000-0000-4000-8000-0000000000d1', 'dom', 'pl', 'дом', 'ru', 'pl', now(), now());
    assert (select count(*) from public.words) = 1, 'B must see only its own word';
    assert (select term from public.words) = 'dom', 'B must see its own copy of the id';

    -- Any language pair fits (not only ru/pl), with category as a stable id.
    insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                              category, created_at, due_date)
    values ('00000000-0000-4000-8000-0000000000d4', 'Haus', 'de', 'house', 'en', 'de', 'home', now(), now());
    assert (select count(*) from public.words where term_language = 'de' and translation_language = 'en') = 1,
           'a de/en word must be accepted';

    begin
        insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                                  created_at, due_date)
        values (gen_random_uuid(), 'a', 'pl', 'b', 'pl', 'pl', now(), now());
        raise exception 'FAIL: same term and translation language accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                                  created_at, due_date)
        values (gen_random_uuid(), 'a', 'pl', 'b', 'ru', 'en', now(), now());
        raise exception 'FAIL: entered_language outside the pair accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                                  created_at, due_date)
        values (gen_random_uuid(), 'a', 'Polish', 'b', 'ru', 'ru', now(), now());
        raise exception 'FAIL: non-BCP 47 language code accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                                  category, created_at, due_date)
        values (gen_random_uuid(), 'a', 'pl', 'b', 'ru', 'ru', 'Еда и напитки', now(), now());
        raise exception 'FAIL: localized category title accepted';
    exception when check_violation then null;
    end;

    -- Owner may soft-delete and hard-delete its own rows.
    update public.words set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 1, 'B must be able to update its own word';
    delete from public.words where id = '00000000-0000-4000-8000-0000000000d1';
    get diagnostics affected = row_count;
    assert affected = 1, 'B must be able to delete its own word';
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
        insert into public.words (user_id, id, term, term_language, translation, translation_language,
                                  entered_language, created_at, due_date)
        values ('00000000-0000-4000-8000-00000000000a', '00000000-0000-4000-8000-0000000000d3',
                'a', 'pl', 'b', 'ru', 'ru', now(), now());
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
            where schemaname = 'public' and tablename in ('words', 'folders')) = 8,
           'words and folders must have exactly one policy per command';
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
