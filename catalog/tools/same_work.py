"""A rights hide follows the work, wherever an upload filed it (catalog DECISIONS 032).

Owner, 2026-11-09: "Obviously The Shadow is still under copyright. All seasons should be hidden if the
copyright is still active." The audit (audit_audio_rights.py) judges an episode by its series key, so a
series hidden for a claim on the work (a named claimant, a series takedown, a series' renewed scripts)
stayed served wherever an upload gave the same broadcasts another name: "Season 11 (9-7-47 to 5-30-48)",
"20 best The Shadow", "The Shadow Recreations", a reel or a station's day. This module finds them, from
what the build already holds; build_db then judges each one under the hidden work's key (the same audit,
the same claims file, no second list), and records why in the episode's evidence.

Three rules, each on evidence a reader can open:

  broadcast  an episode with the same full air date and the same title (six letters or more, not either
             series' own name) as an episode hidden for a claim, when its series is upload-named, the two
             share an archive.org item, or the two series repeat each other MIN_SHARED times (P-10's test
             for one broadcast in two places, DECISIONS 031). It takes that episode's verdict.
  series     an upload-named series more than half of whose dated episodes (MIN_SHARED at least) are a
             hidden work's broadcasts by date and title is that work's upload ("Season 11"): every episode.
  named      an upload-named series whose name carries a hidden work's name as whole words, not followed
             by "of" or "'s" ("The Shadow of a Gunman" is another work), with at least one episode that
             carries a title or a broadcast of that work: every episode ("The Shadow Recreations" re-perform
             its scripts; a re-performance of a claimed script is the claimed work).

A LibriVox project is never caught: it reads a public-domain text.
"""
import re

import display_text as DT

MIN_SHARED = DT.MIN_SHARED
# The buckets whose claim is on the work or on its recordings as a program, and so follows them: a named
# claimant, a takedown, a renewed script (one or the series'), a scheduled recording. A post-1972 date or a
# foreign producer describes one production, not the work, and is judged where it stands.
FOLLOW = {"rec_takedown", "rec_schedule_claim", "rec_rights_holder_claim", "work_script_claim",
          "work_script_renewed", "work_series_renewals"}
SERIES_WIDE = {"rec_rights_holder_claim", "work_script_claim", "work_series_renewals", "rec_takedown"}
NOT_AFTER = {"of", "s"}


TRAIL_NOTE = re.compile(r"\s*\([^()]*\)\s*$")
LEADS = re.compile(r"^\s*(?:the\s+)?(?P<name>.+?)\s*(?:\s-+\s|:\s)")


def title_key(title, *series_names):
    """The comparable form of a title, or None when it is short or only a series' own name. A trailing
    parenthetical is a note on this copy ("Struggle with Death (Recreation 4-11-2019)"), not the title."""
    t = title or ""
    for _ in range(2):
        t2 = TRAIL_NOTE.sub("", t)
        t = t2 if t2.strip() else t
    k = DT._title_key(t)
    if not k:
        return None
    for n in series_names:
        if n and k == " ".join(DT.name_tokens(n)):
            return None
    return k


def name_carries(name, work):
    """True when `name` carries `work`'s name (article dropped) as whole words, not followed by of / 's."""
    w = DT.name_tokens(work)
    if not w or not DT._strong_name(w):
        return False
    t = DT._tokens(re.sub(r"['’]s\b", " s", name or ""))
    n = len(w)
    for i in range(len(t) - n + 1):
        if tuple(t[i:i + n]) == w and (i + n == len(t) or t[i + n] not in NOT_AFTER):
            return True
    return False


def name_leads(name, work):
    """True when `name` is "<work> - <a title>" or "<work>: <a title>": the program-and-title form, the
    program's name leading (reattribute.stem_program's evidence)."""
    m = LEADS.match(name or "")
    return bool(m) and DT.name_tokens(m.group("name")) == DT.name_tokens(work) and DT._strong_name(DT.name_tokens(work))


def _title_in(k, titles):
    """A title the work has, or one that begins with a work title of two words or more ("The Death House
    Rescue Psychological")."""
    if not k:
        return False
    return k in titles or any(" " in t and len(t) >= 10 and k.startswith(t + " ") for t in titles)


