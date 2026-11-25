"""Tests of the originality search (R4-9b/c) over planted data. Run: python3 -I tools/originality/test_originality.py

Every threshold and privacy rule here has a mutant in mutants.py that must make one of these fail.
"""
import contextlib
import gzip
import io
import json
import os
import random
import shutil
import sys
import tempfile
import unittest
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testkit as K  # noqa: E402,F401  (puts tools/ on the path)

from originality import cli  # noqa: E402
from originality import fingerprint as F  # noqa: E402
from originality import index as I  # noqa: E402
from originality import judge as J  # noqa: E402
from originality import normalize as N  # noqa: E402
from originality import phrases as P  # noqa: E402
from originality import plant as PL  # noqa: E402
from originality import selftest as ST  # noqa: E402
from originality import services as S  # noqa: E402
from originality import titles as T  # noqa: E402
from originality.publiclog import LogRefused, PublicLog  # noqa: E402

TMP = tempfile.mkdtemp(prefix="originality-test-")
CORPUS = K.corpus()
PLAYS = {n: CORPUS["gut"][n] for n in ("gut-0", "gut-1", "gut-2", "gut-3")}


def wr(path, text):
    with open(path, "w") as f:
        f.write(text)


def wrb(path, data):
    with open(path, "wb") as f:
        f.write(data)


def rd(path):
    with open(path) as f:
        return f.read()


def rdb(path):
    with open(path, "rb") as f:
        return f.read()


def jd(obj, path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "wt") as f:
        json.dump(obj, f)


EMPTY = {"wikipedia": {"query": {"search": []}}, "wikidata": {"search": []}, "openlibrary": {"docs": []}}


def setUpModule():
    global IX
    K.build_index(os.path.join(TMP, "ix"), CORPUS)
    IX = I.Index(os.path.join(TMP, "ix"), verify=True)


def tearDownModule():
    IX.close()
    shutil.rmtree(TMP, ignore_errors=True)


def gate():
    return ST.run(IX, PLAYS)


def script(seed=99, n=1800):
    """A made-up script that is not any text held (the same made-up vocabulary, another draw)."""
    rng = random.Random(seed)
    words = K.vocab(random.Random(7))
    return K.doc(rng, words, [1 / (i + 4) for i in range(len(words))], n)


def fixtures(text, parts=(), ia=None, title_fx=None, skip=()):
    """Recorded answers for one script: ia(i) is the body for the i-th phrase, or None for no answer."""
    fx = {}
    for i, ph in enumerate(P.pick(text, list(parts), IX.freq)):
        body = (ia or (lambda i: K.fixture("ia_none.json")))(i)
        if body is not None:
            fx["archive_fts\t" + ph] = body
    return fx


def with_titles(fx, title, wp=None, wd=None, ol=None, skip=()):
    for svc, body in (("wikipedia", wp or EMPTY["wikipedia"]), ("wikidata", wd or EMPTY["wikidata"]),
                      ("openlibrary", ol or EMPTY["openlibrary"])):
        if svc not in skip:
            fx[svc + "\t" + title] = body
    return fx


def judge(text, title="Zebra Moon", parts=("Quillo",), fx=None, gate_=None, ix=None):
    http = S.Http(fx if fx is not None else with_titles(fixtures(text), title), sleep=lambda s: None)
    v = J.judge(ix or IX, gate_ or gate(), http, {"key": "k1", "title": title, "parts": list(parts), "text": text})
    return v, http


class Normalize(unittest.TestCase):
    def test_words(self):
        self.assertEqual(N.words("Don't go, Zoë! O'er the [Sound: bell] 'tis"), ["dont", "go", "zoe", "oer", "the", "sound", "bell", "tis"])

    def test_labels_and_spans(self):
        t = "ALICE: Hello there.\n\nBOB: Hi.\n\nALICE: Again.\n\nALICE: More. (aside) [Crash]\n\nBOB: Ok.\n\nBOB: Yes."
        self.assertEqual(N.words(N.strip_labels(t)), ["hello", "there", "hi", "again", "more", "ok", "yes"])

    def test_title_keys(self):
        self.assertEqual(N.title_keys("The Glass Menagerie: A Play; or, More"), ["glassmenagerieaplayormore", "glassmenagerie"])
        self.assertEqual(N.title_keys("Fences"), ["fences"])


