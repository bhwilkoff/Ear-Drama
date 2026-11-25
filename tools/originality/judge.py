"""The judge: content, then archive.org's full-text search, then titles, into one verdict with no script text.

Verdicts: `clear` (searched, nothing found: never proof the words are new), `asks` (a title alone: one question
to the person), `held` (words found elsewhere, or too short to search: the owner reads it), `wait` (a search did
not answer: it never clears).

Nothing is judged until a self-test with planted copies has passed against this very index (selftest.py).
"""
from originality import phrases as P
from originality import services as S
from originality import titles as T
from originality.normalize import strip_labels

RUN_WORDS = 40        # a run of this many words from one work holds
SHARE = 0.02          # or this share of the script, and RUN_WORDS words, from one work
PHRASES_MIN = 2       # two or more of the phrases in one archive.org item hold
PHRASES_NEEDED = 3    # fewer phrases than this cannot be searched: a person reads it
MAX_FINDINGS = 8
MAX_SPANS = 8


class SelfTestFailed(Exception):
    pass


def is_held(max_run, top):
    """The design's rule: a run of RUN_WORDS, or SHARE of the script (and RUN_WORDS words) from the top work."""
    return max_run >= RUN_WORDS or (top is not None and top["covered"] >= SHARE and top["copied"] >= RUN_WORDS)


def content(index, text):
    """{held, words, works: [findings]} of one script against every text held. No word of the script leaves."""
    n, res = index.match(strip_labels(text))
    top = res[0] if res else None
    held = is_held(max((r["run"] for r in res), default=0), top)
    works = [{"work": r["doc"], "run": r["run"], "copied": r["copied"], "share": round(r["covered"], 4),
              "spans": [list(s) for s in r["spans"][:MAX_SPANS]]} for r in res[:MAX_FINDINGS] if r["copied"]]
    return {"held": held, "words": n, "works": works}


def archive(http, found):
    """(state, held, items). `found` is the list of phrases; a phrase that was not answered makes state failed."""
    items, ok = {}, True
    for ph in found:
        try:
            for id_, title in S.ia_search(http, ph):
                items.setdefault(id_, [title, set()])[1].add(ph)
        except S.ServiceDown:
            ok = False
    hits = sorted(((len(v[1]), k, v[0]) for k, v in items.items() if len(v[1]) >= PHRASES_MIN), reverse=True)
    return ("ok" if ok else "failed"), bool(hits), [{"item": k, "title": t, "phrases": n} for n, k, t in hits[:5]]


def judge(index, gate, http, job):
    if gate is None or not gate.passed or gate.index_id != index.id:
        raise SelfTestFailed("no_selftest")
    title, parts, text = job.get("title", ""), job.get("parts") or [], job["text"]
    services = {"index": "ok", "local_titles": "ok", "archive_fts": "skipped",
                "wikipedia": "skipped", "wikidata": "skipped", "openlibrary": "skipped"}
    reasons, findings = [], {}
    ours = T.local(index.titles, title)

    c = content(index, text)
    if c["held"]:
        reasons.append("content")
        findings["content"] = c["works"]
    found = []
    if not reasons:
        found = P.pick(text, parts, index.freq)
        if len(found) < PHRASES_NEEDED:
            reasons.append("too_short")
        else:
            state, held, items = archive(http, found)
            services["archive_fts"] = state
            if held:
                reasons.append("archive_phrases")
                findings["archive"] = items
            elif state == "failed":
                reasons.append("search_down")
    if reasons == ["search_down"]:
        verdict = "wait"
    elif reasons:
        verdict = "held"
        if ours:
            reasons.append("title")
            findings["titles"] = _named(T.decide(title, ours))
    else:
        cands, state = T.remote(http, title)
        services.update(state)
        asks = T.decide(title, ours + cands)
        verdict = "asks" if asks else "clear"
        if "failed" in state.values():
            verdict = "wait"
            reasons.append("search_down")
        elif asks:
            reasons.append("title")
            findings["titles"] = _named(asks)
    return {"v": 1, "key": job.get("key"), "verdict": verdict, "reasons": reasons,
            "searched": {"index": index.date, "index_id": index.id, "works": index.works, "sources": index.sources,
                         "left_out": index.left_out, "services": services, "phrases": len(found), "words": c["words"]},
            "findings": findings}


def _named(asks):
    return [{"title": a["title"], "author": a["author"], "source": a["source"], "id": a["id"]} for a in asks]
