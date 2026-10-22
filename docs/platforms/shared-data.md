# Shared data, determinism, and multiplayer, in full

Read this when a second client reads your data, when a value must come
out the same on every platform, or when you build anything networked
between players.

These rules lived in `AGENTS.md` until October 3, 2026, when it was cut
below 24,000 bytes so that Antigravity, which stops reading a rule file
at that size, would read all of it. They moved here word for word, and
`AGENTS.md` links to this page with one line saying when to read it. The
rules that hold on every platform stayed in `AGENTS.md`.

## Shared data plane (if your app has one)

If multiple clients consume the same content/data (a catalog, a
feed, a corpus), build it ONCE as a published data plane and make
every client a consumer. No client re-implements the pipeline,
re-derives flags, or re-hosts the data. Author
`docs/DATA-CONTRACT.md` from
`docs/templates/DATA-CONTRACT-template.md` the moment the second
client exists. The `shared-data-plane-contract` skill carries the
full pattern (publishing, CORS/Range realities for the browser,
ETag refresh, additive evolution, merge-guarded mutations). A data
contract is a test: assert the documented shape over the real published
artifact, because one client's tolerance hides a defect from the others.
Thin clients read projections cut from one gatekeeper index, and every
builder imports the same policy predicates.

**Cross-platform determinism.** If a pipeline can compute the value,
publish the result and let every client read it; mirror an algorithm
only when it must run on device. Any value that must come out identical
on every platform (a "daily" pick, a shared shuffle, a match plan, a
hash key) is produced by ONE algorithm mirrored in each language and
proven by a **golden test that runs the real code on every stack and
diffs**. Never a seeded shuffle (RNGs differ across languages); prefer
an order-independent hash-rank. Watch the Kotlin signed-`Byte` hash
gotcha (`and 0xFF`). See `cross-platform-determinism`.

**Networked multiplayer rides a transport seam.** The wire protocol +
the authoritative arbiter live in `Core/` with NO platform-networking
import, so they compile for every target and unit-test offline; each
transport (Bonjour+TCP, GameKit, a backend WebSocket) is a thin adapter
below one `PeerLink` interface. Local same-room and online are the same
feature with a different adapter. See `cross-platform-multiplayer`.
