"""Network names: one spelling per network, applied where networks are first parsed.

Goldin's SOURCE column and OTRRpedia's run histories carry hand-typed network
names, typos included ("Bllue", "Mutaul-Don Lee", "NBC Paciic"). enrich_db.py
passes every name through canonical_network() before it reaches episodes,
program_runs, goldin_records or series.networks, so the research database, the
projection and every client agree. goldin_records keeps the raw SOURCE text
beside the parsed network.

ALIASES maps a clear typo, or a spacing, punctuation or "radio" suffix variant,
to its network. It never merges two networks: NBC Red, NBC Blue, NBC Pacific,
Mutual-Don Lee, Blue (which became ABC) and ABC Blue stay separate. DISTINCT is
the reviewed list of near-spelled names that really are different networks; the
guard in tests/test_networks.py fails on any other pair within edit distance 2.
"""
import re

ALIASES = {
    "Bllue": "Blue",
    "Bue": "Blue",
    "Mutrual": "Mutual",
    "Mutul": "Mutual",
    "Mutuqal": "Mutual",
    "Mutaul-Don Lee": "Mutual-Don Lee",
    "Mutul-Don Lee": "Mutual-Don Lee",
    "Mutual-Don-Lee": "Mutual-Don Lee",
    "Mutual-Don lee": "Mutual-Don Lee",
    "Mutual Don-Lee": "Mutual-Don Lee",
    "NBC Paciic": "NBC Pacific",
    "NBCPacific": "NBC Pacific",
    "NBC radio": "NBC",
    "CBS radio": "CBS",
    "Michigan radio": "Michigan Radio",
    "The Michigan Radio": "Michigan Radio",
    "ABC-Blue": "ABC Blue",
    "ABC (Blue)": "ABC Blue",
    "ABC/Blue": "ABC Blue",
}

# A hedge ("possible Blue", "Blue or Mutual") is not a network; not knowing is not a claim.
_HEDGE = re.compile(r"^(possibly|possible|probably)\b|\bor\b", re.I)

# Real, different networks whose names sit within edit distance 2 of each other.
DISTINCT = {
    frozenset(p) for p in [
        ("ABC", "NBC"), ("ABC", "CBC"), ("ABC", "BBC"), ("NBC", "CBS"), ("NBC", "BBC"), ("CBS", "CBC"),
        ("CBC", "BBC"), ("CBC", "CBCF"), ("CBC", "NBC"), ("CBS", "BBC"), ("ABC", "CBS"), ("ABC", "AFRS"),
        ("AFRS", "AFRTS"), ("WOR", "NPR"), ("NBC", "NPR"), ("CBS", "NPR"), ("ABC", "NPR"), ("CBC", "NPR"),
        ("BBC", "NPR"), ("ABC", "WOR"), ("BBC", "WOR"), ("CBC", "WOR"), ("NBC", "WOR"), ("CBS", "WOR"),
        ("ABC", "AFRTS"), ("NBC Red", "NBC Blue"), ("NBC Pacific", "ABC Pacific"), ("NBC Blue", "ABC Blue"),
        ("NBC Pacific", "CBS Pacific"), ("CBS Pacific", "ABC Pacific"), ("NBC Pacific", "Mutual Pacific"),
        ("Mutual", "Mutual Pacific"), ("CBS Pacific", "Mutual Pacific"), ("ABC Pacific", "Mutual Pacific"),
        ("Blue", "NBC Blue"), ("Blue", "ABC Blue"), ("AFRS", "NPR"), ("AFRS", "CBS"), ("AFRS", "NBC"),
        ("AFRS", "WOR"), ("AFRS", "BBC"), ("AFRS", "CBC"), ("ABC", "ABC Blue"), ("NBC", "NBC Red"),
        ("NBC", "NBC Blue"), ("CBS", "CBS Pacific"), ("NBC", "NBC Pacific"), ("ABC", "ABC Pacific"),
        ("ABC", "ABC Entertainment"), ("CBS", "WCBS"), ("CBC", "WCBS"), ("CBS", "CNS"), ("CBC", "CNS"),
        ("CNS", "WCBS"), ("ABC", "NVC"), ("BBC", "NVC"), ("CBC", "NVC"), ("NBC", "NVC"), ("NPR", "NVC"),
    ]
}

_ALIAS_KEYS = {k.casefold(): v for k, v in ALIASES.items()}


