"""Build every play's phonemes for the Kokoro voices (Decision 078) beside the play library.

    bash tools/setup_phoneme_env.sh                                  # once: catalog/.venv-phonemes
    .venv-phonemes/bin/python tools/build_play_phonemes.py [DIR]     # DIR default out/plays-library
    .venv-phonemes/bin/python tools/build_play_phonemes.py --check   # build in memory, print the report

For each play in DIR/index.json, every speech line's words (play_phonemes.line_text, the key a client
looks a line up by) go through misaki 0.9.4 (Apache-2.0; US and GB lexicons, spaCy tags, NO fallback, so
no eSpeak) and, for a word misaki does not know, in this order:
  1. catalog/plays/phoneme-corrections.json (the play's own entries, then the library's),
  2. play_phonemes.derive: elisions, early-modern spellings, archaic endings, capitals, accents and
     compounds, each accepted only when the lexicon knows the result,
  3. CMUdict (BSD-style, pinned by commit and SHA-256): a real pronunciation, mostly of names misaki
     lacks (Leonard, Sylvia, Cordelia); the GB form is approximated (play_phonemes.us_to_gb),
  4. a neural guess (g2p_en's Apache-2.0 network, run here in numpy), counted as guessed.
A possessive ("Paramore's") is its stem through the same steps plus the ending.
An unknown word in capitals is never spelled letter by letter. Writes:
  DIR/phonemes/<id>.json      play_phonemes.phoneme_file; the index row gains "phonemes": "phonemes/<id>.json"
  DIR/phonemes-report.json    per play: words, guessed, held; the library's guessed words by frequency
A play whose guessed share is above play_phonemes.HOLD_GUESSED_SHARE gets no file (held for an editor).
"""
import collections
import importlib.util
import json
import multiprocessing
import os
import re
import sys
import unicodedata

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play_phonemes as PH

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "..", "out", "plays-library")
CORRECTIONS = os.path.join(HERE, "..", "plays", "phoneme-corrections.json")
G2P_ID = "misaki 0.9.4 (us, gb; no fallback) + Ear Drama rules 1 + corrections + CMUdict 7479086 + g2p_en 2.1.0 network for guesses"


# ---- the neural guesser: g2p_en's network (Apache-2.0), its forward pass in numpy, no nltk ----
PHONES = ["<pad>", "<unk>", "<s>", "</s>", "AA0", "AA1", "AA2", "AE0", "AE1", "AE2", "AH0", "AH1", "AH2", "AO0", "AO1",
          "AO2", "AW0", "AW1", "AW2", "AY0", "AY1", "AY2", "B", "CH", "D", "DH", "EH0", "EH1", "EH2", "ER0", "ER1", "ER2",
          "EY0", "EY1", "EY2", "F", "G", "HH", "IH0", "IH1", "IH2", "IY0", "IY1", "IY2", "JH", "K", "L", "M", "N", "NG",
          "OW0", "OW1", "OW2", "OY0", "OY1", "OY2", "P", "R", "S", "SH", "T", "TH", "UH0", "UH1", "UH2", "UW", "UW0",
          "UW1", "UW2", "V", "W", "Y", "Z", "ZH"]
GRAPHEMES = ["<pad>", "<unk>", "</s>"] + list("abcdefghijklmnopqrstuvwxyz")


class Neural:
    def __init__(self):
        import numpy as np
        self.np = np
        spec = importlib.util.find_spec("g2p_en")
        if spec is None:
            raise SystemExit("g2p_en is not installed (bash tools/setup_phoneme_env.sh)")
        v = np.load(os.path.join(list(spec.submodule_search_locations)[0], "checkpoint20.npz"))
        self.v = {k: v[k] for k in v.files}

    def _cell(self, x, h, p):
        np, v = self.np, self.v
        a = x @ v[p + "w_ih"].T + v[p + "b_ih"]
        b = h @ v[p + "w_hh"].T + v[p + "b_hh"]
        n3 = a.shape[-1] // 3
        r = 1 / (1 + np.exp(-(a[:, :n3] + b[:, :n3])))
        z = 1 / (1 + np.exp(-(a[:, n3:2 * n3] + b[:, n3:2 * n3])))
        n = np.tanh(a[:, 2 * n3:] + r * b[:, 2 * n3:])
        return (1 - z) * n + z * h

    def arpa(self, word):
        np, v = self.np, self.v
        h = np.zeros((1, v["enc_w_hh"].shape[1]), np.float32)
        for ch in list(word) + ["</s>"]:
            x = v["enc_emb"][[GRAPHEMES.index(ch) if ch in GRAPHEMES else 1]]
            h = self._cell(x, h, "enc_")
        dec = v["dec_emb"][[2]]
        out = []
        for _ in range(20):
            h = self._cell(dec, h, "dec_")
            pred = int((h @ v["fc_w"].T + v["fc_b"]).argmax())
            if pred == 3:
                break
            out.append(PHONES[pred])
            dec = v["dec_emb"][[pred]]
        return out

    def guess(self, word, dialect):
        w = re.sub(r"[^a-z]", "", unicodedata.normalize("NFKD", word.lower()).encode("ascii", "ignore").decode())
        if not w:
            return None
        ps = PH.arpa_to_misaki(self.arpa(w))
        return (PH.us_to_gb(ps) if dialect == "gb" else ps) or None


