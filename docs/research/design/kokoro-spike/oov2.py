"""Staged OOV measurement: what each eSpeak-free fix buys, on 300 lines and on the corpus.

usage: python -I oov2.py <lib dir> <out json> [corpus_stride]
Stages are cumulative:
  S0 misaki 0.9.4 (us gold + silver), no fallback, whitespace folded
  S1 + text normalization (dashes spaced, ligatures and long s, curly quotes)
  S2 + a per-play lexicon of role-name words (neural G2P at build time)
  S3 + elision rules (-'d -> -ed, a small table: o'er, 'tis, on't, i'th')
  S4 + early-modern spelling variants (u/v, i/j, final -e, doubled vowels), accepted only when the lexicon knows the variant
  S5 + all-caps words are looked up lowercased, never spelled letter by letter
What is left goes to the neural fallback (g2p_en's seq2seq, Apache-2.0): counted as "guessed".
"""
import json, os, random, re, sys, glob, unicodedata
from collections import Counter, defaultdict
from misaki import en

lib, out_path = sys.argv[1], sys.argv[2]
stride = int(sys.argv[3]) if len(sys.argv) > 3 else 4

scripts = []
seen = set()
for f in sorted(glob.glob(os.path.join(lib, 'scripts', '*.json'))):
    for s in json.load(open(f))['scripts']:
        if s['id'] not in seen:
            seen.add(s['id'])
            scripts.append(s)

def raw_text(l):
    t = ' '.join(p.get('say', '') for p in l.get('parts', []) if p.get('say')).replace('_', '')
    return re.sub(r'\s+', ' ', t).strip()

def normalize(t):
    t = t.replace('ſ', 's').replace('æ', 'ae').replace('Æ', 'Ae').replace('œ', 'oe').replace('Œ', 'Oe')
    t = t.replace('‘', "'").replace('’', "'").replace('“', '"').replace('”', '"')
    t = re.sub(r'\s*(—|–|--+)\s*', ' — ', t)
    t = re.sub(r'\[|\]', ' ', t)
    return re.sub(r'\s+', ' ', t).strip()

lines = [(s, l) for s in scripts for l in s['lines'] if l['kind'] == 'speech' and raw_text(l)]
random.seed(76)
sample = random.sample(lines, 300)
corpus = lines[::stride]

g2p = en.G2P(trf=False, british=False, fallback=None)
LEX = g2p.lexicon
CTX = en.TokenContext()
def known(word, tag='NN'):
    ps, _ = LEX.get_word(word, tag, None, CTX)
    return ps

# ---- neural fallback (g2p_en network only) ----
ARPA = {'AA': 'ɑ', 'AE': 'æ', 'AH': 'ʌ', 'AO': 'ɔ', 'AW': 'W', 'AY': 'I', 'EH': 'ɛ', 'ER': 'ɜɹ', 'EY': 'A',
        'IH': 'ɪ', 'IY': 'i', 'OW': 'O', 'OY': 'Y', 'UH': 'ʊ', 'UW': 'u', 'B': 'b', 'CH': 'ʧ', 'D': 'd',
        'DH': 'ð', 'F': 'f', 'G': 'ɡ', 'HH': 'h', 'JH': 'ʤ', 'K': 'k', 'L': 'l', 'M': 'm', 'N': 'n',
        'NG': 'ŋ', 'P': 'p', 'R': 'ɹ', 'S': 's', 'SH': 'ʃ', 'T': 't', 'TH': 'θ', 'V': 'v', 'W': 'w',
        'Y': 'j', 'Z': 'z', 'ZH': 'ʒ'}
def arpa_to_misaki(phones):
    out = []
    for p in phones:
        m = re.fullmatch(r'([A-Z]+)([012]?)', p)
        if not m:
            continue
        base, st = m.groups()
        v = 'ə' if (base == 'AH' and st == '0') else 'əɹ' if (base == 'ER' and st == '0') else ARPA[base]
        out.append(('ˈ' if st == '1' else 'ˌ' if st == '2' else '') + v)
    return ''.join(out)
