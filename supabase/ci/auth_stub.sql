-- Minimal stand-in for the Supabase pieces the migrations rely on, so the RLS tests run on
-- a plain Postgres in CI (no Supabase project, no secrets). Never apply this to Supabase.
-- Mirrors: API roles anon/authenticated, auth.users, auth.uid() and the default grants that
-- Supabase gives API roles on new tables in schema public.

-- Roles are cluster-wide, so tolerate a cluster where an earlier run created them.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin noinherit;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin noinherit;
    end if;
end $$;

create schema auth;
grant usage on schema auth to anon, authenticated;

-- Supabase pre-installs the `extensions` schema (uuid-ossp lives there).
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated;

create table auth.users (
    id uuid primary key,
    aud varchar(255),
    role varchar(255),
    is_anonymous boolean not null default false
);

create function auth.uid() returns uuid
language sql stable
as $$
    select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    )::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;

grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
