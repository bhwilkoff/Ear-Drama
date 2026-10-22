"""Rule-based radio script parser (research prototype). Text -> blocks typed
speech / cue / direction / other. Run: python3 -I radio_parse.py FILE..."""
import html, re, sys, json, collections

CUE_TAGS = {
 'music': r'MUSIC|THEME|ORCH(?:ESTRA)?|ORGAN|BAND|QUARTET|SONG|BRIDGE|STING',
 'sound': r'SOUND(?:\s*(?:EFFECTS?|FX))?|SFX|F/?X|EFFECTS?|SOUND\s*EFFECT|SOUND\s*PATTERN|BIZ|BUSINESS|APPLAUSE|NOISE',
 'pause': r'PAUSE|BREAK|STATION BREAK|SILENCE',
}
CUE = re.compile(r'^\(?\s*(%s)\s*[:;.\-]\s*(.*)$' % '|'.join(f'(?P<{k}>{v})' for k, v in CUE_TAGS.items()), re.I)
# Role label: 1-5 words, starts with a letter, mostly capitals OR Title-case followed by colon.
ROLE = re.compile(r"^\[?(?P<role>(?:\d+(?:ST|ND|RD|TH|st|nd|rd|th)\.?\s+)?[A-ZÀ-Þ][A-Za-zÀ-ÿ0-9.'&/\- ]{0,38}?)\]?\s*(?:\((?P<paren>[^)]{0,60})\))?\s*[:;]\s*(?P<text>.*)$")
ROLE_SPACED = re.compile(r"^(?P<role>[A-ZÀ-Þ][A-ZÀ-Þ0-9.'&\- ]{1,30}?)(?:\s*\((?P<paren>[^)]{0,60})\))?\s{3,}(?P<text>\S.*)$")
NOTROLE = re.compile(r'^(DATE|CAST|NOTE|PRODUCTION|SCENE|ACT|PAGE|PROGRAM|WRITER|DIRECTOR|SPONSOR|http|https)$', re.I)
SOUNDROLE = re.compile(r'\b(DOOR|KNOCK|PHONE|TELEPHONE|CROWD|APPLAUSE|LAUGH\w*|SCENE \d+|COMMERCIAL|BACKGROUND|VIBRAPHONE|GONG|BELL|SIREN|GUN\w*|SHOTS?|WIND|RAIN|THUNDER|FOOTSTEPS|CREDITS|AD LIBS?|SIGNOFF|ECHO|FILTER|CLOCK|CAR|TRAIN|PLANE|ENGINE|HORN|WHISTLE)\b')
PAREN = re.compile(r'\(([^)]*)\)')

def clean(raw):
    t = raw.replace('\r', '')
    t = re.sub(r'<br\s*/?>', '\n', t, flags=re.I)
    t = re.sub(r'</p>', '\n\n', t, flags=re.I)
    t = re.sub(r'<[^>]+>', '', t)
    return html.unescape(t)

def blocks(text):
    out = []
    for para in re.split(r'\n\s*\n', text):
        lines = [l.strip() for l in para.split('\n') if l.strip()]
        # a paragraph may hold several "ROLE: text" lines (the GRW files do, after cues)
        cur = None
        for l in lines:
            if cur is not None and not (ROLE.match(l) or ROLE_SPACED.match(l) or CUE.match(l)):
                cur += ' ' + l
            else:
                if cur is not None: out.append(cur)
                cur = l
        if cur is not None: out.append(cur)
    return out

def header(bs):
    h = {'series': bs[0] if bs else None, 'title': bs[1] if len(bs) > 1 else None, 'date': None}
    for b in bs[:4]:
        m = re.match(r'Date:\s*([A-Z][a-z]{2} \d{1,2} \d{4}|[^A-Z]*\d{4}|.{0,25})', b)
        if m: h['date'] = m.group(1).strip()
    return h

def cast_list(bs):
    for i, b in enumerate(bs[:40]):
        if re.match(r'^(CAST|CAST OF CHARACTERS|CHARACTERS|DRAMATIS PERSONAE)\s*:?\s*$', b, re.I):
            names = []
            for c in bs[i+1:i+40]:
                if ROLE.match(c) or CUE.match(c): break
                if len(c) > 60: break
                names.append(c)
            return names
    return None

def in_body(k, seq):
    # a bare capitals line is a role label only after the speech has begun (not in a cast list)
    return any(ROLE.match(x) for x in seq[max(0, k-6):k])

def parse(raw):
    text = clean(raw)
    bs = blocks(text)
    h = header(bs)
    start = 0
    for i, b in enumerate(bs[:6]):
        if b.startswith('Date:'):
            start = i + 1
            # header line may run straight into the first block ("Date: Apr 05 1939ANNCR: ...")
            m = re.match(r'Date:\s*(?:[A-Z][a-z]{2} \d{1,2} \d{4}|Date Unknown|circa \d{4}s|\d{4})(.+)$', b)
            if m: bs.insert(i + 1, m.group(1).strip())
    items = []
    seq = bs[start:]
    merged = []
    k = 0
    while k < len(seq):
        b = seq[k]
        if (re.match(r"^[A-ZÀ-Þ][A-ZÀ-Þ.'\- ]{1,24}$", b) and len(b.split()) <= 3 and k + 1 < len(seq)
                and not ROLE.match(seq[k+1]) and not CUE.match(seq[k+1]) and not SOUNDROLE.search(b)
                and not re.match(r"^[A-ZÀ-Þ][A-ZÀ-Þ.'\- ]{1,24}$", seq[k+1]) and in_body(k, seq)):
            merged.append(b + ': ' + seq[k+1]); k += 2; continue
        merged.append(b); k += 1
    for b in merged:
        m = CUE.match(b)
        if m:
            kind = next(k for k in CUE_TAGS if m.group(k))
            items.append({'t': 'cue', 'kind': kind, 'text': b}); continue
        m = ROLE.match(b) or ROLE_SPACED.match(b)
        if m and not NOTROLE.match(m.group('role').strip()) and len(m.group('role').split()) <= 5:
            role = re.sub(r'\s+', ' ', m.group('role').strip()).upper()
            if SOUNDROLE.search(role):
                items.append({'t': 'cue', 'kind': 'sound', 'text': b}); continue
            txt = m.group('text').strip()
            dirs = PAREN.findall(txt)
            if m.group('paren'): dirs.insert(0, m.group('paren'))
            items.append({'t': 'speech', 'role': role, 'text': txt, 'dir': dirs}); continue
        if re.match(r'^\(.*\)$', b):
            items.append({'t': 'direction', 'text': b}); continue
        items.append({'t': 'other', 'text': b})
    return h, cast_list(bs), items

if __name__ == '__main__':
    for f in sys.argv[1:]:
        h, cast, items = parse(open(f, encoding='utf-8', errors='replace').read())
        c = collections.Counter(i['t'] for i in items)
        roles = collections.Counter(i['role'] for i in items if i['t'] == 'speech')
        print(json.dumps({'file': f, **h, 'cast': cast, 'counts': c, 'roles': roles.most_common(12)}))
