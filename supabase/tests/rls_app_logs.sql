-- End-to-end checks for public.app_logs as the real API roles: insert-only, own rows only,
-- unreadable through the API, and shaped so free-form user content does not fit.
-- Runs in one rolled-back transaction (see rls_words_folders.sql for how to run).

begin;

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000001a', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-00000000001b', 'authenticated', 'authenticated', false);

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000001a","role":"authenticated"}', true);
set local role authenticated;

-- A valid row, with user_id filled by the database default.
insert into public.app_logs (occurred_at, session_id, level, event, properties, app_version, os_version)
values (now(), '00000000-0000-4000-8000-0000000000aa', 'info', 'word.added',
        '{"source":"manual","language":"ru","count":1}', '1.0 (1)', '18.2');

-- Contract: the exact body the iOS app sends (AppLogQueueTests.goldenRequestBody) is accepted.
insert into public.app_logs (occurred_at, session_id, level, event, properties, app_version, os_version)
select occurred_at, session_id, level, event, properties, app_version, os_version
from jsonb_populate_recordset(null::public.app_logs,
    '[{"app_version":"1.0 (1)","event":"word.added","level":"info","occurred_at":"2027-01-15T08:00:00.000","os_version":"18.2.0","properties":{"count":1,"language":"ru","source":"manual"},"session_id":"00000000-0000-4000-8000-0000000000AA"}]');

do $$
declare
    affected integer;
begin
    begin
        perform count(*) from public.app_logs;
        raise exception 'FAIL: authenticated can read logs';
    exception when insufficient_privilege then null;
    end;

    begin
        update public.app_logs set level = 'error';
        raise exception 'FAIL: authenticated can update logs';
    exception when insufficient_privilege then null;
    end;

    begin
        delete from public.app_logs;
        raise exception 'FAIL: authenticated can delete logs';
    exception when insufficient_privilege then null;
    end;

    begin
        insert into public.app_logs (user_id, occurred_at, session_id, level, event, app_version, os_version)
        values ('00000000-0000-4000-8000-00000000001b', now(), gen_random_uuid(), 'info', 'word.added', '1.0', '18.2');
        raise exception 'FAIL: inserted a log row for another user';
    exception when insufficient_privilege then null;
    end;

    -- Server-owned columns are not insertable (column-level grant).
    begin
        insert into public.app_logs (received_at, occurred_at, session_id, level, event, app_version, os_version)
        values ('2000-01-01', now(), gen_random_uuid(), 'info', 'word.added', '1.0', '18.2');
        raise exception 'FAIL: client set received_at';
    exception when insufficient_privilege then null;
    end;
    begin
        insert into public.app_logs (user_id, occurred_at, session_id, level, event, app_version, os_version)
        values ('00000000-0000-4000-8000-00000000001a', now(), gen_random_uuid(), 'info', 'word.added', '1.0', '18.2');
        raise exception 'FAIL: client set user_id (even its own)';
    exception when insufficient_privilege then null;
    end;

    -- Shape constraints: free text does not fit into event, level or versions.
    begin
        insert into public.app_logs (occurred_at, session_id, level, event, app_version, os_version)
        values (now(), gen_random_uuid(), 'info', 'User typed: кот', '1.0', '18.2');
        raise exception 'FAIL: free-form event accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.app_logs (occurred_at, session_id, level, event, app_version, os_version)
        values (now(), gen_random_uuid(), 'debug', 'word.added', '1.0', '18.2');
        raise exception 'FAIL: unknown level accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.app_logs (occurred_at, session_id, level, event, properties, app_version, os_version)
        values (now(), gen_random_uuid(), 'info', 'word.added', '["a"]', '1.0', '18.2');
        raise exception 'FAIL: non-object properties accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.app_logs (occurred_at, session_id, level, event, properties, app_version, os_version)
        values (now(), gen_random_uuid(), 'info', 'word.added',
                jsonb_build_object('blob', repeat('x', 4000)), '1.0', '18.2');
        raise exception 'FAIL: oversized properties accepted';
    exception when check_violation then null;
    end;
    begin
        insert into public.app_logs (occurred_at, session_id, level, event, app_version, os_version)
        values (now(), gen_random_uuid(), 'info', 'word.added', 'https://evil.example/?q=кот', '18.2');
        raise exception 'FAIL: free-form app_version accepted';
    exception when check_violation then null;
    end;
end $$;

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

do $$
begin
    begin
        insert into public.app_logs (user_id, occurred_at, session_id, level, event, app_version, os_version)
        values ('00000000-0000-4000-8000-00000000001a', now(), gen_random_uuid(), 'info', 'word.added', '1.0', '18.2');
        raise exception 'FAIL: anon can insert logs';
    exception when insufficient_privilege then null;
    end;
end $$;

reset role;

do $$
begin
    assert (select count(*) from public.app_logs
            where user_id = '00000000-0000-4000-8000-00000000001a' and event = 'word.added') = 2,
           'both valid rows must be stored for their author';
    assert (select occurred_at from public.app_logs
            where session_id = '00000000-0000-4000-8000-0000000000aa' and os_version = '18.2.0')
           = '2027-01-15 08:00:00+00'::timestamptz,
           'the app''s zone-less timestamp must be read as UTC';
    assert (select relrowsecurity from pg_class where oid = 'public.app_logs'::regclass),
           'RLS must be enabled on app_logs';
    assert (select count(*) from pg_policies where schemaname = 'public' and tablename = 'app_logs') = 1
       and (select cmd from pg_policies where schemaname = 'public' and tablename = 'app_logs') = 'INSERT',
           'app_logs must have exactly one INSERT policy';
end $$;

select 'rls_app_logs: all assertions passed' as result;

rollback;
