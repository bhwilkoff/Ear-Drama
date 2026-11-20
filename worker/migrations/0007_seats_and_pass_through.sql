-- Classes that own productions, seats without accounts, and takes that pass
-- through (Decision 082, PLAYS-DESIGN §12.4-§12.5). Owner, 2026-11-19: "We are
-- using archive.org for storage, not cloudflare." No column here holds audio,
-- and the take table loses its object key: a take's bytes cross the Worker to
-- the director's (the teacher's) device and are never written anywhere.

-- A seat: a name the teacher typed. No account, email, birth date or photo.
-- key_hash is the SHA-256 of the seat key the claiming device was given once;
-- NULL while the seat is free (never claimed, or released by the teacher).
CREATE TABLE play_class_seats (
  class_id    TEXT NOT NULL REFERENCES play_classes(id) ON DELETE CASCADE,
  id          TEXT NOT NULL,
  label       TEXT NOT NULL,
  key_hash    TEXT,
  claimed_at  INTEGER,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (class_id, id)
);
CREATE UNIQUE INDEX play_class_seats_label ON play_class_seats (class_id, label COLLATE NOCASE);
CREATE UNIQUE INDEX play_class_seats_key ON play_class_seats (key_hash) WHERE key_hash IS NOT NULL;

-- A class production: seen by its class's seats without an invite, and by no
-- one else outside its members. Deleted with the class.
ALTER TABLE play_productions ADD COLUMN class_id TEXT REFERENCES play_classes(id) ON DELETE CASCADE;
CREATE INDEX play_productions_class ON play_productions (class_id);

-- The teacher's casting: a part (or a scene range of it, from_line..to_line,
-- both lines of that part) given to a seat. A production with any row here
-- lets every assigned part record at once; one without keeps the C7 relay.
CREATE TABLE play_assignments (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  seq            INTEGER NOT NULL,
  part           TEXT NOT NULL,
  from_line      TEXT,
  to_line        TEXT,
  seat_id        TEXT NOT NULL,
  PRIMARY KEY (production_id, seq)
);
CREATE INDEX play_assignments_seat ON play_assignments (production_id, seat_id);

-- The take table, rebuilt without object_key (Decision 066's R2 store is gone)
-- and with seat_id: a seat's take belongs to the teacher's account (user_id)
-- and names the seat that recorded it. A row is the take's fields only,
-- written when the take reached the director's device. R2 was never bound in
-- production, so the copy below moves metadata only.
CREATE TABLE play_takes_new (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  id             TEXT NOT NULL,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seat_id        TEXT,
  line_id        TEXT NOT NULL,
  part           TEXT NOT NULL,
  file           TEXT NOT NULL,
  content_type   TEXT NOT NULL,
  bytes          INTEGER NOT NULL,
  frames         INTEGER NOT NULL,
  sample_rate    REAL NOT NULL,
  capture        TEXT NOT NULL,
  heard          TEXT NOT NULL DEFAULT '{}',
  loudness       REAL,
  peak           REAL NOT NULL DEFAULT 0,
  created        REAL NOT NULL,
  uploaded_at    INTEGER NOT NULL,
  chosen         INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (production_id, id)
);
INSERT INTO play_takes_new (production_id, id, user_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, heard, loudness, peak, created, uploaded_at, chosen)
  SELECT production_id, id, user_id, line_id, part, file, content_type, bytes, frames, sample_rate, capture, heard, loudness, peak, created, uploaded_at, chosen FROM play_takes;
DROP TABLE play_takes;
ALTER TABLE play_takes_new RENAME TO play_takes;
CREATE INDEX play_takes_user ON play_takes (user_id);
CREATE INDEX play_takes_line ON play_takes (production_id, line_id);
CREATE INDEX play_takes_seat ON play_takes (production_id, seat_id);
CREATE UNIQUE INDEX play_takes_chosen ON play_takes (production_id, line_id) WHERE chosen = 1;

-- The teacher's review of a take: approved or again, with an optional typed
-- note that only the take's seat is shown. A take never changes; the latest
-- review stands. Goes with the production.
CREATE TABLE play_reviews (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  take_id        TEXT NOT NULL,
  state          TEXT NOT NULL CHECK (state IN ('approved', 'again')),
  note           TEXT NOT NULL DEFAULT '',
  reviewed_at    INTEGER NOT NULL,
  PRIMARY KEY (production_id, take_id)
);

-- Bucket objects are gone, so nothing is left to retry deleting.
DROP TABLE play_orphan_objects;
