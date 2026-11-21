# DRAFT: Ear Drama data retention policy

**DRAFT (R3d, 2026-11-21). The numbers and the words are the owner's to set.**
Every number below marked *(owner)* is a proposal. Rows marked *(build)*
describe a rule the code does not yet carry; until it does, the published
policy must say what the code does (`data-inventory.md`).

The amended COPPA Rule requires an operator to set out, in writing, the
purposes for which it collects children's personal information, the business
need for keeping it, and a timeframe for deleting it, to keep it no longer
than reasonably necessary, never indefinitely, and to post this policy in its
online notice (16 CFR 312.10 as amended; see R3d §2.1 for the sources). This
draft is written to be posted as part of the privacy policy.

## 1. The rule we keep

We keep a piece of personal information only while it does the job it was
collected for, then delete it. Student information is kept for the school's
purposes only, and the school (through the teacher) decides when it goes.
Nothing is kept "in case."

## 2. Student information (classes)

| Information | Purpose | Kept until | Then |
|---|---|---|---|
| Seat names the teacher typed | Let a student pick their name | The teacher removes the seat or deletes the class; at the latest, the class's end date *(build)* | Deleted from the server |
| A seat's device key (stored as a hash) | One device holds one seat | The teacher releases the seat, or the class ends | Deleted |
| Take audio | Get a student's line to the teacher | It reaches the teacher's device (seconds) | Never written to our server; deleted from memory on arrival |
| Take details (line, length, loudness; no audio) | Review and progress | The class is deleted | Deleted |
| Teacher's notes to a student, and Approve/Again | Feedback | The class is deleted | Deleted |
| Casting (who reads which part) | The class production | The class is deleted | Deleted |
| School authorization record (under-13 classes) | Proof the school authorized collection | The class is deleted, plus 1 year *(owner)* | Deleted. (Kept a little longer so we can show a school or the FTC that authorization existed. Holds no student data.) |
| Recordings on the teacher's device | The class's work | The teacher deletes them, or deletes the class *(build: the app offers to delete the class's takes on that device)* | Deleted from that device |
| A student's takes on a shared school device | Sent when the teacher's app is open | Sent and confirmed delivered, then removed from the shared device *(build)* | Deleted from that device |

**Class end date.** *(owner)* Proposed: every class has an end date, set by
default to **July 31** after the class is made (the end of a US school year),
which the teacher can change or extend. Thirty days before it, the teacher's
app says so and offers Export. On the end date, the class, its seats,
productions, casting, take details, and notes are deleted from the server. A
class with no activity for **12 months** is deleted the same way, after the
same notice. *(build: the class table has no end date or activity column
today.)*

**Published recordings.** A 13-and-over class recording the teacher publishes
to the Internet Archive is public and permanent there (the consent says so).
It is outside this retention schedule because it is no longer held by us; a
performer or teacher can remove a line from the item (P12), and copies others
made cannot be recalled. Under-13 class work is never published.

## 3. Account information (adults and teens 13 and over)

| Information | Purpose | Kept until |
|---|---|---|
| Account number from Apple or Google, our account id | Sign-in | The person deletes the account |
| Sign-in sessions | Stay signed in | 60 days, or sign-out |
| History, queue, follows | Sync | The person removes them or deletes the account |
| Productions, takes' details, consents, member names | Shared plays | The person leaves, deletes the account, or the director deletes the production *(build: no delete-production route today)* |
| Inactive accounts | none | *(owner)* Proposed: an account not used for **3 years** is deleted (no notice is possible: we hold no email) |

## 4. Safety and legal records

| Information | Purpose | Kept until |
|---|---|---|
| Reports and blocks | Safety (App Store guideline 1.2) | Blocks: until either account goes. Reports: closed reports lose their note and reporter **1 year** after closing *(owner, build)*; the record that a take was removed stays without names |
| Take-down requests | Respond to rights holders | Requester details blanked 3 years after the case closes (built) |
| IP addresses | Rate limits | Not stored by us; counted for one minute |

## 5. Backups

D1 keeps point-in-time recovery (Cloudflare Time Travel) for 7 days on the
Workers Free plan and 30 days on Workers Paid
(<https://developers.cloudflare.com/d1/reference/time-travel/>). A deleted row
can live in that window and is not restored except to repair our own
failure. *(owner: confirm the plan in use; the policy states its number.)*

## 6. When a school asks

A teacher (or the school, through the privacy contact) can ask us to delete
any class's data at any time; we do it within **30 days** *(owner; most
district agreements ask 30 to 60 days)* and confirm in writing. Deleting the
class in the app does it at once.

## 7. Review

The owner reviews this schedule once a year, and whenever a new kind of
information is collected; the date of the last review is shown at the top.
