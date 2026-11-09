"""The audio rights audit: two ordered layers, hides before rescues, first match wins.

Owner, 2026-10-17: "I like the idea of moving to a 'take down request' model
for this, but a licensed model at $1000 per year is definitely not in keeping
with our regular process." So an unclaimed pre-1972 broadcast is KEPT
(`keep_unclaimed`), and hidden the moment a claim a reader can open appears;
no recording is kept on a paid licence.

Why that posture holds (docs/research/02-rights.md §12, statute read
2026-10-17): 17 U.S.C. §1401(f)(5) bars statutory damages and fees unless the
owner filed a schedule; §1401(f)(3) applies the §512 safe harbor. The app
never calls `keep_unclaimed` public domain (Decision 153's lesson).

States, in the order a client must treat them:
    keep_clean        public domain, a PD dedication, or a government work
    keep_unclaimed    no claim found; removed on request
    hide_claim        a claim a reader can open (schedule, claimant, takedown,
                      renewal, post-1972, non-US origin)
    hide_unidentified no series or date to check a claim against
    hide_out_of_scope identified as music, a modern podcast, scripture, a DJ aircheck or shortwave DX
"""
import datetime
import re

FOREIGN = re.compile(
    r"\b(BBC|B\.B\.C\.|CBC|Canadian Broadcasting|Radio[- ]Canada|Australian Broadcasting|"
    r"ABC Australia|Grace Gibson|Springbok Radio|SABC|Radio New Zealand|NZBC|RTE Radio|"
    r"Radio Luxembourg)\b"
    # A BBC programme id in brackets ("[b007k108]", "[m000fg0q]") names the programme page at bbc.co.uk/programmes:
    # the file was taken from a BBC broadcast (DECISIONS 032).
    r"|\[(?:b0|m0|p0)[0-9a-z]{6}\]")
GOV_PRODUCER = re.compile(
    r"\b(Office of War Information|Voice of America|U\.?S\.? Treasury|Treasury Department|"
    r"Federal Civil Defense|United States Army|United States Navy|U\.?S\.? Army|U\.?S\.? Navy)\b", re.I)
ADAPTATION_SERIES = {"luxradiotheater", "screenguildtheater", "screenguildplayers", "academyawardtheater",
                     "screendirectorsplayhouse", "hollywoodstartime", "hollywoodradiotheater"}
POST_1972 = datetime.date(1972, 2, 15)
# A claimant who renewed this many of a series' scripts is claiming the series:
# the printed catalogs lose a quarter to a third of entries to OCR (MEASURED,
# fetch_cce_drama_renewals), so an unmatched episode of such a series is more
# likely a lost entry than an unrenewed script. A default for the owner (README).
SERIES_RENEWAL_FLOOR = 10
# A series whose program genres lead with music, or carry music and no story genre,
# is built on songs, whose copyrights are registered and actively claimed: hidden,
# stricter than drama (owner, 2026-10-22; DECISIONS 006). Genres are OTRRpedia's,
# in its own order; comedy with songs (Jack Benny: Comedy, Variety, Music) stays.
MUSIC_GENRES = {"Music", "Songs", "Country Music"}
STORY_GENRES = {"Comedy", "Sitcom", "Drama", "Anthology Drama", "Anthology", "Mystery", "Suspense", "Western",
                "Crime", "Adventure", "Serial", "Romance", "Science Fiction", "Horror", "Private Detective",
                "Police", "Action", "Youth", "Super Hero"}

# An AFRS original is kept as government work only when no performer is credited
# (owner, 2026-10-22; DECISIONS 006): the stars of Command Performance were on loan
# from the networks, and their performances carry their own claims. A credit in any
# other role (announcer, writer, crew) is the agency's own.
NON_PERFORMER_ROLES = {"announcer", "writer", "author", "producer", "director", "engineer", "sound effects",
                       "production", "script", "adaptation", "adapter"}


MONTHS = "january|february|march|april|may|june|july|august|september|october|november|december"
MODERN_DATE = re.compile(r"(?<![\d\w])(19[7-9]\d|20[0-4]\d)[-._ ]?(0[1-9]|1[0-2])[-._ ]?(0[1-9]|[12]\d|3[01])(?!\d)|"
                         r"\b(?:" + MONTHS + r")\s+\d{1,2},?\s+(19[7-9]\d|20[0-4]\d)\b", re.I)
BRACKETED = re.compile(r"\[[^\]]*\]|\([^)]*\)")


