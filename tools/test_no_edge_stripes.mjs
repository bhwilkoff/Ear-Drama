// Direction D: no stripe on a card's edge (WEB-DESIGN 6.4b Color). A card takes its genre's board;
// the genre hue stays on marks. This reads the shipped stylesheet. Negative control: put
// `border-left: 8px solid var(--genre-accent)` back in `.type-card` and this fails.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const css = readFileSync(join(dirname(fileURLToPath(import.meta.url)), '..', 'css', 'styles.css'), 'utf8');
let failures = 0;
const check = (name, ok) => { if (!ok) failures++; console.log(`${ok ? 'ok' : 'FAIL'}  ${name}`); };

const block = (selector) => {
  const at = css.indexOf(`${selector} {`);
  return at < 0 ? null : css.slice(at, css.indexOf('}', at));
};

const card = block('.type-card');
check('the typographic card exists', card !== null);
check('the typographic card has no edge stripe', card !== null && !/border-(left|right|top|bottom|inline)[a-z-]*\s*:\s*\d+px/.test(card)
  && !/box-shadow\s*:\s*inset[^;]*var\(--genre/.test(card));
check('the typographic card sits on the genre board', card !== null && /background:\s*var\(--genre-board/.test(card));

const sides = [...css.matchAll(/border-(?:left|right)\s*:\s*(\d+)px\s+solid\s+var\(--genre[^)]*\)/g)].filter(m => Number(m[1]) >= 8);
check('no genre-colored side border of 8 px or more anywhere', sides.length === 0);

console.log(failures ? `FAIL: ${failures} failing` : 'ok: 4 checks');
process.exit(failures ? 1 : 0);
