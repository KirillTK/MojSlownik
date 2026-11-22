-- CI-only: the pre-migration backup tables of 20261121090000_language_workspaces keep the seeded
-- legacy shape and are unreachable for API roles. Needs the CI seed. Dropped together with the
-- backup tables by the later drop migration. One transaction that is rolled back.

begin;

do $$
begin
    assert (select count(*) from private.words_backup_20261121) = 3, 'all seeded words (tombstone included)';
    assert (select count(*) from private.folders_backup_20261121) = 3, 'all seeded folders';
    assert (select count(*) from information_schema.columns
            where table_schema = 'private' and table_name = 'words_backup_20261121'
              and column_name in ('term_language', 'translation_language', 'entered_language', 'folder_ids')) = 4,
           'the backup keeps the legacy columns';
    assert (select entered_language from private.words_backup_20261121
            where id = '00000000-0000-4000-8000-0000000000e1') = 'ru';
    assert (select term_language from private.words_backup_20261121
            where id = '00000000-0000-4000-8000-0000000000e3') = 'de';
    assert (select cardinality(folder_ids) from private.words_backup_20261121
            where id = '00000000-0000-4000-8000-0000000000e1') = 3, 'folder_ids kept incl. dangling';

    assert not has_schema_privilege('anon', 'private', 'usage');
    assert not has_schema_privilege('authenticated', 'private', 'usage');
    assert not has_table_privilege('anon', 'private.words_backup_20261121', 'select');
    assert not has_table_privilege('authenticated', 'private.words_backup_20261121', 'select');
    assert not has_table_privilege('authenticated', 'private.folders_backup_20261121', 'select');
    assert (select bool_and(relrowsecurity) from pg_class
            where oid in ('private.words_backup_20261121'::regclass,
                          'private.folders_backup_20261121'::regclass)), 'RLS on the backups';
end $$;

select set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-00000000000c","role":"authenticated","is_anonymous":false}', true);
set local role authenticated;
do $$
begin
    begin
        perform count(*) from private.words_backup_20261121;
        raise exception 'FAIL: authenticated read the backup';
    exception when insufficient_privilege then null;
    end;
end $$;
reset role;

select 'workspaces_backup: all assertions passed' as result;

rollback;