def modern_date(*texts):
    """A full date after POST_1972 that an episode's own file name or title carries outside brackets, else None:
    "BBC R4 SD - A Slow Air by David Harrower 20121201", "The-Big-Broadcast-2003-05-04". A bracketed or
    parenthesized date is a note on the copy (a rebroadcast "[2018-03-08]", "(Recreation 4-22-2016)") and is not
    read (DECISIONS 032)."""
    for t in texts:
        for m in MODERN_DATE.finditer(BRACKETED.sub(" ", t or "")):
            y = int(m.group(1) or m.group(4))
            if m.group(1):
                try:
                    d = datetime.date(y, int(m.group(2)), int(m.group(3)))
                except ValueError:
                    continue
                if d >= POST_1972:
                    return d.isoformat()
            elif y > 1972:
                return m.group(0)
    return None


def foreign_series(item_texts):
    """Evidence that a series is a non-US production, or None: its items' own metadata names a non-US broadcaster
    on two recordings and half of them, or on its only recording (DECISIONS 032: the two-recording floor let every
    one-recording BBC upload through, "King David by Katie Hims", "BBC R3")."""
    hits = [FOREIGN.search(t or "") for t in item_texts]
    n = sum(1 for h in hits if h)
    if item_texts and n >= min(2, len(item_texts)) and n / len(item_texts) >= 0.5:
        terms = {}
        for h in hits:
            if h:
                terms[h.group(0)] = terms.get(h.group(0), 0) + 1
        return {"source": "item metadata names a non-US broadcaster",
                "term": max(sorted(terms), key=lambda t: terms[t]), "share": round(n / len(item_texts), 2)}
    return None


def credited_performers(ep):
    return [p["name"] for p in ep.get("people") or []
            if (p.get("role") or "").strip().lower() not in NON_PERFORMER_ROLES]


def music_led(genres):
    g = list(genres or ())
    return bool(g) and (g[0] in MUSIC_GENRES or (bool(set(g) & MUSIC_GENRES) and not set(g) & STORY_GENRES))


def norm_title(t):
    t = (t or "").lower()
    t = re.sub(r"^(the|a|an)\s+", "", t)
    return re.sub(r"[^a-z0-9]", "", t)


def pd_published_year(today=None):
    """Newest first-publication year freed by §1401(a)(2)(B)(ii): 1925 in 2026."""
    return (today or datetime.date.today()).year - 101


def rec_bucket(ep, ctx):
    """Recording layer. `ep`: dict with series_key, date (YYYY-MM-DD or None),
    title, recordings[{archive_id, file, item_text, collections, variant, is_dark}].
    `ctx`: the evidence indexes built by build_db."""
    key, date = ep["series_key"], ep.get("date")
    recs = ep["recordings"]
    ev = []

    for t in ctx["takedowns"]:
        if (t["scope"] == "series" and t["key"] == key) or \
           (t["scope"] in ("episode", "recording") and t["key"] in (ep["id"], *[r["archive_id"] for r in recs])):
            return "rec_takedown", [t]
    if recs and all(r.get("is_dark") for r in recs):
        return "rec_takedown", [{"source": "archive.org item is dark"}]

    sched = ctx["schedule_match"](ep)
    if sched:
        return "rec_schedule_claim", sched

    claim = ctx["claims"].get(key)
    if claim and claim["layer"] == "recording":
        return "rec_rights_holder_claim", [claim]

    if date and datetime.date.fromisoformat(date) >= POST_1972:
        return "rec_post_1972", [{"date": date}]
    modern = None if date else modern_date(ep.get("title"), *[(r.get("file") or "").rsplit("/", 1)[-1] for r in recs[:1]])
    if modern:
        return "rec_post_1972", [{"date_in_name": modern, "source": "the episode's own file name or title"}]
    if ctx["series_post_1972"].get(key):
        return "rec_post_1972", [ctx["series_post_1972"][key]]

    if ctx["series_foreign"].get(key):
        return "rec_foreign_origin", [ctx["series_foreign"][key]]

    gov = ctx["gov_series"].get(key)
    afrs_stars = bool(gov) and "Armed Forces Radio" in (gov.get("agency") or "") and credited_performers(ep)
    if gov and not afrs_stars:
        return "rec_gov_work", [gov]
    for r in recs if not afrs_stars else ():
        m = GOV_PRODUCER.search(r.get("producer_text") or "")
        if m and not r.get("variant"):
            ev.append({"archive_id": r["archive_id"], "producer": m.group(0)})
    if ev and len(ev) == len(recs):
        return "rec_gov_work", ev

    if any("librivoxaudio" in (r.get("collections") or []) for r in recs) or ep.get("librivox"):
        return "rec_librivox", [{"source": "LibriVox: all recordings are public domain"}]

    for r in recs:
        lic = ctx["licence_evidence"].get(r["archive_id"]) or ctx["licence_evidence"].get(key)
        if lic:
            return "rec_cc_corroborated", [lic]

    for r in recs:
        pub = ctx["published_records"].get(r["archive_id"] + "/" + r["file"]) or ctx["published_records"].get(r["archive_id"])
        if pub and int(pub["year"]) <= pd_published_year(ctx.get("today")):
            return "rec_pd_published_age", [pub]

    if not key or (not date and not ep.get("num") and not ep.get("title")):
        return "rec_no_evidence", []
    return "rec_orphan_unclaimed", []


