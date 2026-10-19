"""Episode identity from archive.org file names and ID3 album tags.

Copied from tools/probe_otr_corpus.py (MEASURED 2026-10-17: 14 families parse
93.8% of 16,544 sampled episode files, 80% to a full broadcast date). Every
pattern's example is a real file name; see docs/research/radio/07.
"""
import re


def seconds(length):
    if length in (None, ""):
        return None
    parts = str(length).split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        return float(parts[0])
    except ValueError:
        return None


def stem(name):
    base = name.rsplit("/", 1)[-1]
    return re.sub(r"\.[A-Za-z0-9]{2,4}$", "", base)


def valid_date(y, m, d):
    try:
        y, m, d = int(y), int(m), int(d)
    except (TypeError, ValueError):
        return False
    if not (1920 <= y <= 1999 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    import datetime
    try:
        datetime.date(y, m, d)
        return True
    except ValueError:
        return False


# Filename families, in the order they are tried. Every example is a real
# file name measured 2026-10-17 (item id in brackets).
# yy may be "4x" (decade known, year not) or "xx"; month/day may be "xx".
_D = r"(?P<yyyy>19[2-9]\d)|(?P<yyyx>19[2-9x]x)|(?P<yy>[2-9][\dx]|xx)"
_DATE_DASH = rf"(?:{_D})[-.](?P<mm>\d{{1,2}}|xx)[-.](?P<dd>\d{{1,2}}|xx)"
_NUM = r"(?P<num>\d{1,4}[A-Za-z]?|x{1,4})"
PATTERNS = [
    # "Suspense 420617 001 The Burning Court (128-44) 28455 30m00s"  [OTRR_Suspense_Singles_By_Year_1942]
    #  OTRR v2: series YYMMDD epNNN title (kbps-kHz) KiB MMmSSs
    ("F0_otrr_v2", re.compile(
        r"^(?P<series>.+?)[ _](?P<yy>\d{2}|xx)(?P<mm>\d{2}|xx)(?P<dd>\d{2}|xx)[ _]"
        r"(?P<num>\d{1,4}|x{1,4})[ _](?P<title>.+?)"
        r"(?:[ _]\((?P<kbps>\d{2,3})-(?P<khz>\d{2})\))?(?:[ _](?P<kib>\d{3,7}))?"
        r"(?:[ _](?P<mins>\d{1,3})m(?P<secs>\d{2})s)?$", re.I)),
    # "Whistler_42-05-16_ep001_Retribution", "Whistler_xx-xx-xx_epxxx_Kaleidoscope_epAFRTS",
    # "CP_42-03-01_ep001-Eddie_Cantor", "Dragnet_49-06-10_ep002_Homicide"   [OTRR_Whistler_Singles, CommandPerformance, Dragnet_OTR]
    ("F1_otrr_ep", re.compile(
        rf"^(?P<series>.+?)[ _-]+{_DATE_DASH}[ _-]+(?:ep)?{_NUM}(?:[ _-]+(?P<title>.+?))?"
        r"(?:_aka_(?P<aka>.+?))?(?:[ _-]ep(?P<variant>AFRTS|AFRS|Rehearsal|Audition))?$", re.I)),
    # "Space_Patrol_53-02-14_020_The_Mysterious_Meteor", "YTJD 1957-09-29 554 The Doubtful Dairy Matter [AFRTS]",
    # "MBF_5x.xx.xx_ep49_First_Song", "Lux_Radio_Theatre_45-11-05_500R_Destry_Rides_Again" are F1 too.
    # "Gunsmoke 52-04-26 (001) Billy the Kid", "The Shadow 1937-09-26 (87) The Death House Rescue",
    # "FMM 1931-06-01 (xx) Smackout"   [OTRR_Gunsmoke_Singles, the-shadow-..., fibber-mc-gee-and-molly]
    ("F1c_paren_num", re.compile(
        rf"^(?P<series>.+?)[ _-]+{_DATE_DASH}[ _-]*\({_NUM}\)[ _-]*(?P<title>.+)$", re.I)),
    # "Father Knows Best (055) 1950-11-02 Too Many Problems"   [OTRR_Father_Knows_Best_Singles]
    ("F1f_paren_num_first", re.compile(
        rf"^(?P<series>.+?)[ _-]*\({_NUM}\)[ _-]*{_DATE_DASH}[ _-]+(?P<title>.+)$", re.I)),
    # "XMinusOne55-04-24001NoContact", "LuxRadioTheatre46-09-02535OurVinesHaveTenderGrapes",
    # "LightsOut-1936-06-17CatWife"   [OTRR_X_Minus_One_Singles, OTRR_Lux_Radio_Theater_Singles, LightsOutoldTimeRadio]
    ("F1d_camel_glued", re.compile(
        rf"^(?P<series>[A-Za-z][A-Za-z'&]+?)[-_ ]?{_DATE_DASH}(?P<num>\d{{3,4}})?[-_ ]?(?P<title>[A-Za-z].*)$")),
    # "Pwh541114319AGuyNamedScottc" (YYMMDD + NNN glued, CamelCase)   [OTRR_Proudly_We_Hail_Singles]
    ("F0b_camel_yymmdd_num", re.compile(
        r"^(?P<series>[A-Za-z]+?)(?P<yy>[2-7]\d)(?P<mm>\d{2})(?P<dd>\d{2})(?P<num>\d{3,4})(?P<title>[A-Z].*)$")),
    # "Inner_Sanctum_-_450109_Desert_Death"   [Inner_Sanctum_otr]
    ("F2b_series_yymmdd_title", re.compile(
        r"^(?P<series>.+?)[ _-]+(?P<yy>[2-7]\d)(?P<mm>\d{2})(?P<dd>\d{2})[ _-]+(?P<title>[A-Za-z].*)$")),
    # "X Minus One 1955 04 24 No Contact ( 001)"   [xminusone19550424nocontact001 title]
    ("F3_spaced_date", re.compile(
        r"^(?P<series>.+?)[ _-]+(?P<yyyy>19[2-7]\d)[ _](?P<mm>\d{2})[ _](?P<dd>\d{2})"
        r"[ _-]*(?P<title>.*?)(?:\(\s*(?P<num>\d{1,4})\s*\))?$")),
    # "Rex Stout's Nero Wolfe 04 82-02-06 The Cop Killer" (number BEFORE the date)
    #   [04-rex-stouts-nero-wolfe-04-82-02-06-the-cop-killer, after the leading track is stripped]
    ("F1g_num_then_date", re.compile(
        rf"^(?P<series>[A-Za-z].*?)[ _-]+(?P<num>\d{{1,4}})[ _-]+{_DATE_DASH}[ _-]+(?P<title>.+)$")),
    # "Series 42-06-17 Title" / "Series_1942-06-17_Title" (no episode number)
    # "esca.53.04.12_Classified_Secret", "amos.1945.01.12_One_Phoney_Antique" (dotted)   [Escape1953, AA441110]
    ("F1e_series_date_title", re.compile(
        rf"^(?P<series>[A-Za-z].*?)[ _.-]+{_DATE_DASH}[ _-]+(?P<title>[A-Za-z].*)$")),
    # "42-06-17_Burning_Court", "1932-05-02 - 001) First Show", "01 38-07-11 Dracula"
    #  no series in the name: the ITEM supplies it   [SUSPENSE, TheJackBennyProgram, OrsonWelles_MercuryTheatre]
    ("F7_date_first", re.compile(
        rf"^(?:\d{{1,3}}[ _.-]+)?{_DATE_DASH}[ _-]*(?:-[ _]*)?(?:\(?(?P<num>\d{{1,4}})\)[ _-]*)?(?P<title>.*)$")),
    # "SuspenseTheHitchHiker09021942"   [SuspenseTheHitchHiker09021942]
    ("F4_us_mmddyyyy", re.compile(
        r"^(?P<head>.+?)[ _-]*(?P<mm>0[1-9]|1[0-2])[-_ ]?(?P<dd>[0-3]\d)[-_ ]?(?P<yyyy>19[2-7]\d)$")),
    # "xminusone_550424_NoContact", "X_Minus_One_560515_Hallucination_Orbit", "TSP420617",
    # "JackBennyProgram481017SorryWrongNumber"
    ("F2_yymmdd", re.compile(
        r"^(?P<series>[A-Za-z][A-Za-z_ ]*?)[_ -]?(?P<yy>[1-7]\d)(?P<mm>0[1-9]|1[0-2])"
        r"(?P<dd>0[1-9]|[12]\d|3[01])(?:[_ -]+(?P<num>\d{1,4})(?=[_ -]|$))?(?:[_ -]?(?P<title>[A-Za-z].*))?$")),
    # "SM400219 04 Kent Captured By The Wolfe" is F2 with a number   [Superman items]
    # "Mindwebs-830326__AvailableOnTheWarpReaction" (a 1980s YYMMDD needs an explicit separator)   [Mindwebs_230]
    ("F2c_yymmdd_80s", re.compile(
        r"^(?P<series>[A-Za-z][A-Za-z_ ]*?)[_-](?P<yy>[89]\d)(?P<mm>0[1-9]|1[0-2])"
        r"(?P<dd>0[1-9]|[12]\d|3[01])(?:_+(?P<title>[A-Za-z].*))?$")),
    # "521029 1030 The Microfilm of Death", "410203_0154 The Black Pearl Of Osiris Part 09",
    # "510328_05_Shadow_of_Evil" (YYMMDD, number, title; the item names the series)
    #   [Green Hornet, Superman, NBC Short Story items]
    ("F7c_yymmdd_num_title", re.compile(
        r"^(?P<yy>[2-7]\d)(?P<mm>0[1-9]|1[0-2])(?P<dd>0[1-9]|[12]\d|3[01])[ _-]+(?P<num>\d{1,4})"
        r"(?:[ _-]+(?P<title>[A-Za-z].*))?$")),
    # "GrandOleOpry05-10-58", "ThisIsTheStory-ACzechEarForAmericanMusic05-24-47" (M-D-YY last)
    #   [GrandOleOpryOtr, AFRS items]
    ("F4b_mmddyy_last", re.compile(
        r"^(?P<head>[A-Za-z].*?)[ _-]?(?P<mm>0?[1-9]|1[0-2])-(?P<dd>[0-3]?\d)-(?P<yy>[2-7]\d)$")),
    # "481209TheSisters" (glued YYMMDD first, no series)   [Half-Hours_With_Rosalind]
    ("F7b_glued_yymmdd_first", re.compile(
        r"^(?P<yy>[2-7]\d)(?P<mm>0[1-9]|1[0-2])(?P<dd>0[1-9]|[12]\d|3[01])[ _-]*(?P<title>[A-Za-z].*)$")),
    # "Taxi_-_Red_-_The_Writer_1969-06-01", "The Queens Messenger 21 1984-07-16" (ISO date last)
    #   [taxi-05-red-becomes-a-hippie, the-queens-messenger-13-1984-07-04]
    ("F10_iso_date_last", re.compile(
        r"^(?P<head>[A-Za-z].*?)[ _-]+(?P<yyyy>19[2-9]\d)[-.](?P<mm>\d{1,2})[-.](?P<dd>\d{1,2})$")),
    # "Friday Theatre - Deadly Marriages 19-07-1985" (D-M-Y or M-D-Y last; ambiguous when both <= 12)
    #   [friday-theatre-deadly-marriages-19-07-1985]
    ("F10b_dmy_or_mdy_last", re.compile(
        r"^(?P<head>[A-Za-z].*?)[ _-]+(?P<a>\d{1,2})[-.](?P<b>\d{1,2})[-.](?P<yyyy>19[2-9]\d)$")),
    # "Inspector Steine - s02e06- End Game"   [inspector-steine-series-2]
    ("F11s_season_episode", re.compile(
        r"^(?P<series>[A-Za-z].*?)[ _-]+[sS](?P<season>\d{1,2})[eE](?P<num>\d{1,3})(?:[ _-]+(?P<title>.*[A-Za-z].*))?$")),
    # "Yes What Episode (252) Cow Noises" (number in brackets, no date)   [0245-yes-what-episode-245-...]
    ("F1h_paren_num_nodate", re.compile(
        r"^(?P<series>[A-Za-z].*?)[ _-]*\((?P<num>\d{1,4})\)[ _-]*(?P<title>[A-Za-z].*)?$")),
    # "Dimension X 011 Zero Hour" (number, no date)
    ("F5_number", re.compile(
        r"^(?P<series>.+?)[ _-]+(?:#|ep\.?|no\.?\s*)?(?P<num>\d{1,4})[ _-]+(?P<title>[A-Za-z].+)$", re.I)),
    # "X_Minus_One-A_Gun_for_Dinosaur" (series + title, nothing else)   [xminusoneotr]
    ("F8_series_dash_title", re.compile(r"^(?P<series>[A-Za-z][A-Za-z_ ]+?)-(?P<title>[A-Za-z].+)$")),
    # An episode marker and a number: "Gregory Keen - Dossier On Dumetrius  Ep 045", "Grey_Goose_(Aust)_ep048",
    # "Latin Rendezvous Ep#52=70", "Tip Toe Thru the 20's Prg #152", "Dimx_e049_Requiem",
    # "The Hound of the Baskervilles episode 3"   [gregory-keen-..., grey-goose-aust-ep-056, Dimension-X]
    ("F11_ep_marker", re.compile(
        r"^(?P<series>[A-Za-z].*?)[ _(-]*(?<![A-Za-z])(?:ep(?:isode)?|e|prg|programme|program|no|part|pt|chapter|chap|ch)"
        r"\.?[ _#-]*(?P<num>\d{1,4})\)?(?:\s*(?:=|of)\s*\d{1,4})?(?:[ _-]+(?P<title>.*[A-Za-z].*))?$", re.I)),
    # A bare number last: "Upstate Radio Theatre 2310", "Great Expectations - 32 1985",
    # "Charles Chilton - Space Force - TheRedPlanet - 11of20"   [upstate-radio-theatre-2310, great-expectations-33-1985]
    ("F12_series_num_last", re.compile(
        r"^(?P<series>[A-Za-z][^\d]*?)[ _-]+#?(?P<num>\d{1,4})(?:\s*of\s*\d{1,4})?(?:[ _-]+(?P<year>19[2-9]\d))?$", re.I)),
]
GENERIC_FILE_SERIES = {"chapter", "chap", "part", "pt", "episode", "ep", "track", "side", "disc", "disk", "show",
                       "program", "programme", "prg", "audio", "file", "audiofile", "tape", "reel", "record",
                       "recording", "untitled", "unknown", "no", "number", "vol", "volume", "cd"}
# The OTRR sets also write identity into the ID3 album tag:
# album "04/26/52, episode 1"   [OTRR_Gunsmoke_Singles, OTRR_X_Minus_One_Singles, OTRR_Lux_Radio_Theater_Singles]
ALBUM_TAG = re.compile(r"^(?P<mm>\d{1,2}|xx)/(?P<dd>\d{1,2}|xx)/(?P<yy>\d{2}|xx),\s*episode\s*(?P<num>\d{1,4}|x+)", re.I)
AFRS = re.compile(r"(?:^|[ _(\[{\-]|(?<=[a-z]))(afrs|afrts)(?:$|[ _)\]}\-])", re.I)


def _date(g, fam):
    if g.get("a") is not None:
        a, b, yyyy = int(g["a"]), int(g["b"]), g["yyyy"]
        if a > 12 and valid_date(yyyy, b, a):
            return f"{yyyy}-{b:02d}-{a:02d}", False
        if b > 12 and valid_date(yyyy, a, b):
            return f"{yyyy}-{a:02d}-{b:02d}", False
        if a == b and valid_date(yyyy, a, b):
            return f"{yyyy}-{a:02d}-{b:02d}", False
        return None, False                             # both could be the month: not guessed
    yyyy = g.get("yyyy")
    yy = g.get("yy")
    if not yyyy and yy and yy.lower() != "xx":
        yyyy = "19" + yy
    mm, dd = g.get("mm") or "", g.get("dd") or ""
    if not yyyy or not mm or not dd or "x" in (mm + dd).lower():
        return None, False
    if valid_date(yyyy, mm, dd):
        return f"{yyyy}-{int(mm):02d}-{int(dd):02d}", False
    if yy and valid_date("19" + dd, yy, mm):          # MM-DD-YY written in a YY-MM-DD slot
        return f"19{dd}-{int(yy):02d}-{int(mm):02d}", True
    return None, None                                  # digits that are not a date


LEAD_TRACK = re.compile(r"^(\d{1,4})[ ._-]+(?=[A-Za-z])")
_NEED_DATE = ("F7c_yymmdd_num_title", "F4b_mmddyy_last", "F0_otrr_v2", "F0b_camel_yymmdd_num", "F2_yymmdd", "F2b_series_yymmdd_title", "F1d_camel_glued",
              "F7_date_first", "F1e_series_date_title", "F1g_num_then_date", "F2c_yymmdd_80s",
              "F7b_glued_yymmdd_first", "F10_iso_date_last")
# A title is something a person could read as one. Junk stems that are not:
# "UIUC_Archives_1306005_0913_B", "vvl_4005_Audio_file", "05", "Track 3", "DA9363~1"   [MEASURED 2026-10-19]
_JUNK_TITLE = re.compile(r"^(track|audio|file|disc|disk|side|part|untitled|unknown|new recording|tape|reel|record(ing)?|"
                         r"chapter|episode|ep|show|program|cd|mp3|sample|test)\b|audio[ _]?file|uiuc[ _]archives|~\d", re.I)


_ONE_WORD_JUNK = {"intro", "outro", "theme", "opening", "closing", "close", "open", "promo", "unknown", "untitled",
                  "audio", "track", "music", "blank", "silence", "test", "sample", "commercial", "commercials",
                  "announcement", "break", "filler", "misc", "various", "bonus", "extra", "extras", "news"}


def is_titleish(t):
    t = (t or "").strip()
    if not t or _JUNK_TITLE.search(t):
        return False
    words = re.findall(r"[A-Za-z][a-z]+|[A-Z]{2,}(?![a-z])", re.sub(r"([a-z])([A-Z])", r"\1 \2", t))
    letters = sum(c.isalpha() for c in t)
    if len(words) == 1 and re.fullmatch(r"[A-Z]?[a-z]{4,}", t) and t.lower() not in _ONE_WORD_JUNK:
        return True                                   # "Hydrolysis", "Meltdown"   [bbcmyword, comedydramaonbbcr4]
    return len(words) >= 2 and letters >= 6 and letters >= 0.5 * len(re.sub(r"[\s_.-]", "", t))


def _clean(x):
    return re.sub(r"\s+", " ", re.sub(r"[_]+", " ", x or "")).strip(" -.") or None


def parse(name):
    st = stem(name)
    lead = LEAD_TRACK.match(st)
    s = LEAD_TRACK.sub("", st)
    for fam, rx in PATTERNS:
        m = rx.match(s)
        if not m:
            continue
        g = m.groupdict()
        date, swapped = _date(g, fam)
        if swapped is None and fam in _NEED_DATE:
            continue
        if swapped:
            fam += "_mdy"
        if g.get("head") is not None:
            head = _clean(g["head"]) or ""
            if fam.startswith(("F10", "F4b")):
                if " - " in head:
                    ser, _, ttl = head.partition(" - ")
                    g = dict(g, series=ser, title=ttl)
                else:
                    mn = re.match(r"^(.*?[A-Za-z].*?)[ _-]+(\d{1,4})$", head)
                    g = dict(g, series=mn.group(1), num=mn.group(2)) if mn else dict(g, series=head)
            else:
                ser, _, ttl = head.partition(":") if ":" in head else ("", "", head)
                g = dict(g, series=ser.strip(), title=ttl.strip())
        series = _clean(g.get("series"))
        if series and norm_series(series) in GENERIC_FILE_SERIES:
            series = None
        num = g.get("num")
        yyyy = g.get("yyyy") or g.get("year")
        if fam == "F12_series_num_last" and num and re.fullmatch(r"19[2-9]\d", num) and not yyyy:
            yyyy, num = num, None                       # "Christmas 1950": a year, not an episode number
        variant = g.get("variant") or (AFRS.search(s).group(1).upper() if AFRS.search(s) else None)
        yy = g.get("yy") or ""
        yx = g.get("yyyx") or ""
        decade = (yyyy[:3] + "0s") if yyyy else ("19" + yy[0] + "0s" if yy[:1].isdigit() else
                                                  (yx[:3] + "0s" if yx[2:3].isdigit() else None))
        title = _clean(g.get("title"))
        if fam == "F12_series_num_last" and series and " - " in series and not num:
            series, _, title = series.partition(" - ")    # "Springbok Library of the Air - Beware ... 1985"
        mt = re.fullmatch(r"(?:episode|ep|part|pt|chapter|prg|program)\.?\s*#?\s*(\d{1,4})", title or "", re.I)
        if mt and not num:
            num, title = mt.group(1), None                # "Dr_Jekyll_and_Mr_Hyde.1932.xx.xx_Episode_33"
        if title and re.fullmatch(r"(?:audio[ _]?file|track\s*\d*|untitled|unknown|no description)", title, re.I):
            title = None                                  # "vvl_4005_Audio_file"
        if g.get("season") and title:
            title = f"S{int(g['season']):02d}E{int(num):02d} {title}"
        return {"family": fam, "series": series, "date": date, "decade": decade,
                "num": None if not num or "x" in num.lower() else int(re.sub(r"\D", "", num)),
                "title": title,
                "aka": _clean(g.get("aka")),
                "variant": variant}
    if is_titleish(s):
        # No pattern, but the name is a title: "Guest Is Victor Moore", "003_Grave_Robber",
        # "137 Paradise Regained - Cogswell Thomas"; the item or folder supplies the series.
        # A leading number here is usually a track number in the upload, not the broadcast's
        # number, so the title (not the number) is the episode's identity.
        return {"family": "F13_lead_num_title" if lead else "F14_title_only", "series": None, "date": None,
                "decade": None, "num": None, "title": _clean(s), "aka": None,
                "variant": AFRS.search(s).group(1).upper() if AFRS.search(s) else None}
    return {"family": "F6_none", "series": None, "date": None, "decade": None, "num": None,
            "title": None, "aka": None, "variant": None}


MONTHS = {m: i + 1 for i, m in enumerate(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct",
                                          "nov", "dec"))}
