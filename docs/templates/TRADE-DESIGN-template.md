# [APP NAME] Trading & Peer-to-Peer Design

<!-- SEED TEMPLATE. Author as docs/TRADE-DESIGN.md once user-to-user
     trading/selling/matching reaches the roadmap, BEFORE Phase 1
     code. Read the `marketplace-adjacent-design` skill first; it
     carries the reasoning behind every rule below. Fill every
     [FILL IN]; delete the guidance comments as you go. -->

> **This document is binding.** Every trading-related feature must
> trace to a rule here. When a proposal reaches into expensive
> territory (in-app messaging, escrow, ongoing operational cost),
> the failure is here, not in the proposal. Fix the document, then
> fix the proposal.
>
> Companion to the per-platform design docs, DECISIONS.md, and
> PARITY.md. This is research-derived design, not legal advice.

---

## 0. Hard constraints (what the design must respect)

<!-- Non-negotiable inputs from the owner. Be honest: the whole doc
     is shaped by these. -->

1. **Ongoing cost budget for this feature:** [FILL IN: e.g. "$0
   beyond existing infra"]
2. **Legal entity:** [FILL IN: LLC exists? formalities maintained?]
3. **Legal counsel:** [FILL IN: retained / one-time consult /
   template + owner judgment (risks documented in §3)]
4. **Liability insurance:** [FILL IN: carried / declined (risks
   documented in §3)]
5. **Monetization paths under consideration:** [FILL IN: e.g.
   "subscription only; per-trade fees off the table (see §2); ads
   off-brand"]
6. **Lightest-possible architecture.** Every feature added to
   trading is a future obligation to maintain. Ship the smallest
   surface that produces real value.

---

## 1. Why this document exists

Two competing failure modes:

- **Over-build:** in-app chat, escrow, ID verification, dispute
  staff → App Store Review Guideline 1.2 per-message moderation burden,
  marketplace-facilitator status, ongoing operational cost. Killed
  by §0.
- **Under-build:** matches with no controls → store rejection under
  Guideline 1.2, scammer concentration, brand damage.

This doc threads the needle: **introduce users to each other, push
the conversation to [FILL IN: messaging platform people already
use], provide the minimum Guideline 1.2 controls + clear ToS disclaimers,
and step entirely out of the transaction.**

---

## 2. Architectural rule: the app never touches money. Period.

No processing, holding, escrowing, or refunding of funds for any
user-to-user transaction. No platform currency. No per-trade fees.
No "support the seller" buttons routing through us.

**Why:** funds flowing through the app trigger state
marketplace-facilitator laws (tax collection/remittance across ~45
jurisdictions, 1099-K reporting, money-transmitter analysis,
KYC/AML). Inoperable at this team size. Store-IAP subscriptions are
NOT touching money: the user pays the store for access to features,
not a cut of transactions.

**How to apply:** any proposal with a "Pay" button, escrow flow, or
fund-holding gets killed at proposal stage.

---

## 3. Risks the owner is explicitly accepting

<!-- The table exists so future sessions honor the judgment instead
     of relitigating it. Fill honestly; include the uncomfortable
     rows. -->

| Risk | Mitigation we have | Mitigation we don't have | Net exposure |
|---|---|---|---|
| Bad-actor lawsuit | [FILL IN: entity shield, ToS clauses, pure-introduction = no facts to be liable for] | [FILL IN: e.g. no insurance, no counsel-reviewed ToS] | [FILL IN] |
| Marketplace-facilitator audit | Never touch money (§2); passive matching (§6) | [FILL IN] | [FILL IN] |
| Store rejection | Guideline 1.2 controls (§6); no IAP misuse | None | [FILL IN] |
| Legal cost spike (demand letter, subpoena) | [FILL IN] | [FILL IN] | [FILL IN] |
| Scammer concentration | Off-platform pivot is the architecture; nothing in-app to scam | No active fraud detection | [FILL IN] |

**Net stance:** [FILL IN: one paragraph recording that the owner
judges these acceptable for this project's scope, dated.]

---

## 4. Architecture: pure introduction

1. **Match detection:** [FILL IN: where it runs]. A match = user
   A's for-sale/for-trade list overlaps user B's want list **by
   canonical item ID** (see the data contract). Written to a
   `trade_matches` table.
2. **Match list view:** per match, item thumbnails, the other
   user's handle + linked-identity handle(s).
3. **"Open [platform]" deep link:** starts the conversation where
   messaging infrastructure already exists.
4. **Block user:** `user_blocks` row; bilateral hide, silent.
5. **Report user:** `mailto:` to [FILL IN: support email] with
   pre-filled subject + context.

**That is the entire v1 surface.** Explicitly skipped (each with the
reason recorded; see the skill's skip table): in-app messaging ·
address exchange · dispute resolution · KYC · photo verification ·
algorithmic trader recommendations (never, not just v1).

**Identity gate:** trading requires a verified [FILL IN: e.g.
Discord] link. It is both the messaging destination and the $0
fraud signal (account age + community history). The toggle is
disabled until the link completes.

---

## 5. Required ToS clauses

Start from a free template ([FILL IN: Termly / Iubenda / Cooley
Go]); add the three trading-specific clauses templates miss:

| # | Clause | Source |
|---|---|---|
| 1 | Warranty disclaimer (AS IS) | template |
| 2 | Limitation of liability (capped) | template |
| 3 | UGC responsibility shift | template |
| 4 | **Not-a-party**: introduction service only; no payment, funds, escrow, shipping, identity verification, or outcome guarantee | **manual** |
| 5 | Indemnification | template |
| 6 | Arbitration + class waiver | template |
| 7 | **Tax responsibility**: users owe their own taxes; no 1099-K issued | **manual** |
| 8 | **Third-party services**: not affiliated; recommend buyer-protected payment (PayPal Goods & Services); Friends & Family prohibited for goods | **manual** |
| 9 | Reporting + appeal mechanism | template |
| 10 | Account termination | template |
| 11 | Force majeure | template |
| 12 | Governing law + venue | template |

Privacy policy: enumerate the new tables (`trade_matches`,
`user_blocks`, linked identity, optional payment handles) and where
reports route.

---

## 6. Store-policy compliance

- **Guideline 1.2 user-generated content controls**: structural filtering (bounded listing
  shape; banned-words on the one free-text field) · mailto-based
  reporting · bilateral block · published contact info. Mod SLA the
  owner can actually keep: [FILL IN: e.g. 48h].
- **Physical-goods exemption (Guideline 3.1.3(e))**: no IAP required for
  trading actions because the app collects no payment for them.
- **No "pay outside the app" affordances in v1.** The only external
  link is the messaging deep link.
- **Section 230 posture**: matching stays passive (overlap of explicit
  user inputs). Ranking by recency/count is fine; "recommended
  traders" is not.
- **EU Digital Services Act**: trading endpoints geo-blocked from EU traffic at the
  edge; the rest of the app keeps working. [FILL IN: mechanism.]

---

## 7. Monetization boundary

- Only [FILL IN: e.g. "a single Pro subscription via store IAP"].
- Pro may deliver matches faster (push) or raise list caps.
- **Pro never alters matching standing. No paid placement.** Free
  and paid users occupy identical positions in the matching graph.

---

## 8. UI / IA recipes

**Match list row** (adapt per platform, per its design doc):

```
[avatar]  @other-username        [n trades · rating]   [⋯ Menu]
          "They have 3 of your wanted items"
          [thumbnail row of matched items]
          [platform]: @handle            [Open (platform)]
```

`⋯ Menu`: Block this user · Report this user (mailto) · Hide this
match. Empty state: [FILL IN: productive next action, e.g. "Add
items to your want list to start matching."]

**Block:** tap → confirm → bilateral hide, silent.
**Report:** opens mailto with pre-filled subject
"Report user: @{username}" + context body.

---

## 9. Ship list

| Phase | Items | Gate |
|---|---|---|
| **0** | ToS + privacy updated (template + §5 manual clauses), read by the owner | **Gates all later phases. Nothing ships before this.** |
| 1 | `trade_matches` + detection · `user_blocks` · Profile trading section (toggle, identity gate) | |
| 2 | Match list view (all platforms, with PARITY.md rows) | |
| 3 | Block + report flows · EU geo-block | |
| 4+ | [FILL IN: subscription tier, push notifications, …] | |

---

## 10. Out of scope (intentionally)

| Feature | Why |
|---|---|
| In-app messaging / chat / DMs | §4 architecture rule |
| Escrow / fund-holding / per-trade fees | §2 hard rule |
| Algorithmic trader recommendations | §6 Section 230 posture: never |
| Dispute resolution | Directed to payment platform's process |
| KYC integration | No payment flow → no trigger |
| EU trading | §6 geo-block |
| [FILL IN: project-specific rejections] | |

Add an entry whenever a trading idea is deliberately rejected, so it
isn't re-proposed next session.
