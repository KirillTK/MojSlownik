-- Language-neutral words: a word is a pair (term in the studied language, translation into the
-- learner's language), each side with a BCP 47 language code, so any language pair fits.
-- Replaces the ru/pl-specific columns of 20261117224918_words_folders_rls. The table was
-- created empty and nothing writes to it yet; the guard below refuses to drop data anyway.
--
-- category is a stable identifier (WordCategory case name: food, home, …, other), not the
-- localized title.

do $$
begin
    if exists (select 1 from public.words) then
        raise exception 'public.words is not empty: write a data-preserving migration instead';
    end if;
end $$;

drop table public.words;

create table public.words (
    id uuid not null,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    term text not null check (char_length(btrim(term)) between 1 and 500),
    term_language text not null check (term_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    translation text not null check (char_length(btrim(translation)) between 1 and 500),
    translation_language text not null check (translation_language ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,3}$'),
    entered_language text not null,
    category text not null default 'other' check (category ~ '^[a-z][a-z0-9_]{0,31}$'),
    folder_ids uuid[] not null default '{}' check (cardinality(folder_ids) <= 500),
    created_at timestamptz not null,
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    ease_factor double precision not null default 2.5 check (ease_factor >= 1.3),
    interval_days double precision not null default 0 check (interval_days >= 0),
    repetitions integer not null default 0 check (repetitions >= 0),
    due_date timestamptz not null,
    last_review_grade text check (last_review_grade in ('again', 'hard', 'good', 'easy')),
    knowledge_tier integer check (knowledge_tier between 0 and 3),
    consecutive_soft_misses integer not null default 0 check (consecutive_soft_misses >= 0),
    primary key (user_id, id),
    constraint words_distinct_languages check (term_language <> translation_language),
    constraint words_entered_language_in_pair check (entered_language in (term_language, translation_language))
);

-- Delta sync pulls "changed since cursor" per user; per-pair decks filter by language pair.
create index words_user_id_updated_at_idx on public.words (user_id, updated_at);
create index words_user_id_language_pair_idx on public.words (user_id, term_language, translation_language);

alter table public.words enable row level security;

revoke all on table public.words from anon;
grant select, insert, update, delete on table public.words to authenticated;

create policy words_select_own on public.words
    for select to authenticated
    using ((select auth.uid()) = user_id);
create policy words_insert_own on public.words
    for insert to authenticated
    with check ((select auth.uid()) = user_id);
create policy words_update_own on public.words
    for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);
create policy words_delete_own on public.words
    for delete to authenticated
    using ((select auth.uid()) = user_id);