_TXT_DMY = re.compile(r"\b(?P<d>[0-3]?\d)(?:st|nd|rd|th)?\s+(?P<m>[A-Za-z]{3,9})\.?,?\s+(?P<y>19[2-9]\d)\b")
_TXT_MDY = re.compile(r"\b(?P<m>[A-Za-z]{3,9})\.?\s+(?P<d>[0-3]?\d)(?:st|nd|rd|th)?,?\s+(?P<y>19[2-9]\d)\b")
_ISO = re.compile(r"(?<!\d)(?P<y>19[2-9]\d)[-./](?P<m>[01]?\d)[-./](?P<d>[0-3]?\d)(?!\d)")
_US = re.compile(r"(?<!\d)(?P<m>[01]?\d)/(?P<d>[0-3]?\d)/(?P<y>19[2-9]\d|[2-9]\d)(?!\d)")


def parse_text_date(t):
    """A full broadcast date written out: "27 August 1944", "August 27, 1944", "1944-08-27",
    "8/27/1944". Only months spelled as month names count for the textual forms."""
    t = t or ""
    for rx in (_TXT_DMY, _TXT_MDY):
        for m in rx.finditer(t):
            mo = MONTHS.get(m.group("m")[:3].lower())
            if mo and valid_date(m.group("y"), mo, m.group("d")):
                return f"{m.group('y')}-{mo:02d}-{int(m.group('d')):02d}"
    m = _ISO.search(t)
    if m and valid_date(m.group("y"), m.group("m"), m.group("d")):
        return f"{m.group('y')}-{int(m.group('m')):02d}-{int(m.group('d')):02d}"
    m = _US.search(t)
    if m:
        y = m.group("y") if len(m.group("y")) == 4 else "19" + m.group("y")
        if valid_date(y, m.group("m"), m.group("d")):
            return f"{y}-{int(m.group('m')):02d}-{int(m.group('d')):02d}"
    return None


