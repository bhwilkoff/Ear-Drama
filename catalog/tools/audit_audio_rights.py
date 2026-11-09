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
    r"Radio Luxembourg|Aussie|[2-7][A-Z]{2}\s+(?:Melbourne|Sydney|Adelaide|Brisbane|Perth|Hobart))\b"
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
# P-12 (catalog DECISIONS 033): a date that is not a full date still dates a production. The month names as written,
# never a word that begins with one ("Marshall", "Jane").
MONTH_WORD = (r"(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sept?(?:ember)?|"
              r"oct(?:ober)?|nov(?:ember)?|dec(?:ember)?|enero|febrero|marzo|abril|mayo|junio|julio|agosto|"
              r"septiembre|octubre|noviembre|diciembre)\.?")
MODERN_YEAR = r"(19[7-9]\d|20[0-4]\d)"
PARTIAL_DATES = (
    ("month and year", re.compile(r"(?<![a-z])" + MONTH_WORD + r"[\s,._-]*(?:de\s+)?" + MODERN_YEAR + r"(?!\d)", re.I)),
    ("day, month and year", re.compile(r"(?<!\d)(\d{1,2})[\s._/-](\d{1,2})[\s._/-]" + MODERN_YEAR + r"(?!\d)")),
    ("year", re.compile(r"(?<![\d\w'’])" + MODERN_YEAR + r"(?![\d\w'’])")),
)
DATE_ONLY = re.compile(r"^[\s\d.,/_-]*(?:(?:\d{1,2}(?:st|nd|rd|th)?|" + MONTH_WORD + r")[\s\d.,/_-]*)*$", re.I)
FULL_ISO = re.compile(r"(?<!\d)(?:19|20)\d\d[-._ ]?\d\d[-._ ]?\d\d(?!\d)")
OWN_DATE = re.compile(r"(?<!\d)(?:1[89]\d\d|\d\d)[-._ ]\d{1,2}[-._ ]\d{1,2}(?!\d)|(?<!\d)\d{1,2}[-._ ]\d{1,2}[-._ ]\d\d(?!\d)")


def _readable(t):
    """The text with every bracket that holds anything but a date blanked (a note: "[Rpt BBC7 3 Oct 2003]",
    "(Recreation 4-22-2016)"). A bracket that holds only a date is the copy's own date ("(2015)", "(28th July
    2012)"), unless the text carries a date of its own outside it, when the bracket notes a rebroadcast ("Navy
    Lark - 1966-10-16 - The Army Lark [2019-05-29]")."""
    t = re.sub(r"\.(?:mp3|ogg|flac|m4a|wav|opus|aac|wma)$", "", (t or ""), flags=re.I).replace("_", " ")
    outside = BRACKETED.sub(" ", t)
    own = bool(OWN_DATE.search(outside))
    return BRACKETED.sub(lambda m: " " if own or not DATE_ONLY.match(m.group(0)[1:-1]) else " " + m.group(0) + " ", t)


def modern_date(*texts, partial=False, name=None, bare=True):
    """A full date after POST_1972 that an episode's own file name or title carries outside brackets, else None:
    "BBC R4 SD - A Slow Air by David Harrower 20121201", "The-Big-Broadcast-2003-05-04". A bracketed or
    parenthesized date is a note on the copy (a rebroadcast "[2018-03-08]", "(Recreation 4-22-2016)") and is not
    read (DECISIONS 032). With `partial` (DECISIONS 033) a month and year ("Oct 2019"), a day, month and year
    ("18 10 2025", "14.03.1988"), a year on its own ("Upstate Radio Theatre 2004") or a bracket holding only a date
    ("(2015)") count too: a year after 1972 dates the production after 1972 whatever the rest of the date is. A year
    the series' own `name` carries ("2000 Plus") or a title that is only a year ("1984") is a name, not a date."""
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
    if partial:
        for t in texts:
            r = _readable(t)
            for how, rx in PARTIAL_DATES:
                for m in rx.finditer(r):
                    y = m.groups()[-1]
                    if int(y) <= 1972 or (how == "year" and not bare and r[m.start() - 1:m.start()] not in ("(", "[")):
                        continue
                    if how == "year" and (y in re.findall(r"\d+", name or "") or
                                          not re.search(r"[^\W\d_]", r[:m.start()] + r[m.end():])):
                        continue
                    return m.group(0).strip()
    return None


