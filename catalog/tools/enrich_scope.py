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
import display_text as DT
import genres as G
import enrich_genres as EG

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
# A speech named as one. "Address Unknown" and "to address us" are titles, not addresses.
SPEECH_NAME = re.compile(r"\b(?:speech(?:es)?|addresses|address(?!\s+(?:unknown|us|the\s+(?:problem|issue)))|rede|reden|ansprache|"
                         r"fireside\s+chats?|inaugural\s+address|oration|sermons?)\b", re.I)
HUMP_NAME = re.compile(r"(?<=[a-z])(?=[A-Z][a-z]{3,})")
SPOKEN_NAME = re.compile(r"\b(?:dramatic reading|reading|readings|poems?|poetry|poets?|drama|play|plays|theat(?:er|re)|story|stories|"
                         r"mystery|adventure|sherlock|holmes)\b", re.I)
SPEECH_SHARE = 0.6
MUSIC_SUBJECTS = {"music", "jazz", "big band", "dance band", "swing", "country music", "bluegrass", "folk music",
                  "classical music", "opera", "concert", "concerts", "orchestra", "symphony", "choir", "chorus",
                  "gospel music", "blues", "songs", "yodeling", "dobro", "banjo", "fiddle", "piano", "band music",
                  "marching band", "hillbilly", "country", "folk", "popular music", "vocal music"}
MUSIC_COLLECTIONS = {"audio_music", "78rpm", "etree", "georgeblood", "netlabels", "folksoundomy_music", "audio_music"}
LECTURE_SUBJECTS = {"lecture", "lectures", "public lectures", "speeches", "symposium"}
SHARE = 0.6
REASONS = ("name_names_a_concert", "name_names_a_lecture", "episodes_are_lectures", "music_in_its_own_keywords",
           "live_set_by_one_performer", "name_names_a_band_remote", "name_names_a_music_group", "name_names_a_speech",
           "episodes_are_speeches", "some_episodes_are_speeches")


def classify(name, items, kinds, drama_items, music_hits, lecture_hits, music_colls, performers=None, titles=()):
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
    if SPEECH_NAME.search(name) and not (items and drama_items * 2 >= items):
        return "speech", "name_names_a_speech", {"name": SPEECH_NAME.search(name).group(0).lower()}
    if titles and len(titles) >= 3 and not (items and drama_items * 2 >= items):
        n_speech = sum(bool(DT.SPEECH_TITLE.search(t or "")) for t in titles)
        if n_speech >= SPEECH_SHARE * len(titles):
            return "speech", "episodes_are_speeches", {"titles": len(titles), "speech titles": n_speech}
        if len(titles) >= 5 and n_speech >= 0.3 * len(titles):
            return "speech_episodes", "some_episodes_are_speeches", {"titles": len(titles), "speech titles": n_speech}
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
        series[key] = dict(name=name, named=bool(spine or otrr or lv), librivox=bool(lv), genre=G.genre_of(
            json.loads(genres_otrr) if genres_otrr else None, genre, bool(lv))[0])
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
    title_of = collections.defaultdict(list)
    for key, title in con.execute(f"SELECT series_key, title FROM episodes WHERE state IN ({q})", SERVED):
        title_of[key].append(title)
    rows, stats = [], collections.Counter()
    cache, artists_of = {}, {}
    for key in sorted(files):
        s = series.get(key)
        if s is None:
            continue
        stats["served series"] += 1
        if key in keep:
            stats["kept by the reviewed list"] += 1
            continue
        if s["named"] or s["genre"]:
            # A speech is out of scope even when a registry files it as a program (owner, 2026-10-31); a drama genre,
            # a LibriVox reading and a golden-age news program (no speech word in its name or its titles) stay.
            if not s["librivox"] and s["genre"] in (None, "documentary", "news"):
                got = classify(s["name"], 0, kinds[key], 0, 0, 0, 0, None, title_of.get(key, ()))
                if got and got[0].startswith("speech"):
                    rows.append((key, got[0], got[1], json.dumps(dict(got[2], named=s["named"]), ensure_ascii=False, sort_keys=True), 0))
                    stats[got[0]] += 1
                    continue
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
                       title_of.get(key, ()))
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
              "byKind": {k: stats[k] for k in ("concert", "lecture", "music", "speech", "speech_episodes")},
              "keptByReview": stats["kept by the reviewed list"], "keptNamedByRegistry": stats["named by a registry or a genre label"]}
    L.write_json(REPORT, report)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
