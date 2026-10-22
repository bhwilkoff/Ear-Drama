---
name: content-corpus-derivation
description: Use when the app ships a CORPUS derived from a messy external source — extracting facts, cards, questions, entries, or any structured content from Wikipedia/an API/a dump/scraped text. Carries the precision-over-recall funnel, build-time-not-runtime, stdlib-only-rule-based extraction, overgenerate-then-rank, an oracle source that gates risky derived data, type-bucketed distractors from a rank window, and answer-leak stripping. The corpus is the FILTER, not the fetch. Triggers on corpus, dataset build, fact extraction, content pipeline, "generate questions/cards from", scraping, distractors, data derivation, seed data.
---

# Content-Corpus Derivation

Any app that ships a body of content derived from a messy source (an encyclopedia,
an API, a public dump, scraped pages) faces the same problem: the source is vast
and noisy, and shipping its noise makes the product worse. This is the discipline
that turns a messy source into a high-precision shipped artifact.

## Rule 1 — The corpus is the FILTER, not the fetch. Precision ≫ recall.

The goal is NOT to extract as much as possible; it's to extract only what's *good*.
A smaller, cleaner corpus beats a larger, noisier one every time — one bad entry
(a wrong fact, an unanswerable card, a leaked answer) costs more trust than ten
missing good ones buy. Design every stage to **drop** aggressively.

## Rule 2 — Build-time, not runtime. Derivation can be arbitrarily heavy.

Extraction runs ONCE, offline, in a build step — so it can be as expensive as it
needs to be (multi-pass, cross-referenced, slow). Clients consume only the
published artifact; no client re-derives. This is the producer half of
[[shared-data-plane-contract]] — publish once, every client is a consumer.

## Rule 3 — A cheapest-first reject funnel; every stage has a drop-exit

Order the pipeline so the cheapest checks run first and reject the most:

1. Cheap structural gates (length, language/script, required fields) — drop most.
2. Rule-based extraction (regex/grammar/lookup) on what survives.
3. Quality gates (ambiguity, leak, richness) — drop again.
4. Rank + cap what remains.

Log what each stage dropped and why — silent truncation reads as "we covered
everything" when you didn't.

## Rule 4 — Stdlib-only, rule-based extraction is a feature, not a limitation

Rule-based (regex, grammar, dictionary) extraction is **auditable and
high-precision** — you can read exactly why any entry was produced or rejected, and
tune it. It also mirrors the clients' no-heavy-deps rule. Reach for an LLM/ML pass
only where rules genuinely can't reach, and treat its output as *candidates* that
still pass the same downstream gates.

## Rule 5 — Overgenerate, then rank

Produce more candidates than you'll ship, score them, keep the top. A hard quality
score (fame/notability, richness, distinctiveness) as the ranking key lets you
tighten or loosen the corpus size by moving one threshold instead of rewriting
extraction.

## Rule 6 — An oracle source gates the riskiest derived data

When a derived value could be wrong (a computed relationship, an inferred fact),
verify it against an independent structured **oracle** (a knowledge graph, a
canonical dataset) before shipping it. Derived data that can't be oracle-checked
ships only when the extraction rule is itself high-precision.

## Rule 7 — Distractors come from a rank window, never top-1 or random

If the corpus feeds a multiple-choice / matching feature, wrong options must be
**plausible but wrong**: pull them from the same *type bucket* as the answer
(same category/class), from a **rank window** (not the single nearest — too
confusable; not random — too obviously wrong). Type-bucketed, mid-rank distractors
are what make the choice feel fair.

## Rule 8 — Strip answer leakage

The prompt must not contain its own answer. Redact the answer and its aliases from
the prompt text (leading proper-noun runs, title words, synonyms). An un-stripped
leak is the most common "this entry is broken" bug and is invisible until someone
plays it — gate on it in the build.

## See also

- [[shared-data-plane-contract]] — publish-once, every-client-a-consumer (the producer half)
- [[cross-platform-determinism]] — stable IDs + deterministic selection over the corpus
