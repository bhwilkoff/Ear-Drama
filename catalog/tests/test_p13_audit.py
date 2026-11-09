"""P-13 (catalog DECISIONS 036): what 035 left open, each decided by a rule we already had, guarded over a real build.

    python3 tests/test_p13_audit.py
    PROJECTION=out/publish/ear-drama.sqlite SOURCE=out/radio-catalog.sqlite python3 tests/test_p13_audit.py

1. A non-US production is hidden (006) on the evidence RadioGOLDINdex's Source gives: the originator it names
   ("BBC origination, NBC net rebroadcast", "Grace Gibson syndication (Australia)"), never a carrier's copy, and
   never when a US party is named with it ("NBC net origination, CBC rebroadcast" and "transcribed in London for
   NBC" stay US). A run of a program's records that is mostly non-US is one production.
2. An undated episode whose own title or file name carries a date note ("The Viennese Strangler (04-09-45)") is
   dated from it, by the parser's conventions, and the title loses the note (025).

The guards over a real build never pin a row; each asks whether the build serves something a rule withholds:
  - an episode the GOLDINdex origination reading hides (episode, run, or series);
  - an undated episode whose own title or file name carries a date note the build would read;
  - an episode whose title still carries a note restating its own date.
Seen failing on the 2026-11-09 dry-run artifacts of the unchanged tools (counts in DECISIONS 036).
"""
import gzip
import json
import os
import sqlite3
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import audit_audio_rights as A
import display_text as DT
import otr_parse as P

ran = failed = 0


def check(name, got, want):
    global ran, failed
    ran += 1
    if got != want:
        failed += 1
        print(f"FAIL {name}: got {got!r}, want {want!r}")


# ---- fixtures: who originated a broadcast (006, 001) ----
for src, want in (
        ("BBC origination, NBC net rebroadcast", ("non-US", True)),
        ("BBC Light Programme origination, WETA-FM, Washington,D.C. rebroadcast", ("non-US", True)),
        ("Grace Gibson syndication (Australia), 2UW, Sydney data", ("non-US", False)),
        ("Springbok Radio (South Africa), AFRTS rebroadcast", ("non-US", False)),
        ("CBC net, Toronto origination", ("non-US", False)),
        ("South African Broadcasting Corporation", ("non-US", False)),
        ("ABC Radio (Australia)", ("non-US", False)),
        ("Radio New Zealand", ("non-US", False)),
        ("BBC", ("non-US", False)),
        ("NBC net", ("US", False)),
        ("CBS net origination, AFRTS rebroadcast", ("US", True))):
    check(f"origin: {src}", A.goldin_origin(src)[0::2], want)
for src, want in (
        ("NBC net origination, CBC rebroadcast", "US"),          # a BBC or CBC rebroadcast note on a US broadcast
        ("NBC net, BBC rebroadcast", "US"),
        ("CBS net origination for the BBC", "US"),               # made FOR the BBC by a US network
        ("transcribed in London for NBC", "US"),
        ("NBC Blue net, Montreal origination", "US"),           # a city is not a producer
        ("ABC net", "US"),                                      # the American ABC, not Australia's
        ("BBC/CBS co-production", None),                        # a US co-producer: joint
        ("BBC origination for Mutual", None),                   # made for a US network: joint
        ("NBC net, Towers Of London syndication", None),
        ("Mutual net, CBC, Toronto origination", None),
        ("CFCF, Montreal aircheck", None),                      # the station a copy was taken from
        ("UNESCO Radio, Paris origination", None),
        ("William F. Holland Productions syndication", None),
        ("Bundles For Britain Committee syndication", None),
        ("BBC-TV, Audio + Video", None),
        ("", None), ("*", None)):
    check(f"control: origin: {src}", A.goldin_origin(src)[0], want)


def rec(cat, ep, date, prog, source, series="sh", title=None):
    return {"cat": cat, "episode": ep, "date": date, "program": prog, "source": source, "keys": [series],
            "title": title}


