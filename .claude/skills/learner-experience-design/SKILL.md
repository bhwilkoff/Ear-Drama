---
name: learner-experience-design
description: Use when designing what a person sees once they are signed in, enrolled, or otherwise "in" (a home, dashboard, account page, header, or role-based view), and whenever an app serves learners and the people who teach them. Covers switching the home for members, ordering by what needs the person now, one page for several roles, empty states that teach, teacher "what needs me" lists, account pages for rare jobs, the signed-in header, moving a feature without breaking old links, and checking it as a real person at phone width. Triggers on dashboard, signed-in home, logged-in experience, member view, my account, student view, teacher view, roles, personalized home, "stop marketing to members".
---

# Learner experience design

People who have joined came to do something: learn, teach, build, answer.
Once they are in, every screen is theirs, not the product's. This skill is
the method for that side of an app. It pairs with
`learning-orientation-design` (should a feature exist, and does it keep the
learning with the person) and `universal-feature-states` (every list's
loading, empty, error, and offline states). It is meant to grow: each round
of work on a member experience adds what it learned under **Lessons** at the
end.

Sources for the rules below (GitHub, Heroku, Moodle, Canvas, Google
Classroom, Nielsen Norman Group, Baymard, GOV.UK One Login, WCAG 2.2) are
collected with their links in humanshaped.org's
`research/notes/signed-in-experience-notes.md`.

## The rules

### 1. Stop pitching to people who have joined

The address people already use (`/`, the app's first screen) becomes their
own home once they are signed in: GitHub's dashboard, Heroku's dashboard at
its root with the marketing page moved aside. Keep the pitch reachable
(an About page, a `?public` switch) for the member who wants to share it.

- Decide which version to draw **before the first paint**, from what the
  device already holds (a saved session), so neither version flashes. A
  skeleton line ("Gathering your cohorts…") is fine; the pitch is not.
- If the saved session turns out to be dead, fall back to the public
  version quietly.
- Sweep the rest of the app for "Join", "Sign up", and "Sign in with…"
  shown to people who are already in, and change the words ("Join this
  cohort", not "Join with GitHub").

### 2. Order by what needs the person now

Learners first need what is on and what is next, then the way back to
their class (Moodle 4.0 refocused its dashboard on exactly this; Canvas
and Classroom lead with To Do). The order that works:

1. **Now and next**: a session on right now (with the one button that
   joins it), or one coming soon, on the reader's own clock.
2. **Waiting for you**: things only this person can act on, each a row
   with a direct link.
3. **Their things**: classes, conversations, polls, their own work.
4. **Where they left off**: the last stage or lesson they touched.
5. **More they can do**: the tools, as a plain list of links.

One `h1`, an `h2` per section, each section a region named by its heading.
Put the current thing in the one tinted panel; everything else stays on the
page's ground.

### 3. Teachers get a list of what needs them, not charts

Teacher-dashboard research keeps finding that teachers can read analytics
but struggle to turn them into action. Give them rows: "3 people are waiting
for your feedback" with a button that lands on that queue. Counts and
links, never a graph of engagement.

### 4. One page for every role

A person can be a student in one class, a teacher of another, and a builder
on their own. Use one page with a section per role, never a role switcher.

- A section appears for a role the person holds, or when it has something
  in it.
- The core sections (their classes, their work) always appear, and when
  empty they say what fills them and offer **one** action ("Plan a
  cohort", "Add your app"). Never a blank box, never "nothing here" while
  still loading.

### 5. Never turn learning into a score

A home page is where streaks, progress bars, and leaderboards creep in.
Do not let them. Show *where the person was* ("The stage you marked most
recently: Going native"), not *how much* they have done. Notices are counts
of things waiting ("a teacher wrote you a note"), never the words, and
never a comparison with anyone else.

"New since you last looked" is a per-device convenience (a timestamp in
local storage), and it says so by being modest: it decides what appears
under Waiting for you, nothing more.

### 6. The account page is for rare jobs

People open account pages for one task at a time (Baymard). Keep there: how
they sign in, linked accounts, how others may reach them, what they keep
(notes, marks, credentials, with ways to remove them), leaving a group, and
their data with sign-out and deletion last. Move the weekly things to the
home. A plain sign-in lands on the home, not on settings; flows that need
the account page (joining, handing a session to another window) stay
there.

### 7. The signed-in header

- A labeled **Home** first in the menu (GOV.UK: a labeled home link, not
  just the logo).
- In place of the sign-in button, the person's picture and name, opening a
  short list: their home, their account, sign out. Build it as a
  disclosure button and a list of links (`aria-expanded`, Escape closes,
  a click outside closes), not an ARIA menu.
- At phone width, the picture alone, with the name kept in the button's
  label, so the header stays on one row.
- Sign-out from the header goes through the page that owns the session
  (`/account/?sign-out`), then lands on the public home.

### 8. Every row lands on the exact thing

A row that says "Minerva poll, 4 answers" opens that poll, not the list of
polls. Add the anchor or the `#id` handling to the destination page in the
same change. Check every link the home draws before calling it done.

### 9. Moving a feature keeps its old links

Emails, bookmarks, and other pages point at where a feature used to be.
When a section moves (exchanges from the account page to the home), the
old address redirects to the new one, and sentences elsewhere that say
"open it from your account" change in the same commit.

### 10. Check it as the person, at both widths

Look at it signed in, with the real account and real data, at 375px and at
desktop width, in light and dark. When the browser window will not resize,
draw the page in a same-origin `<iframe>` of the width you need, scaled
down: it shares the saved session, so it shows the member view. Look
especially at the empty states, since a new member sees mostly those.

## Checklist

- [ ] The home switches before paint; the pitch is still reachable.
- [ ] Now/next first, then waiting, then their things, then the tools.
- [ ] Every section has an empty state with one action, or is hidden.
- [ ] No streak, score, leaderboard, or comparison anywhere.
- [ ] Teachers see counts with links, not charts.
- [ ] The account page holds only rare jobs; sign-in lands on the home.
- [ ] The header has Home and an account disclosure; one row at 375px.
- [ ] Every row's link opens the exact thing; moved features redirect.
- [ ] Seen signed in, with real data, at 375px and desktop, light and dark.

## Lessons

Add a dated entry each time a member experience teaches something new.

- **2026-10-14, humanshaped.org's signed-in home.** A section's own grid
  styles (`gap`) silently overrode the shared hanging-heading layout, and
  only the desktop check caught it. The account button with a name took a
  row of its own at 375px. The daily email's link to the old exchanges
  address needed a redirect, not an email change, because the script that
  sends it could not be redeployed that day.
- **2026-10-21, humanshaped.org's workspace.** Three corrections from the
  owner in one day. A list page that unfolds one item under itself has no
  single purpose: each thing gets its own address, and making or changing
  it is its own page. Public menu items (principles, events, the open
  cohorts list) do not serve someone signed in to teach or learn: signed
  in, the site becomes a workspace with a sidebar of the person's own
  things (home, each cohort by name, exchanges, teaching, admin) and the
  public pages in a quieter group. And a sentence explaining the interface
  ("You teach this cohort, and this is the page the people in it see") is
  a missing component: role, state, privacy, and what is possible should
  show through shared pieces (a row of views with the current one marked,
  status labels, visibility markers, empty states with one action,
  disclosures for rare detail). An audit found about 35 privacy sentences
  and 25 state sentences that one visibility marker and one status label
  would replace.
