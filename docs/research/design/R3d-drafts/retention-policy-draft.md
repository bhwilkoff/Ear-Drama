# DRAFT: Ear Drama data retention policy

**DRAFT record (R3d, 2026-11-21; revised the same day to the owner's rulings and the code of Decision
084).** The owner approved the policy wording on 2026-11-21 ("The policy wording looks good to me."); the
published form is the "How long we keep things" section of `privacy/index.html`. This file is the longer
record: purposes and business need, as 16 CFR 312.10 asks. Every row says what the code does
(`worker/src/plays-retention.js`, `worker/test/retention.test.js`).

The amended COPPA Rule requires an operator to set out, in writing, the purposes for which it collects
children's personal information, the business need for keeping it, and a timeframe for deleting it, to keep
it no longer than reasonably necessary, never indefinitely, and to post this policy in its online notice
(16 CFR 312.10 and 312.4(d) as amended; R3d §2.1).

## 1. The rule we keep

We keep a piece of personal information only while it does the job it was collected for, then delete it.
Student information is kept for the school's purposes only, and the school (through the teacher) decides
when it goes. Nothing is kept "in case." The owner's ruling, 2026-11-21: *"I don't mind deleting the info
about who recorded what, but we need to be able to keep the recorded Ear Dramas in our database. That should
work, given that identifiable information is not accessible via the recordings."*

## 2. Student information (classes)

| Information | Purpose | Kept until | Then |
|---|---|---|---|
| Seat names the teacher typed | Let a student pick their name | The teacher removes the seat or deletes the class; the class's end date; 12 months idle after a 30-day notice; a school's request | Deleted from the server |
| A seat's device key (stored as a hash) | One device holds one seat | The teacher releases the seat, another device moves in, or the class is deleted | Deleted |
| Take audio | Get a student's line to the teacher | It reaches the teacher's device (seconds) | Never written to our server; held in memory only while it moves |
| Take details (line, length, loudness; no audio) and the link from a take to its seat | Review and progress | The class is deleted | Deleted; on a published production only the seat link goes and the take's fields stay (they name no one) |
| Teacher's notes to a student, and Approve/Again | Feedback | The class is deleted | Deleted |
| Casting (who reads which part) | The class production | The class is deleted | Deleted |
| School authorization record and its reference (under-13 classes) | Proof the school or district authorized collection | The class is deleted | Deleted with the class (R3d proposed keeping it a year longer; the ruling's schedule does not, so the code does not) |
| Recordings on the teacher's device | The class's work | The teacher deletes them | Deleted from that device |
| A student's takes on the device that recorded them | Sent when the teacher's app is open | They are deleted on that device | (Shared-device clearing, R3d D5, is not built) |
| A published 13-and-over class recording | The ear drama | Kept: on the Internet Archive and in the finished listing, under the teacher's name, with no student's name | A performer or the teacher removes a line (P12) |

**Class end date.** Every class has an end date, set by default to the July 31 that closes the US school
year (August to July) it was made in. The teacher can change or extend it, up to 400 days ahead. The class
may go from noon UTC the day after, once that day has ended in every US time zone. The date is on the class
page from the day the class is made.

**Idle classes.** A class with no use for 12 months is deleted, after a notice: at 11 months the teacher's
class list shows "Deleted {date} unless opened"; any use clears it. Use is the teacher opening the class,
any activity on its productions, or a seat being claimed.

## 3. Account information (adults and teens 13 and over)

| Information | Purpose | Kept until |
|---|---|---|
| Account number from Apple or Google, our account id | Sign-in | The person deletes the account |
| Sign-in sessions | Stay signed in | 60 days, or sign-out |
| History, queue, follows | Sync | The person removes them or deletes the account |
| Productions, takes' details, consents, member names | Shared plays | The person leaves or deletes the account, or the director deletes the production (before it is submitted) |
| Inactive accounts | none | Not signed into for 3 years: deleted as if the owner had, 30 days after a notice any sign-in cancels. We hold no email, so the published policy is the notice |
| The age question's answer | Keep under-13 sharing off | Only "under 13 or not", on the device; never sent |

## 4. Safety and legal records

| Information | Purpose | Kept until |
|---|---|---|
| Reports and blocks | Safety (App Store guideline 1.2) | Until the account that made them is deleted; a report about someone loses their account when it is deleted. (R3d D7, notes fading after a year, is not built) |
| Take-down requests | Respond to rights holders | Requester details blanked 3 years after the case closes |
| IP addresses | Rate limits | Not stored by us; counted for one minute |

## 5. Backups

D1 keeps point-in-time recovery (Cloudflare Time Travel) for 7 days on the Workers Free plan and 30 days on
Workers Paid (<https://developers.cloudflare.com/d1/reference/time-travel/>). The policy says "up to 30
days", true on either plan. A deleted row is never restored except to repair our own failure.

## 6. When a school asks

A teacher (or the school, through the privacy contact) can ask us to delete any class's data at any time; we
do it within 30 days and confirm in writing. Deleting the class in the app does it at once. The owner's route
is `docs/WORKER.md` "A school asks".

## 7. Review

The owner reviews this schedule once a year, and whenever a new kind of information is collected.
