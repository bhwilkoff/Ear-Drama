"""Turn a parsed play into the proposed canonical script JSON (research prototype)."""
import re, sys, json, hashlib, collections
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import stage_parse as S
SOUND = re.compile(r'\b(knock|sound|door|mob|crowd|noise|bell|shot|thunder|wind|music|bugle|drum|cheer|footsteps|horse|hoof)', re.I)
MIC = re.compile(r'^(in|off|coming in|going off|fading|fade|close|distant|on mike|off mike)\b', re.I)
def h(s): return hashlib.sha1(s.encode()).hexdigest()[:10]
def model(items, script_id, meta):
    roles = collections.OrderedDict(); lines = []; n = 0
    for it in items:
        if it['t'] == 'speech':
            n += 1
            text = it['text']
            dirs = [d.strip() for d in re.findall(r'\[_?([^\]]*?)_?\]', text)]
            spoken = re.sub(r'\s*\[[^\]]*\]\s*', ' ', text).strip()
            cues = [{'kind': 'sound', 'text': d} for d in dirs if SOUND.search(d) and not MIC.match(d)]
            mic = [d for d in dirs if MIC.match(d)]
            other = [d for d in dirs if d not in mic and not (SOUND.search(d) and not MIC.match(d))]
            lid = f"L{n:04d}"
            r = roles.setdefault(it['role'], {'id': 'R' + re.sub(r'[^A-Z0-9]', '', it['role'])[:12], 'name': it['role'], 'lines': 0, 'words': 0, 'gender': None})
            r['lines'] += 1; r['words'] += len(spoken.split())
            parts = []
            for seg in re.split(r'(\[[^\]]*\])', text):
                seg = seg.strip()
                if not seg: continue
                if seg.startswith('['):
                    d = seg.strip('[]_ ').strip('_')
                    k = 'mic' if MIC.match(d) else ('sound' if SOUND.search(d) else 'direction')
                    parts.append({k: d})
                else:
                    parts.append({'say': seg})
            lines.append({'id': lid, 'role': r['id'], 'parts': parts, 'text': spoken, 'rev': 1, 'text_sha1': h(spoken)})
        elif it['t'] in ('direction',):
            n += 1
            lines.append({'id': f"L{n:04d}", 'role': None, 'kind': 'direction', 'text': it['text'], 'rev': 1, 'text_sha1': h(it['text'])})
    return {'id': script_id, **meta, 'roles': list(roles.values()), 'lines': lines}
if __name__ == '__main__':
    f, sid, start, end, out = sys.argv[1:6]
    t = S.body(open(f, encoding='utf-8').read())
    a = t.find(start); b = t.find(end, a)
    items = S.parse(t[a:b if b > 0 else None])
    m = model(items, sid, {})
    json.dump(m, open(out, 'w'), indent=1, ensure_ascii=False)
    c = collections.Counter(i['t'] for i in items)
    print(dict(c)); print([(r['name'], r['lines'], r['words']) for r in m['roles']])
    for i in items:
        if i['t'] == 'other': print('OTHER|', i['text'][:100])
