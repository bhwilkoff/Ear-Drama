# [APP NAME]: [DEVICE FAMILY] audit ledger

<!-- SEED TEMPLATE. Copy to docs/audits/[device-family]-ledger.md when a
     device campaign will run longer than one session (one ledger per
     device family: tvOS, an iPhone, Android TV, Roku, and so on). The
     shape comes from docs/AUTONOMOUS-FLEET-TESTING.md section 13.
     Fill every [FILL IN] and delete these comments as you go. -->

Archive Watch kept one of these for each device family it shipped to:
tvOS, the iPhone 12, Android TV and Roku. I want every session that
picks up device work to know what was already tried, what is still
broken, and what is waiting on a person, without asking anyone.

The ledger is the work queue.

Read it before planning any device work. Then read the runbook in
`docs/DEVICE-HARNESSES.md` and the docstrings of the tools you are
about to run. Most device problems have been solved once already, and
the fastest fix is the one someone wrote down.

The cost is real: a ledger nobody updates is worse than none, because
it reads as current. So every pass ends with its counts, and every
finding carries a status and a date.

---

## The device

| Field | Value |
|---|---|
| Bench name (`tools/bench.py`) | [FILL IN, e.g. `atv`] |
| Model | [FILL IN] |
| OS, as last verified | [FILL IN] on [YYYY-MM-DD] |
| Role | [FILL IN: test / floor / os-control / owner-watches] |
| Build under test | [FILL IN: version (build)], read back off the device |
| Runner | [FILL IN, e.g. `python3 tools/atv_run.py`] |

<!-- "Read back off the device" means `xcrun devicectl device info apps`
     or `adb shell dumpsys package`, never the version you meant to
     install. A stale build explains symptoms it did not cause. -->

---

## Findings

Every finding has one tier. The tier says who can move it next.

- **T1 needs the device.** Only a run on the real hardware can confirm
  or close it.
- **T2 is a code fix.** The cause is known and the change can land
  without the device. It goes back to T1 for confirmation after.
- **T3 needs the owner.** A decision, an account, a physical action or
  a judgment only the owner can make.

Status is one of: `open`, `fixed (unverified)`, `verified`, `wontfix`.
Fixed and verified are different words on purpose. A fix is verified
only when a device run shows it.

### T1: needs the device

| ID | Finding | Evidence | Next step | Status | Updated |
|---|---|---|---|---|---|
| T1-1 | [FILL IN: what the glass showed] | [FILL IN: `build/qa/...` report path] | [FILL IN] | open | [YYYY-MM-DD] |

### T2: code fix

| ID | Finding | Cause | Change | Status | Updated |
|---|---|---|---|---|---|
| T2-1 | [FILL IN] | [FILL IN: file and line] | [FILL IN: commit] | fixed (unverified) | [YYYY-MM-DD] |

### T3: needs the owner

| ID | What is needed | Why only the owner | Asked on | Status |
|---|---|---|---|---|
| T3-1 | [FILL IN: e.g. clear the lock screen once] | [FILL IN] | [YYYY-MM-DD] | open |

<!-- Passcodes and passwords are never typed by an agent. Waking the
     owner's everyday television, an audible run, and a store review
     outcome are T3 items, never things a run decides on its own. -->

---

## Passes

One section per pass, newest first. A pass is one sweep of the
scenarios against one build.

### Pass [N]: [YYYY-MM-DD], build [version (build)]

| Scenario | Result | Evidence or reason |
|---|---|---|
| [FILL IN: e.g. `home`] | PASS | [report path] |
| [FILL IN] | FAIL | [assertion that failed]; see T1-[n] |
| [FILL IN] | SKIP | [reason: device leased elsewhere, TV off and would not wake, owner-watches without leave] |

<!-- Every SKIP carries its reason in this row. A SKIP is not a pass,
     and a skip with no reason cannot be told apart from a runner that
     never ran. -->

**Counts:** [n] pass, [n] fail, [n] skip.

---

## For the owner's eyes

Things a runner cannot judge, listed for the owner to look at on the
real device. Keep this list separate from the findings: these are
not failures, they are questions only a person looking at the screen
can answer.

- [ ] [FILL IN: e.g. does the hero art read at ten feet on the living room TV?]
- [ ] [FILL IN: e.g. is the focus ring visible against the darkest poster?]

<!-- When the owner answers, move the answer into a finding (with a
     tier) or strike the item with the date and what they said. -->

---

## Totals across passes

| Pass | Date | Build | Pass | Fail | Skip |
|---|---|---|---|---|---|
| [N] | [YYYY-MM-DD] | [build] | [n] | [n] | [n] |

Bring the counts back at the end of every pass.