class Winnowing(unittest.TestCase):
    def test_sixteen_shared_words_always_share_a_number(self):
        rng = random.Random(3)
        vocab = [f"w{i}" for i in range(60)]  # a small vocabulary: repeats, ties, and low entropy all happen
        for _ in range(400):
            shared = [rng.choice(vocab) for _ in range(rng.randint(F.K + F.W - 1, 40))]
            a = [rng.choice(vocab) for _ in range(rng.randint(0, 50))] + shared + [rng.choice(vocab) for _ in range(rng.randint(0, 50))]
            b = [rng.choice(vocab) for _ in range(rng.randint(0, 50))] + shared + [rng.choice(vocab) for _ in range(rng.randint(0, 50))]
            known = F.winnow(F.grams(a, F.K), F.W)
            ours = set(F.grams(b, F.K))
            self.assertTrue(known & ours, shared)

    def test_fifteen_words_need_not_share(self):
        rng = random.Random(4)
        miss = 0
        for _ in range(200):
            shared = [f"s{rng.random()}" for _ in range(F.K + F.W - 2)]
            a = [f"a{rng.random()}" for _ in range(40)] + shared + [f"a{rng.random()}" for _ in range(40)]
            b = [f"b{rng.random()}" for _ in range(40)] + shared + [f"b{rng.random()}" for _ in range(40)]
            miss += not (F.winnow(F.grams(a, F.K), F.W) & set(F.grams(b, F.K)))
        self.assertGreater(miss, 0)


class IndexFiles(unittest.TestCase):
    def build(self, name, **kw):
        d = os.path.join(TMP, name)
        K.build_index(d, CORPUS, **kw)
        return d

    def test_missing_required_source_refused(self):
        for src in I.REQUIRED:
            d = self.build("miss-" + src, without=(src,))
            with self.assertRaises(I.IndexRefused):
                I.Index(d)

    def test_empty_source_refused(self):
        d = self.build("empty")
        wrb(os.path.join(d, "gut.u64"), b"")
        with self.assertRaises(I.IndexRefused):
            I.Index(d)

    def test_source_with_no_documents_refused(self):
        d = os.path.join(TMP, "nodocs")
        os.makedirs(d)
        man = {"gut": I.build_source("gut", [], d), "tr": I.build_source("tr", [("tr-a", script(3))], d)}
        I.write_manifest(d, "2026-11-25", 5, 12, man)
        with self.assertRaises(I.IndexRefused):
            I.Index(d)

    def test_changed_file_refused_by_sha(self):
        d = self.build("sha")
        p = os.path.join(d, "tr.u64")
        b = bytearray(rdb(p))
        b[100] ^= 1
        wrb(p, bytes(b))
        I.Index(d).close()
        with self.assertRaises(I.IndexRefused):
            I.Index(d, verify=True)

    def test_workshop_part_can_be_left_out(self):
        d = self.build("nogrw", without=("grw",))
        ix = I.Index(d, verify=True)
        self.assertEqual((ix.sources, ix.left_out), (["gut", "tr"], ["grw"]))
        self.assertNotEqual(ix.id, IX.id)
        self.assertFalse(os.path.exists(os.path.join(d, "grw.u64")))
        # the Workshop's text is no longer found, the others' still is
        self.assertFalse(J.content(ix, CORPUS["grw"]["grw-1"])["held"])
        self.assertTrue(J.content(ix, CORPUS["gut"]["gut-5"])["held"])
        ix.close()
        self.assertTrue(J.content(IX, CORPUS["grw"]["grw-1"])["held"])

    def test_build_from_caches(self):
        c = os.path.join(TMP, "cache")
        marker = "zqxjkmarker"
        for d in ("gutenberg/text", "grw/text"):
            os.makedirs(os.path.join(c, d))
        wr(os.path.join(c, "gutenberg/text/1.txt"), 
            "front\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\n" + CORPUS["gut"]["gut-0"] + f" {marker}\n*** END OF THE PROJECT GUTENBERG EBOOK X ***\nlicense")
        wr(os.path.join(c, "grw/text/A1.txt"), "<p>" + CORPUS["grw"]["grw-0"].replace("\n", "<br>") + "</p>")
        jd({"plays": [{"id": "gut-1", "title": "First Play: A Comedy", "authors": [{"name": "Quill, Ada"}]}]}, os.path.join(c, "gutenberg/plays.json"))
        jd({"scripts": [{"id": "A1", "title": "Radio Night"}]}, os.path.join(c, "grw/scripts.json"))
        jd([{"title": "Cce Drama", "author": "AKINS, ZOE", "r": "R1"}], os.path.join(c, "cce_drama_renewals.json.gz"))
        jd({"a|b|1940-01-01": {"text": CORPUS["tr"]["tr-0|x|1940-01-01"]}, "e": {"text": ""}}, os.path.join(c, "t.json.gz"))
        out = os.path.join(TMP, "built")
        man = I.build(c, os.path.join(c, "t.json.gz"), out, "2026-11-25")
        self.assertEqual({k: v["docs"] for k, v in man["sources"].items()}, {"gut": 1, "tr": 1, "grw": 1})
        ix = I.Index(out, verify=True)
        self.assertEqual(ix.titles["gut"]["firstplay"], [["gut-1", "First Play: A Comedy", "Ada Quill"]])
        self.assertEqual(ix.titles["gut"]["firstplayacomedy"][0][0], "gut-1")
        self.assertEqual(ix.titles["cce"]["cce drama".replace(" ", "")][0][2], "Zoe Akins")
        self.assertFalse(J.content(ix, "other words entirely here and there in this short text").get("held"))
        ix.close()
        for f in os.listdir(out):  # no word of a text is in any file
            data = rdb(os.path.join(out, f))
            if f.endswith(".gz"):
                data = gzip.decompress(data)
            self.assertNotIn(marker.encode(), data, f)
            self.assertNotIn(b"radio night" if f.startswith("grw") else b"\x00\x01", data.lower() if f == "grw.u64" else b"")
        man = I.build(c, os.path.join(c, "t.json.gz"), out, "2026-11-25", without=("grw",))
        self.assertNotIn("grw", man["sources"])
        self.assertFalse(os.path.exists(os.path.join(out, "titles-grw.json.gz")))


