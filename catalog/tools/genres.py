"""The eight Ear Drama genres, mapped from the labels the sources give (research 05 §3.3).

Imported by every builder, never copied. A series' genre comes from data: the
first OTRRpedia label that maps, in OTRRpedia's own order, else RadioEchoes'
human tag, else none. "Serial" decides over the rest unless the show is a comedy,
because a serial queues by arc (R3). A label no row here names is not a genre.
"""
GENRES = ("drama", "mystery", "scifi", "western", "comedy", "news", "documentary", "serial")
NAMES = {"drama": "Drama", "mystery": "Mystery", "scifi": "Science fiction", "western": "Western",
         "comedy": "Comedy", "news": "News", "documentary": "Documentary", "serial": "Serials"}

OTRR = {
    "Anthology Drama": "drama", "Drama": "drama", "Anthology": "drama", "Episodic Drama": "drama",
    "Episodic": "drama", "Adventure": "drama", "Action": "drama", "Romance": "drama",
    "Crime": "mystery", "Mystery": "mystery", "Private Detective": "mystery", "Police": "mystery",
    "Suspense": "mystery", "Horror": "mystery", "Amateur Detective": "mystery", "Espionage": "mystery",
    "Science Fiction": "scifi", "Fantasy": "scifi", "Super Hero": "scifi",
    "Western": "western",
    "Comedy": "comedy", "Sitcom": "comedy", "Variety": "comedy", "Game Show": "comedy", "Quiz": "comedy",
    "Audience Participation": "comedy",
    "News": "news", "War": "news",
    "Nonfiction": "documentary", "Documentary": "documentary", "Information": "documentary",
    "Discussion": "documentary", "Interview": "documentary", "Talk Show": "documentary",
    "Religion": "documentary", "Sports": "documentary",
    "Serial": "serial", "Youth": "serial", "Children": "serial",
}
RADIOECHOES = {
    "OTR-Drama": "drama", "OTR-Adventure": "drama", "OTR-Detective": "mystery", "OTR-Thriller": "mystery",
    "OTR-Mystery": "mystery", "OTR-SciFi": "scifi", "OTR-Western": "western", "OTR-Comedy": "comedy",
    "OTR-Variety": "comedy", "OTR-Quiz": "comedy", "OTR-News": "news", "OTR-WW2": "news",
    "OTR-Patriotic": "news", "OTR-Historical": "documentary", "OTR-Talk": "documentary",
    "OTR-Religion": "documentary", "OTR-Sports": "documentary", "OTR-Soap": "serial", "OTR-Kids": "serial",
}


def genre_of(otrr_labels=None, radioechoes=None, librivox=False):
    """(genre, source) or (None, None). A LibriVox work is drama: the harvest admits
    only its Dramatic Readings, Plays, and Drama genres (harvest_librivox.py)."""
    labels = list(otrr_labels or ())
    mapped = [OTRR[x] for x in labels if x in OTRR]
    if "Serial" in labels:
        return ("comedy" if "comedy" in mapped else "serial"), "otrrpedia"
    if mapped:
        return mapped[0], "otrrpedia"
    for tag in (radioechoes or "").split("|"):
        if tag.strip() in RADIOECHOES:
            return RADIOECHOES[tag.strip()], "radioechoes"
    if librivox:
        return "drama", "librivox"
    return None, None


# Evidence for a series no OTRRpedia label, RadioEchoes tag or LibriVox listing places (DECISIONS
# 024). Every key is a word one record carries itself; none is read from a title. A word that names
# a subject (a war, a band, a decade) or a medium ("old time radio", "music") is not here.
KEYWORDS = {
    "drama": ("radio drama", "radio dramas", "radio play", "radio plays", "audio theater", "audio theatre",
              "audio drama", "otr drama", "drama", "hoorspel", "hoorspelen", "hörspiel"),
    "mystery": ("mystery", "mysteries", "suspense", "horror", "crime", "detective", "detectives", "thriller",
                "murder mystery", "crime drama", "espionage"),
    "scifi": ("science fiction", "sci-fi", "scifi", "fantasy"),
    "western": ("western", "westerns"),
    "comedy": ("comedy", "sitcom", "situation comedy", "humor", "humour", "sketch comedy", "variety"),
    "news": ("news", "newscast", "newscasts", "news broadcast"),
    "documentary": ("documentary", "documentaries", "interview", "interviews", "talk show", "sports"),
    "serial": ("serial", "serials", "soap opera", "soap operas"),
}
KEYWORD = {w: g for g, ws in KEYWORDS.items() for w in ws}
# Wikidata's `genre` (P136) on the series' item, once it is matched on more than its title.
WIKIDATA = {
    "Q170238": "comedy", "Q121388202": "mystery", "Q23653": "drama", "Q121747822": "comedy",
    "Q5937792": "mystery", "Q4506063": "scifi", "Q2049337": "comedy", "Q23739": "serial",
    "Q21590660": "western", "Q1748941": "comedy", "Q121356781": "comedy", "Q40831": "comedy",
    "Q846662": "comedy", "Q6585139": "mystery", "Q3071014": "serial", "Q24925": "scifi",
    "Q468478": "scifi", "Q186424": "mystery", "Q185867": "mystery", "Q2123557": "comedy",
    "Q9335576": "comedy", "Q1366112": "drama",
}


def item_genres(subjects, file_genres):
    """{genre: [source words]} one archive.org item's own record names: its subject keywords and the
    genre tag of its default copy's file. A word counts only whole and exact. (A collection does not
    count: the uploader files an item under "Audio News" because it is not music, not because it is news.)"""
    found = {}
    for kind, words in (("subject", subjects), ("file", file_genres)):
        for w in words or ():
            g = KEYWORD.get(w.strip().lower())
            if g:
                found.setdefault(g, []).append(f"{kind}:{w.strip().lower()}")
    return found


def archive_genre(per_item):
    """(genre, {word: items}) from a series' items, each an `item_genres` result: the genre that
    more than half of the items name, when exactly one does, "drama" yielding to a specific one that
    also passes. Two specific genres that both pass, or none, is no evidence: the series stays
    unassigned."""
    n = len(per_item)
    votes = {}
    words = {}
    for found in per_item:
        for g, ws in found.items():
            votes[g] = votes.get(g, 0) + 1
            for w in set(ws):
                words.setdefault(g, {})
                words[g][w] = words[g].get(w, 0) + 1
    passing = sorted(g for g, v in votes.items() if v * 2 > n)
    if len(passing) > 1 and "drama" in passing:   # "audio drama" + "horror" is a horror drama: the specific one
        passing.remove("drama")
    if len(passing) != 1:
        return None, {}
    return passing[0], words[passing[0]]
