/**
 * The web app's one account config (Decision 063, docs/WORKER.md "Needs Ben").
 * None of these is a secret: a client id names the app and is public by design.
 *
 * OWNER: replace each REPLACE_WITH value once the Worker is deployed and the
 * providers are set up. While any value a provider needs is a placeholder,
 * that provider's sign-in shows as not available, with no error.
 */
const CONFIG = Object.freeze({
  // The deployed Worker, e.g. https://api.eardrama.org (no trailing slash). A page served from this machine may name a
  // local `wrangler dev` instead with `?worker=http://localhost:PORT` (tools/class_bench.py); a deployed page never can.
  worker: (() => {
    const deployed = 'https://eardrama-api.benwilkoff.workers.dev';
    if (typeof location === 'undefined' || !/^(localhost|127\.0\.0\.1)$/.test(location.hostname)) return deployed;
    const w = new URLSearchParams(location.search).get('worker') || '';
    return /^http:\/\/(localhost|127\.0\.0\.1):\d+$/.test(w) ? w : deployed;
  })(),
  apple: {
    // The Services ID made for the web (it is also in the Worker's APPLE_AUDIENCES).
    servicesId: 'app.eardrama.signin',
    // A return URL registered on that Services ID. The popup flow never navigates to it.
    redirectURI: 'https://eardrama.org/',
  },
  // The sound pack's manifest (B32 §5.2), e.g. https://archive.org/download/eardrama-sounds-1/sounds.json. Null until
  // the owner rules on its archive.org item: the board then offers own sounds and performed cues only.
  sounds: { manifest: null },
  google: {
    // The Web OAuth client id (it is also in the Worker's GOOGLE_AUDIENCES).
    clientId: '1083349339355-hmed22o33qemdc3dfhbqhkt0vho782ak.apps.googleusercontent.com',
  },
});
