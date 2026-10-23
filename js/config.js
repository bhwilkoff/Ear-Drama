/**
 * The web app's one account config (Decision 063, docs/WORKER.md "Needs Ben").
 * None of these is a secret: a client id names the app and is public by design.
 *
 * OWNER: replace each REPLACE_WITH value once the Worker is deployed and the
 * providers are set up. While any value a provider needs is a placeholder,
 * that provider's sign-in shows as not available, with no error.
 */
const CONFIG = Object.freeze({
  // The deployed Worker, e.g. https://api.eardrama.org (no trailing slash).
  worker: 'https://eardrama-api.benwilkoff.workers.dev',
  apple: {
    // The Services ID made for the web (it is also in the Worker's APPLE_AUDIENCES).
    servicesId: 'REPLACE_WITH_APPLE_SERVICES_ID',
    // A return URL registered on that Services ID. The popup flow never navigates to it.
    redirectURI: 'https://eardrama.org/',
  },
  google: {
    // The Web OAuth client id (it is also in the Worker's GOOGLE_AUDIENCES).
    clientId: 'REPLACE_WITH_GOOGLE_WEB_CLIENT_ID',
  },
});