def parse_album_tag(album):
    m = ALBUM_TAG.match((album or "").strip())
    if not m:
        return None
    g = m.groupdict()
    date, _ = _date(g, "tag")
    num = g.get("num")
    return {"date": date, "num": None if "x" in num.lower() else int(num)}


def _fold(s):
    import unicodedata
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.replace("’", "'").replace("‘", "'").replace("–", "-").replace("—", "-")
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)              # CamelCase: "TheShadow" -> "The Shadow"
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1 \2", s)
    s = s.lower().replace("_", " ")
    s = re.sub(r"\s*&\s*|\s+'n'?\s+|\s+n'\s+|\s+n\s+", " and ", s)   # "&", "'n'", "N" between words
    return s


def norm_series(s):
    """The series key: lower case, letters and digits only. "The" leading or as a trailing
    ", The" (OTRR's "Shadow, The") is dropped, "&" and "'n'" read as "and", Theatre as Theater,
    CamelCase split first so "TheShadow" and "The Shadow" agree."""
    s = _fold(s)
    s = re.sub(r",\s*(the|a|an)\s*$", "", s.strip())
    s = re.sub(r"^\s*(otrr|the)\s+", "", s)
    s = re.sub(r"theatre", "theater", s)
    return re.sub(r"[^a-z0-9]", "", s)


