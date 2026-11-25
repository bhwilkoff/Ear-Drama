"""R4-9b: time and memory of one run with work: the self-test once, then N scripts through the judge.

    python3 bench.py <originality index dir> <plays dir> <N> [fake-latency seconds per service call]

Scripts are real plays with the words of every line shuffled (no run of five survives, real vocabulary and
length), so each takes the longest path: content, six archive.org phrases, three title services, with recorded
empty answers. No request is made. The politeness waits the live client would add are counted, not slept: the
fake clock advances by the gap and the latency of each call, as the real one's does.
"""
import json
import os
import random
import resource
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "tools"))
from originality import cli  # noqa: E402
from originality import index as I  # noqa: E402
from originality import judge as J  # noqa: E402
from originality import phrases as P  # noqa: E402
from originality import selftest as ST  # noqa: E402
from originality import services as S  # noqa: E402

D, PLAYS, N = sys.argv[1], sys.argv[2], int(sys.argv[3])
LAT = float(sys.argv[4]) if len(sys.argv) > 4 else 1.5
rng = random.Random(11)
t0 = time.time()
ix = I.Index(D, verify=True)
plays = cli.load_plays(PLAYS)
gate = ST.run(ix, plays)
t_self = time.time() - t0
fake = [0.0]
clock = lambda: fake[0]  # noqa: E731


def sleep(s):
    fake[0] += s


empty = {"archive_fts": {"response": {"body": {"hits": {"total": 0, "hits": []}}}}, "wikipedia": {"query": {"search": []}},
         "wikidata": {"search": []}, "openlibrary": {"docs": []}}
texts = list(plays.values())
t1, waited, verdicts, words = time.time(), 0.0, [], 0
for i in range(N):
    lines = texts[i % len(texts)].split("\n")
    rng.shuffle(lines)
    text = "\n".join(" ".join(rng.sample(l.split(), len(l.split()))) for l in lines)
    title = f"Shuffled {i}"
    fx = {"archive_fts\t" + p: empty["archive_fts"] for p in P.pick(text, [], ix.freq)}
    fx.update({s + "\t" + title: empty[s] for s in ("wikipedia", "wikidata", "openlibrary")})

    class Timed(S.Http):
        def get(self, service, query, url):
            gap = S.GAPS[service] - (fake[0] - self.last.get(service, -1e9))
            fake[0] += max(0.0, gap)
            self.last[service] = fake[0]
            fake[0] += LAT
            return super().get(service, query, url)
    http = Timed(fx, sleep=sleep, clock=clock)
    v = J.judge(ix, gate, http, {"key": "k", "title": title, "parts": [], "text": text})
    verdicts.append(v["verdict"])
    words += v["searched"]["words"]
compute = time.time() - t1
print(json.dumps({"scripts": N, "verdicts": verdicts, "words_total": words, "selftest_s": round(t_self, 1),
                  "compute_s": round(compute, 1), "fake_clock_s": round(fake[0], 1),
                  "estimated_live_s": round(t_self + compute + fake[0]),
                  "maxrss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e6)}))