def series_name_year(name):
    """A year after 1972 that an upload-named series' own name carries outside brackets ("WKBW 1973 Halloween Show",
    "Upstate Radio Theatre 2018"), else None (DECISIONS 033)."""
    for m in PARTIAL_DATES[2][1].finditer(BRACKETED.sub(" ", (name or "").replace("_", " "))):
        if int(m.group(1)) > 1972:
            return m.group(1)
    return None


# P-12 (DECISIONS 033): a production label the upload or its registry writes beside the name ("Lux Radio Theater - AU",
# "The Fat Man (Australia)", "Aus 62 Rocky Starr", "High Adventure (South Africa)"): the production is not American (006).
COUNTRY_LABEL = re.compile(
    r"\b(?:Sth|South) African\b|[(\[]\s*(?:au|aus|aust|australia|australian|nz|new zealand|south africa|s\.?a\.?|uk|u\.k\.|britain|british|"
    r"canada|canadian|ireland|irish)\s*[)\]]|"
    r"(?:\s[-–]\s*|\s)(?:AU|Aus|NZ)\s*$|^Aus\s+(?:\d+\b|[-–])")
COUNTRY_LABEL_CI = re.compile(r"[(\[]\s*(?:au|aus|aust|australia|australian|nz|new zealand|south africa|s\.?a\.?|uk|"
                              r"u\.k\.|britain|british|canada|canadian|ireland|irish)\s*[)\]]", re.I)


def country_label(text):
    """The production label `text` carries, or None."""
    t = (text or "").strip()
    m = COUNTRY_LABEL_CI.search(t) or COUNTRY_LABEL.search(t)
    return m.group(0).strip(" -–") if m else None


# A recording in another language is another country's production (006), read from archive.org's own `language`
# field, else from the title's own script or words. Speeches and addresses are kept whatever their language
# (owner 2026-10-31, "Keep them"; DECISIONS 027), and so is a US government service broadcasting abroad.
ENGLISH = {"eng", "en", "english", "english-handwritten", "en-us", "en-gb", "en_us", "american english"}
NO_LANGUAGE = {"", "und", "zxx", "mul", "none", "unknown"}
SPEECH = re.compile(r"\b(?:speech(?:es)?|address(?:es)?|speaks|spricht|\w*rede|reden|\w*ansprache|kundgebung\w*|"
                    r"aufruf|appell|proklamation|discours|discorso|discurso|allocution|proclamation|declaration|"
                    r"sportpalast\w*|reichstag\w*|\w*kongress\w*|\w*parteitag\w*|\w*versammlung\w*|wahlkampf\w*)\b", re.I)
FOREIGN_WORDS = {"der", "das", "und", "mit", "von", "ein", "eine", "ueber", "über", "auf", "dem", "den", "des", "im",
                 "zum", "zur", "nicht", "ist", "le", "les", "du", "une", "et", "avec", "pour", "dans", "sur", "est",
                 "el", "los", "las", "del", "una", "con", "por", "para", "het", "een", "van", "met", "voor", "niet",
                 "il", "gli", "della", "di", "che", "uma", "da", "dos", "não", "och", "på", "är", "og", "af", "til",
                 "jeg", "en", "de", "la", "deel", "aflevering", "op", "aan", "bij", "naar", "uit"}
# A genre word the item's own record writes in another language: a Dutch or German radio play or audiobook.
FOREIGN_GENRE = re.compile(r"\b(?:hoorspel\w*|h(?:ö|oe)rspiel\w*|luisterboek\w*|h(?:ö|oe)rbuch\w*)\b", re.I)
ENGLISH_WORDS = {"the", "and", "of", "with", "for", "from", "his", "her", "my", "your", "show", "episode", "part",
                 "this", "that", "who", "what", "when"}   # none of them a word of the languages above
SCRIPTS = re.compile(r"[Ͱ-ϿЀ-ӿ֐-׿؀-ۿऀ-෿฀-๿"
                     r"぀-ヿ㐀-鿿가-힯]")


