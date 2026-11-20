-- Relay across time and the consent rule (Decision 082, PLAYS-DESIGN §12.11).
-- Owner, 2026-11-19: "credit the maker, never the leader". A take recorded by
-- someone with no account (an adult room's reader, who gave a name on joining)
-- is a row of the director's production, so `user_id` would name the director.
-- `credit` is the maker's own name, kept only on such a take: a name the person
-- typed to join, passed through the same name filter as every name, never audio.
ALTER TABLE play_takes ADD COLUMN credit TEXT;
