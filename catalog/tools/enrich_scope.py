#!/usr/bin/env python3
"""POST-BUILD step: which series are outside Ear Drama's scope, only from evidence the records carry
(catalog DECISIONS 026; owner, 2026-10-31: "Drama and spoken story only"). Reads caches only (no network):
.cache/meta/<archive id>.json.gz for each series' items' own subject keywords. Adds ONLY its own table to
out/radio-catalog.sqlite, dropping and rebuilding it each run:

  series_scope   (series_key, kind, reason, evidence, items)
                 kind     concert | lecture | music
                 reason   the rule that fired (one of REASONS)
                 evidence JSON: the words, collections and counts the rule read

The series stays in the research database; build_projection.py withholds it from the apps as
`out_of_scope_<kind>`. A program a registry names (OTRR, RadioEchoes, the editorial spine), a LibriVox
project, a series with a drama genre (its own label or its own keywords) and a series on the reviewed keep
list (editorial/scope_review.json, each with a reason) are never classified: golden-age variety, music
variety and news programs are named by the registries, and stay.

SPEECHES ARE IN SCOPE (owner, 2026-10-31, "Keep them"): historical speeches and wartime addresses (Churchill's broadcasts,
FDR, Truman, Lindbergh, Nimitz, the Hitler speeches) are the spoken word of radio's golden age. No rule here may withhold a
series or an episode for being a speech or an address (DECISIONS 027). Nazi-state recordings keep their existing
`no_recommend` (never recommended, always findable).

Run: python3 tools/enrich_scope.py
"""
import collections
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ia_lib as L
import genres as G
import enrich_genres as EG
import audit_audio_rights as A

DB = os.path.join(L.OUT, "radio-catalog.sqlite")
if "--db" in sys.argv:
    DB = sys.argv[sys.argv.index("--db") + 1]
REVIEW = os.path.join(L.EDITORIAL, "scope_review.json")
REPORT = os.path.join(L.OUT, "enrich_scope_report.json")
SERVED = ("keep_clean", "keep_unclaimed")

CONCERT_NAME = re.compile(r"\b(?:concerts?|recitals?)\b", re.I)
LECTURE_NAME = re.compile(r"\b(?:lectures?|symposium|symposia|colloquium|convocation)\b", re.I)
MUSIC_NAME = re.compile(r"\b(?:orchestra|quartet|quintet|chorus|choir|chorale|band|symphony|ensemble|jazz|bluegrass)\b", re.I)
LIVE_NAME = re.compile(r"\blive\b", re.I)
# A band remote is a dance band playing from a hotel ballroom: file names "Remote-DukeEllington", series "Remote Dukeellington".
REMOTE_NAME = re.compile(r"^(?:band[\s-]+)?remotes?(?:[\s-]+\S.*)?$", re.I)
HUMP_NAME = re.compile(r"(?<=[a-z])(?=[A-Z][a-z]{3,})")
SPOKEN_NAME = re.compile(r"\b(?:dramatic reading|reading|readings|poems?|poetry|poets?|drama|play|plays|theat(?:er|re)|story|stories|"
                         r"mystery|adventure|sherlock|holmes)\b", re.I)
MUSIC_SUBJECTS = {"music", "jazz", "big band", "dance band", "swing", "country music", "bluegrass", "folk music",
                  "classical music", "opera", "concert", "concerts", "orchestra", "symphony", "choir", "chorus",
                  "gospel music", "blues", "songs", "yodeling", "dobro", "banjo", "fiddle", "piano", "band music",
                  "marching band", "hillbilly", "country", "folk", "popular music", "vocal music"}
MUSIC_COLLECTIONS = {"audio_music", "78rpm", "etree", "georgeblood", "netlabels", "folksoundomy_music", "audio_music"}
LECTURE_SUBJECTS = {"lecture", "lectures", "public lectures", "speeches", "symposium"}
SHARE = 0.6
REASONS = ("name_names_a_concert", "name_names_a_lecture", "episodes_are_lectures", "music_in_its_own_keywords",
           "live_set_by_one_performer", "name_names_a_band_remote", "name_names_a_music_group",
           "name_names_a_game_broadcast", "name_names_v_discs", "music_show_in_its_own_keywords")
