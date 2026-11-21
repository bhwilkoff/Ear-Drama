# DRAFT: Ear Drama privacy policy

> **DRAFT for the owner (R3d, 2026-11-21). Not published. These are proposed
> words; the owner approves, edits, or rejects every one** (AGENTS.md: consent
> and policy words are the owner's). It is written in plain language for
> roughly an 8th-grade reader: short sentences, everyday words, one idea at a
> time. Text in **[square brackets]** is either a choice for the owner or a
> promise the code does not keep yet (marked BUILD). A bracketed BUILD
> sentence must be removed, or the feature built, before this is published.
> Every factual sentence was checked against the code on 2026-11-21
> (`data-inventory.md`).


> **Status, 2026-11-21: approved and published.** The owner approved the wording ("The policy wording looks
> good to me.") and the rulings in Decision 084. Published as `privacy/index.html`, version
> `privacy-2026-11-21`, with every bracket resolved: Learning is Change, 8287 S. Pennsylvania Ct., Littleton,
> CO 80122, ben@learningischange.com; the delete link `eardrama.org/delete-account`; every BUILD now built
> (Delete class, the class end date and idle rule, the class export) or dropped; the 30-day and 72-hour
> numbers; students' names never on the Internet Archive (the code's rule, now confirmed); the 13-and-over
> teacher confirmations and the age question added; the retention section from `retention-policy-draft.md`;
> jsDelivr removed (the runtime is self-hosted); the nonprofit-or-company bracket dropped (not ruled). This
> file stays as the record of the draft.

---

# Privacy

*Last updated: [date]. Version: [policy version id, also used as
`SCHOOL_CONSENT_POLICY`].*

Ear Drama is free. It has no ads. We do not sell, rent, or trade anyone's
information, and we never will. We collect as little as we can, and we tell
you exactly what that is below.

Ear Drama is made by Learning is Change, Inc., a [nonprofit / company: owner],
[address]. Questions: **ben@learningischange.com**.

## The short version

- You can listen without signing in. We don't ask for your name or email.
- What you record stays on your device unless you choose to share it.
- In a class, students don't need accounts or emails. Their teacher types
  their first names.
- A student's recording passes through our server to the teacher's device
  and is not kept on our server.
- Work by a class of students under 13 is never published.
- No ads, no tracking, no selling, no profiles of you.

## What we never do

- We never show ads, and never use anything about you to target ads.
- We never sell or rent personal information.
- We never build a profile of a student except to run their class.
- We never use your recordings to train AI. (A play you choose to publish is
  public under CC0, so others may; the consent says so.)
- We never use analytics, tracking pixels, or advertising cookies.
- We never store a synthetic copy of anyone's voice.

## Listening

Listening needs no account. Your app or browser keeps your history, your
queue, the shows you follow, and your playback speed **on your device**. We
never see them unless you sign in.

The audio plays straight from the Internet Archive, which sees the request
(including your internet address), as any website does.

## Recording on your own device

The app asks to use the microphone only when you press Start recording. Your
takes and finished plays are saved on your device. They leave it only if you
share, export, or publish them yourself.

## Signing in (optional)

You can sign in with Apple or Google. They send us an account number. We do
not keep your name or email address. While you are signed in, we copy your
history, queue, and followed shows to our server so your other devices can
use them.

You can delete your account at any time in the app or at
[eardrama.org/delete-account]. That deletes your account, sessions, history,
queue, follows, and classes from our server right away. A play you made with
others passes to the person who joined it first, with their takes; one no one
else is in is deleted. Two things stay, without your name: lines of a play that was already published
stay on the Internet Archive (your name is taken off the credits), and a
report someone made about you keeps its record with your account removed.

## Making plays with other people

If you make a play with others (by invite link):

- We keep the production: the script, who plays which part, and the name you
  chose to show (it can be a nickname).
- Each recording ("take") passes through our server to the director's device.
  Our server does not keep the sound. It keeps details about the take, like
  which line it is and how long it is.
- We keep a record that you agreed to publish, if you did, and which version
  of the words you agreed to.
- If you report someone or block someone, we keep that report or block.

## Reading together in a room

A read room shares a place in a script among devices. It needs no account. If
you type a name to join, other people in the room see it. A room and
everything in it is deleted 6 hours after it is last used.

Listen Together rooms work the same way, with no names at all.

## Classes: for teachers and students

A teacher makes a class and types each student's name (a first name, a
nickname, or something like "Group 3"). A student joins with the class code
and taps their name. **Students do not make accounts and do not give an email,
a birth date, or a photo.**

