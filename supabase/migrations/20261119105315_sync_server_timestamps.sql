-- Sync support for public.words / public.folders: server-assigned updated_at, a keyset index and
-- soft-delete-only semantics.
--
-- Security model (unchanged: RLS scoped by (select auth.uid()) = user_id, WITH CHECK on
-- INSERT/UPDATE, no anon grants):
-- * The trigger function is SECURITY INVOKER with an empty search_path and lives in the schema
--   `private`, which API roles cannot use (not exposed by PostgREST, no USAGE grant). Postgres
--   does not check EXECUTE on a trigger function when the trigger fires.
-- * Server hard deletes are revoked: DELETE, TRUNCATE (which bypasses RLS), REFERENCES and
--   TRIGGER are removed from API roles and the delete policies are dropped. Clients soft-delete
--   (deleted_at); account deletion still cascades through the auth.users foreign key.
--
-- updated_at is assigned by the server on every INSERT and UPDATE, so client values are
-- ignored: the device clock never decides a conflict. clock_timestamp() (not now()) plus the
-- "previous + 1 ms" floor guarantees every committed version of a row has a strictly larger
-- updated_at than the one before. With now() (transaction start) two concurrent upserts of the
-- same row could leave a final row older than the loser's acknowledgement, and that device's
-- later pull would skip it forever. Millisecond truncation makes updated_at round-trip exactly
-- through Swift Date and the (updated_at, id) sync cursor.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create function private.set_server_updated_at() returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
    if tg_op = 'UPDATE' then
        new.updated_at := greatest(date_trunc('milliseconds', pg_catalog.clock_timestamp()),
                                   old.updated_at + interval '1 millisecond');
    else
        new.updated_at := date_trunc('milliseconds', pg_catalog.clock_timestamp());
    end if;
    return new;
end
$$;
revoke all on function private.set_server_updated_at() from public, anon, authenticated;

-- Existing rows to millisecond precision, before the triggers exist.
update public.words set updated_at = date_trunc('milliseconds', updated_at)
where updated_at <> date_trunc('milliseconds', updated_at);
update public.folders set updated_at = date_trunc('milliseconds', updated_at)
where updated_at <> date_trunc('milliseconds', updated_at);

create trigger words_set_server_updated_at
    before insert or update on public.words
    for each row execute function private.set_server_updated_at();
create trigger folders_set_server_updated_at
    before insert or update on public.folders
    for each row execute function private.set_server_updated_at();

-- Keyset pull: where user_id = $1 and (updated_at, id) after the cursor, ordered.
create index words_user_id_updated_at_id_idx on public.words (user_id, updated_at, id);
create index folders_user_id_updated_at_id_idx on public.folders (user_id, updated_at, id);
drop index public.words_user_id_updated_at_idx;
drop index public.folders_user_id_updated_at_idx;

-- Soft delete is the only deletion path.
drop policy words_delete_own on public.words;
drop policy folders_delete_own on public.folders;
revoke delete, truncate, references, trigger on table public.words, public.folders from authenticated, anon;

comment on column public.words.updated_at is
    'Server-assigned (trigger private.set_server_updated_at), ms precision, strictly increasing per row; sync cursor.';
comment on column public.folders.updated_at is
    'Server-assigned (trigger private.set_server_updated_at), ms precision, strictly increasing per row; sync cursor.';
