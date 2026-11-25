-- Checks for migration words_fsrs_state: nullable FSRS columns with a defaulted step, updatable,
-- range CHECKs, owner scoping and no anon access. One transaction that is rolled back: no data is
-- left behind.
--
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/words_fsrs_state.sql

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
-- Inserted without the fsrs columns, as a word nobody reviewed yet.
insert into public.words (id, workspace_id, term, translation, entered_side, created_at, due_date)
values ('00000000-0000-4000-8000-0000000000d1', '0db61f29-e285-5e06-84f5-d85acfa1b5cc', 'kot', 'кот',
        'translation', now(), now());

do $$
begin
    assert (select fsrs_state is null and fsrs_stability is null and fsrs_difficulty is null
                   and fsrs_last_review is null and fsrs_learning_step = 0
            from public.words where id = '00000000-0000-4000-8000-0000000000d1'),
           'fsrs columns must be null (step 0) on an insert without them';

    update public.words
    set fsrs_state = 2, fsrs_stability = 12.5, fsrs_difficulty = 6.9, fsrs_learning_step = 1,
        fsrs_last_review = now()
    where id = '00000000-0000-4000-8000-0000000000d1';
    assert (select fsrs_state = 2 and fsrs_stability = 12.5 and fsrs_difficulty = 6.9
                   and fsrs_learning_step = 1 and fsrs_last_review is not null
            from public.words where id = '00000000-0000-4000-8000-0000000000d1'),
           'fsrs columns must be updatable';

    begin
        update public.words set fsrs_state = 4 where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: fsrs_state 4 accepted';
    exception when check_violation then null;
    end;
    begin
        update public.words set fsrs_difficulty = 11 where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: fsrs_difficulty 11 accepted';
    exception when check_violation then null;
    end;
    begin
        update public.words set fsrs_stability = -1 where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: negative fsrs_stability accepted';
    exception when check_violation then null;
    end;
    begin
        update public.words set fsrs_learning_step = -1 where id = '00000000-0000-4000-8000-0000000000d1';
        raise exception 'FAIL: negative fsrs_learning_step accepted';
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
    assert (select count(*) from public.words where fsrs_state = 2) = 0, 'B must not see A''s word';
end $$;

-- ---------------------------------------------------------------- anon
reset role;
do $$
declare
    col text;
begin
    foreach col in array array['fsrs_state', 'fsrs_stability', 'fsrs_difficulty', 'fsrs_learning_step',
                               'fsrs_last_review'] loop
        assert not has_column_privilege('anon', 'public.words', col, 'select'),
               'anon must not read ' || col;
        assert not has_column_privilege('anon', 'public.words', col, 'update'),
               'anon must not write ' || col;
    end loop;
end $$;

select 'words_fsrs_state: all assertions passed' as result;

rollback;