_LEAD_NOISE = re.compile(
    r"^(?:the|otrr?|old[ -]time[ -]radio|afrts?|aus(?:tralian)?\s*\d*|australian old[ -]time radio|"
    r"ron bowser[ -]+john dunning project|bdp|pdp|american armed forces radio(?: vietnam)?(?: no)?\s*\d*|"
    r"radio|presenting)\b[\s:.-]*")
_TAIL_NOISE = re.compile(
    r"[\s:.#-]*\b(?:singles?|doubles?|episodes?|collection|set|complete|incomplete|digitally restored|remastered|"
    r"restored|broadcast ready|upgrade|high quality|rare(?: shows)?|serial|otr|old[ -]time[ -]radio|"
    r"radio (?:show|program(?:me)?|drama|series)s?|show|program(?:me)?|hour|series|"
    r"vol(?:ume)?\.?\s*\d*|no\.?\s*\d*|part\s*\d*|\d+|sa|aust|sth african version|south african|"
    r"\d+ minute (?:shows?|series|episodes?)|of the classic show|syndicated|re ?runs?|official tape archive)\s*$")


def series_variants(raw):
    """Candidate keys for a raw series name, most specific first: the key itself, then with
    bracketed text, leading collection words ("OTRR", "Aus 108 -", "AFRS") and trailing set words
    ("Singles", "Digitally Restored", "Show", "Program", "Hour", a volume number) removed, and the
    "Adventures of" form in both directions. Only a variant the registry knows is ever used."""
    if not raw:
        return []
    out = [norm_series(raw)]
    t = _fold(raw)
    t = re.sub(r",\s*(the|a|an)\s*$", "", t.strip())
    t = re.sub(r"[\(\[\{][^\)\]\}]*[\)\]\}]", " ", t)
    for _ in range(4):
        t2 = _LEAD_NOISE.sub("", t.strip())
        t2 = _TAIL_NOISE.sub("", t2.strip())
        if t2 == t:
            break
        t = t2
        out.append(norm_series(t))
    # each " - " / ":" piece on its own ("Aus 108 - Grey Goose", "Rudy Vallee - Sealtest Show")
    for piece in re.split(r"\s+-\s+|:\s+", _fold(raw)):
        if piece.strip() and piece.strip() != _fold(raw).strip():
            out.extend(series_variants_simple(piece))
    for k in list(out):
        if k.startswith("adventuresof") and len(k) > 15:
            out.append(k[len("adventuresof"):])
        elif k:
            out.append("adventuresof" + k)
    seen, res = set(), []
    for x in out:
        if x and x not in seen:
            seen.add(x)
            res.append(x)
    return res