from g2p_en import G2p as _G2p
class Neural(_G2p):
    def __init__(self):
        self.graphemes = ["<pad>", "<unk>", "</s>"] + list("abcdefghijklmnopqrstuvwxyz")
        ph = ['AA0', 'AA1', 'AA2', 'AE0', 'AE1', 'AE2', 'AH0', 'AH1', 'AH2', 'AO0', 'AO1', 'AO2', 'AW0', 'AW1', 'AW2',
              'AY0', 'AY1', 'AY2', 'B', 'CH', 'D', 'DH', 'EH0', 'EH1', 'EH2', 'ER0', 'ER1', 'ER2', 'EY0', 'EY1', 'EY2',
              'F', 'G', 'HH', 'IH0', 'IH1', 'IH2', 'IY0', 'IY1', 'IY2', 'JH', 'K', 'L', 'M', 'N', 'NG', 'OW0', 'OW1',
              'OW2', 'OY0', 'OY1', 'OY2', 'P', 'R', 'S', 'SH', 'T', 'TH', 'UH0', 'UH1', 'UH2', 'UW', 'UW0', 'UW1', 'UW2',
              'V', 'W', 'Y', 'Z', 'ZH']
        self.phonemes = ["<pad>", "<unk>", "<s>", "</s>"] + ph
        self.g2idx = {g: i for i, g in enumerate(self.graphemes)}
        self.idx2g = {i: g for i, g in enumerate(self.graphemes)}
        self.p2idx = {p: i for i, p in enumerate(self.phonemes)}
        self.idx2p = {i: p for i, p in enumerate(self.phonemes)}
        self.load_variables()
neural = Neural()
def neural_ps(word):
    w = unicodedata.normalize('NFKD', word.lower()).encode('ascii', 'ignore').decode()
    w = re.sub(r'[^a-z]', '', w)
    return arpa_to_misaki(neural.predict(w)) if w else None

# ---- rules ----
ELISIONS = {"o'er": 'over', "e'er": 'ever', "ne'er": 'never', "e'en": 'even', "'tis": 'tis', "'twas": 'twas',
            "th'": 'the', "i'": 'in', "'gainst": 'against', "ta'en": 'taen', "heav'n": 'heaven', "i'le": "i'll",
            "d'ye": 'dye', "i'th'": 'ith', "o'th'": 'oth', "a'm": "i'm", "a've": "i've", "i'faith": 'ifaith'}
EXTRA = {'tis': 'tˈɪz', 'twas': 'twˈʌz', 'taen': 'tˈAn', 'dye': 'dʒə', 'ith': 'ɪðə', 'oth': 'əðə', 'ifaith': 'ɪfˈAθ'}
def elision(word):
    lw = word.lower()
    if lw in ELISIONS:
        return [ELISIONS[lw]]
    m = re.fullmatch(r"([a-z]+)'d", lw)
    if m:
        return [m.group(1) + 'ed', m.group(1) + 'd']
    m = re.fullmatch(r"([a-z]+)'(t|s)", lw)  # on't, is't, for't
    if m and m.group(2) == 't':
        return [m.group(1) + ' it']
    if lw.endswith('èd'):
        return [lw[:-2] + 'ed']
    return []

def spelling_variants(word):
    w = word.lower()
    c = set()
    def add(x):
        if x != w:
            c.add(x)
    if w.startswith('v') and len(w) > 1 and w[1] not in 'aeiou':
        add('u' + w[1:])
    if w.startswith('i') and len(w) > 1 and w[1] in 'aeiou':
        add('j' + w[1:])
    add(re.sub(r'(?<=[aeiou])u(?=[aeiou])', 'v', w))
    add(re.sub(r'(?<=[aeiou])u(?=[aeiou])', 'v', w).rstrip('e'))
    if w.endswith('e') and len(w) > 3:
        add(w[:-1])
    add(re.sub(r'ee', 'e', w))
    add(re.sub(r'(.)\1e$', r'\1', w))
    add(w.replace('ie', 'y') if w.endswith('ie') else w)
    for x in list(c):
        if x.endswith('e') and len(x) > 3:
            add(x[:-1])
    return [x for x in c if x.isalpha()]

STAGE = 0
guessed = []
def fallback(tk):
    w = tk.text
    if STAGE >= 3:
        for cand in elision(w):
            if cand in EXTRA:
                return EXTRA[cand], 2
            parts = cand.split(' ')
            ps = [known(p) for p in parts]
            if all(ps):
                return ' '.join(ps), 2
    if STAGE >= 4 and w.isalpha():
        for cand in spelling_variants(w):
            ps = known(cand)
            if ps:
                return ps, 2
    if STAGE >= 5 and w.isalpha() and w.upper() == w and len(w) >= 3:
        ps = known(w.lower())
        if ps:
            return ps, 2
    guessed.append(w)
    return None, None
g2p.fallback = fallback

spelled = []
orig_nnp = en.Lexicon.get_NNP
def nnp(self, word):
    r = orig_nnp(self, word)
    if r[0] is not None and len(word) >= 3 and word.isalpha():
        spelled.append(word)
    return r