# P-12 (DECISIONS 033): a game's play-by-play is neither drama nor a spoken story, whoever names the series. A sport and
# a broadcast word ("Classic Baseball on the Radio", "Baseball Games", "State High School Basketball Championship
# Game"), a sporting event's own name ("World Series", "Kentucky Derby Broadcasts"), or a sport alone ("Boxing"). A
# sports talk or story show ("Bill Stern Sports Newsreel", "Red Grange Football Show") names no game and stays.
SPORT = r"(?:baseball|football|basketball|hockey|boxing|softball|soccer|wrestling|prize ?fights?)"
GAME = r"(?:games?|broadcasts?|on the radio|play[- ]by[- ]play|championships?|tournaments?|vs\.?)"
SPORT_GAME = re.compile(r"\b" + SPORT + r"\b.*\b" + GAME + r"(?!\w)|\b" + GAME + r"\b.*\b" + SPORT + r"\b", re.I)
SPORT_EVENT = re.compile(r"^(?:the\s+)?(?:\d{4}\s+)?(?:world series|kentucky derby|rose bowl|sugar bowl|orange bowl|"
                         r"cotton bowl|all[- ]star game|indianapolis 500|indy 500)(?:\s+(?:broadcasts?|games?|game \d+|"
                         r"\d{4}))*(?:\s*[-–:].*\bvs\b.*)?$", re.I)
SPORT_ONLY = re.compile(r"^(?:the\s+)?" + SPORT + r"$", re.I)
V_DISC = re.compile(r"\bV[- ]?Discs?\b", re.I)
RE_STORY = {"OTR-Drama", "OTR-Adventure", "OTR-Detective", "OTR-Thriller", "OTR-Mystery", "OTR-SciFi", "OTR-Western",
            "OTR-Comedy", "OTR-Soap", "OTR-Kids"}


def sports(name):
    """The scope reason when the series' name names a game broadcast, else None."""
    n = (name or "").strip()
    if SPOKEN_NAME.search(n):
        return None
    if SPORT_GAME.search(n) or SPORT_EVENT.match(n) or SPORT_ONLY.match(n):
        return "name_names_a_game_broadcast"
    return None


def music_show(story, eps, music_eps):
    """A registry program that is a music show (006: built on songs, hidden, stricter than drama): no story genre in
    its registry labels, and SHARE of its served episodes from items of its own whose subject keywords name music."""
    return not story and eps >= 3 and music_eps >= SHARE * eps


def classify(name, items, kinds, drama_items, music_hits, lecture_hits, music_colls, performers=None):
    """(kind, reason, evidence) or None. `items`: items read; `kinds`: {content_kind: episodes};
    `drama_items`: items whose own keywords name a spoken genre; `music_hits`, `lecture_hits`,
    `music_colls`: items carrying a music keyword / lecture keyword / music collection; `performers`: the
    ID3 artists on the series' files (one name on every file, with "live" in the series' name, is a live set)."""
    broken = bool(HUMP_NAME.search(name or ""))
    name = HUMP_NAME.sub(" ", name or "")
    if SPOKEN_NAME.search(name or "") and not (CONCERT_NAME.search(name) or LECTURE_NAME.search(name)):
        return None
    if REMOTE_NAME.match(name.strip()) and not (items and drama_items * 2 >= items):
        return "music", "name_names_a_band_remote", {"name": name.strip()}
    if items and drama_items * 2 >= items:
        return None
    n_eps = sum(kinds.values())
    if CONCERT_NAME.search(name or "") and not SPOKEN_NAME.search(name):
        return "concert", "name_names_a_concert", {"name": CONCERT_NAME.search(name).group(0).lower()}
    if LECTURE_NAME.search(name or "") and not SPOKEN_NAME.search(name):
        return "lecture", "name_names_a_lecture", {"name": LECTURE_NAME.search(name).group(0).lower()}
    if LIVE_NAME.search(name or "") and performers is not None and len(performers) == 1:
        return "concert", "live_set_by_one_performer", {"name": "live", "artist": sorted(performers)[0]}
    if n_eps and kinds.get("lecture", 0) >= SHARE * n_eps:
        return "lecture", "episodes_are_lectures", {"content_kind lecture": kinds["lecture"], "episodes": n_eps}
    if broken and MUSIC_NAME.search(name) and not (items and drama_items * 2 >= items):
        return "music", "name_names_a_music_group", {"name": name.strip(), "why": "a name with its words run together has no keywords to read"}
    if items and (music_hits >= SHARE * items or (MUSIC_NAME.search(name or "") and (music_hits or music_colls) and
                                                  max(music_hits, music_colls) >= SHARE * items)):
        return "music", "music_in_its_own_keywords", {"items": items, "keyword items": music_hits, "music collection items": music_colls}
    return None


