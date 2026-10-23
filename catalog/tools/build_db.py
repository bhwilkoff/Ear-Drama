"""Build the radio catalog database from the harvested caches.

    python3 tools/build_db.py            -> out/radio-catalog.sqlite, out/build_report.json

Inputs (all under .cache/, written by the harvest_* and fetch_* tools):
  meta/<id>.json.gz          archive.org items, slimmed
  librivox.json.gz           LibriVox dramatic works
  radioechoes/series/*.json  the episode spine (owner: RadioEchoes as spine)
  p72_schedules.json.gz      the Copyright Office's pre-1972 schedules
plus editorial/*.json and Archive Watch's shared/editorial/cce_renewals.json.

Model (docs/research/RESEARCH.md §4): series -> episode (the broadcast,
keyed by series + air date) -> recording (a file in an archive.org item).
"""
import collections
import datetime
import glob
import gzip
import json
import os
import re
import sqlite3
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia
import otr_parse as P
import audit_audio_rights as A

# A copy of Archive Watch's shared/editorial/cce_renewals.json (tools/fetch_cce_renewals.py
# there), so this catalog builds outside that repository.
AW_RENEWALS = os.path.join(ia.EDITORIAL, "film_renewals_cce.json")
PLAYABLE = {"VBR MP3": 0, "128Kbps MP3": 0, "320Kbps MP3": 0, "256Kbps MP3": 0, "192Kbps MP3": 0,
            "160Kbps MP3": 0, "96Kbps MP3": 0, "64Kbps MP3": 0, "48Kbps MP3": 0, "32Kbps MP3": 0,
            "24Kbps MP3": 0, "16Kbps MP3": 0, "MP3": 0, "Ogg Vorbis": 1, "MPEG-4 Audio": 2, "Opus": 2}
ITEM_NOISE = re.compile(
    r"\b(otrr|certified|maintained|non[- ]?maintained|curated|singles?|and doubles|set|sets|collection|"
    r"old[- ]time[- ]radio|otr|radio shows?|radio programs?|radio drama|episodes?|complete|"
    r"by year|vol(ume)?\.?\s*\d+|part\s*\d+|\d{4}(\s*-\s*\d{2,4})?|mp3s?|archive|library)\b", re.I)


# Decision 149's rule carried over: the regime's own speeches and broadcasts are
# never recommended and always findable; the evidence is the speaker or event
# named in the title WITH a speech or rally; a program ABOUT Hitler is not his
# broadcast (Decision 149: never widen on a keyword).
_NAZI = r"(?:Adolf Hitler|Hitler|Goebbels|G(?:ö|oe)ring|Himmler)"
_SPEECH = r"(?:Rede|Ansprache|Sportpalast\w*|speech|address|broadcast to)"
NO_RECOMMEND = re.compile(rf"\b(?:{_NAZI}\b.{{0,40}}\b{_SPEECH}|{_SPEECH}\b.{{0,40}}\b{_NAZI}\b|Reichstagsrede|Reichsparteitag)", re.I)


def load(path, default):
    return ia.read_json(path) if os.path.exists(path) else default


def item_series(item):
    t = item.get("title") or item.get("identifier") or ""
    t = re.sub(r"[_]+", " ", t)
    t = ITEM_NOISE.sub(" ", t)
    t = re.sub(r"[\[\]()\-:,.#]+", " ", t)
    return re.sub(r"\s+", " ", t).strip() or None


def seconds(v):
    return P.seconds(v)


def bitrate_kbps(f):
    s, l = f.get("size"), seconds(f.get("length"))
    try:
        return round(int(s) * 8 / l / 1000) if s and l else None
    except (ValueError, ZeroDivisionError):
        return None


def stem_key(name):
    s = name.rsplit("/", 1)[-1]
    s = re.sub(r"\.[A-Za-z0-9]{2,4}$", "", s)
    return re.sub(r"_(64kb|128kb|vbr|sample)$", "", s, flags=re.I)


def pick_files(files):
    """One playable file per stem: the uploaded MP3 when there is one (92% are VBR MP3
    and archive.org derives only Ogg from them, MEASURED), else the best derivative."""
    by = collections.defaultdict(list)
    for f in files:
        if f.get("private") in ("true", True) or f.get("format") not in PLAYABLE:
            continue
        by[stem_key(f["name"])].append(f)
    out = []
    for st, fs in by.items():
        fs.sort(key=lambda f: (PLAYABLE[f["format"]], f.get("source") != "original", -(bitrate_kbps(f) or 0)))
        out.append(fs[0])
    return out


class Registry:
    """One canonical key per program. Every name a source uses for a program — OTRR's
    program titles and all their alias titles (pTitles), RadioEchoes' series names, the
    editorial and learned aliases — is a key that resolves to the canonical key, which is
    norm_series of the program's display name (RadioEchoes' when the spine has it)."""

    def __init__(self):
        self.k2c, self.src = {}, {}
        self.name = {}
        self.idps = collections.defaultdict(set)
        self.idp2c = {}
        self.re_keys = set()

    def add(self, key, canon, alias, source, override=False):
        if not key or not canon or (key in self.k2c and not override):
            return
        self.k2c[key] = canon
        self.src[key] = (alias, source)

    def resolve(self, raw, prefix=True):
        vs = P.series_variants(raw)
        for i, v in enumerate(vs):
            c = self.k2c.get(v)
            if c:
                return c, "exact" if i == 0 else "variant"
        if not prefix or not vs:
            return None, None
        # "Lum and Abner of the classic Show" -> lumandabner: the longest known key the name
        # starts with, ending where a word ends, two words and eight letters at least.
        # MEASURED 2026-10-19: without the word rules "Conflicting Concepts of Education" became
        # "Conflict", "Whistler's Mother" The Whistler, "American Armed Forces Radio" Americana.
        words = [P.norm_series(w) for w in re.split(r"\s+", P._fold(raw).strip())]
        words = [w for w in words if w]
        if words and words[0] in ("the", "otrr"):
            words = words[1:]
        acc = ""
        bounds = []
        for w in words:
            acc += w
            bounds.append(acc)
        for i in range(len(bounds) - 2, 0, -1):
            k = bounds[i]
            if len(k) >= 8 and k in self.k2c:
                return self.k2c[k], "prefix"
        return None, None

    def display(self, canon, fallback=None):
        return self.name.get(canon) or fallback


# One-word OTRR alias titles that name a kind of program, not a program (MEASURED 2026-10-19:
# "Interviews" filed files from three shows under Adventures by Morse). "Superman" stays.
SCRIPTURE_ITEM_FLOOR = 20
GENERIC_ALIAS_WORDS = {"interviews", "interview", "christmas", "music", "news", "comedy", "drama", "mystery",
                       "theater", "variety", "sports", "specials", "special", "commercials", "documentary",
                       "religion", "religious", "education", "children", "western", "westerns", "detective",
                       "horror", "science", "history", "quiz", "talk", "speeches", "speech", "concert", "concerts",
                       "poetry", "audition", "auditions", "promos", "promo", "misc", "miscellaneous", "various",
                       "sermon", "sermons", "newscast", "newscasts", "bulletins", "bulletin", "dance", "jazz",
                       "classical", "opera", "country", "gospel", "hymns", "serial", "serials", "soap", "radio"}


def median_length(recs):
    return statistics.median([r["length_s"] for r in recs if r["length_s"]] or [0]) or None


def order_recordings(recs):
    """The default copy first (catalog DECISIONS 007): a complete copy before a partial
    one (under 60% of the episode's median length), then the domestic broadcast before
    an AFRS/AFRTS or rehearsal variant, then OTRR's copy, then the higher measured
    bitrate. A fragment of the domestic broadcast never beats a whole AFRS disc."""
    med = median_length(recs)
    for r in recs:
        r["partial"] = bool(med and r["length_s"] and r["length_s"] < 0.6 * med)
    recs.sort(key=lambda r: (r["partial"], bool(r["variant"]), not r["otrr"], -(r["kbps"] or 0)))
    return recs


