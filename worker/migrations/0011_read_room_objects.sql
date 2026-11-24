-- Read rooms held in a Durable Object (Decision 082), by code alone, so the
-- hourly sweep can visit an object whose alarm was lost: Cloudflare drops an
-- alarm that fails its retries, and no object can be found without its code.
-- A row holds the code and when to look next; no name, no account, no key. It
-- goes once the object says it holds nothing. Times are milliseconds.

CREATE TABLE read_room_objects (
  code      TEXT PRIMARY KEY,
  check_at  INTEGER NOT NULL
);
CREATE INDEX read_room_objects_check ON read_room_objects (check_at);
