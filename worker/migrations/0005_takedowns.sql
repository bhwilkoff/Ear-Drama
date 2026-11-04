-- Take-down cases (Decision 074). The ONLY place a requester's details exist:
-- the repository is public and carries a date and a case number. The cron
-- (sweepTakedowns) blanks the personal columns three years after a case
-- closes; the row and its outcome stay, so a public case number still resolves.
CREATE TABLE takedown_cases (
  ref          TEXT PRIMARY KEY,
  created_ms   INTEGER NOT NULL,
  closed_ms    INTEGER,
  status       TEXT NOT NULL,
  kind         TEXT NOT NULL,
  complete     INTEGER NOT NULL,
  source       TEXT NOT NULL,
  external_ref TEXT,
  links        TEXT NOT NULL,
  work         TEXT,
  reason       TEXT,
  verdict      TEXT,
  note         TEXT,
  name         TEXT,
  org          TEXT,
  email        TEXT,
  phone        TEXT,
  address      TEXT,
  signature    TEXT
);
CREATE INDEX takedown_status ON takedown_cases (status);