# One series holding a US production (1939-47) and a BBC one (1955): the run is one production.
recs = [rec(1, "e39", "1939-10-02", "Adv", "NBC net"), rec(2, "e40", "1940-01-01", "Adv", "NBC net"),
        rec(3, "e55a", "1955-01-02", "Adv", "BBC origination, NBC net rebroadcast", title="The Red Circle"),
        rec(4, "e55b", "1955-01-09", "Adv", "BBC origination, NBC net rebroadcast"),
        rec(5, "e55c", "1955-01-16", "Adv", "NBC net"),
        rec(6, None, "1955-01-23", "Adv", "BBC origination, NBC net rebroadcast", title="Silver Blaze"),
        rec(7, "e55e", "1955-02-06", "Guest Star", "NBC net origination, CBC rebroadcast")]
eps = [("e39", "sh", "1939-10-02", "A"), ("e40", "sh", "1940-01-01", "B"), ("e55a", "sh", "1955-01-02", "C"),
       ("e55b", "sh", "1955-01-09", "D"), ("e55c", "sh", "1955-01-16", "E"), ("e55d", "sh", "1955-01-20", "F"),
       ("e55e", "sh", "1955-02-06", "G"), ("u1", "sh", None, "Silver Blaze"), ("u2", "sh", None, "Unknown Title")]
by_ep, by_series = A.goldin_productions(recs, eps)
check("its own record names the BBC", by_ep.get("e55a", {}).get("how"), "episode")
check("the run holds a copy recorded off NBC", by_ep.get("e55c", {}).get("how"), "run")
check("the run holds an episode with no record", by_ep.get("e55d", {}).get("how"), "run")
check("an undated episode whose title aired only inside the run", by_ep.get("u1", {}).get("placed"),
      "by its title's nights")
check("control: an episode whose own record names a US origin for another program", "e55e" in by_ep, False)
check("control: the US production's episodes", sorted(e for e in by_ep if e in ("e39", "e40")), [])
check("control: an undated title no record dates", "u2" in by_ep, False)
check("control: a mixed series is not hidden whole", by_series, {})
one = [rec(1, "x1", "1955-01-02", "Adv", "BBC origination, NBC net rebroadcast")]
check("control: one non-US record is not a run", sorted(A.goldin_productions(one, [("x1", "sh", "1955-01-02", "C"),
      ("x2", "sh", "1955-01-09", "D")])[0]), ["x1"])
bbc = [rec(i, f"b{i}", f"1960-0{i}-01", "Play", "BBC Home Service", series="bb") for i in range(1, 4)]
bbc_eps = [(f"b{i}", "bb", f"1960-0{i}-01", "T") for i in range(1, 4)]
check("a series whose records name a non-US origin", sorted(A.goldin_productions(bbc, bbc_eps)[1]), ["bb"])
check("control: a carrier's copy of a series a registry vouches for as American",
      A.goldin_productions(bbc, bbc_eps, us_series={"bb"}), ({}, {}))
expl = [rec(1, "j1", "1960-01-01", "Benny", "BBC origination, BBC Transcription Service syndication", series="jb")]
check("an explicit origination counts in a vouched series",
      sorted(A.goldin_productions(expl, [("j1", "jb", "1960-01-01", "T")], {"jb"})[0]), ["j1"])
alt = [rec(1, "t1", "1944-01-02", "Call", "CBS net, BBC origination", series="tc"),
       rec(2, "t2", "1944-01-09", "Call", "CBS net, BBC origination", series="tc"),
       rec(3, "t3", "1944-01-16", "Call", "CBS net origination", series="tc")]
got = A.goldin_productions(alt, [("t1", "tc", "1944-01-02", "A"), ("t4", "tc", "1944-01-23", "B")])[0]
check("control: a program whose weeks alternate originations is not one production", sorted(got), ["t1"])
axis = [rec(i, f"h{i}", f"1940-0{i}-01", "Lord Haw Haw", "Reichssender Hamburg, DXB (31 meters), Bremen", series="hh")
        for i in range(1, 4)]
check("control: the Axis states' wartime radio is propaganda, findable (006)",
      A.goldin_productions(axis, [(f"h{i}", "hh", f"1940-0{i}-01", "T") for i in range(1, 4)]), ({}, {}))