def cmudict():
    """CMUdict at the pinned commit, cached in catalog/.cache/cmudict and checked by SHA-256."""
    import hashlib
    import urllib.request
    path = os.path.join(HERE, "..", ".cache", "cmudict", "cmudict.dict")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        req = urllib.request.Request(PH.CMUDICT_URL, headers={"User-Agent": "ear-drama-catalog"})
        with urllib.request.urlopen(req, timeout=120) as r:
            blob = r.read()
        with open(path + ".part", "wb") as f:
            f.write(blob)
        os.replace(path + ".part", path)
    got = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if got != PH.CMUDICT_SHA256:
        raise SystemExit(f"{path}: sha256 {got} is not the pinned {PH.CMUDICT_SHA256}")
    return PH.load_cmudict(path)


# ---- one dialect's phonemizer ----

class Phonemizer:
    """misaki for one dialect, with the project's lexicon steps as its fallback. Per play: `begin(play_id,
    role_words)`, then `__call__(text)` per line; `stats` counts how each unknown word was handled."""

    def __init__(self, dialect, corrections, neural, cmu):
        from misaki import en
        self.en = en
        self.dialect = dialect
        self.g2p = en.G2P(trf=False, british=(dialect == "gb"), fallback=None)
        lex = self.g2p.lexicon
        golds, silvers = lex.golds, lex.silvers
        orig_known, orig_nnp = lex.is_known, lex.get_NNP
        self.spelled = []

        def is_known(word, tag):
            # An unknown word in capitals is a word, never initials: CHESTERTON is not C-H-E-S-...
            if len(word) >= 3 and word.isalpha() and word == word.upper() and word not in golds and word not in silvers:
                return False
            return orig_known(word, tag)

        def get_nnp(word):
            r = orig_nnp(word)
            if r[0] is not None and len(word) >= 3 and word.isalpha():
                self.spelled.append(word)
            return r

        lex.is_known, lex.get_NNP = is_known, get_nnp
        self.ctx = en.TokenContext()
        self.corrections = corrections
        self.neural = neural
        self.cmu = cmu
        self.play = None
        self.roles = {}
        self.like = {}
        self.g2p.fallback = self.fallback
        self.reset()

    def known(self, word):
        if not word:
            return None
        return self.g2p.lexicon.get_word(word, "NN", None, self.ctx)[0]

    def reset(self):
        self.stats = collections.Counter()
        self.guessed = collections.Counter()
        self.ruled = collections.Counter()
        self.spelled = []

    def begin(self, play_id, role_words):
        self.play = play_id
        self.roles = {w: None for w in role_words}

    def respell(self, like):
        if like not in self.like:
            saved, self.g2p.fallback = self.g2p.fallback, None
            try:
                ps, toks = self.g2p(like)
            finally:
                self.g2p.fallback = saved
            self.like[like] = None if (not ps or self.g2p.unk in ps) else ps
        return self.like[like]

    def correction(self, word):
        c = PH.correction_for(self.corrections, self.play, word, self.dialect)
        if not c:
            return None
        return c[1] if c[0] == "ps" else self.respell(c[1])

    def dictionary(self, word):
        phones = self.cmu.get(word.lower()) or self.cmu.get(PH.ascii_fold(word).lower())
        if not phones:
            return None
        ps = PH.arpa_to_misaki(phones)
        return (PH.us_to_gb(ps) if self.dialect == "gb" else ps) or None

    def resolve(self, w, depth=0):
        """(phonemes, how) for a word misaki does not know: corrected, rule, dictionary or guessed."""
        ps = self.correction(w)
        if ps:
            return ps, "corrected"
        r = PH.derive(w, self.known, self.dialect)
        if r:
            self.ruled[r[1]] += 1
            return r[0], "rule"
        ps = self.dictionary(w) or self.dictionary(w.strip(".,;:!?\"()-—–'*"))
        if ps:
            return ps, "dictionary"
        pos = PH.possessive(w) if depth == 0 else None
        if pos:
            stem_ps, how = self.known(pos[0]), "rule"
            if not stem_ps:
                stem_ps, how = self.resolve(pos[0], depth + 1)
            if stem_ps:
                return stem_ps + PH.possessive_ending(stem_ps, pos[1] == "s'"), how
        if not PH.is_word(w):
            return "", "punct"
        return self.neural.guess(w, self.dialect), "guessed"

    def fallback(self, tk):
        w = tk.text
        ps, how = self.resolve(w)
        if how == "punct":
            return "", 2
        self.stats[how] += 1
        if how == "guessed":
            self.guessed[w] += 1
            if w.lower() in self.roles:
                self.stats["guessed_role_name"] += 1
        return ps, {"corrected": 5, "rule": 2, "dictionary": 2, "guessed": 1}[how]

    def line(self, text):
        """Phonemes for a line's words, and how many words it holds."""
        norm = PH.normalize(text)
        ps, toks = self.g2p(norm)
        words = sum(1 for t in toks if PH.is_word(t.text))
        ps = re.sub(r"\s+", " ", ps.replace(self.g2p.unk, "")).strip()
        ps = "".join(c for c in ps if c in PH.KOKORO_VOCAB)
        return ps, words


