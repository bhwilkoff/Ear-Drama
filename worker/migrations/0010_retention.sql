-- Retention (Decision 084; owner 2026-11-21: "I don't mind deleting the info
-- about who recorded what, but we need to be able to keep the recorded Ear
-- Dramas in our database."). Who recorded what goes on a schedule; a submitted
-- production (it has an archive job) and its non-identifying fields stay.

-- A class ends on `ends_on` (the last day, 'YYYY-MM-DD'; by default the July 31
-- that closes the school year it was made in; its teacher may change it).
-- `touched_at` is the teacher's last use of the class; the sweep also reads its
-- productions' updated_at and its seats' claimed_at. `notice_at` is when the
-- idle notice began; activity after it clears it.
ALTER TABLE play_classes ADD COLUMN ends_on TEXT;
ALTER TABLE play_classes ADD COLUMN touched_at INTEGER;
ALTER TABLE play_classes ADD COLUMN notice_at INTEGER;
UPDATE play_classes SET touched_at = created_at WHERE touched_at IS NULL;
UPDATE play_classes SET ends_on = CASE
  WHEN CAST(strftime('%m', created_at / 1000, 'unixepoch') AS INTEGER) >= 8
    THEN printf('%04d-07-31', CAST(strftime('%Y', created_at / 1000, 'unixepoch') AS INTEGER) + 1)
  ELSE printf('%04d-07-31', CAST(strftime('%Y', created_at / 1000, 'unixepoch') AS INTEGER))
END WHERE ends_on IS NULL;
CREATE INDEX play_classes_ends ON play_classes (ends_on);

-- An account's last sign-in or refresh; after 3 idle years, and a 30-day
-- notice that any sign-in cancels, the account is deleted as if its owner had.
ALTER TABLE users ADD COLUMN seen_at INTEGER;
ALTER TABLE users ADD COLUMN idle_notice_at INTEGER;
UPDATE users SET seen_at = CAST(strftime('%s', 'now') AS INTEGER) * 1000 WHERE seen_at IS NULL;

-- A 13-and-over class's publish: the teacher confirmed that every performer
-- agreed, and that the school holds a media release for each performer under
-- 18 (owner 2026-11-21). The times they confirmed; no student is named.
ALTER TABLE play_archive_jobs ADD COLUMN performers_agreed_at INTEGER;
ALTER TABLE play_archive_jobs ADD COLUMN media_release_at INTEGER;