post = [rec(1, "g1", "1962-01-01", "Hoerspiel", "NDR, Germany", series="gg")]
check("a German production after the war", sorted(A.goldin_productions(post, [("g1", "gg", "1962-01-01", "T")])[0]), ["g1"])
night = [rec(1, "a1", "1955-01-02", "The Adventures Of Sherlock Holmes", "BBC origination, NBC net rebroadcast", series="adv"),
         rec(2, "a2", "1955-01-09", "The Adventures Of Sherlock Holmes", "BBC origination, NBC net rebroadcast", series="adv")]
cb = [("c1", "casebook", "1955-01-02", "Milverton"), ("c2", "casebook", "1955-01-05", "Red-Headed League"),
      ("c3", "casebook", "1947-01-16", "Other")]
got = A.goldin_productions(night, cb, named_by=lambda p: {"casebook"} if "Sherlock Holmes" in p else set())[0]
check("a record of the same night naming the series witnesses its broadcast", got.get("c1", {}).get("how"), "episode")
check("a run of a program naming the series holds its episodes inside it", got.get("c2", {}).get("how"), "run")
check("control: outside the run", "c3" in got, False)
check("control: a program that does not name the series", A.goldin_productions(night, cb)[0], {})

# ---- fixtures: date notes (036; the parser's conventions; 032's notes) ----
for t, want in (("The Viennese Strangler (04-09-45)", ("1945-04-09", "The Viennese Strangler")),
                ("Passenger to Bali (11-13-1938)", ("1938-11-13", "Passenger to Bali")),
                ("The Old Man (04-07-1945)", ("1945-04-07", "The Old Man")),     # month-day, the catalog's order
                ("Barry Gray 49-10-07", ("1949-10-07", "Barry Gray")),           # YY-MM-DD
                ("Father Coughlin 38-11-20 (fixed)", ("1938-11-20", "Father Coughlin (fixed)")),
                ("Philco Radio Time (02-09-1949) (Guests - Groucho Marx)", ("1949-02-09", "Philco Radio Time (Guests - Groucho Marx)")),
                ("Show [1945-04-09]", ("1945-04-09", "Show"))):
    check(f"note: {t}", P.title_date_note(t), want)
for t in ("X (19-07-45)",                                   # day-month with a two-digit year: not guessed
          "Show (1985-04-03)",                              # a bracketed date is never read as a modern one
          "Money [Rpt 1966-10-16]",                         # a bracket with words is a note on the copy
          "Navy Lark 1966-10-16 [1966-10-17]",              # two dates: which is the broadcast is not known
          "The Big Broadcast 09 24 06", "Clearing the Static 12-20-15", "Episode 12-3", "The 1-2-3 Show",
          "Aspects of the Fringe Tx 1.9.81", "01-13-57"):          # a name that is only a date notes no title
    check(f"control: note: {t}", P.title_date_note(t), (None, t))
check("control: upload-day digits", P.is_upload_stamp(P.title_date_note("Talk (9-25-21)")[0], "2021-09-25"), True)

