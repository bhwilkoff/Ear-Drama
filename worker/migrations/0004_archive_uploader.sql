-- The archive.org uploader (LOOP-PLAN P14, Decision 073). A job runs from the
-- cron once both IA_S3_ACCESS_KEY and IA_S3_SECRET_KEY are set; its status is
-- queued, uploading, published (item_url set), or failed (reason set).
-- attempts counts consecutive transient failures; next_attempt_at is the
-- backoff; lease_until keeps two runs off one job.
ALTER TABLE play_archive_jobs ADD COLUMN identifier TEXT;
ALTER TABLE play_archive_jobs ADD COLUMN item_url TEXT;
ALTER TABLE play_archive_jobs ADD COLUMN reason TEXT;
ALTER TABLE play_archive_jobs ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE play_archive_jobs ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0;
ALTER TABLE play_archive_jobs ADD COLUMN lease_until INTEGER NOT NULL DEFAULT 0;
ALTER TABLE play_archive_jobs ADD COLUMN credits TEXT;
ALTER TABLE play_archive_jobs ADD COLUMN published_at INTEGER;

-- Jobs queued before the uploader existed wait at the old status; they are queued.
UPDATE play_archive_jobs SET status = 'queued' WHERE status = 'pending_owner_account';

-- One row per line of a published production: the file it is on the item.
-- state: pending (to PUT), sent (on the item), remove (to DELETE), removed,
-- failed (archive.org refused a change; reason says why). stale_name is an
-- earlier name of this line's file (a replacement in another format) still to
-- delete. removed_by is 'performer' or 'director'. No column names a person:
-- the take row says whose it is, so account deletion needs nothing here.
CREATE TABLE play_archive_files (
  production_id  TEXT NOT NULL REFERENCES play_archive_jobs(production_id) ON DELETE CASCADE,
  line_id        TEXT NOT NULL,
  seq            INTEGER NOT NULL,
  part           TEXT NOT NULL,
  take_id        TEXT NOT NULL,
  name           TEXT NOT NULL,
  state          TEXT NOT NULL,
  stale_name     TEXT,
  removed_by     TEXT,
  reason         TEXT,
  updated_at     INTEGER NOT NULL,
  PRIMARY KEY (production_id, line_id)
);
CREATE INDEX play_archive_files_state ON play_archive_files (production_id, state);