def build_registry(re_series, otrr_progs, ptitles, aliases, editorial_named):
    reg = Registry()
    re_eps = collections.Counter()
    re_name = {}
    for s in re_series:
        k = P.norm_series(s["series"])
        if k:
            re_eps[k] += len(s.get("episodes") or [])
            re_name.setdefault(k, s["series"])
    reg.re_keys = set(re_name)
    names_by_idp = collections.defaultdict(set)
    for idp, t in otrr_progs.items():
        names_by_idp[idp].add(t)
    for r in ptitles:
        if r.get("idp") and r.get("title"):
            names_by_idp[r["idp"]].add(r["title"])
    key_idps = collections.defaultdict(set)
    for idp, names in names_by_idp.items():
        for n in names:
            for k in {P.norm_series(n), P.norm_series(P.reorder_title(n))}:
                if len(k) >= 4:
                    key_idps[k].add(idp)
    stats = collections.Counter()
    for idp in sorted(names_by_idp, key=lambda x: int(x) if x.isdigit() else 0):
        names = names_by_idp[idp]
        main = P.reorder_title(otrr_progs.get(idp) or sorted(names)[0])
        keys = {}
        for n in names:
            # An alias of one word ("Interviews", "Christmas") names too much; the program's own
            # title may be one word ("Suspense").
            if n != otrr_progs.get(idp) and len(re.findall(r"[A-Za-z0-9]+", P.reorder_title(n))) < 2 and \
                    P.norm_series(n) in GENERIC_ALIAS_WORDS:
                stats["otrr_alias_one_word_skipped"] += 1
                continue
            for k in (P.norm_series(n), P.norm_series(P.reorder_title(n))):
                if len(k) >= 4 and len(key_idps[k]) == 1:
                    keys.setdefault(k, n)
                elif len(k) >= 4:
                    stats["otrr_alias_ambiguous"] += 1
        hits = [k for k in keys if k in re_name]
        if hits:
            canon = max(hits, key=lambda k: (re_eps[k], k))
            reg.name.setdefault(canon, re_name[canon])
            stats["otrr_programs_on_spine"] += 1
        else:
            canon = P.norm_series(main)
            reg.name.setdefault(canon, main)
        if not canon:
            continue
        reg.idps[canon].add(idp)
        reg.idp2c[idp] = canon
        reg.add(canon, canon, main, f"otrr:{idp}")
        for k, n in keys.items():
            reg.add(k, canon, n, f"otrr:{idp}")
    for k, n in re_name.items():
        reg.add(k, k, n, "radioechoes")
        reg.name.setdefault(reg.k2c[k], n)
    for name, origin in editorial_named:
        c = reg.resolve(name)[0] or P.norm_series(name)
        reg.add(P.norm_series(name), c, name, origin)
        reg.name.setdefault(c, name)
    for abbr, name in aliases.items():
        if abbr.startswith("_") or not isinstance(name, str):
            continue
        c = reg.resolve(name)[0] or P.norm_series(name)
        reg.add(P.norm_series(abbr), c, abbr, "editorial alias", override=True)
        reg.name.setdefault(c, name)
    # "_learned" is re-derived by every build (learn_abbreviations) and only RECORDED in the
    # file, with its evidence; "_rejected" is the editorial veto.
    return reg, stats


def learn_abbreviations(files, reg, rejected):
    """Abbreviations a file name uses for a series, learned where the file's prefix is
    unknown and its item (or OTRR's log) names a known series: "esca" in Escape1953,
    "dimx" in Dimension-X. Kept only when the prefix could abbreviate that series
    (P.is_abbreviation), at least 3 files across the corpus say so, and 80% agree."""
    votes = collections.defaultdict(collections.Counter)
    items = collections.defaultdict(lambda: collections.defaultdict(set))
    for fr in files:
        fs = fr["p"]["series"]
        if not fs:
            continue
        fk = P.norm_series(fs)
        if not fk or fk in reg.k2c or reg.resolve(fs)[0]:
            continue
        target = reg.idp2c.get(fr["orow"]["idp"]) if fr.get("orow") else None
        if not target and fr.get("item_series"):
            target = reg.resolve(fr["item_series"])[0]
        if target:
            votes[fk][target] += 1
            items[fk][target].add(fr["ident"])
    learned = {}
    for fk, c in votes.items():
        if fk in rejected:
            continue
        target, n = c.most_common(1)[0]
        total = sum(c.values())
        name = reg.display(target, target)
        if n < 3 or n / total < 0.8:
            continue
        if not (P.is_abbreviation(fk, target) or fk == P.initials(name)):
            continue
        # A two- or three-letter prefix ("md", "st", "la") applies corpus-wide only when two
        # uploads independently use it for the same series; otherwise it is recorded, not applied.
        applied = len(fk) >= 4 or (len(items[fk][target]) >= 2 and n >= 20)
        learned[fk] = {"series": name, "files": n, "disagree": total - n, "items": len(items[fk][target]),
                       "applied": applied, "evidence": sorted(items[fk][target])[:5],
                       "why": "file-name prefix vs item title / OTRR log"}
    return learned


def resolve_file(fr, reg):
    """A file's series: the first of its names (file, folder, item, item title, then the ID3
    album and artist) the registry knows; else the first usable name as a series of its own."""
    f, p, it = fr["f"], fr["p"], fr["it"]
    cands = [("file", p["series"])] + [("dir", x) for x in item_dirs(f["name"])] + \
            [("item", fr["item_series"]), ("item_title", it.get("title"))]
    tags = [("id3_album", f.get("album")), ("id3_artist", f.get("artist"))]
    for origin, raw in cands + tags:
        if raw and isinstance(raw, str):
            c, m = reg.resolve(raw, prefix=not origin.startswith("id3"))
            if c:
                return c, raw, f"{origin}:{m}"
    for origin, raw in cands:
        k = P.norm_series(raw) if raw and isinstance(raw, str) else ""
        if k and (origin != "file" or len(k) >= 5) and k not in P.GENERIC_FILE_SERIES:
            return k, raw, origin
    return None, None, "none"


FULL_DATE = re.compile(r"19\d\d-\d\d-\d\d")
# Words an uploader puts around a series' name ("SUSPENSE Radio Digitally Restored").
FOLD_NOISE = re.compile(r"\b(?:otrr?|old[ -]?time[ -]?radio|radio|digitally|restored|remastered|collection|complete|"
                        r"series|shows?|programs?|presents|episodes?|the|mp3s?|vol(?:ume)?|set|singles?|doubles?|"
                        r"numbers?|eps|afrts?|\d+)\b")
# A re-creation re-stages a broadcast on its date; it is a modern performance, not a copy
# of the broadcast, and never joins the original's versions. MEASURED 2026-10-22 over 879
# candidates: the name says so for "The Suspense Project" (17 series) and "The Shadow
# Recreations"; "project" in item metadata named digitizing projects (AFRS-V-Discs, aporee,
# calisphere) on 25 items, so in metadata only the re-creation words count.
RECREATION = re.compile(r"\b(?:re-?creations?|re-?created|re-?enact\w*)\b", re.I)
RECREATION_NAME = re.compile(r"\b(?:re-?creations?|re-?created|re-?enact\w*|project|tribute)\b", re.I)
FOLD_RUN_SHARE = 0.8        # of the candidate's dates inside the target's run
FOLD_SHARED_SHARE = 0.5     # of the candidate's dates the target already has
FOLD_KEY_MIN = 5
# A name that only begins or ends with the series' name ("Charlie McCarthy guest Fred Allen")
# needs this many dates; one shared date is a coincidence in a weekly series (MEASURED
# 2026-10-22: 1-date begin/end folds included "Afrs117-CharlieMccarthy-guestFredAllen" -> Fred
# Allen and "The Beatles January 13 Lecture").
FOLD_PARTIAL_MIN_DATES = 3