def series_variants_simple(raw):
    t = _fold(raw)
    t = re.sub(r"[\(\[\{][^\)\]\}]*[\)\]\}]", " ", t)
    out = [norm_series(t)]
    for _ in range(3):
        t2 = _TAIL_NOISE.sub("", _LEAD_NOISE.sub("", t.strip()).strip())
        if t2 == t:
            break
        t = t2
        out.append(norm_series(t))
    return [x for x in out if x]


def reorder_title(t):
    """OTRR writes "Shadow, The"; the display name is "The Shadow"."""
    m = re.match(r"^(.*), (The Adventures of|Adventures of|The|A|An)$", (t or "").strip(), re.I)
    return f"{m.group(2)} {m.group(1)}" if m else (t or "").strip()


def is_abbreviation(abbr, key):
    """Could `abbr` (a series key a file name uses) abbreviate `key` (a known series key)?
    True for initials ("ytjd" -> yourstrulyjohnnydollar via its words), a prefix of at least
    four letters ("esca" -> escape) or an in-order subsequence that starts with the same letter
    and is at least half as long as the shortest word run ("dimx" -> dimensionx)."""
    if not abbr or not key or abbr == key or len(abbr) < 2 or len(abbr) >= len(key):
        return False
    if abbr[0] != key[0] or not abbr.isalpha():
        return False
    if len(abbr) >= 4 and key.startswith(abbr):
        return True
    it = iter(key)
    return all(c in it for c in abbr) and len(abbr) >= 3


