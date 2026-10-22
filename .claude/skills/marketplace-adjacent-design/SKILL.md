---
name: marketplace-adjacent-design
description: Use when adding ANY user-to-user trading, selling, matching, or classifieds feature to an app — before writing the first table or view. Carries the pure-introduction architecture (match users, deep-link them off-platform, never host the transaction), the never-touch-money hard rule (marketplace-facilitator law avoidance), Apple guideline 1.2 minimum-viable UGC controls (filter / mailto report / bilateral block / published contact), the passive-matching §230 posture, EU DSA geo-blocking, the 12-clause ToS checklist with the 3 trading-specific clauses templates miss, and the documented risk-acceptance table. Triggers on trading, marketplace, P2P, user-to-user selling, buy/sell/trade, escrow, per-trade fee, match alerts, §1.2, UGC controls, "let users trade with each other", classifieds, want list matching.
---

# Marketplace-adjacent design — introduce users, never broker them

Distilled from BOBA Playbook's TRADE-DESIGN.md (ratified 2026-05-05):
a solo-dev collectibles app that added trading-match features under a
hard $0-ongoing-cost constraint, four parallel research passes (Apple
policy, US/EU liability, payments, fraud patterns), and one v1 rewrite
that cut the architecture from "thin in-app messaging" down to **pure
introduction**. This is research-derived design, not legal advice.

## The two failure modes

Any "let users trade/sell to each other" feature is squeezed between:

- **Over-build**: in-app chat, escrow, ID verification, dispute
  staff. Triggers Apple §1.2 per-message moderation obligations,
  marketplace-facilitator status the moment money flows, and ongoing
  operational cost a small team cannot staff. The feature becomes a
  liability engine.
- **Under-build**: surface matches with no controls at all. Apple
  rejects under §1.2 (UGC requires filter/report/block/contact),
  scammers concentrate, and the app's brand becomes "the place to
  get scammed."

**The needle-threading answer is PURE INTRODUCTION**: detect the
match (user A's for-sale list overlaps user B's want list, by
canonical item ID), show each side the other's handle + matched
items, and deep-link them to a messaging platform they already use
(Discord, etc.). The conversation, the payment, and the dispute all
happen where the infrastructure for them already exists. Your app is
the introduction layer, not the transaction layer — the
Reddit-classifieds / Craigslist posture, which is also the legally
simplest UGC position under §230.

## Rule 1 — the platform NEVER touches money. Period.

No escrow. No per-trade fees. No holding funds during shipping. No
platform currency. No "pay through us" buttons. No tip jars routing
through you.

**Why:** the moment funds flow through the app, state
marketplace-facilitator laws trigger (thresholds as low as $100K;
the broadest definitions include *facilitating payment processing or
fulfillment*). At facilitator status you owe: sales-tax collection
and remittance across ~45 jurisdictions, 1099-K reporting to
sellers, FinCEN money-transmitter analysis state by state, and full
payment-network compliance (KYC, AML, chargebacks). A small team
cannot operate any of this. "Never touch money" is the single rule
that keeps you out of the entire zone.

**Subscriptions via the store's IAP are NOT touching money** in this
sense: the user pays Apple/Google, the store pays you. You sell
access to your features, not a cut of users' transactions. A Pro
tier may deliver matches *faster* (push notifications) or raise
list-size caps — but see Rule 4: it must never alter matching
standing.

Kill at proposal stage: any "Pay" button, escrow flow, "we hold the
item price until delivery," or percentage-of-trade monetization.

## Rule 2 — Apple §1.2 minimum-viable UGC controls

Apple requires four mechanisms for any UGC surface. The minimum that
satisfies them without staffing a mod queue:

| Requirement | Minimum-viable implementation |
|---|---|
| Filter objectionable content | **Structural**: listings have a bounded shape (item ID, condition, price, notes ≤ 280 chars). The one free-text field runs a banned-words filter. No free-form chat = most risk designed out, not moderated out. |
| Report mechanism | "Report this user" opens `mailto:` to the published contact with pre-filled subject + context (reporter ID, reported ID, listing). Email-based reporting satisfies §1.2 — published contact info is the requirement, not an in-app queue. |
| Block mechanism | `user_blocks` table, **bilateral**: blocker no longer sees the blocked user's listings/matches and vice versa. Silent — the blocked user is not notified. |
| Published contact info | The support email already in the app/store listing. |