def fold_target(raw, reg):
    """The known key a noisy name is built around, and whether the name IS that key once noise
    words are stripped (exact) or only begins or ends with it (whole words, longest first)."""
    words = [P.norm_series(w) for w in FOLD_NOISE.sub(" ", P._fold(raw)).split()]
    words = [w for w in words if w]
    for n in range(len(words), 0, -1):
        for k in ("".join(words[:n]), "".join(words[-n:])):
            for k2 in (k, k[len("adventuresof"):] if k.startswith("adventuresof") else ""):
                if len(k2) >= FOLD_KEY_MIN and k2 in reg.k2c:
                    return k2, n == len(words)
    return None, False


def learn_folds(files, reg, target_dates, rejected):
    """Series names no source knows that are a known series' name with noise around it
    ("Suspense page 2", "The Shadow Season 03 (9-17-39 to 4-7-40)"). A candidate folds into
    the target only on its dates: FOLD_RUN_SHARE of its dated files inside the target's run,
    and FOLD_SHARED_SHARE of its dates already the target's (the spine, OTRR's log, or the
    target's own files); a name that only begins or ends with the target's needs
    FOLD_PARTIAL_MIN_DATES. Never undated, never LibriVox, never a re-creation by the evidence
    its name or item metadata carry."""
    tdates = collections.defaultdict(set, {k: set(v) for k, v in target_dates.items()})
    groups = collections.defaultdict(lambda: {"dates": set(), "files": 0, "items": set(), "names": collections.Counter(),
                                              "text": []})
    for fr in files:
        key, raw, how = resolve_file(fr, reg)
        date = fr["p"]["date"] or (P.parse_album_tag(fr["f"].get("album")) or {}).get("date")
        date = date if date and FULL_DATE.fullmatch(date) else None
        if fr.get("orow"):
            continue
        if ":" in how:
            if date:
                tdates[key].add(date)
            continue
        if not key or key in rejected or key.startswith("librivox") or \
                any(str(c).startswith("librivox") for c in fr["colls"]) or fr["ident"].lower().startswith("librivox"):
            continue
        g = groups[key]
        g["files"] += 1
        g["names"][raw] += 1
        if date:
            g["dates"].add(date)
        if fr["ident"] not in g["items"]:
            g["items"].add(fr["ident"])
            g["text"].append((fr["ident"], fr["text"]))
    out = {}
    for fk, g in groups.items():
        names = [n for n, _ in g["names"].most_common()]
        tk, exact = next((t for t in (fold_target(n, reg) for n in names) if t[0]), (None, False))
        if not tk:
            continue
        target = reg.k2c[tk]
        if target == fk or target.startswith("librivox"):
            continue
        td = tdates.get(target) or set()
        dates = g["dates"]
        inside = sum(1 for d in dates if td and min(td) <= d <= max(td))
        shared = len(dates & td)
        e = {"series": reg.display(target, target), "target": target, "names": names[:3], "files": g["files"],
             "items": len(g["items"]), "evidence": sorted(g["items"])[:5], "dates": len(dates),
             "dates_shared": shared, "share_inside_run": round(inside / len(dates), 2) if dates else None,
             "match": "exact" if exact else "begins_or_ends"}
        rec = next((f"{m.group(0)!r} in {where}" for where, rx, txt in [("its name", RECREATION_NAME, n) for n in names] +
                    [(f"item {i}", RECREATION, t) for i, t in g["text"]] for m in [rx.search(txt or "")] if m), None)
        if rec:
            why = "re-creation: " + rec
        elif not dates:
            why = "undated: a name alone never folds"
        elif not exact and len(dates) < FOLD_PARTIAL_MIN_DATES:
            why = f"name only begins or ends with {e['series']}'s and {len(dates)} date(s) cannot show it"
        elif inside / len(dates) < FOLD_RUN_SHARE:
            why = f"only {inside} of {len(dates)} dates inside {e['series']}'s run"
        elif shared < 1 or shared / len(dates) < FOLD_SHARED_SHARE:
            why = f"only {shared} of {len(dates)} dates are {e['series']}'s"
        else:
            why = "noisy name of a known series; its dates are the series' dates"
        e["applied"] = why.startswith("noisy")
        e["why"] = why
        out[fk] = e
    return out


def item_dirs(name):
    parts = name.split("/")[:-1]
    out = []
    for d in reversed(parts):
        d = re.sub(r"\.(flac\d*|mp3|ogg)$", "", d, flags=re.I)
        if re.fullmatch(r"[\d\s._-]*|undated|mp3s?|disc\s*\d+|cd\s*\d+|side\s*[ab]|vol(ume)?\s*\d+", d.strip(), re.I):
            continue
        out.append(d)
    return out


def item_full_date(it):
    for k in ("date", "year"):
        v = it.get(k)
        if isinstance(v, list):
            v = v[0] if v else None
        m = re.fullmatch(r"(19[2-9]\d)-(\d\d)-(\d\d)", str(v or "").strip()[:10])
        if m and P.valid_date(*m.groups()):
            return m.group(0)
    return None


# For measuring each identity step's effect on a full build (the report's ablation table):
# RADIO_SKIP=logs,uiuc,learn,newfamilies,fallbacks turns those steps off.
SKIP = set(filter(None, os.environ.get("RADIO_SKIP", "").split(",")))
NEW_FAMILIES = ("F2c_", "F7b_", "F7c_", "F4b_", "F10_", "F10b_", "F11", "F12_", "F13_", "F14_", "F1h_")


def first_parse(f, it, ident, n_audio, uiuc):
    """Everything a file says about itself, before any series is resolved."""
    name = f["name"]
    st = P.stem(name)
    idt = {}
    um = P.UIUC_FILE.search(name)
    if um and uiuc.get(um.group(0)) and "uiuc" not in SKIP:
        u = uiuc[um.group(0)]
        prog = u["program"] if u.get("program") and len(u["program"]) <= 70 else None
        ser = prog or re.sub(r"\s*(#\s*\d+|\d+|part\s*\d+(\s*of\s*\d+)?)\s*$", "", u["title"] or "", flags=re.I).strip()
        p = {"family": "UIUC_findingaid", "series": ser or None, "date": u["date"],
             "decade": (u["date"] or "")[:3] + "0s" if u["date"] else None, "num": None, "title": u["title"],
             "aka": None, "variant": None}
        idt = {"uiuc": f"https://archives.library.illinois.edu/archon/?p=collections/findingaid&id=1994&q=#id{u['anchor']}",
               "uiuc_item": u["item"], "speaker": u.get("speaker")}
        return p, "uiuc_findingaid" if u["date"] else None, idt, u
    p = P.parse(name)
    if "newfamilies" in SKIP and p["family"].startswith(NEW_FAMILIES):
        p = {"family": "F6_none", "series": None, "date": None, "decade": None, "num": None, "title": None,
             "aka": None, "variant": None}
    date_source = "filename" if p["date"] else None
    if not p["date"]:
        # Fallbacks, in order: the ID3 title tag, then for a single-episode item its own
        # title and identifier; then a date written out in the title or album tag.
        ttag = f.get("title") if isinstance(f.get("title"), str) else None
        alts = [ttag] + ([it.get("title"), ident] if n_audio <= 2 else [])
        for alt in alts:
            q = P.parse(alt or "") if alt else None
            if q and q["date"]:
                p = dict(q, series=q["series"] or p["series"], title=q["title"] or p["title"],
                         family=q["family"] + "+alt")
                date_source = "filename_alt"
                break
    if "fallbacks" in SKIP:
        return p, date_source, idt, None
    if not p["date"]:
        for src, txt in (("id3_title_text", f.get("title")), ("id3_album_text", f.get("album")),
                         ("filename_text", st)):
            dt = P.parse_text_date(txt if isinstance(txt, str) else "")
            if dt:
                p = dict(p, date=dt, decade=dt[:3] + "0s")
                date_source = src
                break
    if not p["date"] and n_audio == 1:
        dt = P.parse_text_date(it.get("title") or "") or item_full_date(it)
        if dt:
            p = dict(p, date=dt, decade=dt[:3] + "0s")
            date_source = "item_metadata"
    if not p["title"] and n_audio == 1 and P.is_titleish(it.get("title") or ""):
        p = dict(p, title=re.sub(r"\s+", " ", it["title"]).strip())
        idt["title_from"] = "item_title"
    return p, date_source, idt, None


