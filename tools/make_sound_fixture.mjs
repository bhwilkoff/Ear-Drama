// The sound pack fixture for tests and frames only (B32 §5.2; WEB-DESIGN §4.16 item 14a): a manifest in the
// pack's format over a few synthetic tones, so js/sound.test.js and tools/web_fit_sound.py read a pack without
// the real one (its hosting waits on the owner). Never served by the app: a page names it only on this machine,
// with ?sounds=tools/fixtures/sounds/sounds.json. Three planted rows must be refused by the rights gate: a CC-BY
// file, a row with no evidence, and a row from a refused host.   node tools/make_sound_fixture.mjs
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), 'fixtures', 'sounds');
const RATE = 8000;

function wav(seconds, f, kind) {
  const n = Math.round(seconds * RATE);
  const b = Buffer.alloc(44 + n * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + n * 2, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(RATE, 24);
  b.writeUInt32LE(RATE * 2, 28); b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(n * 2, 40);
  let seed = 7;
  for (let i = 0; i < n; i++) {
    const t = i / RATE;
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    const noise = (seed / 0x7fffffff - 0.5);
    const env = kind === 'hit' ? Math.exp(-t * 12) : Math.min(1, t * 8, (seconds - t) * 8);
    const v = kind === 'noise' ? noise * 0.5 * env : Math.sin(2 * Math.PI * f * t) * 0.4 * env;
    b.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2);
  }
  return b;
}

const lic = (id = 'CC0-1.0') => ({ id, url: 'https://creativecommons.org/publicdomain/zero/1.0/', evidence: 'https://example.org/fixture/license', checked: '2026-11-26' });
const src = { name: 'Fixture', page: 'https://example.org/fixture', file: null, maker: null };
const rows = [
  ['thunder-close', 'Thunder, close', 'weather', ['thunder', 'storm'], 'effect', false, 1.2, 60, 'noise'],
  ['thunder-distant', 'Thunder, distant', 'weather', ['thunder', 'storm'], 'effect', false, 1.4, 50, 'noise'],
  ['rain-steady', 'Rain, steady', 'weather', ['rain', 'storm', 'water'], 'ambience', true, 2.0, 0, 'noise'],
  ['knock-wood', 'Knock on wood', 'doors', ['knock', 'door', 'wood'], 'effect', false, 0.6, 180, 'hit'],
  ['door-creak', 'Door creak', 'doors', ['door', 'creak'], 'effect', false, 0.9, 340, 'tone'],
  ['calm-prelude', 'Prelude, calm', 'music', ['calm', 'piano'], 'music', true, 2.5, 262, 'tone'],
];
mkdirSync(OUT, { recursive: true });
const cats = { weather: 'Weather', doors: 'Doors', music: 'Music' };
const bytes = { weather: 0, doors: 0, music: 0 };
const cues = rows.map(([id, title, category, tags, kind, loop, secs, f, shape]) => {
  const data = wav(secs, f, shape);
  mkdirSync(join(OUT, category), { recursive: true });
  writeFileSync(join(OUT, category, `${id}.wav`), data);
  bytes[category] += data.length;
  return { id, title, category, tags, kind, ms: Math.round(secs * 1000), loop, file: `${category}/${id}.wav`, bytes: data.length,
           sha256: createHash('sha256').update(data).digest('hex'), lufs: -20, peak: 0.4, source: src, license: lic() };
});
const planted = (id, patch) => ({ ...cues[0], id, title: `Planted ${id}`, ...patch });
const manifest = {
  format: 1, pack: 'eardrama-sounds-fixture', built: '2026-11-26',
  categories: Object.entries(cats).map(([id, title]) => ({ id, title, bytes: bytes[id] })),
  cues: [
    ...cues,
    planted('planted-cc-by', { license: { ...lic('CC-BY-4.0') } }),
    planted('planted-no-evidence', { license: { ...lic(), evidence: '' } }),
    planted('planted-refused-host', { source: { ...src, page: 'https://freesound.org/people/x/sounds/1/' } }),
  ],
};
writeFileSync(join(OUT, 'sounds.json'), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`wrote ${cues.length} cues and 3 planted rows to ${OUT}`);