def canonical_network(name):
    """The canonical spelling of a network name, or None for an empty one."""
    if name is None:
        return None
    s = re.sub(r"\s+", " ", name).strip().lstrip(".(\"'").rstrip(".\"'").strip()
    if not s:
        return None
    if _HEDGE.search(s):
        return None
    return _ALIAS_KEYS.get(s.casefold(), s)


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def near_misses(counts):
    """Pairs (rare, common) within edit distance 2 where the pair is not a listed
    distinct network pair. counts: {name: episodes}; the first of a pair is the
    less common."""
    out = []
    names = sorted(counts, key=lambda n: (-counts[n], n))
    for i, common in enumerate(names):
        for rare in names[i + 1:]:
            if edit_distance(common.casefold(), rare.casefold()) <= 2 and frozenset((common, rare)) not in DISTINCT:
                out.append((rare, common))
    return out


# ---------------------------------------------------------------- one primary network per series

# series.network (contract section 3.3, Decision 081): the one network a series' label names on its
# rim. The episodes' own networks stay as the witnesses wrote them; only this primary folds the
# parts of one network together, by the date it aired. NBC Red, NBC Pacific and their variants are
# NBC; CBS Pacific is CBS; Mutual-Don Lee and Mutual Pacific are Mutual. NBC's Blue network was run
# apart from NBC from 8 January 1942 (the Blue Network Company) and took the name ABC on 15 June 1945
# (enwiki "Blue Network", "American Broadcasting Company"), so NBC Blue, Blue, ABC Blue and ABC are
# NBC before the split, Blue between, ABC after. Undated, each keeps its own name's network.
BLUE_SPLIT = "1942-01-08"
ABC_NAMED = "1945-06-15"
FOLD = {
    "NBC Red": "NBC", "NBC Pacific": "NBC", "NBC Red West Coast": "NBC", "NBC Pacific Coast": "NBC",
    "RCA/NBC": "NBC", "CBS Pacific": "CBS", "CBS-Don Lee": "CBS", "Columbia": "CBS",
    "Columbia Broadcasting System": "CBS", "Mutual-Don Lee": "Mutual", "Mutual Pacific": "Mutual",
    "Mutual Broadcasting System": "Mutual", "MBS": "Mutual", "ABC Pacific": "ABC", "ABC Entertainment": "ABC",
    "ABC Information": "ABC",
}
# The Blue family: its network before the split, between, after; and undated. "ABC" before the
# split keeps its name (None): a 1930s ABC is Australia's, not the Blue network.
BLUE = {"NBC Blue": ("NBC", "Blue", "ABC", "NBC"), "Blue": ("NBC", "Blue", "ABC", "Blue"),
        "ABC Blue": ("NBC", "Blue", "ABC", "ABC"), "ABC": (None, "Blue", "ABC", "ABC")}
# A primary network is one of these; anything else a log wrote in the network column ("Syndicated",
# "Various", "Australian", a station, a producer, a sponsor) is not a network and names none.
PRIMARY = {"NBC", "CBS", "Mutual", "ABC", "Blue", "AFRS", "AFRTS", "BBC", "CBC", "CBCF", "NPR", "Springbok",
           "WOR", "WCBS", "Don Lee Network", "Michigan Radio"}


def fold_network(name, date=None):
    """The network `name` was part of on `date` ('YYYY-MM-DD', or None), or None when it names none."""
    n = canonical_network(name)
    if n is None:
        return None
    n = FOLD.get(n, n)
    if n in BLUE:
        before, between, after, undated = BLUE[n]
        if not date:
            n = undated
        elif date < BLUE_SPLIT:
            n = before or n
        elif date < ABC_NAMED:
            n = between
        else:
            n = after
    return n if n in PRIMARY else None


def primary_network(dated, listed=None):
    """(network, source) for one series, or (None, None).

    dated: (air_date, network) for the series' served broadcasts that name one. The network heard on
    most of them wins ('episodes'); a tie goes to the one heard first, then the name. With none, the
    first network in the series' `networks` list (the run histories and Goldin's log, most first)
    that names a primary network ('logs'). Clients never parse `networks` (R3a section 3.4)."""
    count, first = {}, {}
    for d, n in dated or ():
        f = fold_network(n, d)
        if f:
            count[f] = count.get(f, 0) + 1
            first[f] = min(first.get(f, d or "9999"), d or "9999")
    if count:
        return min(count, key=lambda n: (-count[n], first[n], n)), "episodes"
    for n in listed or ():
        f = fold_network(n)
        if f:
            return f, "logs"
    return None, None