def initials(name):
    words = [w for w in re.findall(r"[a-z0-9]+", _fold(name)) if w not in ("the", "of", "a", "an", "and")]
    return "".join(w[0] for w in words)


# The University of Illinois Archives' finding aid for record series 13/6/5 (WILL's sound
# recordings, 1927-1999) names each digitized disc side by the file name archive.org's
# "1306005-128-michael-fisher-acc*" uploads use: "UIUC_Archives_1306005_0007_A".
#   https://archives.library.illinois.edu/archon/?p=collections/findingaid&id=1994&q=
UIUC_FILE = re.compile(r"UIUC_Archives_1306005_(\d{4})_([AB])", re.I)
_UIUC_ITEM = re.compile(r"<dt class='faitem'>(?:<a name=\"id(?P<aid>\d+)\"></a>)?Item\s+(?P<item>[^:<]+):\s*(?P<head>.*?)</dt>"
                        r"(?P<body>.*?)(?=<dt class='faitem'>|<dt class='fa|</dl>|$)", re.S)
_UIUC_FIELD = re.compile(r"<dd class='faitemcontent'>\s*(?P<k>[A-Za-z()/ ]+):\s*(?P<v>.*?)</dd>", re.S)


def parse_uiuc_findingaid(html):
    """{file stem: {item, title, date, program, speaker, subjects, duration, anchor}}."""
    import html as H
    out = {}
    for m in _UIUC_ITEM.finditer(html):
        f = {x.group("k").strip().lower(): H.unescape(re.sub(r"<[^>]+>", " ", x.group("v"))).strip()
             for x in _UIUC_FIELD.finditer(m.group("body"))}
        files = UIUC_FILE.findall(m.group("body"))
        if not files:
            continue
        head = H.unescape(re.sub(r"<[^>]+>", "", m.group("head"))).strip()
        date = None
        dm = re.search(r",\s*(\d{1,2})/(\d{1,2})/(19\d\d)\s*$", head)
        if dm and valid_date(dm.group(3), dm.group(1), dm.group(2)):
            date = f"{dm.group(3)}-{int(dm.group(1)):02d}-{int(dm.group(2)):02d}"
        title = re.sub(r",\s*[\d/x?]+\s*$", "", head).strip() or None
        for disc, side in files:
            out[f"UIUC_Archives_1306005_{disc}_{side.upper()}"] = {
                "item": m.group("item").strip(), "title": title, "date": date, "program": f.get("program"),
                "speaker": f.get("speaker"), "subjects": f.get("subject(s)"), "duration": f.get("duration"),
                "anchor": m.group("aid"), "parts": len(files)}
    return out


