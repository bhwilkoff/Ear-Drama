---
name: third-party-ip-monetization
description: Use when planning to monetize an app built around IP or content you don't own — a fan app, a companion app, a catalog/collection app for someone else's game, cards, shows, or music — or when choosing between seeking a license, restructuring what's paid, and accepting gray-zone risk. Carries the takedown-asymmetry principle, the verbatim-policy discipline, the three paths (license / monetize-only-your-own-work / status-quo), the FREE-TIER-PAID surface audit, single-SKU launch with numeric triggers, the entitlement architecture, and the pre-committed decision gates. Triggers on monetization, subscription, paywall, fan app, companion app, licensing, IP risk, rights holder, cease and desist risk, pricing tier, entitlements, "can we charge for this".
---

# Third-Party IP Monetization

The decision framework for making money from an app whose subject
matter — the cards, the game, the catalog, the universe — belongs to
someone else. Distilled from a shipped companion app's monetization
review (policy texts retrieved verbatim the same day the framework
was written).

## The asymmetry comes first

**A takedown or cease-and-desist destroys far more value than
12–18 months of subscription revenue creates.** The downside is
discontinuous (the app, the audience, and the sunk engineering all
go to zero at once); the upside is linear (a few dollars per user
per month). When downside is discontinuous and upside is linear,
sequence to eliminate the discontinuity first: **license-then-
monetize, not monetize-then-hope.**

## Ground truth, not vibes

- **Quote the governing policies verbatim, with retrieval dates** —
  the platform's guidelines, the rights-holder's ToS, and any
  published fan-content policy. Paraphrase is where wishful reading
  enters.
- **Classify yourself into a bucket before choosing a model**:
  operating under a *published* fan-content policy / unlicensed
  gray zone / licensed third party. The classification decides
  everything. A typical published fan-content policy permits ads,
  sponsorships, and donations but **explicitly forbids
  subscriptions and any sale for compensation** — which is exactly
  why the well-known apps in those ecosystems are free.
- **The gray-zone survivors are free or ad-supported.** Study who's
  still standing in your niche and how they charge (usually: they
  don't).
- **Disclaimers reduce confusion, not liability.** Enforcement
  precedent includes projects shut down at millions of sessions
  WITH disclaimers in place. Cite the precedent with dates in your
  own doc so the team stops treating a disclaimer as armor.

## The three paths

State each with speed / upside / residual risk, and pick a default.

**Path A — seek a license** (highest upside, slowest).
- Lead with what you've built and what you can offer THEM,
  quantified: a free distribution channel at zero marketing cost,
  tooling that drives their engagement, data they can syndicate —
  and the ingestion/curation work you've already funded that they'd
  otherwise pay a contractor for (estimate it in dollars; it's
  leverage you may not realize you have).
- **Ask for a 30-minute call. Never negotiate by email.**
- Enumerate all realistic outcomes before sending: yes / no /
  "we're building our own" / **no reply (most likely)**. Even a
  non-reply is information.

**Path B — monetize only what YOU built** (fastest; lower upside;
reduces but doesn't eliminate risk). This is the load-bearing
framing and the usual recommendation while A is pending:

> Draw the line at "who built it." The third party's content stays
> in the product and stays **free, forever** — browsing, images,
> metadata, search, filters, reference material. Money changes
> hands only for things you engineered: your recognition pipeline,
> your sync backend (which you pay to run), your integrations and
> data proxies, your analysis features, your export tooling, your
> specialist modes.

This is defensible under nominative fair use *because the value
proposition the user pays for is your engineering* — and it makes a
far cleaner conversation if the rights holder ever calls.

**Path C — status quo, accept the risk** — explicitly not
recommended. The dollars don't justify personal exposure, and
**"pivoting under duress is much worse than pivoting on your own
timeline."**

## The surface audit

Tag every shipped surface **FREE / TIER / PAID with a reason
column** — the reason is what makes the tier menu defensible later.
Rules of thumb:

- **Free tier = generous limits on your own work, never withheld
  content.** N operations/day, a collection-size cap, a
  saved-object cap — while all content, reference, and
  learning/practice surfaces stay unlimited and free.
- **Charging for browsing the third party's content is the
  highest-risk move you can make.** That's a policy conclusion, not
  a product preference.

## Launch shape

- **Ship ONE SKU**: free tier + a single subscription (monthly +
  annual only), platform-managed free trial, disclaimer screen,
  privacy/terms pages, restore-purchases button. One product is far
  easier to price-test.
- **Later SKUs get numeric triggers**, pre-committed: add lifetime
  pricing only if ≥25% of subscribers choose annual (a commitment
  signal); add a specialist add-on only when 30+ active users of
  that mode exist.
- **Anchor price with a competitor benchmark table** (free tier /
  paid tier / notes per comparable product), then state the implied
  floor and ceiling — "$X is the floor for a credible product in
  this category; $2X is the ceiling without multi-vertical
  positioning."
- Enroll in the platform's small-business commission program
  (15% vs 30% under $1M/yr on Apple; Play has an equivalent).

## Entitlement architecture

- Platform payment SDK per store + a third-party entitlement layer
  (receipt validation you do not want to write yourself; price
  testing without app releases; free below a revenue threshold you
  won't cross in year one) + **ONE server-side `user_entitlements`
  table** (user, entitlement, source store, active, expires_at) —
  **written by webhook, read by every client. One source of truth,
  no client-side trust.**
- Cross-platform unlock is allowed (a web purchase unlocks the
  native app via the shared table), but **the native app must not
  contain calls to action steering users to web checkout** — that's
  a store rule. Linking to *manage an existing* subscription is
  fine.

## Guardrails

- **Gate after the user has felt the value — never ambush the
  paywall.**
- **Model each service's free-tier ceiling before offering
  "unlimited"** — identify which backend surface hits its cap first
  under an unlimited plan, and build the graceful-downgrade path
  (billing lapse, refund, chargeback) on day one.
- **Risk table with severities and one mitigation each**, including
  the low-severity rows (cost runaway, chargebacks) — their
  presence is what makes the ranking credible.

## Pre-committed decision gates

Write these down BEFORE launch, so the response is a lookup, not a
panic:

| Trigger | Response |
|---|---|
| Rights holder says stop | Comply within 7 days; pivot to the named fallback architecture (Path B's own-work-only shape) |
| Platform removes the app | Appeal within 14 days with documentation already prepared |
| Conversion < 0.5% at 90 days post-launch | Reprice or reposition — **the product-market-fit signal is the conversion rate, not the absolute count** |
| Rights holder responds positively | Re-frame the whole plan toward Path A |

## The human-only checklist

Items an agent cannot do for the owner: send the partnership email;
buy a one-hour consult with specialist IP counsel (~$300–$600,
asking specifically "what's my risk profile, and what disclaimer +
pivot reduces it?"); have a lawyer read the ToS; enroll in the
commission program.

## Anti-patterns

- Monetizing first and researching the fan-content policy after.
- Paraphrased policy summaries with no retrieval date.
- A paywall in front of the third party's content because "our
  curation added value."
- Client-side entitlement checks as the source of truth.
- Shipping the full SKU menu (lifetime, add-ons, bundles) before a
  single conversion datapoint exists.
- Treating a disclaimer as a license.
