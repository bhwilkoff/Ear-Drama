"""An episode's sponsor, computed once for every client (docs/CATALOG-CONTRACT.md §3.1).

The research database keeps OTRRpedia's dated sponsor runs per series (`sponsors`).
An episode's sponsor is the run that covers its air date; nothing is shown when no
dated run does. A run with no end lasts until the next dated run of the series starts.
OTRRpedia also files "Sustained" (no sponsor), "Multi" and "Syndicated" in that field:
those are not sponsors and are never published.
"""
NOT_SPONSORS = {"sustained", "multi", "syndicated", "unknown", "none"}
SEP = " / "


def load(db):
    """series_key -> [(start, end, end_exclusive, sponsor)] for the dated runs, by start."""
    if not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='sponsors'").fetchone():
        return {}
    runs = {}
    for key, name, start, end in db.execute("SELECT series_key, sponsor, start, end FROM sponsors "
                                            "WHERE start IS NOT NULL AND start != ''"):
        runs.setdefault(key, []).append((start, end or None, (name or "").strip()))
    out = {}
    for key, rs in runs.items():
        starts = sorted({r[0] for r in rs})
        closed = []
        for start, end, name in sorted(rs, key=lambda r: (r[0], r[2])):
            exclusive = False
            if end is None:
                later = [s for s in starts if s > start]
                end = later[0] if later else None
                exclusive = end is not None
            closed.append((start, end, exclusive, name))
        out[key] = closed
    return out


def sponsor_for(runs, series_key, air_date):
    """The sponsor line for an episode, or None. runs is load()'s result."""
    if not air_date or len(air_date) != 10:
        return None
    names = []
    for start, end, exclusive, name in runs.get(series_key, ()):
        if start > air_date:
            continue
        if end is not None and (air_date >= end if exclusive else air_date > end):
            continue
        if name and name.lower() not in NOT_SPONSORS and name not in names:
            names.append(name)
    return SEP.join(names) or None
