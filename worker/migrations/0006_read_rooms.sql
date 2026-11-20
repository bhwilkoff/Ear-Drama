-- Read rooms carried by D1 polling (Decision 082): the fallback transport for
-- a Worker without the ReadRoom Durable Object binding. A room with a socket
-- lives in its Durable Object and never touches this table. Rows hold a place
-- in a script and anonymous members (a random id and the SHA-256 of a random
-- key); no account, no name, no audio. Deleted when the room ends or after 6
-- idle hours by the hourly sweep. Times are milliseconds on the server's clock.

CREATE TABLE read_rooms (
  code        TEXT PRIMARY KEY,           -- six Crockford Base32 characters
  cast_sheet  TEXT NOT NULL,              -- [[line id, part], ...], written once
  room        TEXT NOT NULL,              -- read-protocol.js room state, JSON
  members     TEXT NOT NULL,              -- members with key hashes, JSON
  version     INTEGER NOT NULL DEFAULT 1, -- optimistic concurrency: first claim wins
  touched_at  INTEGER NOT NULL
);
CREATE INDEX read_rooms_touched ON read_rooms (touched_at);
