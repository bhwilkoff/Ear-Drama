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