def date_source_of(r):
    return r["date_source"] if r["date"] else None


def _title_keys(t):
    """A title's match keys: itself, and the part after a " - " (file titles often carry the
    series first: "Suspense - The Burning Court")."""
    out = []
    for x in [t] + ([t.rsplit(" - ", 1)[1]] if t and " - " in t else []):
        nt = A.norm_title(x)
        if len(nt) >= 6 and not nt.isdigit():
            out.append(nt)
    return out


_STOP = {"the", "and", "with", "guest", "guests", "part", "episode", "show", "program", "for", "from", "pt"}
TITLE_SIM_FLOOR = 0.34


def title_words(t):
    t = re.sub(r"([a-z])([A-Z])", r"\1 \2", t or "")
    return {w for w in re.findall(r"[a-z]{3,}", t.lower()) if w not in _STOP}


def title_similarity(a, b):
    """Shared words over the shorter title's words; 1.0 when either has no words to compare."""
    wa, wb = title_words(a), title_words(b)
    if not wa or not wb:
        return 1.0
    return len(wa & wb) / min(len(wa), len(wb))


NUM_DATE_FLOOR = (0.9, 5)   # a series' numbers give dates only where 90% of 5+ checkable files agree


def match_logs(recs, otrr_rows, reg, re_by_key, stats):
    """Fill date, number, title and credits from OTRR's logs (and dates from the spine) for
    files the log does not list by name. Three rules, each recorded in `identity`:
      series + air date   -> the log row of that date (duration checked against the copies
                             the log lists, 0.6-1.6x; a mismatch is recorded, not applied)
      series + title      -> the date, when the series' log (or spine) has that title on one date
      series + number     -> the date, only in series where numbers and dates already agree
                             on 90% of 5+ files that carry both (NUM_DATE_FLOOR)"""
    by_cd, by_ct, by_cn = (collections.defaultdict(list) for _ in range(3))
    for row in otrr_rows:
        c = reg.idp2c.get(row["idp"])
        if not c:
            continue
        if row["date"]:
            by_cd[(c, row["date"])].append(row)
        for nt in _title_keys(row["title"]):
            by_ct[(c, nt)].append(row)
        if str(row.get("epnum") or "").isdigit() and int(row["epnum"]) > 0:
            by_cn[(c, int(row["epnum"]))].append(row)
    re_ct = collections.defaultdict(set)
    for c, ss in re_by_key.items():
        for s in ss:
            for e in s.get("episodes") or []:
                dt = (e.get("date") or "").replace(".", "-")
                if re.fullmatch(r"19\d\d-\d\d-\d\d", dt) and P.valid_date(*dt.split("-")):
                    for nt in _title_keys(e.get("title")):
                        re_ct[(c, nt)].add(dt)

    def apply_row(r, row, method):
        if r["title"] and row["title"] and title_similarity(r["title"], row["title"]) < TITLE_SIM_FLOOR:
            r["idt"].setdefault("disagree", []).append({"otrr_eid_title_conflict": row["eid"], "otrr_title": row["title"]})
            stats["otrr_title_conflict_not_applied"] += 1
            return False
        r["orow"] = row
        r["idt"]["otrr_eid"] = row["eid"]
        r["idt"]["otrr_match"] = method
        if row["title"]:
            if r["title"] and A.norm_title(r["title"]) != A.norm_title(row["title"]):
                r["idt"]["title_by_name"] = r["title"]
                stats["otrr_title_differs_similar"] += 1
            r["title"] = row["title"]
        if str(row.get("epnum") or "").isdigit() and int(row["epnum"]) > 0:
            if r["num"] is not None and r["num"] != int(row["epnum"]):
                r["idt"].setdefault("disagree", []).append({"num_by_name": r["num"]})
                stats["otrr_num_disagrees"] += 1
            r["num"] = int(row["epnum"])
        return True

    # 1. series + air date
    for r in recs:
        if r["orow"] or not r["key"] or not r["date"]:
            continue
        rows = by_cd.get((r["key"], r["date"]))
        if not rows:
            continue
        if len(rows) > 1:
            tk = set(_title_keys(r["title"]))
            pick = [x for x in rows if tk & set(_title_keys(x["title"]))]
            if len(pick) != 1:
                stats["otrr_series_date_ambiguous"] += 1
                continue
            rows = pick
        row = rows[0]
        secs = [float(fl["seconds"]) for fl in row["files"] if re.fullmatch(r"\d+(\.\d+)?", str(fl.get("seconds") or ""))
                and float(fl["seconds"]) > 0]
        dur = "no_duration"
        if secs and r["length"]:
            ratio = r["length"] / statistics.median(secs)
            if not 0.6 <= ratio <= 1.6:
                stats["otrr_series_date_duration_mismatch"] += 1
                r["idt"].setdefault("disagree", []).append({"otrr_eid_duration_mismatch": row["eid"],
                                                            "ratio": round(ratio, 2)})
                continue
            dur = "duration_verified"
        if apply_row(r, row, "series_date:" + dur):
            stats["otrr_series_date"] += 1
            stats["otrr_series_date:" + dur] += 1

    # 2. series + title -> date, in series where the log's (or the spine's) title->date already
    # agrees with the files that carry both a date and their own title (NUM_DATE_FLOOR).
    # MEASURED 2026-10-19: corpus-wide the log's title->date agrees on only ~1 in 5 such files
    # (repeat performances of one script, re-used titles), the spine's on ~9 in 10.
    tagree = {"otrr": collections.defaultdict(lambda: [0, 0]), "spine": collections.defaultdict(lambda: [0, 0])}
    for r in recs:
        t0 = r.get("title0")
        if not (r["key"] and r["date"] and t0) or r["date_source"] == "otrr_log":
            continue
        for nt in _title_keys(t0):
            dates = {x["date"] for x in by_ct.get((r["key"], nt)) or [] if x["date"]}
            sd = re_ct.get((r["key"], nt)) or set()
            if len(dates) == 1:
                tagree["otrr"][r["key"]][0] += next(iter(dates)) == r["date"]
                tagree["otrr"][r["key"]][1] += 1
            if len(sd) == 1:
                tagree["spine"][r["key"]][0] += next(iter(sd)) == r["date"]
                tagree["spine"][r["key"]][1] += 1
            if dates or sd:
                break
    tok = {}
    for src, d in tagree.items():
        tok[src] = {k for k, (a, n) in d.items() if n >= NUM_DATE_FLOOR[1] and a / n >= NUM_DATE_FLOOR[0]}
        stats[f"title_date_{src}_checks"] = sum(n for a, n in d.values())
        stats[f"title_date_{src}_agree"] = sum(a for a, n in d.values())
        stats[f"title_date_{src}_series_trusted"] = len(tok[src])
        stats[f"title_date_{src}_trusted_checks"] = sum(d[k][1] for k in tok[src])
        stats[f"title_date_{src}_trusted_agree"] = sum(d[k][0] for k in tok[src])
    for r in recs:
        if r["date"] or not r["key"] or not r["title"]:
            continue
        for nt in _title_keys(r["title"]):
            rows = by_ct.get((r["key"], nt)) or []
            dates = {x["date"] for x in rows if x["date"]}
            if len(dates) == 1 and r["key"] in tok["otrr"]:
                if len(rows) == 1 and not apply_row(r, rows[0], "series_title"):
                    break
                r["date"], r["date_source"] = dates.pop(), "otrr_title"
                stats["date_from_otrr_title"] += 1
                break
            sd = re_ct.get((r["key"], nt)) or set()
            if len(sd) == 1 and r["key"] in tok["spine"]:
                r["date"], r["date_source"] = next(iter(sd)), "spine_title"
                r["idt"]["spine_match"] = "series_title"
                stats["date_from_spine_title"] += 1
                break
        if r["date"]:
            r["decade"] = r["date"][:3] + "0s"

    # 3. series + number -> date, where the series' numbering is shown to agree with the log
    agree = collections.defaultdict(lambda: [0, 0])
    for r in recs:
        n0 = r.get("num0")
        if r["key"] and r["date"] and n0 and r["date_source"] not in ("otrr_log", "otrr_title", "otrr_num"):
            dates = {x["date"] for x in by_cn.get((r["key"], n0), []) if x["date"]}
            if len(dates) == 1:
                agree[r["key"]][0] += next(iter(dates)) == r["date"]
                agree[r["key"]][1] += 1
    ok = {k for k, (a, n) in agree.items() if n >= NUM_DATE_FLOOR[1] and a / n >= NUM_DATE_FLOOR[0]}
    stats["num_date_series_checked"] = len(agree)
    stats["num_date_series_trusted"] = len(ok)
    stats["num_date_checks_agree"] = sum(a for a, n in agree.values())
    stats["num_date_checks"] = sum(n for a, n in agree.values())
    for r in recs:
        if r["date"] or not r["key"] or r["num"] is None or r["key"] not in ok:
            continue
        rows = [x for x in by_cn.get((r["key"], r["num"]), []) if x["date"]]
        if len({x["date"] for x in rows}) == 1:
            if len(rows) == 1 and not apply_row(r, rows[0], "series_num"):
                continue
            r["date"], r["date_source"] = rows[0]["date"], "otrr_num"
            r["decade"] = r["date"][:3] + "0s"
            stats["date_from_otrr_num"] += 1