What our server keeps for a class:

- the class name and code, and whether it is a class of students under 13;
- the names the teacher typed;
- who reads which part;
- details about each take (not the sound);
- the teacher's Approve or Again marks, and any typed notes the teacher
  writes to a student;
- for a class under 13, a record that the teacher confirmed the school's
  permission.

A student's take goes **through** our server to the teacher's device and is
deleted from our server the moment it arrives. If the teacher's app is not
open, the take waits on the student's device until it is.

The recordings themselves live on the teacher's device. The teacher decides
what happens to them.

**How long:** a class stays until the teacher deletes it [BUILD: today a
class is deleted only when the teacher deletes their account] [or until its
end date: owner, BUILD]. Deleting a class deletes everything above from our
server.

Students and the teacher are the only people who can see a class.

## Children under 13

We don't knowingly let children under 13 sign in or share recordings on their
own. A child under 13 can use Ear Drama to listen, and to record on their own
device.

A child under 13 can record and send takes in a class only after their
teacher confirms that the school or district has approved Ear Drama for that
class, as the federal children's privacy law (COPPA) allows a school to do for
school use.
The school can only give that permission for learning at school. So:

- we use a student's information only to run their class;
- we never publish an under-13 class's work;
- a parent can ask the school, or us, to see or delete their child's
  information (see "Your choices").

If we learn we have a child's information without that permission, we delete
it.

## Teens 13 and over and adults: publishing

Publishing puts a play on the Internet Archive, in public, forever, under
CC0 (anyone may reuse it for any purpose). Before anything is published, each
performer agrees in the app, using these words: [the consent text from `GET
/consent`, version `cc0-2026-10-29`].

For a class of students 13 and over, the teacher publishes the finished play
under the teacher's name. **Students' names are not put on the Internet
Archive** [owner: confirm this as the rule; it is what the code does today].

## Who else receives requests

These companies help run Ear Drama. Each one gets only what it needs:

| Company | What they get | Why |
|---|---|---|
| Cloudflare | Requests to our server, including your internet address | Runs our server and database |
| GitHub | Requests for the website and catalog files | Hosts the website |
| Internet Archive | Requests for audio; plays that people choose to publish | Holds the recordings |
| Wikimedia Commons, Library of Congress, Smithsonian | Requests for pictures | Holds the pictures |
| jsDelivr | One file request on the web when a stand-in voice is first used | Hosts that file |
| Apple, Google | Only if you choose to sign in with them | Sign-in |

None of them gets a student's name, a class, or a student's recording from us.

Our server counts requests from each internet address for one minute to stop
abuse. We don't store the address.

## How long we keep things

[Insert the table from `retention-policy-draft.md` §2 to §5, as approved.]

## Your choices and rights

- **See or download your data.** In Library, choose Export my data. [Owner:
  for a class, BUILD a teacher export of the class's data.]
- **Delete.** Delete your account in the app. A teacher can remove a
  student's name, or delete a class [BUILD].
- **Parents and students.** A parent (or a student 18 or over) can ask to see,
  fix, or delete a student's information. The quickest way is to ask the
  teacher, who can do it in the app. You can also write to us; we will check
  with the school and answer within [30] days.
- **Schools.** A school can ask us to delete a class's information at any
  time, and can sign a data privacy agreement with us. See [For schools].

## Keeping information safe

We keep very little, which is the best protection. Connections are encrypted.
Keys and tokens are stored only in scrambled (hashed) form. Only the owner
can reach the database. We follow a written security program and review it
every year.

If someone gets into information they should not, we will tell affected
schools within [72 hours] of confirming it, and post a notice in the app and
on this page (we have no email addresses to write to).

## Take-down requests

If you send a take-down request, we keep your name and contact details to
answer it. We never publish them. They are erased 3 years after the request
closes.

## Changes to this policy

If we change this policy, we change the date and version at the top. If a
change would let us use student information in a new way, we ask schools
first and do not apply it to information we already have.

## Contact

Privacy questions, parent requests, and school requests:
**ben@learningischange.com** [owner: or a dedicated privacy address].
Learning is Change, Inc., [postal address].
