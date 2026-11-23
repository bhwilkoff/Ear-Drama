"""tools/uitest_fixture.py: picks by shape from a small catalog, the same picks for the same seed, pins win.

    /usr/bin/python3 tools/test_uitest_fixture.py
"""
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import uitest_fixture as F  # noqa: E402

SCHEMA = """
CREATE TABLE series (key TEXT PRIMARY KEY, name TEXT NOT NULL, episodes INTEGER NOT NULL, picture INTEGER,
    about_text TEXT, star TEXT, network TEXT);
CREATE TABLE episodes (id TEXT PRIMARY KEY, series_key TEXT NOT NULL, air_date TEXT, title TEXT, length_s REAL,
    rights TEXT NOT NULL, no_recommend TEXT);
CREATE TABLE recordings (episode_id TEXT NOT NULL, rank INTEGER NOT NULL, length_s REAL, partial INTEGER NOT NULL
    DEFAULT 0, PRIMARY KEY (episode_id, rank));
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""


def build(path, n=6):
    db = sqlite3.connect(path)
    db.executescript(SCHEMA)
    db.execute("INSERT INTO meta VALUES ('generatedAt', '\"2026-11-23T00:00:00Z\"')")
    for i in range(n):
        db.execute("INSERT INTO series VALUES (?, ?, 60, 1, 'About.', 'Star', 'NBC')", (f"rich{i}", f"Rich Show {chr(65 + i)}"))
        db.execute("INSERT INTO series VALUES (?, ?, 3, NULL, NULL, NULL, NULL)", (f"bare{i}", f"Bare Show {chr(65 + i)}"))
        db.execute("INSERT INTO series VALUES (?, ?, 25, NULL, 'Words.', NULL, NULL)", (f"words{i}", f"Words Show {chr(65 + i)}"))
        db.execute("INSERT INTO series VALUES (?, ?, 1, NULL, NULL, NULL, NULL)", (f"lv{i}", "A Very Long Name " * 5))
        for j, (lo, tag) in enumerate([(1800, "long"), (120, "short")]):
            eid = f"rich{i}|19{50 + j}-01-0{i + 1}"
            db.execute("INSERT INTO episodes VALUES (?, ?, '1950-01-01', ?, ?, 'unclaimed', NULL)",
                       (eid, f"rich{i}", f"The {tag.title()} Night {chr(65 + i)}", lo))
            db.execute("INSERT INTO recordings VALUES (?, 0, ?, 0)", (eid, lo))
    # Shapes the picker must refuse: a duplicated title, digits, a hidden episode, a partial recording.
    for eid, title, extra in [("rich0|dup1", "Twice Told", ""), ("rich1|dup2", "Twice Told", ""),
                              ("rich2|num", "Episode Number Nine 9", ""), ("rich3|hid", "Hidden Away Here", "hide"),
                              ("rich4|part", "Partial Recording Only", "")]:
        db.execute("INSERT INTO episodes VALUES (?, ?, '1950-01-01', ?, 1800, 'unclaimed', ?)",
                   (eid, eid.split("|")[0], title, extra or None))
        db.execute("INSERT INTO recordings VALUES (?, 0, 1800, ?)", (eid, 1 if "part" in eid else 0))
    db.commit()
    db.close()


class PickTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.db = Path(cls.tmp.name) / "c.sqlite"
        build(cls.db)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_same_seed_same_picks(self):
        self.assertEqual(F.pick(self.db, 7), F.pick(self.db, 7))

    def test_seeds_vary_the_picks(self):
        picks = {json.dumps(F.pick(self.db, s), sort_keys=True) for s in range(12)}
        self.assertGreater(len(picks), 3, "a dozen seeds should not all pick the same shows")

    def test_shapes(self):
        db = sqlite3.connect(self.db)
        for seed in range(20):
            fx = F.pick(self.db, seed)
            length = db.execute("SELECT length_s FROM episodes WHERE id = ?", (fx["long"],)).fetchone()[0]
            self.assertTrue(1500 <= length <= 2100, fx)
            length = db.execute("SELECT length_s FROM episodes WHERE id = ?", (fx["short"],)).fetchone()[0]
            self.assertTrue(60 <= length <= 240, fx)
            self.assertNotIn(fx["longTitle"], ("Twice Told", "Episode Number Nine 9", "Hidden Away Here",
                                               "Partial Recording Only"))
            self.assertTrue(fx["rich"].startswith("rich"), fx)
            self.assertTrue(fx["bare"].startswith("bare"), fx)
            self.assertTrue(fx["noPicture"].startswith("words"), fx)
            self.assertTrue(fx["longName"].startswith("lv"), fx)
            self.assertEqual(fx["seriesName"], db.execute("SELECT name FROM series WHERE key = ?",
                                                          (fx["series"],)).fetchone()[0])
            self.assertEqual(len({fx["rich"], fx["bare"], fx["noPicture"], fx["longName"]}), 4)

    def test_pins_win_and_are_listed(self):
        fx = F.resolve(3, json.dumps({"short": "x|y", "shortTitle": "Pinned"}), self.db, env={})
        self.assertEqual((fx["short"], fx["shortTitle"]), ("x|y", "Pinned"))
        self.assertEqual(fx["pinned"], ["short", "shortTitle"])
        self.assertEqual(fx["long"], F.pick(self.db, 3)["long"])

    def test_seed_from_env_and_unknown_field_refused(self):
        self.assertEqual(F.resolve(None, None, self.db, env={"UITEST_FIXTURE_SEED": "5"})["seed"], 5)
        with self.assertRaises(SystemExit):
            F.resolve(1, json.dumps({"lng": "typo"}), self.db, env={})

    def test_describe_carries_seed_and_ids(self):
        fx = F.pick(self.db, 11)
        text = F.describe(fx)
        for key in ("long", "short", "rich", "bare", "noPicture", "longName"):
            self.assertIn(fx[key], text)
        self.assertIn("--fixture-seed 11", text)


if __name__ == "__main__":
    unittest.main()
