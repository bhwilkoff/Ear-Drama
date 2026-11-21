# DRAFT: Ear Drama written information security program (outline)

**DRAFT (R3d, 2026-11-21). The owner adopts, edits, and signs this; names and
numbers marked *(owner)* are proposals.** The amended COPPA Rule requires an
operator to establish, implement, and maintain a written information security
program with safeguards appropriate to its size, complexity, and the
sensitivity of the children's information it holds, and names its elements:
a designated coordinator, an annual risk assessment, safeguards for the risks
found, regular testing and monitoring, and an annual evaluation and update
(16 CFR 312.8(b) as amended; R3d §2.1). New York's Education Law 2-d asks a
vendor's data security and privacy plan to align with the NIST Cybersecurity
Framework (8 NYCRR 121.6; R3d §2.3). This outline follows both, at the size of
a one-person nonprofit project.

## 1. Who is responsible

- **Program coordinator:** *(owner)* the owner of Learning is Change, Inc., or
  a named person. Contact: the privacy address on the policy.
- Anyone (person or AI agent) changing the Worker, its schema, or a client's
  network code follows this program; an AI agent never holds production
  secrets and never answers a parent, school, or regulator.

## 2. What we protect (the inventory)

`data-inventory.md` lists every field. The sensitive set is small by design:
seat names the teacher typed, teachers' notes to students, take details, the
school authorization record, and take audio while in flight. A change that
adds a field holding a person's data updates the inventory in the same
commit; `worker/test/account.test.js` already fails when a person column is
missed by account deletion.

## 3. Annual risk assessment (NIST CSF: Identify)

Once a year *(owner: pick a month, e.g., each July before the school year)*,
and before any feature that collects something new, write down for each
risk: what could happen, how likely, how bad, and what we do. Starting list:

| Risk | Current safeguard | Gap |
|---|---|---|
| Stolen Cloudflare, GitHub, Apple, Google, or archive.org credentials | Owner accounts; secrets as Worker secrets, never in git (AGENTS.md hard rule) | Confirm hardware-key or app-based 2FA on every one *(owner)* |
| A class code guessed, a student joining a class they are not in | Per-address join limits (`SEAT_JOIN_LIMITER`, `READ_JOIN_LIMITER`), 6-character codes | Seat claim shows the class's seat list to anyone with the code; acceptable (first names only) but say so |
| A seat key reused by the next student on a shared device | Keys in memory or per tab only (Decision 082c) | Home-relay keys in Keychain/Keystore: add expiry |
| Take audio kept by mistake | No R2, KV, or D1 audio; a test fails if a route stores audio | Keep the test; review on every relay change |
| Logs holding personal data | Four `console.log` calls; no persisted observability | Confirm Workers Logs is off in the dashboard *(owner)* |
| Over-collection drift | Inventory + review | Add a CI check that new migrations update the inventory |
| A dependency compromised | Few dependencies; no third-party Swift packages | Keep `npm audit` in CI for `worker/` |

## 4. Safeguards (NIST CSF: Protect)

- **Least data:** no email, name, birth date, or photo for any account; seats
  are teacher-typed labels; audio passes through.
- **Encryption in transit:** HTTPS only (Cloudflare, GitHub Pages).
  **At rest:** Cloudflare D1 encrypts stored data at rest *(owner: confirm in
  Cloudflare's documentation and cite it in the policy)*; tokens and keys are
  stored only as SHA-256 hashes; on devices, sign-in is in the Keychain or a
  Keystore-held key.
- **Access:** only the owner can read production D1. No staff, no
  contractors, no support tool that reads student data. *(owner: list anyone
  else with access.)*
- **Separation:** student classes never mix with public listings; an
  under-13 class has no Publish.
- **Deletion that works:** account deletion and (when built) class deletion
  remove every row by name and by foreign key; tested.

## 5. Testing and monitoring (NIST CSF: Detect)

- The Worker's test suite runs on every change (deletion, take pass-through,
  limits).
- Monthly *(owner)*: check Cloudflare security events and rate-limit hits for
  unusual patterns; check that the hourly sweep is running (sessions, rooms,
  invites, take-downs).
- Yearly: a self-assessment against the SDPC NDPA Exhibit F or the NIST CSF
  categories, written into this file.

## 6. Incident response and breach notice (NIST CSF: Respond, Recover)

1. **Contain** within hours: rotate secrets, revoke sessions
   (`sessions.revoked`), disable the affected route.
2. **Assess** what data, whose, how many, and for how long.
3. **Notify:**
   - each affected school or teacher, without unreasonable delay and within
     the shortest deadline that applies *(owner: adopt one number; state
     laws and the NDPA range from 72 hours to 30 days, R3d §2.3)*;
     proposed: **72 hours** from confirming a breach of student data, the
     strictest common term, so one promise satisfies every state;
   - the FTC and state authorities when the law requires it;
   - adults with accounts: we hold no email, so notice is on the website
     and in the apps.
4. **Record** the incident, what was done, and what changes, here.

## 7. Vendors (subprocessors)

Listed in the privacy policy with what each receives: Cloudflare (Worker,
database), GitHub (website, catalog files), Internet Archive (audio, and
published 13-and-over recordings), Wikimedia Commons, Library of Congress,
Smithsonian (images), jsDelivr (one web runtime file), Apple and Google (only
when someone signs in). Before adding one, check its terms protect the data
at least as well as ours and update the list.

## 8. Annual evaluation

Each year the coordinator reads this program, the inventory, the retention
policy, and the year's incidents, updates all three, and records the date.