# ---- the guards over a real build ----
real = os.environ.get("PROJECTION") or os.path.join(os.path.dirname(__file__), "..", "out", "publish", "ear-drama.sqlite")
src_db = os.environ.get("SOURCE") or os.path.join(os.path.dirname(__file__), "..", "out", "radio-catalog.sqlite")
if os.path.exists(real) and os.path.exists(src_db):
    d = sqlite3.connect(f"file:{real}?mode=ro", uri=True)
    s = sqlite3.connect(f"file:{src_db}?mode=ro", uri=True)
    names = dict(d.execute("SELECT key, name FROM series"))
    served = {e: (sk, a, t) for e, sk, a, t in d.execute("SELECT id, series_key, air_date, title FROM episodes")}
    librivox = {k for (k,) in s.execute("SELECT key FROM series WHERE is_librivox = 1")}
    raw = {}
    for eid, sk, a, t, f, aid, pub in s.execute(
            "SELECT e.id, e.series_key, e.air_date, e.title, r.file, r.archive_id, i.publicdate FROM episodes e "
            "JOIN recordings r ON r.episode_id = e.id AND r.rank = 0 LEFT JOIN items i ON i.id = r.archive_id"):
        raw[eid] = (sk, a, t, f or "", aid, pub)
    meta = os.path.join(os.path.dirname(os.path.abspath(src_db)), "..", ".cache", "meta")
    itext = {}
    for aid in sorted({raw[e][4] for e in served if e in raw}):
        p = os.path.join(meta, aid + ".json.gz")
        if os.path.exists(p):
            it = json.load(gzip.open(p)).get("item") or {}
            itext[aid] = " ".join(str(it.get(k) or "") for k in ("title", "description", "subject", "creator",
                                                              "publisher", "contributor", "source", "notes"))
    us = set()
    pedia = os.path.join(os.path.dirname(os.path.abspath(src_db)), "..", ".cache", "otrrpedia", "progPedia.json.gz")
    if os.path.exists(pedia) and "otrr_idp" in {r[1] for r in s.execute("PRAGMA table_info(series)")}:
        keys_of = {}
        for k, idps in s.execute("SELECT key, otrr_idp FROM series WHERE otrr_idp IS NOT NULL"):
            for i in idps.split(","):
                keys_of.setdefault(i, []).append(k)
        us = A.us_series_keys(json.load(gzip.open(pedia)), lambda p: keys_of.get(p.get("idp"), []))
    pkeys = {}
    for prog, k in s.execute("SELECT program, series_key FROM series_map WHERE source = 'goldin'"):
        pkeys.setdefault(prog, set()).add(k)
    recs = [{"cat": c, "keys": sorted(pkeys.get(p, ())), "episode": e, "date": a, "program": p, "title": t,
             "source": src} for c, e, a, p, t, src in s.execute(
                "SELECT catalognum, episode_id, air_date, program, title, source_text FROM goldin_records "
                "WHERE program IS NOT NULL AND is_tv = 0")]
    snames = dict(s.execute("SELECT key, COALESCE(name, key) FROM series"))
    names_of = {k: [n] for k, n in snames.items()}
    for k, prog in s.execute("SELECT series_key, program FROM series_map WHERE source = 'otrr'"):
        if k in names_of:
            names_of[k].append(prog)
    eps = [(e, sk, a, t) for e, (sk, a, t, f, aid, pub) in raw.items() if sk and sk not in librivox]
    by_ep, by_series = A.goldin_productions(recs, eps, us, DT.program_namer(names_of))
    nr = {e for (e,) in s.execute("SELECT id FROM episodes WHERE no_recommend IS NOT NULL")}

    def speech(eid):   # 027 keeps speeches, 006 keeps propaganda findable (build_db.goldin_foreign)
        sk, a, t, f, aid, pub = raw[eid]
        return eid in nr or bool(A.SPEECH.search(" ".join([t or "", snames.get(sk) or "", f.rsplit("/", 1)[-1],
                                                           itext.get(aid, "")])))
    foreign = sorted((names.get(served[e][0]), served[e][2], v["how"], v["goldin"]) for e, v in by_ep.items()
                     if e in served and served[e][0] not in librivox and not speech(e))
    foreign += sorted((names.get(served[e][0]), served[e][2], "series", by_series[raw[e][0]]["term"]) for e in served
                      if e in raw and raw[e][0] in by_series and e not in by_ep and not speech(e))
    check("guard: no served episode is a production GOLDINdex names a non-US origin for",
          (len(foreign), foreign[:8]), (0, []))
    notes = []
    for eid, (sk, a, t) in sorted(served.items()):
        if a or eid not in raw:
            continue
        rsk, ra, rt, f, aid, pub = raw[eid]
        for txt in (rt, P.stem(f)):
            dt = P.title_date_note(txt)[0] if txt else None
            if dt and not P.is_upload_stamp(dt, pub) and not P.modern_two_digit(dt, pub):
                notes.append((names.get(sk), t, txt))
                break
    check("guard: no served undated episode carries a date note on its own title or name", (len(notes), notes[:8]),
          (0, []))
    restate = sorted((names.get(sk), t) for eid, (sk, a, t) in served.items() if a and P.title_date_note(t)[0] == a)
    check("guard: no served title carries a note restating its own date", (len(restate), restate[:8]), (0, []))
elif os.environ.get("PROJECTION"):
    check("the build named by PROJECTION and SOURCE exists", False, True)
else:
    print("  SKIP  guards: no build at out/publish/ear-drama.sqlite and out/radio-catalog.sqlite (name them)")

print(f"{ran - failed}/{ran} passed")
sys.exit(1 if failed else 0)
