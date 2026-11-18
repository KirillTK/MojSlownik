-- Documents that words.category holds the app's stable WordCategory.stableID, not a name.
comment on column public.words.category is
  'Stable category id from the app''s WordCategory.stableID (explicit ids: food, home, travel, nature, people, work, health, other). Never a localized name; ids are never renamed, new ones are only added.';
