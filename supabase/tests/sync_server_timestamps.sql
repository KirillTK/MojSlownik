-- Checks for migration sync_server_timestamps: server-assigned updated_at, upsert under RLS,
-- denied hard deletes, keyset ordering over ties, privileges and indexes.
-- One transaction that is rolled back: no data is left behind.
--
-- Needs a role allowed to `set local session_replication_role` (superuser; CI's postgres is).
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/sync_server_timestamps.sql

begin;

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', false);

-- ---------------------------------------------------------------- user A
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

-- A client-sent updated_at is ignored: the server assigns it (ms precision, not in the future).
insert into public.words (id, term, term_language, translation, translation_language, entered_language,
                          created_at, updated_at, due_date)
values ('00000000-0000-4000-8000-0000000000d1', 'kot', 'pl', 'кот', 'ru', 'ru', now(), '2100-01-01', now());
insert into public.folders (id, name, created_at, updated_at)
values ('00000000-0000-4000-8000-0000000000f1', 'A folder', now(), '2100-01-01');

do $$
declare
    first_stamp timestamptz;
    second_stamp timestamptz;
    third_stamp timestamptz;
begin
    select updated_at into first_stamp from public.words where id = '00000000-0000-4000-8000-0000000000d1';
    assert first_stamp <= clock_timestamp(), 'a client updated_at must be ignored on insert';
    assert first_stamp = date_trunc('milliseconds', first_stamp), 'updated_at must have ms precision';
    assert (select updated_at from public.folders) <= clock_timestamp(), 'folder updated_at is server time';

    -- Strictly increasing per row, even for updates in the same transaction.
    update public.words set term = 'kot2' where id = '00000000-0000-4000-8000-0000000000d1';
    select updated_at into second_stamp from public.words where id = '00000000-0000-4000-8000-0000000000d1';
    update public.words set term = 'kot3', updated_at = '2000-01-01'
    where id = '00000000-0000-4000-8000-0000000000d1';
    select updated_at into third_stamp from public.words where id = '00000000-0000-4000-8000-0000000000d1';
    assert second_stamp > first_stamp, 'updated_at must strictly increase (1st update)';
    assert third_stamp > second_stamp, 'updated_at must strictly increase (2nd update)';

    -- Upsert as the client sends it: conflict on (user_id, id), deleted_at null clears a tombstone.
    update public.words set deleted_at = now() where id = '00000000-0000-4000-8000-0000000000d1';
    assert (select deleted_at from public.words where id = '00000000-0000-4000-8000-0000000000d1') is not null;
    insert into public.words (id, user_id, term, term_language, translation, translation_language,
                              entered_language, created_at, due_date, deleted_at)
    values ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-00000000000a', 'kot4',
            'pl', 'кот', 'ru', 'ru', now(), now(), null)
    on conflict (user_id, id) do update set term = excluded.term, deleted_at = excluded.deleted_at;
    assert (select term from public.words where id = '00000000-0000-4000-8000-0000000000d1') = 'kot4',
           'upsert must update the row';
    assert (select deleted_at from public.words where id = '00000000-0000-4000-8000-0000000000d1') is null,
           'upsert with null deleted_at must clear the tombstone';
    assert (select updated_at from public.words where id = '00000000-0000-4000-8000-0000000000d1') > third_stamp,
           'an upsert update must increase updated_at';

    -- WITH CHECK: an upsert into B's account is refused.
    begin
        insert into public.words (id, user_id, term, term_language, translation, translation_language,
                                  entered_language, created_at, due_date)
        values ('00000000-0000-4000-8000-0000000000d2', '00000000-0000-4000-8000-00000000000b', 'pies',
                'pl', 'пёс', 'ru', 'ru', now(), now())
        on conflict (user_id, id) do update set term = excluded.term;
        raise exception 'FAIL: A upserted a word into B''s account';
    exception when insufficient_privilege then null;
    end;

    -- No hard deletes and no truncate for API roles.
    begin
        delete from public.words;
        raise exception 'FAIL: delete on words allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from public.folders;
        raise exception 'FAIL: delete on folders allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        truncate public.words;
        raise exception 'FAIL: truncate on words allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        truncate public.folders;
        raise exception 'FAIL: truncate on folders allowed';
    exception when insufficient_privilege then null;
    end;
    begin
        perform private.set_server_updated_at();
        raise exception 'FAIL: private function callable';
    exception when insufficient_privilege then null;
    end;
    assert (select count(*) from public.words) = 1, 'the word must still exist';