def run(con):
    review = L.read_json(REVIEW) if os.path.exists(REVIEW) else {}
    keep = {k: v for k, v in (review.get("keep") or {}).items() if not k.startswith("_")}
    series = {}
    for key, name, spine, otrr, lv, genre, genres_otrr in con.execute(
            "SELECT key, name, in_spine, otrr_programs, is_librivox, genre, genres_otrr FROM series"):
        labels = json.loads(genres_otrr) if genres_otrr else []
        series[key] = dict(name=name, named=bool(spine or otrr or lv), librivox=bool(lv), genre=G.genre_of(
            labels or None, genre, bool(lv))[0],
            story=bool(set(labels) & A.STORY_GENRES) or bool(set((genre or "").split("|")) & RE_STORY))
    q = ",".join("?" * len(SERVED))
    kinds = collections.defaultdict(collections.Counter)
    files = collections.defaultdict(lambda: collections.defaultdict(set))
    colls = {}
    shared = collections.defaultdict(set)
    for key, kind, aid, f, c in con.execute(
            f"SELECT e.series_key, e.content_kind, r.archive_id, r.file, i.collections FROM episodes e JOIN recordings r "
            f"ON r.episode_id = e.id AND r.rank = 0 LEFT JOIN items i ON i.id = r.archive_id WHERE e.state IN ({q})", SERVED):
        kinds[key][kind or "radio"] += 1
        files[key][aid].add(f)
        colls[aid] = set(json.loads(c or "[]"))
        shared[aid].add(key)
    rows, stats = [], collections.Counter()
    cache, artists_of, subjects_of = {}, {}, {}
    for key in sorted(files):
        s = series.get(key)
        if s is None:
            continue
        stats["served series"] += 1
        if key in keep:
            stats["kept by the reviewed list"] += 1
            continue
        why = None if s["librivox"] else sports(s["name"])
        if why:
            rows.append((key, "sports", why, json.dumps({"name": s["name"]}, ensure_ascii=False), 0))
            stats["sports"] += 1
            continue
        if not s["librivox"] and V_DISC.search(s["name"] or ""):
            rows.append((key, "music", "name_names_v_discs", json.dumps({"name": s["name"]}, ensure_ascii=False), 0))
            stats["music"] += 1
            continue
        if s["named"] and not s["librivox"]:
            n_eps = sum(len(v) for v in files[key].values())
            m_eps = 0
            for aid in sorted(files[key]):
                if len(shared[aid]) > 1:
                    continue
                if aid not in subjects_of:
                    rec = EG.item_record(aid, files[key][aid])
                    subjects_of[aid] = set(t.lower() for t in rec[0]) if rec else set()
                if subjects_of[aid] & MUSIC_SUBJECTS:
                    m_eps += len(files[key][aid])
            if music_show(s["story"], n_eps, m_eps):
                rows.append((key, "music", "music_show_in_its_own_keywords",
                             json.dumps({"episodes": n_eps, "music keyword episodes": m_eps},
                                        ensure_ascii=False, sort_keys=True), len(files[key])))
                stats["music"] += 1
                continue
        if s["named"] or s["genre"]:
            stats["named by a registry or a genre label"] += 1
            continue
        items = music = lecture = drama = mcoll = 0
        artists, tagged = set(), True
        for aid in sorted(files[key]):
            if len(shared[aid]) > 1:
                continue   # a compilation's keywords belong to the item, not to any program in it
            if aid not in cache:
                rec = EG.item_record(aid, files[key][aid])
                cache[aid] = None if rec is None else (set(t.lower() for t in rec[0]), G.item_genres(*rec))
            if cache[aid] is None:
                continue
            if aid not in artists_of:
                artists_of[aid] = EG.L.read_json(EG.META + "/" + aid + ".json.gz").get("files") or []
            for f in artists_of[aid]:
                if f.get("name") in files[key][aid]:
                    if f.get("artist"):
                        artists.add(str(f["artist"]).strip())
                    else:
                        tagged = False
            subj, genres = cache[aid]
            items += 1
            music += bool(subj & MUSIC_SUBJECTS)
            lecture += bool(subj & LECTURE_SUBJECTS)
            drama += bool(genres)
            mcoll += bool(colls.get(aid, set()) & MUSIC_COLLECTIONS)
        got = classify(s["name"], items, kinds[key], drama, music, lecture, mcoll, artists if tagged and items else None,
)
        if got:
            rows.append((key, got[0], got[1], json.dumps(got[2], ensure_ascii=False, sort_keys=True), items))
            stats[got[0]] += 1
    return rows, stats


def main():
    con = sqlite3.connect(DB)
    rows, stats = run(con)
    con.executescript("DROP TABLE IF EXISTS series_scope; CREATE TABLE series_scope ("
                      "series_key TEXT PRIMARY KEY, kind TEXT NOT NULL, reason TEXT NOT NULL, "
                      "evidence TEXT NOT NULL, items INTEGER NOT NULL)")
    con.executemany("INSERT INTO series_scope VALUES (?,?,?,?,?)", rows)
    con.commit()
    report = {"servedSeries": stats["served series"], "outOfScope": len(rows),
              "byKind": {k: stats[k] for k in ("concert", "lecture", "music", "sports")},
              "keptByReview": stats["kept by the reviewed list"], "keptNamedByRegistry": stats["named by a registry or a genre label"]}
    L.write_json(REPORT, report)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