def find(eps, series, verdicts, item_names=None):
    """{episode id: {"key": work key, "rule": broadcast|series|named, "episode": the hidden episode or None}}.

    eps: id -> (series key, air date or None, title or None, set of archive.org items).
    series: key -> {"name": str, "own": bool (no registry knows it), "librivox": bool}.
    verdicts: id -> (state, rec_bucket, work_bucket) from the first pass of the audit.
    item_names: archive.org item -> its identifier and title as one string (an item that names the work
    is evidence for a broadcast it carries).
    Only episodes the first pass served are returned."""
    item_names = item_names or {}

    def hidden(e):
        st, rb, wb = verdicts[e]
        return st == "hide_claim" and (rb in FOLLOW or wb in FOLLOW)

    def served(e):
        return verdicts[e][0] in ("keep_clean", "keep_unclaimed")

    def dated(air):
        return bool(air) and len(air) == 10

    of_series = {}
    for e in sorted(eps):
        of_series.setdefault(eps[e][0], []).append(e)
    wide = {}
    for sk, es in of_series.items():
        n = sum(1 for e in es if hidden(e) and (verdicts[e][1] in SERIES_WIDE or verdicts[e][2] in SERIES_WIDE))
        if sk and sk in series and n * 2 > len(es):
            wide[sk] = True
    works = set(wide)
    run, work_titles = {}, {}
    for hk in works:
        ds = sorted(eps[e][1] for e in of_series[hk] if dated(eps[e][1]))
        run[hk] = (ds[0], ds[-1]) if ds else (None, None)
        work_titles[hk] = {k for k in (title_key(eps[e][2], series[hk]["name"]) for e in of_series[hk]) if k}

    by_bt = {}
    for e in sorted(eps):
        sk, air, title, _items = eps[e]
        if sk and dated(air) and hidden(e):
            k = title_key(title, series.get(sk, {}).get("name"))
            if k:
                by_bt.setdefault((air, k), []).append(e)

    cands, shared = [], {}
    for e in sorted(eps):
        sk, air, title, _items = eps[e]
        if not sk or not served(e) or not dated(air) or series.get(sk, {}).get("librivox"):
            continue
        k = title_key(title)
        for h in by_bt.get((air, k), ()) if k else ():
            hk = eps[h][0]
            if hk != sk and k == title_key(title, series[hk]["name"]):
                cands.append((e, h))
                pair = (min(sk, hk), max(sk, hk))
                shared[pair] = shared.get(pair, 0) + 1
                break

    out, hits = {}, {}
    for e, h in cands:
        sk, hk = eps[e][0], eps[h][0]
        if hk in works:
            hits.setdefault((sk, hk), set()).add(e)
        named = any(name_carries(item_names.get(a, ""), series[hk]["name"]) for a in eps[e][3])
        if series[sk]["own"] or (eps[e][3] & eps[h][3]) or named or shared[(min(sk, hk), max(sk, hk))] >= MIN_SHARED:
            out[e] = {"key": hk, "rule": "broadcast", "episode": h}

    whole = {}
    for (sk, hk), es in sorted(hits.items()):
        v = series.get(sk, {})
        n_dated = sum(1 for e in of_series.get(sk, ()) if dated(eps[e][1]))
        if v.get("own") and not v.get("librivox") and len(es) >= MIN_SHARED and len(es) * 2 > n_dated:
            whole.setdefault(sk, (hk, "series"))
    for sk in sorted(of_series):
        v = series.get(sk)
        if not v or sk in whole or sk in works or not v.get("own") or v.get("librivox"):
            continue
        mine = of_series[sk]
        for hk in sorted(works):
            if not name_carries(v["name"], series[hk]["name"]):
                continue
            days = [eps[e][1] for e in mine if dated(eps[e][1])]
            corroborated = (
                bool(hits.get((sk, hk)))
                or any(_title_in(title_key(eps[e][2], v["name"], series[hk]["name"]), work_titles[hk]) for e in mine)
                or (bool(days) and DT._in_run(days, run[hk], years=0))
                or any(name_leads(t, series[hk]["name"]) for t in [v["name"]] + [eps[e][2] for e in mine]))
            if corroborated:
                whole[sk] = (hk, "named")
                break
    for sk in sorted(whole):
        for e in of_series[sk]:
            if served(e) and e not in out:
                out[e] = {"key": whole[sk][0], "rule": whole[sk][1], "episode": None}
    return out
