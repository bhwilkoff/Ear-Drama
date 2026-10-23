-- Listen Together rooms (LOOP-PLAN M6), ported from Archive Watch's
-- schema-rooms.sql. A room says what an episode is doing, nothing about
-- people: no account, no name, no address. A member is a random id and the
-- SHA-256 of a random key, and both go when the member leaves or the room
-- ends. Times are milliseconds on the server's clock.

CREATE TABLE rooms (
  code         TEXT PRIMARY KEY,          -- six Crockford Base32 characters
  episode_id   TEXT NOT NULL,
  archive_id   TEXT NOT NULL,             -- the host's copy: an archive.org item
  file         TEXT NOT NULL,             -- and the file in it every guest plays
  position     REAL NOT NULL,             -- seconds, true at updated_at
  playing      INTEGER NOT NULL DEFAULT 0,
  rate         REAL NOT NULL DEFAULT 1,
  updated_at   INTEGER NOT NULL,          -- the server's clock when position was true
  generation   INTEGER NOT NULL DEFAULT 1,
  host_member  TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  touched_at   INTEGER NOT NULL           -- last state change or join; idle rooms expire
);
CREATE INDEX rooms_touched ON rooms (touched_at);

CREATE TABLE room_members (
  id         TEXT PRIMARY KEY,
  code       TEXT NOT NULL REFERENCES rooms(code) ON DELETE CASCADE,
  key_hash   TEXT NOT NULL UNIQUE,        -- SHA-256 of the member key; the key itself is never stored
  joined_at  INTEGER NOT NULL,
  seen_at    INTEGER NOT NULL
);
CREATE INDEX room_members_code ON room_members (code);
CREATE INDEX room_members_seen ON room_members (seen_at);