GENERIC_SERIES = {"various", "variousartists", "unknown", "misc", "miscellaneous", "radio", "oldtimeradio"}
BROADCAST_ROW = re.compile(r"\b(broadcasts?|radio|aired|transcription|airchecks?|on the air)\b", re.I)


def build_schedule_index(rows):
    by_title = collections.defaultdict(list)
    by_artist = collections.defaultdict(list)
    for r in rows:
        nt = A.norm_title(r.get("title"))
        if len(nt) >= 10:
            by_title[nt].append(r)
        # A schedule protects THAT recording. A label's schedule of a performer's
        # commercial records says nothing about the performer's radio show, so a
        # series-level match needs a scheduled row that is itself a broadcast
        # (Sony's Cronkite/Murrow news, Arista's Tommy Dorsey "radio broadcast").
        if not BROADCAST_ROW.search(" ".join(str(r.get(k) or "") for k in ("title", "album", "alt_title"))):
            continue
        for a in (r.get("artist") or "", r.get("album") or ""):
            na = P.norm_series(a)
            if len(na) >= 6:
                by_artist[na].append(r)
    return by_title, by_artist


def make_schedule_matcher(by_title, by_artist):
    def match(ep):
        hits = []
        for r in ([] if ep["series_key"] in GENERIC_SERIES else by_artist.get(ep["series_key"], [])[:5]):
            hits.append({"source": "pre-1972 schedule (series named as artist/album)", "title": r.get("title"),
                         "artist": r.get("artist"), "rights_owner": r.get("rights_owner"),
                         "indexed": r.get("index_date")})
        nt = A.norm_title(ep.get("title"))
        if nt and len(nt) >= 10:
            # The whole artist name must appear in the series name or the file's
            # creator: a shared first name ("John", "Archie") is not the same act.
            hay = [P.norm_series(ep.get("series_name"))] + [P.norm_series(x.get("creator")) for x in ep["recordings"]]
            for r in by_title.get(nt, []):
                na = P.norm_series(r.get("artist"))
                if len(na) >= 6 and any(na in h for h in hay if h):
                    hits.append({"source": "pre-1972 schedule (episode title + artist)", "title": r.get("title"),
                                 "artist": r.get("artist"), "rights_owner": r.get("rights_owner"),
                                 "indexed": r.get("index_date")})
        return hits
    return match