end $$;

-- ---------------------------------------------------------------- owner: ties and keyset
reset role;

-- Triggers off, so the rows can share an identical updated_at (an upsert batch can tie).
set local session_replication_role = replica;
insert into public.words (id, user_id, term, term_language, translation, translation_language,
                          entered_language, created_at, updated_at, due_date)
select ('00000000-0000-4000-8000-0000000001' || lpad(i::text, 2, '0'))::uuid,
       '00000000-0000-4000-8000-00000000000a', 'tie' || i, 'pl', 'x', 'ru', 'ru', now(),
       timestamptz '2030-01-01 00:00:00.123+00', now()
from generate_series(1, 3) as i;
insert into public.words (id, user_id, term, term_language, translation, translation_language,
                          entered_language, created_at, updated_at, due_date)
values ('00000000-0000-4000-8000-000000000199', '00000000-0000-4000-8000-00000000000a', 'later', 'pl', 'x',
        'ru', 'ru', now(), timestamptz '2030-01-01 00:00:00.124+00', now());
set local session_replication_role = origin;

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

do $$
declare
    ids uuid[];
begin
    select array_agg(id order by updated_at, id) into ids
    from public.words
    where user_id = '00000000-0000-4000-8000-00000000000a'
      and updated_at >= timestamptz '2030-01-01 00:00:00.123+00'
      and (updated_at > timestamptz '2030-01-01 00:00:00.123+00'
           or (updated_at = timestamptz '2030-01-01 00:00:00.123+00'
               and id > '00000000-0000-4000-8000-000000000101'));
    assert ids = array['00000000-0000-4000-8000-000000000102', '00000000-0000-4000-8000-000000000103',
                       '00000000-0000-4000-8000-000000000199']::uuid[],
           'keyset after the first tied row must return the remaining ties in id order, then the later row';
end $$;

-- ---------------------------------------------------------------- privileges and shape
reset role;

do $$
declare
    tbl text;
    privilege text;
    api_role text;
begin
    foreach tbl in array array['public.words', 'public.folders'] loop
        foreach api_role in array array['authenticated', 'anon'] loop
            foreach privilege in array array['DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
                assert not has_table_privilege(api_role, tbl, privilege),
                       format('%s must not have %s on %s', api_role, privilege, tbl);
            end loop;
        end loop;
    end loop;

    assert not has_schema_privilege('authenticated', 'private', 'usage'), 'authenticated must not use schema private';
    assert not has_schema_privilege('anon', 'private', 'usage'), 'anon must not use schema private';
    assert not has_function_privilege('authenticated', 'private.set_server_updated_at()', 'execute'),
           'authenticated must not execute the private trigger function';
    assert not has_function_privilege('anon', 'private.set_server_updated_at()', 'execute'),
           'anon must not execute the private trigger function';
    assert not (select prosecdef from pg_proc where oid = 'private.set_server_updated_at()'::regprocedure),
           'the trigger function must be SECURITY INVOKER';

    assert (select count(*) from pg_trigger
            where tgrelid in ('public.words'::regclass, 'public.folders'::regclass)
              and tgname in ('words_set_server_updated_at', 'folders_set_server_updated_at')
              and not tgisinternal) = 2,
           'the server timestamp triggers must exist on words and folders';
    assert exists (select 1 from pg_indexes where schemaname = 'public'
                   and indexname = 'words_user_id_updated_at_id_idx'), 'words keyset index missing';
    assert exists (select 1 from pg_indexes where schemaname = 'public'
                   and indexname = 'folders_user_id_updated_at_id_idx'), 'folders keyset index missing';
    assert not exists (select 1 from pg_indexes where schemaname = 'public'
                       and indexname in ('words_user_id_updated_at_idx', 'folders_user_id_updated_at_idx')),
           'the superseded indexes must be gone';
    assert not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.prosecdef),
           'no SECURITY DEFINER functions may live in schema public';
end $$;

select 'sync_server_timestamps: all assertions passed' as result;

rollback;
