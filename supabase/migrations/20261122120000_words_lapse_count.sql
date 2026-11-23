-- words.lapse_count: how many times a word was forgotten after being answered correctly.
-- Drives the "hard words" (leech) list in the app. Additive and defaulted: older app versions
-- upsert without the column (inserts get 0, updates keep the stored value).
--
-- Security model unchanged: RLS and grants are table-level, so the new column is covered by the
-- existing owner-scoped policies. Adding a defaulted column fires no UPDATE trigger, so existing
-- rows keep their updated_at (no sync churn). No SECURITY DEFINER functions.

begin;

alter table public.words
    add column lapse_count integer not null default 0
    constraint words_lapse_count_nonnegative check (lapse_count >= 0);

comment on column public.words.lapse_count is
    'Failures after a success (hard-word detection); client-maintained, never negative.';

commit;