def main():
    t0 = time.time()
    args = sys.argv[1:]
    out_dir = args[args.index("--out") + 1] if "--out" in args else ia.OUT
    os.makedirs(out_dir, exist_ok=True)
    ed = lambda n: load(os.path.join(ia.EDITORIAL, n), {})
    aliases = ed("series_aliases.json")
    claims_raw = {k: v for k, v in ed("audio_claims.json").items() if not k.startswith("_")}
    gov_raw = {k: v for k, v in ed("gov_series.json").items() if not k.startswith("_")}
    takedowns = list((ed("takedowns.json").get("requests") or {}).values())
    lic_ev = ed("licence_evidence.json").get("evidence") or {}
    pub_rec = ed("published_records.json").get("records") or {}
    stats = collections.Counter()

    # The spine: RadioEchoes series names are the canonical display names.
    re_series = []
    for f in sorted(glob.glob(os.path.join(ia.CACHE, "radioechoes", "series", "*.json"))):
        re_series.append(ia.read_json(f))
    # OTRR's logs: each row names the archive.org file that plays it, so a file
    # found there takes its series, date, number, title and credits from the log
    # rather than from its name (date_source "otrr_log").
    otrr_by_file = {}
    otrr_rows = []
    otrr_progs = {p["idp"]: p["ptitle"] for p in load(os.path.join(ia.CACHE, "otrr", "otterlog.json"), [])}
    for f in sorted(glob.glob(os.path.join(ia.CACHE, "otrr", "programs", "*.json.gz"))):
        prog = ia.read_json(f)
        otrr_progs.setdefault(prog["idp"], prog["program"])
        for r in prog["episodes"]:
            r.setdefault("idp", prog["idp"])
            otrr_rows.append(r)
            for fl in r["files"]:
                otrr_by_file[(fl["archive_id"], fl["file"])] = r
    ptitles = load(os.path.join(ia.CACHE, "otrr", "pTitles.json"), [])
    if not ptitles:
        print("WARNING: no OTRR alias titles (.cache/otrr/pTitles.json); series will not fold aliases", file=sys.stderr)
    named = [(v["series"] if isinstance(v, dict) else v, "audio_claims") for v in claims_raw.values()] + \
            [(v["series"] if isinstance(v, dict) else v, "gov_series") for v in gov_raw.values()]
    reg, rstats = build_registry(re_series, otrr_progs, ptitles, aliases, named)
    stats.update({"registry:" + k: v for k, v in rstats.items()})
    canon = lambda name: reg.resolve(name)[0] or P.norm_series(name)
    claims = {canon(v["series"] if isinstance(v, dict) else v): v for v in claims_raw.values()}
    gov = {canon(v["series"] if isinstance(v, dict) else v): v for v in gov_raw.values()}
    re_by_key = collections.defaultdict(list)
    for s in re_series:
        k = reg.k2c.get(P.norm_series(s["series"]))
        if k:
            re_by_key[k].append(s)

    uiuc_html = os.path.join(ia.CACHE, "uiuc", "findingaid_1994.html")
    uiuc = P.parse_uiuc_findingaid(open(uiuc_html, encoding="utf-8", errors="replace").read()) \
        if os.path.exists(uiuc_html) else {}

    # Pass 1: what every file says about itself.
    items = {}
    files = []
    meta_files = sorted(glob.glob(os.path.join(ia.CACHE, "meta", "*.json.gz")))
    for mf in meta_files:
        d = ia.read_json(mf)
        it = d["item"]
        for k in ("title", "creator", "publisher", "contributor", "licenseurl", "uploader", "publicdate"):
            if isinstance(it.get(k), list):
                it[k] = "; ".join(str(x) for x in it[k])
        ident = it.get("identifier") or os.path.basename(mf)[:-8]
        colls = it.get("collection") or []
        colls = [colls] if isinstance(colls, str) else colls
        text = " ".join(str(it.get(k) or "") for k in ("title", "description", "subject", "creator", "publisher",
                                                     "contributor", "source", "notes"))
        isr = item_series(it)
        items[ident] = {"id": ident, "title": it.get("title"), "collections": colls,
                        "licenseurl": it.get("licenseurl"), "uploader": it.get("uploader"),
                        "publicdate": it.get("publicdate"), "is_dark": d.get("is_dark"),
                        "reviews": d["reviews"]["count"], "avg_stars": d["reviews"]["avg_stars"],
                        "transcripts": len(d.get("transcripts") or []), "item_series": isr}
        tstems = {re.sub(r"(\.autogenerated|_asr|\.asr)$", "", stem_key(t)) for t in d.get("transcripts") or []}
        chosen = pick_files(d["files"])
        n_audio = len(chosen)
        n_scripture = sum(1 for f in chosen if P.is_scripture_name(P.stem(f["name"])))
        for f in chosen:
            stats["files"] += 1
            p, date_source, idt, uiuc_row = first_parse(f, it, ident, n_audio, uiuc)
            files.append({"f": f, "p": p, "date_source": date_source, "idt": idt, "uiuc": uiuc_row,
                          "ident": ident, "item_series": isr, "item_title": it.get("title"),
                          "orow": otrr_by_file.get((ident, f["name"])), "colls": colls, "d": d, "it": it,
                          "text": text, "tstems": tstems, "n_scripture": n_scripture})

    # Abbreviations learned from the corpus join the registry before anything resolves.
    learned = learn_abbreviations(files, reg, set(aliases.get("_rejected") or [])) if "learn" not in SKIP else {}
    for fk, e in learned.items():
        if e["applied"]:
            reg.add(fk, canon(e["series"]), fk, "learned alias")
    stats["learned_aliases"] = len(learned)
    stats["learned_aliases_applied"] = sum(1 for e in learned.values() if e["applied"])
    if "--write-aliases" in args:
        aliases["_learned"] = dict(sorted(learned.items()))
        aliases.setdefault("_rejected", [])
        aliases["_learned_doc"] = ("Learned by build_db.learn_abbreviations: a file-name prefix the registry did not "
                                   "know, in items whose title (or OTRR's log) names a known series, kept when it "
                                   "could abbreviate that series, 3+ files say so and 80% agree. Move a wrong one "
                                   "to _rejected.")
        ia.write_json(os.path.join(ia.EDITORIAL, "series_aliases.json"), aliases)

    # Noisy re-uploads of a known series ("SUSPENSE Radio Digitally Restored", "The Shadow
    # Season 03") fold into it when their dates prove it, before anything resolves.
    target_dates = collections.defaultdict(set)
    for k, ss in re_by_key.items():
        for s in ss:
            for e in s.get("episodes") or []:
                dt = (e.get("date") or "").replace(".", "-")
                if FULL_DATE.fullmatch(dt) and P.valid_date(*dt.split("-")):
                    target_dates[k].add(dt)
    for row in otrr_rows:
        c = reg.idp2c.get(row["idp"])
        if c and row["date"] and FULL_DATE.fullmatch(row["date"]):
            target_dates[c].add(row["date"])
    folds = learn_folds(files, reg, target_dates, set(aliases.get("_rejected") or [])) if "folds" not in SKIP else {}
    for fk, e in folds.items():
        if e["applied"]:
            reg.add(fk, e["target"], e["names"][0], "learned fold")
    stats["learned_folds"] = len(folds)
    stats["learned_folds_applied"] = sum(1 for e in folds.values() if e["applied"])
    stats["learned_folds_files"] = sum(e["files"] for e in folds.values() if e["applied"])
    if "--write-aliases" in args:
        # Applied folds, and the near misses a reader should audit (a shared date, refused on
        # the re-creation or date rules); undated and one-off name matches are counted only.
        aliases["_learned_folds"] = {k: e for k, e in sorted(folds.items()) if e["applied"] or (
            e["dates_shared"] and not e["why"].startswith(("undated", "name only")))}
        aliases["_learned_folds_doc"] = (
            "Learned by build_db.learn_folds: a series name no source knows that is a known series' name with "
            "noise around it (set words stripped, then equal to, or beginning or ending with, a known key). Applied "
            "when 80% of its dated files fall inside the target's run and at least half its dates are dates the "
            "spine, OTRR's log or the target's own files already have, and a name that only begins or ends with "
            "the series' has 3+ dates; never when undated, from LibriVox, or a re-creation. Move a wrong one to "
            "_rejected.")
        ia.write_json(os.path.join(ia.EDITORIAL, "series_aliases.json"), aliases)

    # Pass 2: resolve each file's series against the registry.
    recs_out = []
    known_canon = set(reg.k2c.values())
    seen_names = collections.defaultdict(set)
    for fr in files:
        f, p, it, ident = fr["f"], fr["p"], fr["it"], fr["ident"]
        idt = dict(fr["idt"])
        key, sname, how = resolve_file(fr, reg)
        date, date_source = p["date"], fr["date_source"]
        tag = P.parse_album_tag(f.get("album"))
        if not date and tag and tag.get("date"):
            date, date_source = tag["date"], "album_tag"
        if p["date"] and tag and tag.get("date") and tag["date"] != p["date"]:
            stats["date_tag_disagrees"] += 1
            idt.setdefault("disagree", []).append({"album_tag": tag["date"]})
        title = p["title"] or (f.get("title") if isinstance(f.get("title"), str) and
                               not P.parse(f.get("title") or "")["date"] and P.is_titleish(f.get("title")) else None)
        num = p["num"] if p["num"] is not None else (tag or {}).get("num")
        orow = fr["orow"]
        if orow:
            okey = reg.idp2c.get(orow["idp"]) or canon(orow["program"])
            if key and key != okey:
                idt.setdefault("disagree", []).append({"series_by_name": key})
            key, sname, how = okey, orow["program"], "otrr_log"
            if orow["date"]:
                if date and date != orow["date"]:
                    stats["date_otrr_disagrees"] += 1
                    idt.setdefault("disagree", []).append({date_source or "name": date})
                date, date_source = orow["date"], "otrr_log"
            title = orow["title"] or title
            num = int(orow["epnum"]) if str(orow.get("epnum") or "").isdigit() and orow["epnum"] != "0" else num
            idt["otrr_eid"] = orow["eid"]
        stats["series:" + how.split(":")[0] + (":" + how.split(":")[1] if ":" in how else "")] += 1
        stats["family:" + p["family"]] += 1
        length = seconds(f.get("length"))
        kind = None
        if fr["uiuc"] and fr["uiuc"].get("speaker") and how.split(":")[0] not in ("otrr_log",) and \
                not (key in reg.re_keys or key in reg.idps):
            kind = "lecture"
        if not kind and not orow:
            kind, rule = P.content_kind(P.stem(f["name"]), length, fr["item_title"], fr["colls"], fr["text"],
                                        known_series=key in known_canon)
            # A book-and-chapter name is scripture only in an upload of many of them: "Amos 05"
            # alone is as likely Amos 'n' Andy (SCRIPTURE_ITEM_FLOOR).
            if kind == "scripture" and fr["n_scripture"] < SCRIPTURE_ITEM_FLOOR:
                kind = None
            if kind:
                idt["kind_rule"] = rule
        if sname:
            seen_names[key].add(sname)
        d = fr["d"]
        uiuc_text = (" " + (fr["uiuc"].get("title") or "")) if fr["uiuc"] else ""
        recs_out.append({"key": key, "sname": reg.display(key, sname) if key else None, "how": how, "raw": sname,
                         "title0": p["title"], "num0": num if not orow else None,
                         "date": date, "date_source": date_source, "num": num, "title": title, "aka": p["aka"],
                         "decade": p["decade"], "kind": kind, "idt": idt, "orow": orow, "length": length,
                         "rec": {
            "archive_id": ident, "file": f["name"], "format": f.get("format"), "source": f.get("source"),
            "size": int(f["size"]) if str(f.get("size", "")).isdigit() else None,
            "length_s": length, "kbps": bitrate_kbps(f), "md5": f.get("md5"),
            "variant": p["variant"], "collections": fr["colls"], "is_dark": d.get("is_dark"),
            "creator": f.get("creator") or f.get("artist") or it.get("creator"),
            "item_text": fr["text"] + uiuc_text + " " + " ".join(str(f.get(k) or "") for k in ("album", "genre", "artist")),
            "producer_text": " ".join(str(it.get(k) or "") for k in ("creator", "publisher", "contributor")),
            "otrr": ident.upper().startswith("OTRR_") or "lumedwards" in fr["colls"],
            "transcript": stem_key(f["name"]) in fr["tstems"],
            "url": f"https://archive.org/download/{ident}/{f['name']}"}})
    del files

    # Pass 3: OTRR's logs and the spine fill what the names left out.
    if "logs" not in SKIP:
        match_logs(recs_out, otrr_rows, reg, re_by_key, stats)

    # Group files into broadcasts.
    episodes = {}
    by_md5 = {}
    for r in recs_out:
        key, date, num, title = r["key"], r["date"], r["num"], r["title"]
        if not key:
            ek = None
        elif date:
            ek = f"{key}|{date}"
        elif num is not None:
            ek = f"{key}|n{num}"
        elif title and A.norm_title(title):
            ek = f"{key}|t{A.norm_title(title)}"
        else:
            ek = None
        if ek is None:
            # The same file uploaded to several items is one recording of one unknown broadcast.
            md5 = r["rec"]["md5"]
            ek = by_md5.get(md5) if md5 else None
            if ek is None:
                ek = f"x:{r['rec']['archive_id']}/{r['rec']['file']}"
                if md5:
                    by_md5[md5] = ek
            else:
                stats["x_merged_by_md5"] += 1
        ep = episodes.setdefault(ek, {"id": ek, "series_key": key if not ek.startswith("x:") else key,
                                      "series_name": r["sname"], "date": date if not ek.startswith("x:") else date,
                                      "date_source": date_source_of(r), "num": num, "title": title,
                                      "aka": r["aka"], "decade": r["decade"], "recordings": [], "kinds": [],
                                      "identity": {"series": r["how"], "as": r["raw"]}})
        if not ep["title"] and title:
            ep["title"] = title
        ep["kinds"].append(r["kind"])
        for k2, v in r["idt"].items():
            if k2 == "disagree":
                ep["identity"].setdefault("disagree", []).extend(v)
            else:
                ep["identity"].setdefault(k2, v)
        orow = r["orow"]
        if orow and orow["people"] and not ep.get("people"):
            ep["people"] = orow["people"]
            ep["otrr_eid"] = orow["eid"]
        ep["recordings"].append(r["rec"])
    # Track A's corpus kinds (editorial/extra_seeds.json): an episode whose every
    # recording comes from aircheck (DJ / Top-40) or shortwave-DX items is that
    # kind, not drama, however its file names parse.
    seed_kind = {k: v.get("kind") for k, v in
                 (load(os.path.join(ia.EDITORIAL, "extra_seeds.json"), {}).get("ids") or {}).items()}
    CORPUS_KIND = {"aircheck": "aircheck", "shortwave_dx": "shortwave"}
    for ep in episodes.values():
        ks = collections.Counter(k or "radio" for k in ep.pop("kinds"))
        ep["content_kind"] = ks.most_common(1)[0][0]
        kinds = {CORPUS_KIND.get(seed_kind.get(r["archive_id"])) for r in ep["recordings"]}
        if ep["content_kind"] == "radio" and len(kinds) == 1 and None not in kinds:
            ep["content_kind"] = kinds.pop()
        # Series name and title are tested apart: "Founder's Day Speech" + "Adolph Hitler and
        # the Nazi Movement" is a US talk ABOUT him, and only matched when joined.
        nr = NO_RECOMMEND.search(str(ep.get("title") or "")) or NO_RECOMMEND.search(str(ep.get("series_name") or ""))
        if nr:
            ep["no_recommend"] = f"Nazi-state speech or broadcast ({nr.group(0)})"
    del recs_out

    # LibriVox: each project is a "play" series; its sections are its parts.
    lv = load(os.path.join(ia.CACHE, "librivox.json.gz"), [])
    for b in lv:
        key = "librivox" + str(b["id"])
        name = b.get("title")
        reg.name[key] = name
        aid = (b.get("url_iarchive") or "").rstrip("/").rsplit("/", 1)[-1]
        for sec in sorted(b.get("sections") or [], key=lambda s: int(s.get("section_number") or 0)):
            ek = f"{key}|s{sec.get('section_number')}"
            # MEASURED 2026-10-22: 9,249 of 14,500 sections had no file_name. 2,295 name their
            # file in listen_url (same item); 6,954 belong to projects with no archive.org item
            # at all. A section with no file gets no recording, so it is never served: before
            # this, its URL was the item folder, an HTML page no player can open.
            lu = sec.get("listen_url") or ""
            file = sec.get("file_name") or (lu.split(f"/download/{aid}/", 1)[1] if aid and f"/download/{aid}/" in lu else "")
            if not (aid and file):
                stats["librivox_sections_unplayable"] += 1
            episodes[ek] = {"id": ek, "series_key": key, "series_name": name, "date": None, "date_source": None,
                            "num": int(sec.get("section_number") or 0), "title": sec.get("title"), "aka": None,
                            "decade": None, "librivox": True,
                            "recordings": [] if not (aid and file) else [{"archive_id": aid,
                                            "file": file, "format": "64Kbps MP3",
                                            "source": "librivox", "size": None,
                                            "length_s": seconds(sec.get("playtime")), "kbps": 64, "md5": None,
                                            "variant": None, "collections": ["librivoxaudio"], "is_dark": False,
                                            "creator": ", ".join(r.get("display_name") or "" for r in sec.get("readers") or []),
                                            "item_text": "", "producer_text": "", "otrr": False, "transcript": False,
                                            "url": sec.get("listen_url")}]}
            stats["librivox_sections"] += 1

    # Series-level evidence.
    by_series = collections.defaultdict(list)
    for ep in episodes.values():
        if ep["series_key"]:
            by_series[ep["series_key"]].append(ep)
    by_date = collections.defaultdict(list)
    for ep in episodes.values():
        if ep["date"]:
            by_date[ep["date"]].append(ep)
    series_foreign, series_post = {}, {}
    for k, eps in by_series.items():
        recs = [r for e in eps for r in e["recordings"]]
        hits = [A.FOREIGN.search(r["item_text"]) for r in recs]
        n = sum(1 for h in hits if h)
        if recs and n >= 2 and n / len(recs) >= 0.5:
            series_foreign[k] = {"source": "item metadata names a non-US broadcaster",
                                 "term": collections.Counter(h.group(0) for h in hits if h).most_common(1)[0][0],
                                 "share": round(n / len(recs), 2)}
        dated = [e["date"] for e in eps if e["date"]]
        if dated and min(dated) >= "1972-02-15":
            series_post[k] = {"source": "every dated episode is after 1972-02-15", "earliest": min(dated)}

    film_ren = collections.defaultdict(list)
    for r in load(AW_RENEWALS, []):
        film_ren[A.norm_title(r["t"])].append(r)
    script_ren = collections.defaultdict(list)
    for r in load(os.path.join(ia.CACHE, "cce_drama_renewals.json.gz"), []):
        name = r.get("series") or re.split(r",|\bNo\.", r["title"])[0]
        k = canon(name)
        if k in by_series and r.get("orig_year"):
            script_ren[k].append(r)
    if not script_ren:
        print("WARNING: no script renewals matched any series; work_script_renewed cannot fire", file=sys.stderr)
    series_genres = collections.defaultdict(list)
    progs = load(os.path.join(ia.CACHE, "otrrpedia", "progPedia.json.gz"), [])
    for p in sorted(progs, key=lambda p: int(p["idp"]) if str(p.get("idp", "")).isdigit() else 0):
        k = reg.idp2c.get(p.get("idp"))
        for g in p.get("genres") or []:
            if k in by_series and g.get("genre") and g["genre"] not in series_genres[k]:
                series_genres[k].append(g["genre"])
    if not series_genres:
        print("WARNING: no OTRRpedia genres matched any series; work_music_led cannot fire", file=sys.stderr)
    sched = load(os.path.join(ia.CACHE, "p72_schedules.json.gz"), {"rows": []})
    if not sched["rows"]:
        print("WARNING: no pre-1972 schedules cached; rec_schedule_claim cannot fire", file=sys.stderr)
    bt, ba = build_schedule_index(sched["rows"])
    ctx = {"takedowns": takedowns, "schedule_match": make_schedule_matcher(bt, ba), "claims": claims,
           "series_post_1972": series_post, "series_foreign": series_foreign, "gov_series": gov,
           "licence_evidence": lic_ev, "published_records": pub_rec, "film_renewals": film_ren,
           "script_renewals": script_ren, "series_genres": series_genres,
           "today": datetime.date.today()}

    # The spine: attach RadioEchoes genre and episode facts; unmatched RE episodes are wants.
    wants = []
    for k, ss in re_by_key.items():
        for s in ss:
            for e in s.get("episodes") or []:
                dt = (e.get("date") or "").replace(".", "-")
                if not re.fullmatch(r"19\d\d-\d\d-\d\d", dt):
                    continue
                ep = episodes.get(f"{k}|{dt}")
                if ep:
                    ep.setdefault("spine", {"re_title": e["title"], "re_length": e.get("length"), "re_file": e["file"]})
                    stats["spine_matched"] += 1
                else:
                    wants.append((k, dt, e["title"], e.get("length")))

    # Scripts: the Generic Radio Workshop (GRW: "Assume Copyright"), matched on
    # series + air date. Text is for search; a client shows it in full only for
    # a clean episode, and otherwise links to the GRW page.
    grw = load(os.path.join(ia.CACHE, "grw", "scripts.json"), {"scripts": []})
    script_rows = []
    for sc in grw["scripts"]:
        k = canon(sc["series"])
        ep = episodes.get(f"{k}|{sc['date']}") if sc.get("date") else None
        if ep is None and sc.get("date"):
            # GRW names some series differently ("Columbia Workshop" vs "The Columbia Workshop"):
            # fall back to any series whose episode on that date carries the same title.
            nt = A.norm_title(sc["title"].split(":")[-1])
            for cand in (e for e in by_series.get(k, []) if e["date"] == sc["date"]):
                ep = cand
            if ep is None and nt:
                ep = next((e for e in by_date.get(sc["date"], []) if A.norm_title(e.get("title")) == nt), None)
        txt = os.path.join(ia.CACHE, "grw", "text", sc["id"] + ".txt")
        script_rows.append([sc["id"], "genericradio.com", k, sc.get("date"), sc["title"], sc["url"],
                            os.path.exists(txt), ep["id"] if ep else None])
        stats["scripts"] += 1
        stats["scripts_matched"] += bool(ep)

    db_path = os.path.join(out_dir, "radio-catalog.sqlite")
    tmp = db_path + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    db = sqlite3.connect(tmp)
    db.executescript(open(os.path.join(os.path.dirname(__file__), "schema.sql")).read())
    state_count = collections.Counter()
    bucket_count = collections.Counter()
    for ep in episodes.values():
        recs = ep["recordings"]
        order_recordings(recs)
        med = median_length(recs)
        j = A.judge(ep, ctx)
        state_count[j["state"]] += 1
        bucket_count[j["rec_bucket"]] += 1
        bucket_count[j["work_bucket"]] += 1
        db.execute("INSERT INTO episodes (id, series_key, air_date, date_source, num, title, aka, decade, recordings, "
                   "median_length_s, has_transcript, spine, state, rec_bucket, work_bucket, evidence, content_kind, "
                   "identity, no_recommend) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
            ep["id"], ep["series_key"], ep["date"], ep["date_source"], ep["num"], ep["title"], ep["aka"],
            ep["decade"], len(recs), med, any(r["transcript"] for r in recs),
            json.dumps(ep.get("spine")) if ep.get("spine") else None,
            j["state"], j["rec_bucket"], j["work_bucket"], json.dumps(j["evidence"], ensure_ascii=False),
            ep.get("content_kind") or "radio",
            json.dumps(ep.get("identity"), ensure_ascii=False) if ep.get("identity") else None,
            ep.get("no_recommend")))
        for i, r in enumerate(recs):
            db.execute("INSERT INTO recordings VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (
                ep["id"], i, r["archive_id"], r["file"], r["url"], r["format"], r["source"], r["size"],
                r["length_s"], r["kbps"], r["md5"], r["variant"], r["partial"], r["transcript"]))
    for k, eps in by_series.items():
        ss = re_by_key.get(k) or []
        dates = sorted(e["date"] for e in eps if e["date"])
        db.execute("INSERT INTO series (key, name, genre, first_date, last_date, episodes, is_librivox, "
                   "foreign_evidence, claim, in_spine, otrr_programs, alias_names) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", (
            k, reg.display(k, eps[0]["series_name"]), ss[0]["genre"] if ss else None,
            dates[0] if dates else None, dates[-1] if dates else None, len(eps),
            k.startswith("librivox"), json.dumps(series_foreign.get(k)) if k in series_foreign else None,
            json.dumps(claims.get(k) or gov.get(k)) if (k in claims or k in gov) else None, bool(ss),
            json.dumps(sorted(reg.idps[k])) if reg.idps.get(k) else None,
            json.dumps(sorted(seen_names.get(k) or [])[:50], ensure_ascii=False) if seen_names.get(k) else None))
    for ak, ck in reg.k2c.items():
        if ck in by_series:
            alias, source = reg.src[ak]
            db.execute("INSERT INTO series_aliases VALUES (?,?,?,?)", (ak, ck, alias, source))
    for it in items.values():
        db.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?)", (
            it["id"], it["title"], json.dumps(it["collections"]), it["licenseurl"], it["uploader"],
            it["publicdate"], bool(it["is_dark"]), it["reviews"], it["avg_stars"], it["transcripts"]))
    for ep in episodes.values():
        for pp in ep.get("people") or []:
            db.execute("INSERT INTO credits VALUES (?,?,?,?,?)", (ep["id"], pp["id"], pp["name"], pp["role"], "otrr.org"))
    # OTRR log rows that say a recording survives but name no file we harvested.
    for r in otrr_rows:
        if r["exists"] and r["date"] and not r["files"]:
            k = reg.idp2c.get(r["idp"]) or canon(r["program"])
            if f"{k}|{r['date']}" not in episodes:
                wants.append((k, r["date"], r["title"], "otrr"))
    states = dict(db.execute("SELECT id, state FROM episodes").fetchall())
    for r in script_rows:
        display = "full" if r[7] and states.get(r[7]) == "keep_clean" else "link"
        db.execute("INSERT INTO scripts VALUES (?,?,?,?,?,?,?,?,?)", (*r, display))
    db.executemany("INSERT INTO wants VALUES (?,?,?,?)", wants)
    stats["otrr_rows"] = len(otrr_rows)
    stats["otrr_files"] = len(otrr_by_file)
    db.execute("INSERT INTO meta VALUES (?,?)", ("built", datetime.datetime.now(datetime.timezone.utc).isoformat()))
    db.execute("INSERT INTO meta VALUES (?,?)", ("pd_published_year", str(A.pd_published_year())))
    db.commit()
    db.execute("VACUUM")
    db.close()
    os.replace(tmp, db_path)

    report = {"items": len(items), "episodes": len(episodes), "series": len(by_series),
              "states": dict(state_count), "buckets": dict(bucket_count), "wants": len(wants),
              "spine_series": len(re_series), "schedules_rows": len(sched["rows"]),
              "librivox_projects": len(lv), "stats": dict(stats), "seconds": round(time.time() - t0)}
    ia.write_json(os.path.join(out_dir, "build_report.json"), report)
    print(json.dumps({k: report[k] for k in ("items", "episodes", "series", "states", "wants")}, indent=1))
    # A build that judged nothing is a failed build (ENGINEERING-PROCESS §2).
    if not episodes:
        sys.exit(1)


if __name__ == "__main__":
    main()
