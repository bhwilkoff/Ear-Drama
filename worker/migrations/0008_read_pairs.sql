-- Pairing a TV to a read room (Decision 082, T5; tvOS-DESIGN §4.13): the TV
-- shows a short code, the leader types it on their own device, and the TV
-- joins that room as its screen. A row holds the code, the SHA-256 of the TV's
-- random key, and the room once a leader attached it; no account, no name, no
-- audio. A row lives 10 minutes and is used once; the hourly sweep deletes
-- expired rows. Times are milliseconds on the server's clock.

CREATE TABLE read_pairs (
  code        TEXT PRIMARY KEY,           -- six Crockford Base32 characters
  key_hash    TEXT NOT NULL,              -- SHA-256 of the TV's pair key
  room        TEXT,                       -- the read room's code, once attached
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX read_pairs_expires ON read_pairs (expires_at);
