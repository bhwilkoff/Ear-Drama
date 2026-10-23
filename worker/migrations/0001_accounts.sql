-- Accounts and sync (Decision 057). Every row that belongs to a person carries
-- user_id with ON DELETE CASCADE, and DELETE /v1/account also deletes from
-- each table by name, so deletion does not depend on one mechanism alone.
--
-- No email, name, or address is stored: a person is a provider and that
-- provider's opaque subject. Timestamps are milliseconds since 1970.

CREATE TABLE users (
  id          TEXT PRIMARY KEY,          -- random, ours; never a provider's id
  created_at  INTEGER NOT NULL
);

-- One person may have an Apple and a Google identity on one account later;
-- today each sign-in maps to exactly one user.
CREATE TABLE identities (
  provider    TEXT NOT NULL,             -- 'apple' | 'google'
  subject     TEXT NOT NULL,             -- the token's `sub`
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (provider, subject)
);
CREATE INDEX identities_user ON identities (user_id);

-- A refresh token is stored only as its SHA-256. `family` ties every rotation
-- of one sign-in together, so a replayed old token revokes the whole family.
CREATE TABLE sessions (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  family      TEXT NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  device      TEXT,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL,
  revoked     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX sessions_user ON sessions (user_id);
CREATE INDEX sessions_family ON sessions (family);
CREATE INDEX sessions_expires ON sessions (expires_at);

-- Listening history, one row per episode. Last write wins by updated_at (the
-- client's clock, clamped to the server's); changed_at is the server's clock
-- when the row was written, and is what GET /v1/sync?since= reads, so a late
-- upload with an old updated_at is still delivered. deleted = a tombstone.
CREATE TABLE history (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  episode_id  TEXT NOT NULL,
  position    REAL NOT NULL DEFAULT 0,   -- seconds
  duration    REAL,
  finished    INTEGER NOT NULL DEFAULT 0,
  deleted     INTEGER NOT NULL DEFAULT 0,
  updated_at  INTEGER NOT NULL,
  device      TEXT NOT NULL DEFAULT '',
  changed_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, episode_id)
);
CREATE INDEX history_changed ON history (user_id, changed_at);

-- Followed series. following = 0 is the tombstone for an unfollow.
CREATE TABLE follows (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  series_id   TEXT NOT NULL,
  following   INTEGER NOT NULL DEFAULT 1,
  updated_at  INTEGER NOT NULL,
  device      TEXT NOT NULL DEFAULT '',
  changed_at  INTEGER NOT NULL,
  PRIMARY KEY (user_id, series_id)
);
CREATE INDEX follows_changed ON follows (user_id, changed_at);

-- The queue is one ordered list, so it wins or loses as a whole: queue_meta
-- holds its updated_at, and its items are replaced together.
CREATE TABLE queue_meta (
  user_id     TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  updated_at  INTEGER NOT NULL,
  device      TEXT NOT NULL DEFAULT '',
  changed_at  INTEGER NOT NULL
);

CREATE TABLE queue (
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ord         INTEGER NOT NULL,
  episode_id  TEXT NOT NULL,
  PRIMARY KEY (user_id, ord)
);
