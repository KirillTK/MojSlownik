-- words.fsrs_*: the FSRS memory of a word (state, stability, difficulty, learning step, last
-- review). Client-maintained and synced with the word. Additive: the columns are nullable (a word
-- nobody has reviewed since this migration has no FSRS state; each device derives the same state
-- from the SM-2 columns) except fsrs_learning_step, which defaults to 0.
--
-- Security model unchanged: RLS and grants are table-level, so the new columns are covered by the
-- existing owner-scoped policies. Adding nullable or defaulted columns fires no UPDATE trigger, so
-- existing rows keep their updated_at (no sync churn). No SECURITY DEFINER functions.

begin;

alter table public.words
    add column fsrs_state smallint
        constraint words_fsrs_state_range check (fsrs_state between 0 and 3),
    add column fsrs_stability double precision
        constraint words_fsrs_stability_range check (fsrs_stability >= 0 and fsrs_stability <= 36500),
    add column fsrs_difficulty double precision
        constraint words_fsrs_difficulty_range check (fsrs_difficulty >= 0 and fsrs_difficulty <= 10),
    add column fsrs_learning_step integer not null default 0
        constraint words_fsrs_learning_step_range check (fsrs_learning_step between 0 and 100),
    add column fsrs_last_review timestamptz;

comment on column public.words.fsrs_state is
    'FSRS card state: 0 new, 1 learning, 2 review, 3 relearning. Null until reviewed after the FSRS migration.';
comment on column public.words.fsrs_stability is 'FSRS stability in days (memory half-life style), 0..36500.';
comment on column public.words.fsrs_difficulty is 'FSRS difficulty, 0..10 (0 only before the first review).';
comment on column public.words.fsrs_learning_step is 'Index of the current (re)learning step.';
comment on column public.words.fsrs_last_review is 'When the word was last reviewed with FSRS.';
comment on column public.words.ease_factor is
    'Legacy SM-2 ease, frozen: no longer written by the app (read only to convert SM-2 progress to FSRS).';

commit;
