"""How good is an eSpeak-free neural fallback? g2p_en's seq2seq (trained on CMUdict) against misaki's
gold pronunciations for words CMUdict does NOT contain (so the network never saw them).

usage: python -I fallback_eval.py <oov2.py path> <out json>
Scores with stress marks removed: exact match, and phoneme error rate (edit distance / reference length).
"""
import json, random, re, sys, importlib.resources, runpy
from nltk.corpus import cmudict
from misaki import data

ns = {}
src = open(sys.argv[1]).read()
start = src.index('# ---- neural fallback')
end = src.index('# ---- rules ----')
exec('import re, unicodedata\n' + src[start:end], ns)
neural_ps = ns['neural_ps']

gold = json.load(importlib.resources.open_text(data, 'us_gold.json'))
cmu = set(cmudict.words())
strip = lambda p: re.sub('[ˈˌ]', '', p or '').replace('ɾ', 't').replace('ᵊ', 'ə').replace('ᵻ', 'ɪ')

def lev(a, b):
    d = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        prev, d[0] = d[0], i
        for j, cb in enumerate(b, 1):
            prev, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, prev + (ca != cb))
    return d[-1]

random.seed(76)
names = [w for w, v in gold.items() if isinstance(v, str) and w[:1].isupper() and w[1:].islower() and w.isalpha() and len(w) > 3 and w.lower() not in cmu]
plain = [w for w, v in gold.items() if isinstance(v, str) and w.islower() and w.isalpha() and len(w) > 3 and w not in cmu]
seen_names = [w for w, v in gold.items() if isinstance(v, str) and w[:1].isupper() and w[1:].islower() and w.isalpha() and len(w) > 3 and w.lower() in cmu]
out = {}
for label, pool in (('names not in CMUdict', names), ('lowercase words not in CMUdict', plain), ('names in CMUdict (seen in training: an upper bound)', seen_names)):
    pick = random.sample(pool, min(500, len(pool)))
    exact = 0
    errs = tot = 0
    worst = []
    for w in pick:
        ref, hyp = strip(gold[w]), strip(neural_ps(w))
        e = lev(ref, hyp)
        exact += ref == hyp
        errs += e
        tot += len(ref)
        worst.append((e / max(1, len(ref)), w, gold[w], neural_ps(w)))
    worst.sort(reverse=True)
    out[label] = {'pool': len(pool), 'n': len(pick), 'exact_pct': round(100 * exact / len(pick), 1),
                  'per_pct': round(100 * errs / tot, 1),
                  'examples_bad': [x[1:] for x in worst[:8]], 'examples_ok': [x[1:] for x in worst[len(worst) // 2: len(worst) // 2 + 6]]}
    print(label, {k: v for k, v in out[label].items() if not k.startswith('examples')})
    for x in out[label]['examples_bad'][:5]:
        print('   bad', x)
    for x in out[label]['examples_ok'][:4]:
        print('   mid', x)
json.dump(out, open(sys.argv[2], 'w'), ensure_ascii=False, indent=1)
