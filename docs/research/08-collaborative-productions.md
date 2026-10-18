# Collaborative radio plays: one role at a time (research, 2026-10-18)

Owner, 2026-10-18: *"One more thing I'd like you to research is our ability to
allow users of this new app to record their own radio plays (and perhaps
teleplays and plays in general) in a collaborative way ... We would want to
continue to use archive.org as our storage system, but we would need ways to
organize the recordings and connect them to the scripts, etc. Please research
both the feasibility of such an approach and the best way to do this
collaboratively."* Then, clarifying: *"The simulated audio would not be
recorded. It would only be used when someone is recording their parts of the
play against the simulated voices ... Every time a new person would take a new
part of the play and record it until all of the parts are taken."*

This file is the synthesis. The evidence is in three detail files:

| File | Covers |
|---|---|
| `08a-voices-and-mixing.md` | System voices as live stand-ins (and their licences), recording, cueing, bleed checks, assembly, mastering, sound effects and music |
| `08b-scripts.md` | Which scripts are genuinely free, measured; parsing scripts into roles, lines and cues; the script data model; the day-one library |
| `08c-collaboration-and-storage.md` | LibriVox's precedent, archive.org's upload and ownership rules, the relay, the coordination layer, identity, platform policy, phases |

Prototype parsers and a worked example: `radio-catalog/prototypes/scripts/`.

---

## 1. The verdict

**Feasible on phones and Macs, and the owner's relay design is also the one the
licences allow.** Apple's macOS licence (§2.F) permits the system voices "while
running the Apple Software" and forbids "recording, publishing or redistribution
... in a profit, non-profit, public sharing or commercial context" — so voices
used only as live stand-ins while someone records, never stored, are exactly the
permitted use (the iOS licences say nothing either way, and are treated the
same). Only human takes are stored. LibriVox has run this workflow by hand for
years (forum casting, one reader per role, an editor assembling, 5-12 months a
play); the app automates casting, cueing and assembly. Storage on archive.org
works through ONE app account behind the existing Cloudflare Worker, because an
archive.org item is writable only by its uploader. The constraint that shapes the
product is **scripts**: free stage plays are plentiful, free radio scripts are a
small, specific set (~25-55 on day one), and famous network episodes are mostly
still protected.

## 2. How a production works

1. **A script is opened from the vetted library** (§4). Every line has a stable
   id; recordings attach to a line id and its revision.
2. **Someone takes a role.** While they record, every other role is either an
   earlier contributor's accepted take (downloaded) or a system voice synthesized
   live on their device. Recording is cue-and-response: everything else pauses
   while they speak, headphones by default, each stored clip trimmed to their own
   line, and a pre-upload check compares the microphone against the exact cue
   audio played, so no synthetic voice is ever stored (08a §3).
3. **Each take records what its performer heard** (which takes or stand-ins), so a
   director can see who acted opposite an earlier version when a take is replaced.
4. **The next person takes another role** and hears the human takes so far plus
   stand-ins for the rest. Different roles may be recorded at the same time, with
   the largest roles listed first; a director can make it strictly one at a time.
   A claim lapses after 7 days with no take.
5. **A partial play is never mixed into a file.** Each listener's device plays the
   human takes in script order and voices the open roles live (08a §7).
6. **Complete** = every role has an accepted human take in every scene it appears
   in and the director has listened through. The final mix is rendered in CI
   (ffmpeg, -16 LUFS, -1 dBTP) and published as its own archive.org item; takes are
   assembled line by line in script order, so replacing one never desynchronizes
   the rest.

## 3. Storage and coordination

- **archive.org**: two items per production — a working item (one file per take,
  never overwritten, 48 kHz 24-bit mono FLAC plus a JSON record per take, and the
  production record) and a published item (the final mix). Uploads go through the
  Worker with the app's keys; keys inside an app are extractable and ruled out, and
  per-contributor accounts would leave the app unable to remove abusive audio,
  which App Store guideline 1.2 requires (08c §2). Collections need archive.org
  staff and ~50 items, so a tag and custom-field convention comes first.