Document the mod SLA you can actually keep (e.g. "reports checked
within 48h") — §1.2 has no quantitative SLA; "timely" is
operationally defined, and over-promising is worse than a modest
documented cadence.

## Rule 3 — identity gate via an existing platform identity

Gate trading on a **verified link to an identity platform the
community already uses** (e.g. Discord OAuth), not on phone
verification:

- It IS the messaging path — without a handle to deep-link to, pure
  introduction has no destination.
- It's the $0 fraud signal: account age, server/community history,
  and existing reputation make a linked long-lived account a far
  weaker scam vector than an email-only signup. This is the
  phone-verify equivalent at zero cost and less privacy invasion.
- Email fallback is spammable/harassment-prone; phone is invasive.

UI: the trading toggle is disabled until the link completes
("Link your X account to enable trading").

## Rule 4 — passive matching only (the §230 posture)

Matching = **overlap of explicit user inputs by canonical item ID**.
Never algorithmically recommend traders to each other: *Anderson v.
TikTok* (3d Cir. 2024) weakened §230 protection for first-party
algorithmic recommendation; passive overlap of user-declared lists
stays firmly in third-party-content territory.

- Ranking by recency or completed-trade count: fine.
- "We think these two would be a good match": not fine.
- **No paid placement, ever.** Pro may see matches sooner (push) but
  free and paid users occupy identical positions in the matching
  graph. Paid trader promotion is both an algorithmic-recommendation
  risk and a store-review red flag (pay-to-win in a
  marketplace-adjacent app).

## Rule 5 — geo-block the EU trading endpoints

EU DSA Art. 30 (trader traceability) requires collecting name,
address, ID, and bank details before allowing listings — even with
small-enterprise exemptions, baseline notice-and-action obligations
apply. Geo-blocking only the trading endpoints (match list, block,
report) at the CDN/edge is the $0 way to stay out of scope; the rest
of the app keeps working for EU users ("Trading is not yet available
in your region").

## Rule 6 — the ToS checklist (free template + 3 manual clauses)

A reputable free ToS template (Termly, Iubenda, Cooley Go) covers
~9 of the 12 needed clauses: warranty disclaimer, liability cap, UGC
responsibility shift, indemnification, arbitration + class waiver,
report/appeal mechanism, termination, force majeure, governing law.
**The three trading-specific clauses every template misses** — add
them by hand:

1. **Not-a-party**: "The app acts solely as an introduction service
   between users. We are not a party to any sale, trade, or
   exchange. We do not collect payment, hold funds, escrow goods,
   ship items, verify identity, or guarantee any outcome. All
   transactions complete entirely between users via third-party
   services."
2. **Tax responsibility**: "You are responsible for all applicable
   taxes on your transactions. We do not collect, remit, or report
   any tax on your behalf, and do not issue Form 1099-K or any
   other tax document for transactions between users."
3. **Third-party services**: "We are not affiliated with [PayPal /
   Venmo / Discord / …] and do not guarantee their availability or
   terms. We strongly recommend PayPal Goods & Services for paid
   transactions; Friends & Family payments offer no protection and
   are prohibited by PayPal's own policy for purchases of goods."

Update the privacy policy to enumerate the new tables
(matches, blocks, linked identity, optional payment handles) and
where reports go.

## Rule 7 — write the risk-acceptance table

When the owner declines counsel/insurance (a legitimate call for a
small project), **document it as a table** — risk · mitigations
present · mitigations absent · net exposure — and record that the
owner judged it acceptable. Purpose: future sessions honor the
judgment instead of relitigating it, and the owner sees exactly
what they're carrying (e.g. "a demand letter that requires a
response could cost $1–5K out of pocket even in a winning
defense"). An LLC with clean formalities + the not-a-party ToS +
never-touch-money is the load-bearing trio; the table names what
they don't cover.

## What v1 explicitly skips (and why)

| Skipped | Why |
|---|---|
| In-app messaging / threads / DMs | Triggers per-message §1.2 moderation + creates an archive that becomes dispute evidence you can't responsibly handle. The deep-link IS the messaging story. |
| Address exchange flow | Happens off-platform; hosting it re-creates the archive problem. |
| Dispute resolution | PayPal G&S and the messaging platform are equipped for it; you are not. Direct users there. |
| KYC / identity verification services | No payment flow → no trigger; per-check cost; the linked-identity gate covers the fraud-signal role at $0. |
| Photo/possession verification | Nice v2; users can verify with each other over the deep link first. |
| Algorithmic trader recommendations | Rule 4 — never, not just v1. |

The trade-offs accepted: less engagement (users leave the app to
talk), less data (no conversion telemetry) — both fine for v1, and
the price of a liability footprint a small team can actually carry.

## When trading reaches the roadmap

Author a binding `docs/TRADE-DESIGN.md` from
`docs/templates/TRADE-DESIGN-template.md` BEFORE Phase 1 code. Its
Phase 0 (ToS + privacy updated and read by the owner) gates every
later phase — don't ship match detection ahead of the ToS that
disclaims it. Once authored, the doc is binding per
`binding-design-doc-discipline`: proposals that reach into expensive
territory (chat, escrow, fees) point at the rule that forbids them.
