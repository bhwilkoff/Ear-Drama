"""The title search (R4-9 section 3). A title is not protected, so it never refuses and never holds by itself:
it asks, naming at most three plays, those whose author is known first. A title of one word that matches four
plays or more asks nothing.

Asked of, in order: our own lists (the library, Gutenberg's list, matched radio titles, drama renewals), then
Wikipedia, Wikidata and Open Library. The Copyright Office's records are best effort in the design and are not
asked here. The claimed author's name is never sent or matched.
"""
import re

from originality import normalize as N
from originality import services as S

MAX_NAMED = 3
COMMON_WORD_CAP = 4
OURS_ORDER = ("gut", "cce", "grw")


def local(titles, title):
    """Plays of ours with this title: [{title, author, source, id}]."""
    out, seen = [], set()
    for src in OURS_ORDER:
        for key in N.title_keys(title):
            for id_, t, author in titles.get(src, {}).get(key, []):
                if id_ not in seen:
                    seen.add(id_)
                    out.append({"title": t, "author": author, "source": "ours", "id": id_})
    return out


def _tags(s):
    return re.sub(r"<[^>]+>", "", s or "")


def remote(http, title):
    """(candidates, {service: ok|failed}). A service that is down is recorded and the others still answer."""
    keys = set(N.title_keys(title))
    cands, state = [], {}

    def run(name, fn, pick):
        try:
            for row in fn(http, title):
                c = pick(row)
                if c and N.norm_title(re.sub(r"\s*\([^)]*\)$", "", c["title"])) in keys:
                    cands.append({**c, "source": name, "id": None})
            state[name] = "ok"
        except S.ServiceDown:
            state[name] = "failed"

    def wp(row):
        t, snippet = row
        paren = re.search(r"\(([^)]*)\)$", t)
        if (paren and re.search(r"\bplay\b", paren.group(1), re.I)) or re.search(r"\b(?:a|an)\b[^.<]{0,80}\bplay\b", _tags(snippet)):
            return {"title": t, "author": ""}

    def wd(row):
        label, desc = row
        if re.search(r"\bplay\b", desc or "", re.I):
            m = re.search(r"\bby (.+)$", desc)
            return {"title": label, "author": m.group(1).strip() if m else ""}

    def ol(row):
        t, authors = row
        return {"title": t, "author": authors[0] if len(authors) == 1 else ""}
    run("wikipedia", S.wikipedia, wp)
    run("wikidata", S.wikidata, wd)
    run("openlibrary", S.openlibrary, ol)
    return cands, state


def decide(title, cands):
    """The plays to ask about: [] for none. Candidates of ours come first, then the others."""
    groups = {}
    for c in cands:
        groups.setdefault(N.norm_title(re.sub(r"\s*\([^)]*\)$", "", c["title"])), []).append(c)
    named = []
    for g in groups.values():
        authors = {c["author"].lower() for c in g if c["author"]}
        seen = set()
        for c in g:
            k = c["author"].lower()
            if (not k and authors) or k in seen:
                continue
            seen.add(k)
            named.append(c)
    if len(N.words(re.split(r"[\n\r:;]", title or "")[0])) == 1 and len(named) >= COMMON_WORD_CAP:
        return []
    named.sort(key=lambda c: not c["author"])
    return named[:MAX_NAMED]