# What a file is when it is not a radio broadcast. Every rule names the files that
# made it (MEASURED 2026-10-19 on the unidentified set); `None` means radio.
BIBLE = ("genesis|exodus|leviticus|numbers|deuteronomy|joshua|judges|ruth|samuel|kings|chronicles|ezra|nehemiah|"
         "esther|job|psalms?|proverbs|ecclesiastes|song of solomon|isaiah|jeremiah|lamentations|ezekiel|daniel|"
         "hosea|joel|amos|obadiah|jonah|micah|nahum|habakkuk|zephaniah|haggai|zechariah|malachi|matthew|mark|"
         "luke|john|acts|romans|corinthians|galatians|ephesians|philippians|colossians|thessalonians|timothy|"
         "titus|philemon|hebrews|james|peter|jude|revelations?")
# "1 Chronicles 01", "Psalm 110", "Obadiah"   [1306005-128-michael-fisher-acc_202607: 1,575 such files]
_SCRIPTURE = re.compile(rf"^(?:[1-3]\s*)?(?:{BIBLE})(?:\s+\d{{1,3}})?$", re.I)
# "Jim Davidson & His New Palais Royal Orchestra - Isn't This A Night For Love (1933)"
#   [tribute-to-jim-davidson-part-2-of-2_202106]: a commercial record, artist - song (year)
_MUSIC_RECORD = re.compile(r"\b(orchestra|band|quartet|trio|his|her|and his|singers|ensemble)\b.*\s-\s.+\((19[0-9]\d)\)\s*$", re.I)
# "VintageCommercialsTingPimpleCream", "Commercials.19xx.xx.xx_Radio_Promo", "Boyce & Hart - Coke Spot # 1"
_COMMERCIAL = re.compile(r"(commercials?|promos?\b|\bspots?\b|jingles?|\bpsa\b|\bads?\b|advert)", re.I)
_PODCAST = re.compile(r"\bpodcasts?\b", re.I)


