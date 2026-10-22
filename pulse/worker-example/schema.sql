-- OPTIONAL EXAMPLE: the whole storage of the Pulse Worker. A day, a shape,
-- a count. Nothing about who, from where, or when in the day.
CREATE TABLE IF NOT EXISTS views (
  day   TEXT NOT NULL,              -- YYYY-MM-DD (UTC)
  path  TEXT NOT NULL,              -- a SHAPE from a fixed set, or "(visit)"
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, path)
);

-- Tallies the server keeps while PROVIDING a feature (rooms opened, feed
-- sign-ins). Never a count an app sends.
CREATE TABLE IF NOT EXISTS tallies (
  day   TEXT NOT NULL,
  name  TEXT NOT NULL,              -- the tally, e.g. 'rooms'
  kind  TEXT NOT NULL,              -- e.g. 'room' | 'guest'
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, name, kind)
);

-- Vendor deliveries, stored RAW until the collector reads and acks them.
CREATE TABLE IF NOT EXISTS drops (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  vendor       TEXT NOT NULL,
  received     TEXT NOT NULL,
  content_type TEXT,
  bytes        INTEGER,
  body         TEXT                 -- '' when refused as too large
);