def title_language(text):
    """'script' when most letters of `text` are in a non-Latin script, 'words' when it has two distinct function
    words of another language and none of English, else None. A name ("Le Petit Prince") is one word, not two."""
    t = (text or "")
    letters = re.findall(r"[^\W\d_]", t)
    if letters and sum(1 for c in letters if SCRIPTS.match(c)) * 2 > len(letters):
        return "script"
    words = re.findall(r"[^\W\d_]+", t.casefold())
    if len(words) >= 3 and not set(words) & ENGLISH_WORDS and len(set(words) & FOREIGN_WORDS) >= 2:
        return "words"
    return None


def language_of(value):
    """archive.org's language field, normalized: 'english', None (unknown), or the code it gives."""
    vals = value if isinstance(value, list) else [value]
    vals = [str(v).strip().casefold() for v in vals if v is not None]
    if any(v in ENGLISH for v in vals):
        return "english"
    vals = [v for v in vals if v not in NO_LANGUAGE]
    return vals[0] if vals else None


def foreign_language(ep, item_language, item_text=None):
    """Evidence that an episode is a recording in another language, or None (DECISIONS 033). `item_language`:
    archive.org item -> language_of(its field); `item_text`: item -> its title and subjects. Every recording's
    item names a language other than English, or (none naming one) the title and file name are in another
    script or another language's words. A speech or address (027) and a US government producer are kept."""
    recs = ep.get("recordings") or []
    if not recs or ep.get("librivox"):
        return None
    item_text = item_text or {}
    langs = [item_language.get(r["archive_id"]) for r in recs]
    known = [l for l in langs if l]
    ev = None
    if known and all(l != "english" for l in known):
        ev = {"source": "archive.org item language", "language": known[0]}
    elif not known:
        how = title_language(" ".join([ep.get("title") or ""] + [(r.get("file") or "").rsplit("/", 1)[-1] for r in recs[:1]]))
        if how:
            ev = {"source": "the title's own " + ("script" if how == "script" else "words"), "language": "not English"}
        elif any(FOREIGN_GENRE.search(item_text.get(r["archive_id"]) or "") for r in recs):
            ev = {"source": "the item's own record names a radio play or audiobook in another language",
                  "language": "not English"}
    if not ev:
        return None
    said = " ".join([ep.get("title") or "", ep.get("series_name") or ""] +
                    [(r.get("file") or "").rsplit("/", 1)[-1] + " " + (item_text.get(r["archive_id"]) or "") for r in recs])
    if SPEECH.search(said) or any(GOV_PRODUCER.search(r.get("producer_text") or "") for r in recs):
        return None
    return ev


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
    # The file's whole name in its item, folders included ("Bob & Ray - 1973 - WOR, NY - Skits/04 - Chat ...").
    own = [ep.get("title")] + [(r.get("file") or "").replace("/", " / ") for r in recs[:1]]
    # A dated episode whose own name carries no date of its own but a year after 1972 ("75th Anniversary Special
    # (2013)", dated by a log) is that later production (DECISIONS 033).
    modern = (modern_date(*own, partial=True, name=ep.get("series_name")) if not date else
              modern_date(*[t for t in own if not OWN_DATE.search(BRACKETED.sub(" ", (t or "").replace("_", " ")))
                            and not FULL_ISO.search(t or "")], partial=True, name=ep.get("series_name"), bare=False))
    if modern:
        return "rec_post_1972", [{"date_in_name": modern, "source": "the episode's own file name or title"}]
    if ctx["series_post_1972"].get(key):
        return "rec_post_1972", [ctx["series_post_1972"][key]]

    if ctx["series_foreign"].get(key):
        return "rec_foreign_origin", [ctx["series_foreign"][key]]
    lang = None if key in (ctx.get("us_series") or ()) else foreign_language(ep, ctx.get("item_language") or {},
                                                                              ctx.get("item_subjects"))
    if lang:
        return "rec_foreign_origin", [lang]
    label = country_label(ep.get("title")) or next(
        (country_label(re.sub(r"\.\w{2,4}$", "", (r.get("file") or "").rsplit("/", 1)[-1])) for r in recs[:1]), None)
    if label:   # "Gunsmoke(Aus) xx-xx-xx Al Galeco (Aus)": that episode is the Australian production (DECISIONS 033)
        return "rec_foreign_origin", [{"source": "the episode's own title or file name carries a production label",
                                       "term": label}]

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
