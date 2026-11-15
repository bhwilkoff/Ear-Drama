# Draft: asking misaki's author where its dictionaries come from

Status: DRAFT, not posted. The owner decides whether and when to post it (Decision 078, Q3 (a)).
Where: a new issue on <https://github.com/hexgrad/misaki/issues>, after checking that no open or
closed issue already asks (search "gold", "silver", "dictionary", "source", "license").
When an answer comes, record it in DECISIONS.md under 078 and in
`docs/research/design/R2-kokoro-feasibility.md` §1.

---

**Title:** Where do `us_gold.json` / `us_silver.json` (and the GB files) come from?

**Body:**

Hi, and thank you for misaki and Kokoro.

We're building a free, ad-free app for listening to and reading old radio and stage plays. We'd like
to use misaki (Apache-2.0) at build time to turn play scripts into phonemes for the Kokoro voices.
We run it with `fallback=None`, so no eSpeak is involved.

The README explains how the lexicons are used, but not where `us_gold.json`, `us_silver.json`,
`gb_gold.json` and `gb_silver.json` come from. Could you add a sentence or two about their sources
(for example, which dictionaries or datasets they started from, and how the silver entries were
made) and confirm that they're covered by the repository's Apache-2.0 license?

That would let projects like ours give proper credit and answer license questions with confidence.
Happy to open a pull request for the README if that's easier, once we know what to say.

Thanks again.