- **Coordination** (claims, accepted takes, the current running order) on the
  existing Worker + D1: ~6 writes per take, far inside the free tier; the shared
  limit is the Worker's 100,000 requests a day. D1 is a cache and is rebuilt from
  archive.org's item metadata; a rebuild that errors or reads nothing changes
  nothing (ENGINEERING-PROCESS §1).
- **Identity**: no accounts for invite-only productions (device keys and a
  director key, the Watch Together host-key pattern); open casting needs Sign in
  with Apple and Google so blocking sticks, and then in-app account deletion.

## 4. Scripts

| Class | Day one | Notes |
|---|---|---|
| Stage plays (Gutenberg 1,721 English; Standard Ebooks ~115, CC0; LibriVox 640 with role lists on 444) | ~300-400 | A modern TRANSLATION of a free play is not free (245 Gutenberg records name a translator) |
| US-government radio scripts (USDA *Uncle Sam's Forest Rangers*, 562 scripts 1932-44; ~140 other USDA dramas and dialogues) | ~25-55 after author checks | Some USDA library items came from CBS and others |
| Radio scripts registered and never renewed (1947-49 volumes: 3,342 radio registrations, 146 renewed) | few now | The texts are mostly not online |
| Generic Radio Workshop | 22 of 1,371 clearly free | Volunteer transcriptions with added notes: ask GRW before reuse |

"Before 1931" does **not** free a radio script: a broadcast script was
unpublished, so a 1928 work for hire is protected to 2048 (§§302(c), 303). Parsing
is good enough for an editor to finish: 100/100 correct attributions in a hand
check of GRW transcriptions with ~1.5% of speeches needing a fix; *The Importance
of Being Earnest* matched Standard Ebooks' markup on 877 of 879 speeches. Two-column
government typescripts need OCR word coordinates. An editor approves every script
before casting opens; no model writes or rewrites script text (CLAUDE.md).

## 5. Platforms

Record: iPhone, iPad, Mac, Android phones (full); the web with headphones only and
loose cue timing (browsers cannot capture synthesized speech, so there is no bleed
check). Play back only: Apple TV, Google TV, Fire TV, Roku. Without headphones,
echo cancellation works as a fallback and its takes are flagged for a re-take.

## 6. Phases

1. **Pass the phone (local only)**: a family or class records role after role on
   one device. No server, no user-generated-content obligations, no COPPA exposure.
2. **Invite-only shared productions** by link, through the Worker and the app's
   archive.org account; report, block, filter and contact as guideline 1.2 asks.
3. **Open casting** with sign-in, peer review (LibriVox's prooflistening, Common
   Voice's validation queue) and credits pages built from data.

## 7. Why it fits Archive Watch

It is the most active feature the project has considered: people perform, cast,
direct and listen to each other, and the work is a new public-domain recording
added to the archive rather than consumption of one. Credits come from data (who
took which role), and nothing in a production is written by a model.

## 8. Decisions reserved for the owner

From 08a, 08b and 08c (exact wording there). In order of what they unblock:

| # | Question |
|---|---|
| C1 | Contributions dedicated CC0 (LibriVox, Common Voice) or CC BY? The consent screen must say a recording is permanent, public and reusable, including for voice cloning |
| C2 | One app account uploads through the Worker (recommended), or each contributor's own archive.org account? |
| C3 | Under-13s record locally only (recommended: a child's voice in a file is personal information under COPPA)? |
| C4 | Open with stage plays and radio scripts together, or radio only? |
| C5 | May anyone preview a half-voiced play with live stand-ins? |
| C6 | A role nobody takes: leave the play unfinished, or allow a stored openly licensed synthetic voice (Kokoro, Apache-2.0; Piper's LibriTTS-R voices, CC BY 4.0)? |
| C7 | Strict one-role-at-a-time relay by default, or parallel roles with relay order encouraged? Claim expiry of 7 days? |
| C8 | Ask the Generic Radio Workshop before reusing its transcriptions? |
| C9 | Accept "individual author died by 1955" as evidence for an unregistered script? Who may approve a script for casting? |
| C10 | Sponsors' commercials inside free scripts: keep, optional, or drop? Personal Voice: not offered (recommended; Apple forbids public sharing of it)? |
