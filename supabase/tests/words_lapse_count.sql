-- Checks for migration words_lapse_count: default 0, updatable, non-negative CHECK, owner scoping
-- and no anon access. One transaction that is rolled back: no data is left behind.
--
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/words_lapse_count.sql

begin;

insert into auth.users (id, aud, role, is_anonymous) values
    ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated', false),
    ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated', false);

-- ---------------------------------------------------------------- user A
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

insert into public.workspaces (id, term_language, translation_language, created_at)
values ('0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'pl', 'ru', now());
-- Inserted without lapse_count, as an older app version does.
insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
values ('00000000-0000-4000-8000-0000000000d1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'kot', 'кот',
        'translation', now(), now());

do $$
begin
    assert (select lapse_count from public.words where id = '00000000-0000-4000-8000-0000000000d1') = 0,
           'lapse_count must default to 0';

    update public.words set lapse_count = 7 where id = '00000000-0000-4000-8000-0000000000d1';
    assert (select lapse_count from public.words where id = '00000000-0000-4000-8000-0000000000d1') = 7,
           'lapse_count must be updatable';

    -- An update that does not name the column keeps the value (older app versions).
    update public.words set term = 'kot2' where id = '00000000-0000-4000-8000-0000000000d1';
    assert (select lapse_count from public.words where id = '00000000-0000-4000-8000-0000000000d1') = 7,
           'an update without lapse_count must keep it';

    begin
        update public.words set lapse_count = -1 where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: negative lapse_count accepted';
    exception when check_violation then null;
    end;
end $$;

-- ---------------------------------------------------------------- user B
reset role;
select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;

do $$
begin
    assert (select count(*) from public.words where lapse_count = 7) = 0, 'B must not see A''s word';
end $$;

-- ---------------------------------------------------------------- anon
reset role;
do $$
begin
    assert not has_column_privilege('anon', 'public.words', 'lapse_count', 'select'),
           'anon must not read lapse_count';
    assert not has_column_privilege('anon', 'public.words', 'lapse_count', 'update'),
           'anon must not write lapse_count';
end $$;

select 'words_lapse_count: all assertions passed' as result;

rollback;
