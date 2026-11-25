# Answering a report

You get a GitHub email: "1 report is waiting" (or a comment when more come). It never says who or what, because the
repository is public. Everything below runs on your Mac, in the repository, with your wrangler login.

```sh
python3 tools/reports.py list                     # what waits
python3 tools/reports.py show <id>                # the reason, the note, who, which line, where it is
python3 tools/reports.py dismiss <id> --yes       # nothing wrong; a publish it held may go ahead
python3 tools/reports.py remove-take <id> --yes   # that one recording leaves the production (and archive.org)
python3 tools/reports.py remove-member <id> --yes # that person leaves with their recordings; its invites close
python3 tools/reports.py unshare <id> --yes       # every invite closes; every published line leaves archive.org
```

Leave off `--yes` to see what an answer would do. Every answer closes the report; when none wait, the issue closes
itself within the hour. Answer within a day (App Store guideline 1.2 asks for timely).

- **You cannot hear the recording**: the Worker keeps no audio. A published one is at the archive.org address `show`
  prints; for the rest, judge the note, and remove when in doubt, since its maker can record the line again.
- **While a report is open** its take is held from publishing and hidden from its reporter and from anyone who is not
  signed in. A dismissed take stays hidden from people who are not signed in.
- **archive.org** catches up within five minutes; copies already made cannot be called back.
- **The director** cannot be removed from their own production: `unshare` it. They can invite people again, so a second
  report is the reason to delete the account, which no command does yet: ask for it.
- **Danger to a child, or a threat**: call the police or the NCMEC CyberTipline (report.cybertip.org) first, then
  `unshare`. Do not delete anything else.
- **A read room** has nothing to report afterward: it keeps no words, names, or sound once it ends. Its leader removes
  a person on the spot.

If no email comes: `gh run list --workflow reports.yml -L 3`. A red run could not ask; its log says why.