class Content(unittest.TestCase):
    def test_edges_of_the_rule(self):
        top = lambda cov, copied: {"covered": cov, "copied": copied}  # noqa: E731
        self.assertTrue(J.is_held(40, None))
        self.assertFalse(J.is_held(39, top(0.0, 39)))
        self.assertTrue(J.is_held(0, top(0.02, 40)))
        self.assertFalse(J.is_held(0, top(0.0199, 40)))
        self.assertFalse(J.is_held(0, top(0.5, 39)))

    def test_a_copy_is_held_and_names_its_source(self):
        r = J.content(IX, PLAYS["gut-0"])
        self.assertTrue(r["held"])
        self.assertEqual(r["works"][0]["work"], "gut-0")
        self.assertGreater(r["works"][0]["share"], 0.9)

    def test_labeled_copy_is_held(self):
        text = "\n\n".join(f"ALICE: {l}" if i % 2 else f"BOB: {l}" for i, l in enumerate(PLAYS["gut-1"].split("\n")))
        self.assertTrue(J.content(IX, text)["held"])

    def test_unrelated_is_not(self):
        for seed in range(5):
            self.assertFalse(J.content(IX, script(seed))["held"], seed)

    def test_passage_in_other_words(self):
        ws = PLAYS["gut-4"].split() if "gut-4" in PLAYS else CORPUS["gut"]["gut-4"].split()
        fill = CORPUS["gut"]["gut-6"].split()
        random.Random(1).shuffle(fill)
        for n, held in ((25, False), (60, True), (150, True)):
            text = " ".join(fill[:900]) + " " + " ".join(ws[500:500 + n]) + " " + " ".join(fill[900:1800])
            self.assertEqual(J.content(IX, text)["held"], held, n)

    def test_verdict_findings_hold_no_words(self):
        r = J.content(IX, PLAYS["gut-0"])
        self.assertEqual(set(r["works"][0]), {"work", "run", "copied", "share", "spans"})


class Loops(unittest.TestCase):
    def test_a_loop_is_not_a_copy(self):
        d = os.path.join(TMP, "loop")
        loop = "alpha beta gamma delta epsilon zeta eta " * 120
        os.makedirs(d)
        man = I.build_source("gut", [("gut-loop", loop)], d)
        I.build_source("tr", [("tr-x", script(41))], d)
        I.write_manifest(d, "2026-11-25", 5, 12, {"gut": man, "tr": I.build_source("tr", [("tr-x", script(41))], d)})
        ix = I.Index(d)
        self.assertFalse(J.content(ix, loop)["held"])
        ix.close()