en.Lexicon.get_NNP = nnp
orig_known = en.Lexicon.is_known
def is_known(self, word, tag):
    if STAGE >= 5 and word.isalpha() and len(word) >= 3 and word == word.upper() and word not in self.golds and word not in self.silvers:
        return False
    return orig_known(self, word, tag)
en.Lexicon.is_known = is_known

def role_words(s):
    w = set()
    for r in s.get('roles', []):
        for t in re.split(r"[^A-Za-zÀ-ɏ']+", normalize(r['name'])):
            if len(t) > 1:
                w.add(t.lower())
    return w

project = {}
for s in scripts:
    e = {}
    for w in role_words(s):
        if "'" in w or known(w) or known(w.capitalize()):
            continue
        ps = neural_ps(w)
        if ps:
            e[w] = ps
    project[s['id']] = e

def classify(word, roles):
    w = word
    lw = w.lower()
    if lw in roles:
        return 'role name'
    if re.search(r"[a-z]'d$", w, re.I):
        return "elided -'d"
    if "'" in w:
        return 'other elision'
    if any(ord(c) > 127 for c in w):
        return 'accented / non-ASCII'
    if not w.strip().isalpha():
        return 'token artifact (whitespace, punctuation, hyphen)'
    if re.search(r'(?<=[aeiou])u(?=[aeiou])|^v[^aeiou]|^i[aeiou]|e$', lw) and w[:1].islower():
        return 'old spelling shape, lowercase'
    if w[:1].isupper():
        return 'capitalized (names, places, foreign words)'
    return 'lowercase (archaic, rare, dialect)'

def run(lines_, stage):
    global STAGE, guessed, spelled
    STAGE = stage
    st = Counter()
    classes = Counter()
    ex = defaultdict(Counter)
    sp = Counter()
    for s, l in lines_:
        added = []
        if stage >= 2:
            for w, ps in project.get(s['id'], {}).items():
                for form in {w, w.capitalize(), w.upper()}:
                    if form not in LEX.golds:
                        LEX.golds[form] = ps
                        added.append(form)
        guessed, spelled = [], []
        text = raw_text(l) if stage < 1 else normalize(raw_text(l))
        _, toks = g2p(text)
        st['lines'] += 1
        st['words'] += sum(1 for t in toks if any(c.isalpha() for c in t.text))
        st['guessed'] += len(guessed)
        st['lines_guessed'] += 1 if guessed else 0
        st['spelled'] += len(spelled)
        st['lines_spelled'] += 1 if spelled else 0
        roles = role_words(s)
        for g in guessed:
            c = classify(g, roles)
            classes[c] += 1
            ex[c][g] += 1
        for w in spelled:
            sp[w] += 1
        for f in added:
            del LEX.golds[f]
    return {'stage': stage, 'stats': dict(st),
            'guessed_pct_words': round(100 * st['guessed'] / max(1, st['words']), 2),
            'lines_guessed_pct': round(100 * st['lines_guessed'] / max(1, st['lines']), 1),
            'lines_spelled_pct': round(100 * st['lines_spelled'] / max(1, st['lines']), 1),
            'classes': classes.most_common(), 'examples': {c: ex[c].most_common(20) for c in ex}, 'spelled': sp.most_common(15)}

out = {'scripts': len(scripts), 'speech_lines': len(lines), 'sample': 300, 'corpus_stride': stride, 'sample_runs': [], 'corpus_runs': []}
for stage in range(6):
    r = run(sample, stage)
    out['sample_runs'].append(r)
    print(f"sample S{stage}: words {r['stats']['words']} guessed {r['stats']['guessed']} ({r['guessed_pct_words']}%) "
          f"lines {r['lines_guessed_pct']}% spelled-lines {r['lines_spelled_pct']}%", flush=True)
for stage in (0, 5):
    r = run(corpus, stage)
    out['corpus_runs'].append(r)
    print(f"corpus S{stage}: lines {r['stats']['lines']} words {r['stats']['words']} guessed {r['stats']['guessed']} ({r['guessed_pct_words']}%) "
          f"lines {r['lines_guessed_pct']}% spelled-lines {r['lines_spelled_pct']}%", flush=True)
    for c, n in r['classes']:
        print(f'   {n:7d} {c}: ' + ', '.join(w for w, _ in r['examples'][c][:14]))
    print('   spelled:', r['spelled'][:12])
sizes = sorted(len(v) for v in project.values())
out['project_lexicon'] = {'scripts': len(sizes), 'median': sizes[len(sizes) // 2], 'max': sizes[-1], 'total': sum(sizes)}
print('role lexicon per play', out['project_lexicon'])
json.dump(out, open(out_path, 'w'), ensure_ascii=False, indent=1)