def is_scripture_name(stem_text):
    s = re.sub(r"^\d{1,4}[ ._-]+", "", re.sub(r"[_]+", " ", stem_text or "").strip())
    return bool(_SCRIPTURE.match(s))


def content_kind(stem_text, length_s, item_title="", item_collections=(), item_text="", known_series=False):
    """(kind, rule) for a file that is not a radio broadcast, else (None, None). The podcast and
    music-collection rules apply only to a file whose series is not a known radio program:
    MEASURED 2026-10-19, archive.org's podcast collections hold MindWebs' own tape archive and
    rebroadcast compilations, and an "audio_music" item held a 59-minute War of the Worlds."""
    s = re.sub(r"[_]+", " ", stem_text or "").strip()
    s2 = re.sub(r"^\d{1,4}[ ._-]+", "", s)
    if _SCRIPTURE.match(s2):
        return "scripture", "bible_book_chapter"
    if _MUSIC_RECORD.search(s) and (length_s or 0) < 420:
        return "music", "artist_song_year"
    camel = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    if (length_s or 0) and length_s < 240 and (_COMMERCIAL.search(camel) or _COMMERCIAL.search(item_title or "")):
        return "commercial", "short_spot"
    if known_series:
        return None, None
    cols = set(item_collections or ())
    if cols & {"podcasts", "podcasts_compilations", "podcasts_miscellaneous"} or _PODCAST.search(item_title or ""):
        return "podcast", "podcast_item"
    if cols & {"audio_music", "folksoundomy_music", "hifidelity_soundtracks", "78rpm", "georgeblood"} and \
            (length_s or 0) and length_s < 420:
        return "music", "music_collection"
    return None, None