class Phrases(unittest.TestCase):
    def test_rule(self):
        text = script(5)
        got = P.pick(text, ["Kebalo"], IX.freq)
        self.assertEqual(got, P.pick(text, ["Kebalo"], IX.freq))
        self.assertTrue(4 <= len(got) <= P.COUNT)
        sents = [set(N.words(s)) for s in N.sentences(text)]
        for ph in got:
            ws = ph.split()
            self.assertIn(len(ws), (7, 8))
            self.assertTrue(all(IX.freq.get(w, 0) >= P.SEEN_MIN for w in ws))
            self.assertTrue(any(set(ws) <= s for s in sents))

    def test_no_part_name_and_unseen_words_refused(self):
        text = script(5)
        names = sorted({w for ph in P.pick(text, [], IX.freq) for w in ph.split()})[:5]
        self.assertNotEqual(P.pick(text, names, IX.freq), P.pick(text, [], IX.freq))
        for ph in P.pick(text, names, IX.freq):
            self.assertFalse(set(ph.split()) & set(names))
        freq = {w: 1 for w in IX.freq}
        self.assertEqual(P.pick(text, [], freq), [])

    def test_one_from_each_sixth(self):
        text = script(5)
        got = P.pick(text, [], IX.freq)
        sents = [N.words(s) for s in N.sentences(text)]
        where = [next(i for i, s in enumerate(sents) if " ".join(s).find(ph) >= 0) for ph in got]
        self.assertEqual(where, sorted(where))
        self.assertEqual(len({w * 6 // len(sents) for w in where}), len(got))


class Archive(unittest.TestCase):
    def phrases(self, text):
        return P.pick(text, ["Quillo"], IX.freq)

    def fx(self, text, answers):
        ph = self.phrases(text)
        return {"archive_fts\t" + p: (answers[i] if i < len(answers) else K.fixture("ia_none.json")) for i, p in enumerate(ph)}

    def test_two_phrases_in_one_item_hold(self):
        text = script(11)
        hit = K.fixture("ia_hits.json")
        v, http = judge(text, fx=self.fx(text, [hit, hit]))
        self.assertEqual((v["verdict"], v["reasons"]), ("held", ["archive_phrases"]))
        item = v["findings"]["archive"][0]
        self.assertEqual(item["phrases"], 2)
        self.assertEqual(http.calls, len(self.phrases(text)))  # nothing asked of the title services after a hold

    def test_the_verdict_holds_no_phrase(self):
        text = script(11)
        hit = K.fixture("ia_hits.json")
        v, _ = judge(text, fx=self.fx(text, [hit, hit]))
        raw = json.dumps(v)
        for ph in self.phrases(text):
            self.assertNotIn(ph, raw)
            self.assertNotIn(ph.split()[0] + " " + ph.split()[1], N.words(raw) and " ".join(N.words(raw)))

    def test_one_phrase_is_nothing(self):
        text = script(11)
        v, _ = judge(text, fx=with_titles(self.fx(text, [K.fixture("ia_hits.json")]), "Zebra Moon"))
        self.assertEqual(v["verdict"], "clear")

    def test_three_phrases_hold_and_count(self):
        text = script(11)
        hit = K.fixture("ia_hits.json")
        v, _ = judge(text, fx=self.fx(text, [hit, hit, hit]))
        self.assertEqual(v["findings"]["archive"][0]["phrases"], 3)

    def test_too_short_to_search_goes_to_a_person(self):
        v, http = judge(script(1, n=9))
        self.assertEqual((v["verdict"], v["reasons"], http.calls), ("held", ["too_short"], 0))

    def test_answer_shape_changed_is_down(self):
        text = script(11)
        fx = self.fx(text, [{"response": {"nope": 1}}])
        v, _ = judge(text, fx=with_titles(fx, "Zebra Moon"))
        self.assertEqual(v["verdict"], "wait")


class Titles(unittest.TestCase):
    def plays(self, n, authored=True):
        return [{"title": "Hamlet", "author": f"A{i}" if authored else "", "source": "ours", "id": f"gut-{i}"} for i in range(n)]

    def test_named_with_author_first_and_at_most_three(self):
        c = [{"title": "Fences", "author": "", "source": "wikipedia", "id": None}] + \
            [{"title": "Fences", "author": f"P{i}", "source": "ours", "id": f"x{i}"} for i in range(5)]
        got = T.decide("Fences Cycle", c)
        self.assertEqual(len(got), 3)
        self.assertTrue(all(g["author"] for g in got))

    def test_authorless_plays_come_after_known_ones(self):
        c = [{"title": "Cycle One", "author": "", "source": "ours", "id": "a"}] + \
            [{"title": "Cycle Two", "author": f"P{i}", "source": "ours", "id": f"x{i}"} for i in range(3)]
        self.assertTrue(all(g["author"] for g in T.decide("Cycle Two", c)))

    def test_authorless_duplicate_of_a_known_play_is_dropped(self):
        c = [{"title": "Fences", "author": "", "source": "wikipedia", "id": None},
             {"title": "Fences", "author": "August Wilson", "source": "ours", "id": "a"},
             {"title": "Fences", "author": "august wilson", "source": "wikidata", "id": None}]
        self.assertEqual([g["author"] for g in T.decide("Fences Cycle", c)], ["August Wilson"])

    def test_one_common_word_with_four_plays_asks_nothing(self):
        self.assertEqual(T.decide("Hamlet", self.plays(4)), [])
        self.assertEqual(len(T.decide("Hamlet", self.plays(3))), 3)
        self.assertEqual(len(T.decide("Hamlet Prince", self.plays(4))), 3)

    def test_recorded_answers(self):
        http = S.Http({"wikipedia\tFences": K.fixture("wikipedia_fences.json"), "wikidata\tFences": K.fixture("wikidata_fences.json"),
                       "openlibrary\tFences": K.fixture("openlibrary_fences.json")})
        c, state = T.remote(http, "Fences")
        self.assertEqual(state, {"wikipedia": "ok", "wikidata": "ok", "openlibrary": "ok"})
        self.assertEqual({(x["source"], x["author"]) for x in c},
                         {("wikipedia", ""), ("wikidata", "August Wilson"), ("openlibrary", "August Wilson")})
        http = S.Http({"wikipedia\tThe Visitor": K.fixture("wikipedia_visitor.json"), "wikidata\tThe Visitor": K.fixture("wikidata_visitor.json"),
                       "openlibrary\tThe Visitor": EMPTY["openlibrary"]})
        c, _ = T.remote(http, "The Visitor")
        self.assertEqual([x["title"] for x in c], ["The Visitor (play)"])

    def test_local_titles(self):
        got = T.local(IX.titles, "The Fences: or, more")
        self.assertEqual([(g["title"], g["author"]) for g in got], [("Fences", "August Wilson")])


class Verdicts(unittest.TestCase):
    def test_clear_records_what_was_searched(self):
        v, _ = judge(script(21))
        self.assertEqual(v["verdict"], "clear")
        s = v["searched"]
        self.assertEqual((s["index"], s["works"], s["sources"], s["left_out"]), ("2026-11-25", 41, ["gut", "tr", "grw"], []))
        self.assertEqual(set(s["services"].values()), {"ok"})

    def test_title_alone_asks_and_never_holds(self):
        text = script(22)
        fx = with_titles(fixtures(text), "Fences", K.fixture("wikipedia_fences.json"), K.fixture("wikidata_fences.json"), K.fixture("openlibrary_fences.json"))
        v, _ = judge(text, title="Fences", fx=fx)
        self.assertEqual((v["verdict"], v["reasons"]), ("asks", ["title"]))
        self.assertEqual(v["findings"]["titles"][0]["author"], "August Wilson")
        self.assertNotIn("content", v["findings"])

    def test_title_and_content_go_to_the_owner_with_both(self):
        v, http = judge(PLAYS["gut-0"], title="Fences", fx={})
        self.assertEqual((v["verdict"], v["reasons"]), ("held", ["content", "title"]))
        self.assertIn("content", v["findings"])
        self.assertIn("titles", v["findings"])
        self.assertEqual(http.calls, 0)

    def test_no_service_down_ever_clears(self):
        text = script(23)
        base = with_titles(fixtures(text), "Fences", K.fixture("wikipedia_fences.json"), K.fixture("wikidata_fences.json"), K.fixture("openlibrary_fences.json"))
        v, _ = judge(text, title="Zebra Moon", fx=with_titles(fixtures(text), "Zebra Moon"))
        self.assertEqual(v["verdict"], "clear")
        for svc in ("wikipedia", "wikidata", "openlibrary"):
            fx = with_titles(fixtures(text), "Zebra Moon", skip=(svc,))
            v, _ = judge(text, title="Zebra Moon", fx=fx)
            self.assertEqual((v["verdict"], v["searched"]["services"][svc]), ("wait", "failed"), svc)
            v, _ = judge(text, title="Fences", fx={k: x for k, x in base.items() if not k.startswith(svc)})
            self.assertEqual(v["verdict"], "wait", svc)
        fx = with_titles(fixtures(text), "Zebra Moon")
        fx.pop(next(k for k in fx if k.startswith("archive_fts")))
        v, _ = judge(text, title="Zebra Moon", fx=fx)
        self.assertEqual((v["verdict"], v["searched"]["services"]["archive_fts"]), ("wait", "failed"))
        v, _ = judge(text, title="Zebra Moon", fx={})
        self.assertEqual(v["verdict"], "wait")

    def test_the_workshop_left_out_is_recorded(self):
        d = os.path.join(TMP, "nogrw2")
        K.build_index(d, CORPUS, without=("grw",))
        ix = I.Index(d)
        v, _ = judge(script(24), ix=ix, gate_=ST.run(ix, PLAYS))
        self.assertEqual((v["verdict"], v["searched"]["left_out"], v["searched"]["sources"]), ("clear", ["grw"], ["gut", "tr"]))
        ix.close()


class Gate(unittest.TestCase):
    def test_passes_and_covers_every_disguise(self):
        g = gate()
        self.assertTrue(g.passed, g.failures())
        self.assertEqual(len(g.results), 3 * 6 + 1)
        self.assertEqual({c for _, c, _ in g.results}, {"verbatim", "renamed_characters", "ocr_3pct_letters", "synonyms_all",
                                                         "one_act_third", "passage_150_words_in_2000", "shuffled_control"})

    def test_judge_refuses_without_a_passed_gate(self):
        http = S.Http({}, sleep=lambda s: None)
        job = {"key": "k", "title": "T", "parts": [], "text": script(1)}
        for g in (None, ST.Gate(IX.id, []), ST.Gate(IX.id, [("a", "b", False)]), ST.Gate("0" * 12, [("a", "b", True)])):
            with self.assertRaises(J.SelfTestFailed):
                J.judge(IX, g, http, job)

    def test_fails_with_the_index_emptied(self):
        c = K.corpus(seed=8)  # other texts: none of the plays is in it
        d = os.path.join(TMP, "other")
        K.build_index(d, {s: {n.replace("gut-", "gut-x"): t for n, t in v.items()} for s, v in c.items()})
        ix = I.Index(d)
        self.assertFalse(ST.run(ix, PLAYS).passed)
        ix.close()

    def test_fails_with_k_changed(self):
        k = IX.k
        try:
            IX.k = 4
            self.assertFalse(ST.run(IX, PLAYS).passed)
        finally:
            IX.k = k

    def test_fails_with_the_threshold_at_400(self):
        old = J.RUN_WORDS
        try:
            J.RUN_WORDS = 400
            self.assertFalse(ST.run(IX, PLAYS).passed)
        finally:
            J.RUN_WORDS = old

    def test_fails_when_nothing_is_held(self):
        old = J.SHARE, J.RUN_WORDS
        try:
            J.SHARE, J.RUN_WORDS = 2.0, 10 ** 9
            self.assertFalse(ST.run(IX, PLAYS).passed)
        finally:
            J.SHARE, J.RUN_WORDS = old

    def test_a_source_that_is_not_among_the_works_found_fails(self):
        old = J.content
        try:
            J.content = lambda ix, t: {"held": True, "words": 1, "works": [{"work": "gut-9", "copied": 500}]}
            self.assertFalse(ST.run(IX, PLAYS).passed)
            J.content = lambda ix, t: {"held": True, "words": 1, "works": [{"work": n, "copied": 500} for n in PLAYS]}
            self.assertTrue(ST.run(IX, PLAYS).results[0][2])
            J.content = lambda ix, t: {"held": True, "words": 1, "works": [{"work": n, "copied": 5} for n in PLAYS]}
            self.assertFalse(ST.run(IX, PLAYS).results[0][2])
        finally:
            J.content = old

    def test_fails_with_fewer_plays(self):
        self.assertFalse(ST.run(IX, {n: PLAYS[n] for n in ("gut-0", "gut-1")}).passed)

    def test_a_control_that_is_held_fails(self):
        old = J.is_held
        try:
            J.is_held = lambda *a: True
            self.assertFalse(ST.run(IX, PLAYS).passed)
        finally:
            J.is_held = old


class Client(unittest.TestCase):
    def test_fixture_mode_never_touches_the_network(self):
        real = urllib.request.urlopen
        urllib.request.urlopen = lambda *a, **k: (_ for _ in ()).throw(AssertionError("network"))
        try:
            http = S.Http({"archive_fts\tp": K.fixture("ia_none.json")})
            self.assertEqual(S.ia_search(http, "p"), [])
            with self.assertRaises(S.ServiceDown):
                S.ia_search(http, "missing")
        finally:
            urllib.request.urlopen = real

    def test_budget(self):
        http = S.Http({"wikidata\tx": EMPTY["wikidata"]}, max_calls=2)
        S.wikidata(http, "x")
        S.wikidata(http, "x")
        with self.assertRaises(S.ServiceDown):
            S.wikidata(http, "x")

    def test_live_requests_are_polite_generic_and_retried_once(self):
        seen, clock, slept = [], [0.0], []
        body = json.dumps(K.fixture("ia_none.json")).encode()

        class R:
            def __enter__(s):
                return s

            def __exit__(s, *a):
                return False

            def read(s):
                return body

        def fake(req, timeout):
            seen.append((req.full_url, dict(req.header_items()), timeout))
            if len(seen) == 1:
                raise OSError("reset")
            return R()
        real = urllib.request.urlopen
        urllib.request.urlopen = fake
        try:
            http = S.Http(None, sleep=lambda s: (slept.append(s), clock.__setitem__(0, clock[0] + s)), clock=lambda: clock[0])
            self.assertEqual(S.ia_search(http, "some phrase here"), [])
            self.assertEqual(S.ia_search(http, "another phrase here"), [])
        finally:
            urllib.request.urlopen = real
        self.assertEqual(len(seen), 3)
        for url, headers, timeout in seen:
            self.assertEqual(headers["User-agent"], "EarDrama-originality/1.0 (+https://eardrama.org)")
            self.assertEqual(timeout, S.TIMEOUT)
            self.assertNotIn("Cookie", headers)
        self.assertTrue(all(g >= 3.0 for g in slept if g), slept)
        self.assertIn("%22some%20phrase%20here%22", seen[0][0])

    def test_two_failures_are_down(self):
        real = urllib.request.urlopen
        urllib.request.urlopen = lambda req, timeout: (_ for _ in ()).throw(OSError("x"))
        try:
            with self.assertRaises(S.ServiceDown):
                S.Http(None, sleep=lambda s: None).get("wikidata", "x", "https://example.invalid/")
        finally:
            urllib.request.urlopen = real


MARK = ["zqxjkmarker", "wvbnmtitle", "plmokpart", "ghfdsakey"]


class Privacy(unittest.TestCase):
    def job(self, text):
        return {"key": MARK[3], "title": MARK[1] + " " + MARK[1], "parts": [MARK[2], MARK[0] + "x"], "text": text + " " + MARK[0] + " " + MARK[0]}

    def check(self, text, fx):
        job = os.path.join(TMP, "job.json")
        jd(self.job(text), job)
        jd(fx, os.path.join(TMP, "fx.json"))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cli.main(["judge", "--index", os.path.join(TMP, "ix"), "--plays-dir", self.plays_dir(), "--job", job,
                             "--out", os.path.join(TMP, "verdict.json"), "--fixtures", os.path.join(TMP, "fx.json")], log=PublicLog(out))
        return code, out.getvalue() + err.getvalue()

    def plays_dir(self):
        d = os.path.join(TMP, "plays")
        os.makedirs(d, exist_ok=True)
        for n, t in PLAYS.items():
            wr(os.path.join(d, n + ".txt"), t)
        return d

    def test_a_full_job_prints_only_the_allowed_lines(self):
        text = script(31)
        fx = with_titles(fixtures(text), MARK[1] + " " + MARK[1])
        code, log = self.check(text, fx)
        self.assertEqual(code, 0)
        for m in MARK + N.words(text)[:50]:
            self.assertNotIn(m, log)
        self.assertEqual(log.split("\n")[:-1], ["index 2026-11-25", "service index ok", "selftest passed", "checked 1",
                                                "service local_titles ok", "service archive_fts ok", "service wikipedia ok", "service wikidata ok",
                                                "service openlibrary ok", "verdict clear"])

    def test_the_verdict_holds_no_script_text(self):
        for text, fx in ((script(31), None), (PLAYS["gut-0"], {})):
            if fx is None:
                fx = with_titles(fixtures(script(31)), MARK[1] + " " + MARK[1])
            code, _ = self.check(text, fx)
            raw = rd(os.path.join(TMP, "verdict.json"))
            for m in MARK[:3]:
                self.assertNotIn(m, raw)
            self.assertEqual(json.loads(raw)["key"], MARK[3])
            ws = N.words(text)
            grams = {" ".join(ws[i:i + 3]) for i in range(len(ws) - 2)}
            vw = N.words(raw)
            self.assertFalse(grams & {" ".join(vw[i:i + 3]) for i in range(len(vw) - 2)})

    def test_exceptions_print_their_class_only(self):
        for exc in (ValueError(MARK[0]), KeyError(MARK[1]), RuntimeError(MARK[2]), S.ServiceDown(MARK[3]),
                    type(MARK[0], (Exception,), {})(MARK[1])):
            real = J.judge
            J.judge = lambda *a, e=exc, **k: (_ for _ in ()).throw(e)
            try:
                code, log = self.check(script(32), {})
            finally:
                J.judge = real
            self.assertEqual(code, 1)
            self.assertRegex(log, r"error (ValueError|KeyError|RuntimeError|ServiceDown|other)\n$")
            for m in MARK:
                self.assertNotIn(m, log)

    def test_bad_input_prints_class_only(self):
        code, log = self.check(script(33), {})
        self.assertEqual(code, 0)  # no answer from any service is a wait, not a crash
        self.assertTrue(log.endswith("verdict wait\n"))
        job = os.path.join(TMP, "bad.json")
        wr(job, json.dumps({"title": MARK[0]}))
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = cli.main(["judge", "--index", os.path.join(TMP, "ix"), "--plays-dir", self.plays_dir(), "--job", job,
                             "--out", os.path.join(TMP, "v2.json"), "--fixtures", os.path.join(TMP, "fx.json")], log=PublicLog(out))
        self.assertEqual((code, out.getvalue().split("\n")[-2]), (1, "error KeyError"))
        self.assertNotIn(MARK[0], out.getvalue())

    def test_the_log_refuses_free_text(self):
        log = PublicLog(io.StringIO())
        for call in (lambda: log.verdict(MARK[0]), lambda: log.service(MARK[1], True), lambda: log.index(MARK[2]),
                     lambda: log.checked(MARK[0]), lambda: log.service("wikipedia", MARK[0]), lambda: log.index("2026-11-25 " + MARK[0])):
            with self.assertRaises(LogRefused) as cm:
                call()
            self.assertNotIn(MARK[0], str(cm.exception) + repr(cm.exception.args))

    def test_failed_selftest_judges_nothing(self):
        text = script(34)
        job = os.path.join(TMP, "job2.json")
        jd(self.job(text), job)
        d = os.path.join(TMP, "badplays")
        os.makedirs(d, exist_ok=True)
        for n in PLAYS:
            wr(os.path.join(d, n + ".txt"), script(77))  # not in the index
        out = io.StringIO()
        v = os.path.join(TMP, "never.json")
        code = cli.main(["judge", "--index", os.path.join(TMP, "ix"), "--plays-dir", d, "--job", job, "--out", v,
                         "--fixtures", os.path.join(TMP, "fx.json")], log=PublicLog(out))
        self.assertEqual(code, 2)
        self.assertFalse(os.path.exists(v))
        self.assertEqual(out.getvalue().split("\n")[-2], "selftest failed")


class Plants(unittest.TestCase):
    def test_disguises_change_what_they_say_they_change(self):
        t = PLAYS["gut-0"]
        classes = dict(PL.plants(t, PLAYS["gut-3"], 1))
        self.assertEqual(classes["verbatim"], t)
        self.assertLess(len(classes["one_act_third"]), len(t) * 0.4)
        self.assertEqual(len(classes["passage_150_words_in_2000"].split()), 2000)
        english = "the good man went home and the little house was old " * 40
        self.assertNotEqual(dict(PL.plants(english, english, 1))["synonyms_all"], english)
        self.assertEqual(list(dict(PL.plants(t, PLAYS["gut-3"], 1))), list(classes))
        self.assertEqual(dict(PL.plants(t, PLAYS["gut-3"], 1)), classes)


if __name__ == "__main__":
    unittest.main()