def work_bucket(ep, ctx):
    """Underlying-work layer: scripts and the stories or films they adapt."""
    key = ep["series_key"]
    claim = ctx["claims"].get(key)
    if claim and claim["layer"] == "work":
        return "work_script_claim", [claim]
    genres = ctx.get("series_genres", {}).get(key)
    if music_led(genres):
        return "work_music_led", [{"genres": genres, "source": "OTRRpedia program genres"}]
    live = [r for r in ctx.get("script_renewals", {}).get(key, [])
            if r["orig_year"] + 96 > (ctx.get("today") or datetime.date.today()).year]
    if live and ep.get("date"):
        air = datetime.date.fromisoformat(ep["date"])
        nt = norm_title(ep.get("title"))
        for r in live:
            reg = datetime.date.fromisoformat(r["orig_date"]) if r.get("orig_date") else None
            same_title = nt and len(nt) >= 6 and nt in (norm_title(r.get("episode")), norm_title(r.get("title")))
            if (same_title and reg and abs(reg.year - air.year) <= 1) or (reg and abs((reg - air).days) <= 30):
                return "work_script_renewed", [_renewal_ev(r)]
    if len(live) >= SERIES_RENEWAL_FLOOR:
        return "work_series_renewals", [{"renewals": len(live), "first": _renewal_ev(live[0])}]
    if key in ADAPTATION_SERIES and ep.get("date") and ep.get("title"):
        year = int(ep["date"][:4])
        for r in ctx["film_renewals"].get(norm_title(ep["title"]), []):
            if r["y"] <= year <= r["y"] + 6:
                return "work_adapted_renewed", [{"film": r["t"], "year": r["y"], "renewal": r["r"],
                                                 "registration": r["reg"],
                                                 "source": f"https://archive.org/details/{r['vol']}"}]
    return "work_none_found", []


REC_STATE = {
    "rec_takedown": "hide_claim", "rec_schedule_claim": "hide_claim", "rec_rights_holder_claim": "hide_claim",
    "rec_post_1972": "hide_claim", "rec_foreign_origin": "hide_claim",
    "rec_gov_work": "keep_clean", "rec_librivox": "keep_clean", "rec_cc_corroborated": "keep_clean",
    "rec_pd_published_age": "keep_clean",
    "rec_orphan_unclaimed": "keep_unclaimed", "rec_no_evidence": "hide_unidentified",
}
WORK_HIDES = {"work_script_claim", "work_music_led", "work_script_renewed", "work_series_renewals", "work_adapted_renewed"}


def _renewal_ev(r):
    return {"source": r.get("src"), "registration": r.get("reg"), "registered": r.get("orig_date"),
            "renewal": r.get("r") or r.get("r_printed"), "renewed": r.get("r_date"), "claimant": r.get("claimant"),
            "printed": r.get("text")}


# Identified but not a radio drama/program broadcast (build_db's content_kind):
# not this app's catalog, whatever its rights. Commercials and station lectures
# ARE broadcasts and stay in. Airchecks (DJ / Top-40 shows: other owners' records,
# many on the pre-1972 schedules) and shortwave DX (foreign stations) are out by
# default — owner questions in README.
OUT_OF_SCOPE = {"music", "podcast", "scripture", "aircheck", "shortwave"}


def judge(ep, ctx):
    if ep.get("content_kind") in OUT_OF_SCOPE:
        return {"rec_bucket": "rec_out_of_scope", "work_bucket": "work_none_found", "state": "hide_out_of_scope",
                "evidence": [{"content_kind": ep["content_kind"]}]}
    rb, rev = rec_bucket(ep, ctx)
    wb, wev = work_bucket(ep, ctx)
    state = REC_STATE[rb]
    if wb in WORK_HIDES and state != "hide_unidentified":
        state = "hide_claim"
    return {"rec_bucket": rb, "work_bucket": wb, "state": state, "evidence": rev + wev}