def override_known(ph, corrections):
    """Words an editor corrected that the lexicon already knows: put the correction into the lexicon itself
    (library-wide entries; a play's own entries are applied per play in `phonemize_play`)."""
    lex = ph.g2p.lexicon
    for w in corrections.get("words", {}):
        ps = ph.correction(w)
        if ps:
            for form in {w, w.capitalize(), w.upper()}:
                lex.golds[form] = ps


ROLE_SPLIT = re.compile(r"[^A-Za-zÀ-ɏ']+")


def role_words(script):
    out = set()
    for r in script.get("roles", []):
        for t in ROLE_SPLIT.split(PH.normalize(r["name"])):
            if len(t) > 1:
                out.add(t.lower())
    return out


_W = {}


def _init(corrections):
    neural = Neural()
    cmu = cmudict()
    for d in PH.DIALECTS:
        ph = Phonemizer(d, corrections, neural, cmu)
        override_known(ph, corrections)
        _W[d] = ph


def phonemize_play(path):
    """One play: (script id, rows, per-play report row)."""
    script = json.load(open(path, encoding="utf-8"))["scripts"][0]
    rows, words = [], 0
    stats = collections.Counter()
    guessed = collections.Counter()
    ruled = collections.Counter()
    spelled = 0
    roles = role_words(script)
    per_play = {}
    for d, ph in _W.items():
        ph.reset()
        ph.begin(script["id"], roles)
        lex = ph.g2p.lexicon
        added = {}
        for w in (ph.corrections.get("plays", {}).get(script["id"]) or {}):
            ps = ph.correction(w)
            if ps:
                for form in {w, w.capitalize(), w.upper()}:
                    added[form] = lex.golds.get(form)
                    lex.golds[form] = ps
        out = {}
        n = 0
        for l in script["lines"]:
            if l["kind"] != "speech":
                continue
            t = PH.line_text(l)
            if not t or not PH.is_word(t):
                continue
            ps, k = ph.line(t)
            if ps:
                out[l["id"]] = (t, ps)
            n += k
        for form, old in added.items():
            if old is None:
                lex.golds.pop(form, None)
            else:
                lex.golds[form] = old
        per_play[d] = out
        if d == "us":
            words = n
            stats, guessed, ruled, spelled = ph.stats.copy(), ph.guessed.copy(), ph.ruled.copy(), len(ph.spelled)
    for l in script["lines"]:
        if l["id"] in per_play["us"]:
            t, us = per_play["us"][l["id"]]
            row = {"id": l["id"], "t": t, "us": us}
            gb = per_play["gb"].get(l["id"], (None, None))[1]
            if gb and gb != us:
                row["gb"] = gb
            rows.append(row)
    g = sum(guessed.values())
    report = {"id": script["id"], "revision": script["revision"], "words": words, "guessed": g,
              "guessed_share": round(g / max(1, words), 4), "corrected": stats["corrected"], "rule": stats["rule"], "dictionary": stats["dictionary"],
              "rules": dict(sorted(ruled.items())), "guessed_role_name": stats["guessed_role_name"], "spelled": spelled,
              "guessed_words": guessed.most_common()}
    return script, rows, report


