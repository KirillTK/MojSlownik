-- Checks for migration review_logs: server-assigned updated_at, idempotent insert, immutability,
-- owner scoping under RLS, CHECK constraints, privileges and the keyset index.
-- One transaction that is rolled back: no data is left behind.
--
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/review_logs.sql

begin;

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', false);

-- ---------------------------------------------------------------- user A
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

-- user_id defaults to auth.uid(); updated_at is server time and cannot be sent.
insert into public.review_logs (id, workspace_id, word_id, reviewed_at, rating, mode, affects_schedule,
    elapsed_days, interval_days_before, interval_days_after, due_before, due_after, state_before,
    state_after, stability_before, stability_after, difficulty_before, difficulty_after,
    last_reviewed_before)
values ('00000000-0000-4000-8000-0000000000e1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc',
        '00000000-0000-4000-8000-0000000000d1', now(), 'good', 'flashcards', true,
        0, 0, 2, now(), now() + interval '2 days', 0, 2, 0, 2.3, 0, 6.4, null);

do $$
declare
    stamp timestamptz;
begin
    select updated_at into stamp from public.review_logs
    where id = '00000000-0000-4000-8000-0000000000e1';
    assert stamp <= clock_timestamp(), 'updated_at must be server time';
    assert stamp = date_trunc('milliseconds', stamp), 'updated_at must have ms precision';
    assert (select user_id from public.review_logs where id = '00000000-0000-4000-8000-0000000000e1')
           = '00000000-0000-4000-8000-00000000000a', 'user_id must default to auth.uid()';
end $$;

-- A client-sent updated_at is refused (no column privilege).
do $$
begin
    begin
        insert into public.review_logs (id, workspace_id, word_id, reviewed_at, rating, mode,
            affects_schedule, elapsed_days, interval_days_before, interval_days_after, due_before,
            due_after, state_before, state_after, stability_before, stability_after, difficulty_before,
            difficulty_after, updated_at)
        values ('00000000-0000-4000-8000-0000000000e2', '0db61f29-e285-5e06-84f5-d85acfa1b5cc',
                '00000000-0000-4000-8000-0000000000d1', now(), 'good', 'quiz', true, 0, 0, 0, now(), now(),
                0, 0, 0, 0, 0, 0, '2100-01-01');
        raise exception 'FAIL: updated_at insert accepted';
    exception when insufficient_privilege then null;
    end;
end $$;

-- A duplicate (same user_id, id) with ON CONFLICT DO NOTHING leaves one row.
insert into public.review_logs (id, workspace_id, word_id, reviewed_at, rating, mode, affects_schedule,
    elapsed_days, interval_days_before, interval_days_after, due_before, due_after, state_before,
    state_after, stability_before, stability_after, difficulty_before, difficulty_after)
values ('00000000-0000-4000-8000-0000000000e1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc',
        '00000000-0000-4000-8000-0000000000d1', now(), 'again', 'quiz', true, 0, 0, 0, now(), now(),
        0, 0, 0, 0, 0, 0)
on conflict (user_id, id) do nothing;

do $$
begin
    assert (select count(*) from public.review_logs) = 1, 'a duplicate insert must leave one row';
    assert (select rating from public.review_logs) = 'good', 'a duplicate must not overwrite the row';

    -- Immutable through the API.
    begin
        update public.review_logs set rating = 'easy';
        raise exception 'FAIL: update accepted';
    exception when insufficient_privilege then null;
    end;
    begin
        delete from public.review_logs;
        raise exception 'FAIL: delete accepted';
    exception when insufficient_privilege then null;
    end;

    -- Another user's id is refused by the WITH CHECK policy.
    begin
        insert into public.review_logs (id, user_id, workspace_id, word_id, reviewed_at, rating, mode,
            affects_schedule, elapsed_days, interval_days_before, interval_days_after, due_before,
            due_after, state_before, state_after, stability_before, stability_after, difficulty_before,
            difficulty_after)
        values ('00000000-0000-4000-8000-0000000000e3', '00000000-0000-4000-8000-00000000000b',
                '0db61f29-e285-5e06-84f5-d85acfa1b5cc', '00000000-0000-4000-8000-0000000000d1', now(),
                'good', 'quiz', true, 0, 0, 0, now(), now(), 0, 0, 0, 0, 0, 0);
        raise exception 'FAIL: insert for another user accepted';
    exception when insufficient_privilege then null;
    end;
end $$;

-- CHECK violations (one bad value each).
do $$
declare
    bad text;
begin
    foreach bad in array array[
        'rating',  'mode', 'elapsed', 'state', 'stability', 'difficulty', 'reviewed_at'] loop
        begin
            insert into public.review_logs (id, workspace_id, word_id, reviewed_at, rating, mode,
                affects_schedule, elapsed_days, interval_days_before, interval_days_after, due_before,
                due_after, state_before, state_after, stability_before, stability_after,
                difficulty_before, difficulty_after)
            values (gen_random_uuid(), '0db61f29-e285-5e06-84f5-d85acfa1b5cc',
                    '00000000-0000-4000-8000-0000000000d1',
                    case when bad = 'reviewed_at' then '2019-12-31T00:00:00Z'::timestamptz else now() end,
                    case when bad = 'rating' then 'perfect' else 'good' end,
                    case when bad = 'mode' then 'typing' else 'quiz' end, true,
                    case when bad = 'elapsed' then -1 else 0 end, 0, 0, now(), now(),
                    case when bad = 'state' then 4 else 0 end, 0,
                    case when bad = 'stability' then -1 else 0 end, 0,
                    case when bad = 'difficulty' then 11 else 0 end, 0);
            raise exception 'FAIL: invalid % accepted', bad;
        exception when check_violation then null;
        end;
    end loop;
end $$;

-- ---------------------------------------------------------------- user B
reset role;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

do $$
begin
    assert (select count(*) from public.review_logs) = 0, 'B must not see A''s log rows';
end $$;

-- ---------------------------------------------------------------- anon, privileges, index
reset role;
do $$
begin
    assert not has_table_privilege('anon', 'public.review_logs', 'select'), 'anon must not read';
    assert not has_table_privilege('anon', 'public.review_logs', 'insert'), 'anon must not insert';
    assert not has_table_privilege('authenticated', 'public.review_logs', 'update'), 'no update grant';
    assert not has_table_privilege('authenticated', 'public.review_logs', 'delete'), 'no delete grant';
    assert has_table_privilege('authenticated', 'public.review_logs', 'select'), 'select is granted';
    assert not has_column_privilege('authenticated', 'public.review_logs', 'updated_at', 'insert'),
           'updated_at must not be insertable';
    assert (select relrowsecurity from pg_class where oid = 'public.review_logs'::regclass),
           'RLS must be enabled';
    assert exists (select 1 from pg_indexes where schemaname = 'public' and tablename = 'review_logs'
                   and indexname = 'review_logs_user_id_updated_at_id_idx'), 'keyset index must exist';
end $$;

select 'review_logs: all assertions passed' as result;

rollback;
