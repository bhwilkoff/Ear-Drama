# Archive Watch gap audit (2026-10-22)

Ben asked for this before Ear Drama, an audio-drama app built on
archive.org for the same platforms, is copied from the template: *"I
want to make sure that we have made sure that all of the lessons we have
learned from this repository is represented in our Universal App
Template."*

The 2026-09-30 audit covered Archive Watch (AW) through Decision 158.
This one covers what came after it, plus the recommendations from that
audit that never landed.

## Method

- Diffed every global and AW project skill against the template's copy.
  The template's copies were newer or deliberately generalized in every
  case; two were missing (`social-video-teaser-craft`, now vendored, and
  `macos-creation-studio-engine`, still a deliberate exclusion).
- Read AW Decisions 159 to 168, the AW memories written since
  2026-09-29, and the Ear Drama research's reuse map
  (`docs/research/radio/06-archive-watch-reuse.md` on AW's
  `claude/radio-drama-research-lpvgea` branch; it moves with Ear Drama).
- A research agent read the diffs of fifteen AW docs and the non-catalog
  commits since 2026-09-30, and checked each lesson against this
  template with `git grep`.
- Checked the 09-30 audit's §6 "new homes" against the tree: its
  `evidence-gated-catalog-curation` and `live-broadcast-studio` skills had
  never been written.

## What landed

**New skills**: `evidence-gated-catalog-curation`, `internet-archive-source`,
`live-capture-and-broadcast`, `social-video-teaser-craft` (vendored).

**Stale rules corrected**:
- Versioning said a store release bumps MINOR. AW's owner corrected that
  on 2026-09-30: MINOR only when a release carries something new.
  Fixed in `autonomous-loop-cadence`, `feature-shipping-discipline`, and
  `docs/AUTONOMOUS-LOOPS.md`.
- `store-submission-playbook` argued against Roku's `rsg_version=1.3`,
  which Roku has required since 2026-10-01.
- `docs/DEVICE-HARNESSES.md` said a retail Samsung set cannot be
  inspected. It can, through Chii.
- `docs/templates/TV-DESIGN-template.md` said Back exits at the root on
  every TV. Samsung requires an exit question.

**Code that would have failed the same way AW did**:
- `tv.js`: Samsung's exit question at the root, one Return press
  handled once (keydown and `tizenhwkey`), and media the app paused on
  backgrounding resumes on return. `tools/test_tv_focus.mjs` 18/18.
- `js/compat.js`, `tools/test_tv_compat.py` (with planted controls and a
  missing-polyfill control), the package build gate, and
  `required_version="6.5"` plus the screen-size feature in
  `tv/tizen/config.xml`.
- `pulse.yml` and `play-release.yml` retried pushes with
  `pull --rebase || true`, the loop that failed all five attempts in AW.

**Ported tools**: `tv_chii.mjs`, `tv_inspect.mjs`, `tv_press.mjs`,
`tv_walk.mjs`, `asc_asset_library.py`, `asc_stage_assets.py`.

**Lessons added to existing skills and docs**: sub-item ids and merged-id
URLs (`canonical-entity-identity`, `web-platform-patterns`); iPhone Duo
and Wi-Fi-held downloads (`ios-production-gotchas`); Duo screenshots,
creative assets, public Xcode, YouTube API terms
(`store-submission-playbook`); unique Lazy keys, the Cast chooser theme,
crash triage, Play's minSdk 24 (`android-production-gotchas`,
`play-cli-submission`); BrightScript init-order traps and a flaky first
App Behavior Analysis (`roku-brightscript-app`, `store-submission-playbook`);
Tizen player and rendering traps (`smart-tv-platform-expansion`,
`smarttv-web-app`, `docs/store/tizen-submission.md`); CI push races,
durable failure memory, gated ingest, fair queues (`docs/CI-FLEET.md`,
`ci-fleet-engineering`); Play acquisitions and zero-filled tallies
(`store-metrics-pipelines`, `product-pulse-dashboard`); bench etiquette
(`docs/AUTONOMOUS-FLEET-TESTING.md` §7); shelving a platform with
reopening triggers (`multiplatform-expansion-method`).

## Left open, on purpose or for Ben

- **Whether an Xcode Release Candidate counts as "publicly available."**
  AW's memory records the owner choosing "27.0 now, 27.1 at release"; AW's
  scratchpad quotes them saying *"a release candidate is the final
  version."* The playbook says to ask once and write the answer down.
- AW's two archive.org defects found by the Ear Drama research (a
  throttled call read as "nothing found"; CORS on audio storage nodes
  contradicting AW's contract) stay open in AW. The template's
  `internet-archive-source` states both as rules.
- A coverage report should not owe playback for container entities
  (series spines). Minor; not added.
- `live-capture-and-broadcast` carries the generic half of AW's Studio.
  The Studio engine itself stays excluded.
- The Ear Drama-specific rules (take-down model for audio and images, no
  paid license, no review queue for images, synthetic voices as live
  stand-ins only) belong in Ear Drama's own CLAUDE.md, per its research
  doc 10 §5, not in the template.