def build(root, workers=None, write=True):
    corrections = PH.load_corrections(CORRECTIONS)
    idx = json.load(open(os.path.join(root, "index.json"), encoding="utf-8"))
    paths = [os.path.join(root, p["path"]) for p in idx["plays"]]
    workers = workers or max(1, (os.cpu_count() or 2) - 1)
    results = {}
    with multiprocessing.get_context("spawn").Pool(workers, initializer=_init, initargs=(corrections,)) as pool:
        for i, (script, rows, rep) in enumerate(pool.imap_unordered(phonemize_play, paths, chunksize=1), 1):
            results[script["id"]] = (script, rows, rep)
            if i % 50 == 0:
                print(f"  {i}/{len(paths)} plays", file=sys.stderr, flush=True)
    out_dir = os.path.join(root, "phonemes")
    if write:
        os.makedirs(out_dir, exist_ok=True)
    library = collections.Counter()
    where = collections.defaultdict(set)
    plays, held, keep = [], [], set()
    totals = collections.Counter()
    for p in idx["plays"]:
        script, rows, rep = results[p["id"]]
        totals["words"] += rep["words"]
        totals["guessed"] += rep["guessed"]
        totals["corrected"] += rep["corrected"]
        totals["rule"] += rep["rule"]
        totals["dictionary"] += rep["dictionary"]
        totals["spelled"] += rep["spelled"]
        totals["guessed_role_name"] += rep["guessed_role_name"]
        for w, n in rep["guessed_words"]:
            library[w] += n
            where[w].add(p["id"])
        rep = {**rep, "guessed_words": rep["guessed_words"][:50]}
        p.pop("phonemes", None)
        if rep["guessed_share"] > PH.HOLD_GUESSED_SHARE:
            rep["held"] = True
            held.append(p["id"])
        else:
            doc = PH.phoneme_file(script, rows, G2P_ID)
            PH.check_phoneme_file(doc, script)
            name = f"{p['id']}.json"
            keep.add(name)
            p["phonemes"] = f"phonemes/{name}"
            if write:
                with open(os.path.join(out_dir, name), "w", encoding="utf-8") as f:
                    json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
                    f.write("\n")
        plays.append(rep)
    if write:
        for name in sorted(os.listdir(out_dir)):
            if name not in keep:
                os.remove(os.path.join(out_dir, name))
    summary = {"plays": len(plays), "with_phonemes": len(keep), "held_for_review": sorted(held),
               "hold_guessed_share": PH.HOLD_GUESSED_SHARE, "words": totals["words"], "guessed": totals["guessed"],
               "guessed_share": round(totals["guessed"] / max(1, totals["words"]), 4),
               "guessed_role_name": totals["guessed_role_name"], "corrected": totals["corrected"],
               "rule": totals["rule"], "dictionary": totals["dictionary"], "spelled": totals["spelled"], "distinct_guessed_words": len(library)}
    report = {"format": PH.FORMAT, "g2p": G2P_ID, "summary": summary,
              "sources": ["misaki 0.9.4, Apache-2.0, https://github.com/hexgrad/misaki",
                          "CMUdict " + PH.CMUDICT_URL + ": " + PH.CMUDICT_NOTICE,
                          "g2p_en 2.1.0 network, Apache-2.0, https://github.com/Kyubyong/g2p"],
              "guessed_words": [{"word": w, "count": n, "plays": len(where[w]), "in": sorted(where[w])[:5]}
                                for w, n in sorted(library.items(), key=lambda kv: (-kv[1], kv[0]))[:2000]],
              "plays": sorted(plays, key=lambda r: (-r["guessed_share"], r["id"]))}
    idx["phonemes"] = {"format": PH.FORMAT, "g2p": G2P_ID, "dialects": list(PH.DIALECTS), "report": "phonemes-report.json",
                       "plays": len(keep), "held_for_review": len(held)}
    if write:
        with open(os.path.join(root, "phonemes-report.json"), "w", encoding="utf-8") as f:
            json.dump(report, f, ensure_ascii=False, indent=1)
            f.write("\n")
        with open(os.path.join(root, "index.json"), "w", encoding="utf-8") as f:
            json.dump(idx, f, ensure_ascii=False, separators=(",", ":"))
            f.write("\n")
    return report


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    root = args[0] if args else DEFAULT
    report = build(root, write="--check" not in sys.argv)
    print(json.dumps(report["summary"], indent=1))
    print("most guessed:", ", ".join(f"{g['word']} {g['count']}" for g in report["guessed_words"][:40]))


if __name__ == "__main__":
    main()
