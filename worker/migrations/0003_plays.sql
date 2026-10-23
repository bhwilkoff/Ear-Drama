-- Shared plays, phase 2 (LOOP-PLAN M8, docs/PLAYS-DESIGN.md §11): invite-only
-- productions across devices. Every table that holds a person's rows has a
-- column referencing users(id), and every one is in USER_TABLES
-- (src/account.js); test/account.test.js reads the foreign keys from D1 and
-- fails on a table or a person column that deletion would miss.
--
-- Take audio is not here: it is an object in the TAKES bucket (R2), named by
-- object_key. Times are milliseconds on the server's clock, except a take's
-- `created`, which is the client's Foundation seconds (production.json).

-- A production of one castable script at one revision. `cast_sheet` is the script's
-- lines as [[line id, part], ...] in script order, checked against the
-- castable manifest by its SHA-256 when the production is made. user_id is the
-- director; deleting that account hands the production to the member who
-- joined first, and deletes it only when no one else is in it.
CREATE TABLE play_productions (
  id               TEXT PRIMARY KEY,
  user_id          TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  script_id        TEXT NOT NULL,
  script_revision  TEXT NOT NULL,
  title            TEXT NOT NULL,
  cast_sheet       TEXT NOT NULL,
  created_at       INTEGER NOT NULL,
  updated_at       INTEGER NOT NULL
);
CREATE INDEX play_productions_user ON play_productions (user_id);

-- Who is in a production: the director and everyone who came in by an invite.
-- display_name passed the deny list (src/plays-names.js) and may be empty.
CREATE TABLE play_members (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name   TEXT NOT NULL DEFAULT '',
  joined_at      INTEGER NOT NULL,
  PRIMARY KEY (production_id, user_id)
);
CREATE INDEX play_members_user ON play_members (user_id);

-- An invite link: the token is returned once and stored only as its SHA-256.
CREATE TABLE play_invites (
  id             TEXT PRIMARY KEY,
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash     TEXT NOT NULL UNIQUE,
  created_at     INTEGER NOT NULL,
  expires_at     INTEGER NOT NULL,
  revoked        INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX play_invites_production ON play_invites (production_id);
CREATE INDEX play_invites_expires ON play_invites (expires_at);

-- A part's place in the relay. No row means open. A 'recording' row is a
-- claim, and it lapses CLAIM_TTL_MS after claimed_at (PLAYS-DESIGN C7).
CREATE TABLE play_parts (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  part           TEXT NOT NULL,
  status         TEXT NOT NULL CHECK (status IN ('recording', 'done', 'silent')),
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  claimed_at     INTEGER NOT NULL,
  PRIMARY KEY (production_id, part)
);
CREATE INDEX play_parts_user ON play_parts (user_id);

-- One take: immutable once written (PLAYS-DESIGN §8 rule 5). chosen = 1 marks
-- the line's chosen take, at most one per line.
CREATE TABLE play_takes (
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  id             TEXT NOT NULL,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  line_id        TEXT NOT NULL,
  part           TEXT NOT NULL,
  file           TEXT NOT NULL,
  object_key     TEXT NOT NULL UNIQUE,
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
CREATE INDEX play_takes_user ON play_takes (user_id);
CREATE INDEX play_takes_line ON play_takes (production_id, line_id);
CREATE UNIQUE INDEX play_takes_chosen ON play_takes (production_id, line_id) WHERE chosen = 1;

-- The CC0 consent, per person per production, by the consent text's version
-- id. The words themselves are the owner's (Decision 059).
CREATE TABLE play_consents (
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  production_id  TEXT NOT NULL REFERENCES play_productions(id) ON DELETE CASCADE,
  version        TEXT NOT NULL,
  consented_at   INTEGER NOT NULL,
  PRIMARY KEY (user_id, production_id, version)
);

-- A report of a take or a member (App Store guideline 1.2). The reporter's row
-- goes with the reporter's account; a reported account's deletion clears
-- target_user_id and leaves the report's trail anonymous. production_id has
-- no foreign key, so the trail outlives the production.
CREATE TABLE play_reports (
  id              TEXT PRIMARY KEY,
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  production_id   TEXT NOT NULL,
  target_user_id  TEXT REFERENCES users(id) ON DELETE SET NULL,
  take_id         TEXT,
  reason          TEXT NOT NULL,
  note            TEXT NOT NULL DEFAULT '',
  created_at      INTEGER NOT NULL,
  status          TEXT NOT NULL DEFAULT 'open'
);
CREATE INDEX play_reports_user ON play_reports (user_id);
CREATE INDEX play_reports_target ON play_reports (target_user_id);
CREATE INDEX play_reports_production ON play_reports (production_id);

-- user_id hides blocked_id's takes from themselves, and blocked_id's invites
-- do not work for user_id (nor user_id's for blocked_id).
CREATE TABLE play_blocks (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id  TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, blocked_id)
);
CREATE INDEX play_blocks_blocked ON play_blocks (blocked_id);

-- The archive.org upload, queued only: no job runs until the Ear Drama
-- archive.org account exists (status 'pending_owner_account').
CREATE TABLE play_archive_jobs (
  production_id  TEXT PRIMARY KEY REFERENCES play_productions(id) ON DELETE CASCADE,
  user_id        TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status         TEXT NOT NULL,
  take_ids       TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX play_archive_jobs_user ON play_archive_jobs (user_id);

-- Teacher classes (Decision 059). under13 is fixed at creation; such a class
-- takes no student until play_school_consents holds its record.
CREATE TABLE play_classes (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  code        TEXT NOT NULL UNIQUE,
  under13     INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);
CREATE INDEX play_classes_user ON play_classes (user_id);

CREATE TABLE play_class_members (
  class_id      TEXT NOT NULL REFERENCES play_classes(id) ON DELETE CASCADE,
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL DEFAULT '',
  joined_at     INTEGER NOT NULL,
  PRIMARY KEY (class_id, user_id)
);
CREATE INDEX play_class_members_user ON play_class_members (user_id);

-- The school's consent for a class of students under 13, recorded by its
-- teacher against the privacy policy's version. A placeholder until that
-- policy exists: without SCHOOL_CONSENT_POLICY set, none can be recorded.
CREATE TABLE play_school_consents (
  class_id        TEXT PRIMARY KEY REFERENCES play_classes(id) ON DELETE CASCADE,
  user_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  policy_version  TEXT NOT NULL,
  reference       TEXT NOT NULL DEFAULT '',
  recorded_at     INTEGER NOT NULL
);
CREATE INDEX play_school_consents_user ON play_school_consents (user_id);

-- Take objects whose deletion from the bucket failed during an account
-- deletion; the hourly sweep retries them. A key names a production and a
-- take, never a person.
CREATE TABLE play_orphan_objects (
  object_key  TEXT PRIMARY KEY,
  queued_at   INTEGER NOT NULL
);
