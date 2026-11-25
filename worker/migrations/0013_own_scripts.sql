-- Own scripts (Decision 088.3 and 088.4, src/plays-own.js): the text a person
-- brought, for the people of one production and gone with it. One row a
-- production of an own script, made with it: bytes = 0 while the text is owed,
-- and again once it is removed. user_id is who brought it; it goes with that
-- account even when the production passes to someone else. `body` is last so
-- nothing reads past it to another column. There is no route that lists these.
CREATE TABLE play_scripts (
  production_id  TEXT PRIMARY KEY REFERENCES play_productions(id) ON DELETE CASCADE,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bytes          INTEGER NOT NULL DEFAULT 0,
  episode_id     TEXT,
  created_at     INTEGER NOT NULL,
  held_at        INTEGER,
  body           TEXT
);
CREATE INDEX play_scripts_user ON play_scripts (user_id);

-- How much text is kept, in one row, so the cap costs one read and not one a
-- script. Triggers keep it right on every path, cascades included.
CREATE TABLE play_script_total (
  id     INTEGER PRIMARY KEY CHECK (id = 1),
  bytes  INTEGER NOT NULL
);
INSERT INTO play_script_total (id, bytes) VALUES (1, 0);

CREATE TRIGGER play_scripts_total_update AFTER UPDATE OF bytes ON play_scripts WHEN NEW.bytes <> OLD.bytes
BEGIN
  UPDATE play_script_total SET bytes = bytes + NEW.bytes - OLD.bytes WHERE id = 1;
END;

CREATE TRIGGER play_scripts_total_delete AFTER DELETE ON play_scripts WHEN OLD.bytes > 0
BEGIN
  UPDATE play_script_total SET bytes = bytes - OLD.bytes WHERE id = 1;
END;

-- What the owner removed, so the same text (`revision:<12 hex>`) or the same
-- episode's transcript (`episode:<id>`) is refused at its next share. No person.
CREATE TABLE play_removed_scripts (
  key         TEXT PRIMARY KEY,
  removed_at  INTEGER NOT NULL
);

-- A report of the production's own script: no take, and target_user_id is who brought it.
ALTER TABLE play_reports ADD COLUMN script INTEGER NOT NULL DEFAULT 0;
