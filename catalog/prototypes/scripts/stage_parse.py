"""Rule-based stage-play parser for Project Gutenberg plain text (research prototype)."""
import re, sys, json, collections
CAP = r"[A-ZÀ-Þ][A-ZÀ-Þ0-9.'’\- ]{0,40}?"
ROLE_OWN = re.compile(r"^(?P<role>%s)\.?\s*(?P<d>\[[^\]]*\]|\(_[^)]*_\))?\s*$" % CAP)                       # NORA.
ROLE_COLON = re.compile(r"^(?P<role>%s)\s*:\s*(?P<text>.+)$" % CAP)           # SHERIFF: text
ROLE_INLINE = re.compile(r"^(?P<role>%s)\.\s+(?P<text>\S.+)$" % CAP)          # HAMLET. text
DIR = re.compile(r"\[([^\]]*)\]|\(_([^)]*)_\)|_([^_]+)_")
CASTHEAD = re.compile(r"^_?(CAST|PERSONS|CHARACTERS|DRAMATIS PERSONAE|THE PERSONS OF THE PLAY|PERSONS IN THE PLAY)_?\.?\s*$", re.I)
HEADING = re.compile(r"^(ACT|SCENE|CURTAIN|END|THE END|PERSONS|CHARACTERS|DRAMATIS PERSONAE|FIRST ACT|SECOND ACT|THIRD ACT|TRIFLES|PLAYS|CONTENTS|PREFACE)\b", re.I)

def body(raw):
    t = raw.replace('\r', '')
    a = re.search(r'\*\*\* ?START OF TH(?:E|IS) PROJECT GUTENBERG[^\n]*\n', t)
    b = re.search(r'\*\*\* ?END OF TH(?:E|IS) PROJECT GUTENBERG', t)
    return t[a.end() if a else 0: b.start() if b else len(t)]

def parse(text, start_pat=None, end_pat=None, continuation=True):
    pending_dir = None
    if start_pat:
        m = list(re.finditer(start_pat, text, re.M))
        text = text[m[-1].start() if len(m) == 1 else m[1].start():] if m else text
    if end_pat:
        m = re.search(end_pat, text[50:], re.M)
        if m: text = text[:m.start() + 50]
    paras = [p.strip() for p in re.split(r'\n\s*\n', text) if p.strip()]
    items, pending, cast, incast = [], None, [], False
    for p in paras:
        lines = p.split('\n')
        first = lines[0].strip()
        if CASTHEAD.match(first):
            incast = True; cast.extend(l.strip() for l in lines[1:] if l.strip()); continue
        if incast:
            if all(len(l.strip()) < 60 for l in lines) and not any(l.strip().endswith(('.', '?', '!')) and len(l) > 40 for l in lines):
                cast.extend(l.strip() for l in lines if l.strip()); continue
            incast = False
        if HEADING.match(first) and len(lines) <= 2 and first.upper() == first:
            items.append({'t': 'heading', 'text': first}); pending = None; continue
        m = ROLE_OWN.match(first)
        if m and len(m.group('role').split()) <= 4 and m.group('role').upper() == m.group('role'):
            role = m.group('role').strip(' .')
            rest = ' '.join(l.strip() for l in lines[1:]).strip()
            if m.group('d'): rest = (m.group('d') + ' ' + rest).strip() if rest else rest
            if m.group('d') and not rest: pending_dir = m.group('d')
            if rest:
                items.append({'t': 'speech', 'role': role, 'text': rest})
                pending = None
            else:
                pending = role
            continue
        joined = ' '.join(l.strip() for l in lines)
        m = ROLE_COLON.match(joined) or ROLE_INLINE.match(joined)
        if m and len(m.group('role').split()) <= 4 and not HEADING.match(m.group('role')):
            items.append({'t': 'speech', 'role': m.group('role').strip(' .'), 'text': m.group('text')}); pending = None; continue
        if pending:
            items.append({'t': 'speech', 'role': pending, 'text': ((pending_dir + ' ') if pending_dir else '') + joined}); pending = None; pending_dir = None; continue
        if items and items[-1]['t'] == 'speech' and not re.match(r'^[\[(_]', joined) and continuation:
            items[-1]['text'] += '\n' + joined; items[-1]['cont'] = items[-1].get('cont', 0) + 1; continue
        if re.match(r'^[\[(_]', joined):
            items.append({'t': 'direction', 'text': joined}); continue
        items.append({'t': 'other', 'text': joined})
    parse.cast = cast
    for i in items:
        if i['t'] == 'speech':
            i['dir'] = [next(g for g in m.groups() if g) for m in DIR.finditer(i['text'])]
            i['role'] = re.sub(r'\s+', ' ', i['role'].replace('’', "'")).upper()
    return items

if __name__ == '__main__':
    f, sp, ep = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else None), (sys.argv[3] if len(sys.argv) > 3 else None)
    items = parse(body(open(f, encoding='utf-8').read()), sp, ep)
    c = collections.Counter(i['t'] for i in items)
    r = collections.Counter(i['role'] for i in items if i['t'] == 'speech')
    print(json.dumps({'counts': c, 'roles': r.most_common(25)}))
