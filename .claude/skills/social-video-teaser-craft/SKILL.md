---
name: social-video-teaser-craft
description: Use when building an automated social-media programme that posts VIDEO — vertical teasers for Reels, Shorts, TikTok, Bluesky or Threads — or when shaping captions per platform. Carries the safe-area geometry that platform chrome imposes, the rule that a burned caption must be verified against the audio, per-platform cadence and caption ORDER, and the measurement instrument. Triggers on vertical video, Reels, Shorts, TikTok, teaser clip, burned captions, ffmpeg drawtext, social cadence, hashtag policy, engagement metrics.
---

# Social Video Teaser Craft

Hard-won on an automated daily programme posting to five platforms.
Every rule below replaced something that shipped and was wrong.

## The frame is BANDED, not layered

Reels, Shorts and TikTok draw their OWN chrome over your video: the
account name, caption and action rail across the bottom, a header
across the top. Anything you burn into the bottom third is printed
through by the platform.

- Bound every drawn element by measured safe areas. On a 1080x1920
  frame the union of the published Reels and TikTok specs is
  **250 px top, 480 px bottom**. Assert it in a test — the fix is a
  number, not a look.
- Give the picture its own band and the words theirs: title above,
  film in the middle, quote below, none touching. Fit the video
  INSIDE its box at its own aspect (`force_original_aspect_ratio=
  decrease` bounds BOTH dimensions), so a 4:3 source sits narrower
  than the frame rather than being cropped or covered.
- Full-width does not work with a bottom caption: a 4:3 film fitted
  to 1080 wide is 810 tall, leaving 75 px inside the safe area — a
  third of one line of type.
- Never dim the picture to make type readable. Laying a wordmark over
  a photograph under a gradient scrim put white type on white
  plaster; banding solved what the scrim could not.

## Every teaser carries sound

A silent Short does not read as restraint, it reads as broken. Keep
the audio on EVERY clip, not just the ones where dialogue is the
point. Normalise it (`loudnorm=I=-16:TP=-1.5:LRA=11`) because archive
sources range from whisper to clipping and a feed autoplays them
beside professionally mastered video, and fade both ends.

**Measure the audio at both ends and refuse rather than publish a
silent teaser.** A missing audio track is invisible in a frame — it
was reported twice by a human before being caught. Probe the SOURCE
and the RENDER; a source that is genuinely silent is fine and says
so, a render that LOST audio the source had is a bug and must not
ship.

## A burned caption must be HEARD, never trusted

If you cut to a line of dialogue and burn it on screen, verify the
words against the actual audio before committing. Subtitle files are
routinely mistimed, and some belong to an entirely different film.

- Cut the cue's window out of the audio, transcribe it, and score how
  many of the cue's CONTENT words are heard (drop stopwords — "the",
  "to", "you" match everything).
- Calibrate the threshold on real material rather than picking one.
  Measured across four films: a correctly-timed track scored
  0.625-1.0 on every cue; three mistimed or wrong-film tracks scored
  0.0 on every cue. A gap that wide means the threshold is not a
  tuning parameter — do not lower it to rescue more lines.
- Keep **"could not check"** distinct from "checked and failed". No
  audio, no recogniser, or too few content words must return None,
  and None must never burn. Otherwise the gate disappears silently
  the day a dependency goes missing.
- Try several candidate lines, then fall back to a non-caption cut.
- VAD is not enough: voice-activity detection tells you somebody is
  talking, which is exactly what a wrong caption sits on top of.
- A recogniser that hallucinates is acceptable HERE even when it is
  not acceptable for generating captions — a hallucinated transcript
  simply fails to match and the teaser falls back. The failure
  direction is safe, which is what makes the same tool right for
  verifying and wrong for authoring.

## Caption shape is per platform; the material is not

Same sourced text everywhere. What changes is the ORDER, and it
matters because in a feed that shows the first line and hides the
rest, the first line IS the post.

| platform | leads with | why |
|---|---|---|
| Bluesky | the quote | 300 chars, chronological, hook-driven |
| Instagram / Threads | the quote | caption collapses after ~1 line |
| Mastodon | title + facts | descriptive culture; readers arrive by hashtag |
| YouTube | the link | description is read by search; ~150 chars show |
| Facebook | title + facts | the link preview does the work |

Rules that survived contact:

- **Reserve the subject's NAME and the LINK before anything competes
  for space.** A naive "add parts while they fit" produced a post
  that quoted a viewer at length and never said what it was about.
- **Trim a quotation at a SENTENCE end**, never mid-clause, and treat
  a quote plus its attribution as ONE unit — shorten only the quote.
  Losing the attribution to a character count is not a smaller post,
  it is a different rule.
- **Metadata is filler on a tight platform and the point on YouTube.**
  Runtime, format and credits earn their place only where space is
  not scarce.
- **Instagram does not linkify captions.** A 60-character URL nobody
  can tap is 60 characters of noise; use the bare domain.
- If the source picks the quotable item, rank it so that what
  survives whole is preferred — ranking by LENGTH MAXIMISED
  guarantees truncation on the tightest platform, which is what one
  selector was doing on purpose.

## Cadence is per platform too

"Daily" is not one decision. Measured bands differ (Instagram's
growth compounds in a 6-9/week window; Threads' sweet spot is 2-5;
chronological feeds tolerate more). Encode it as a table keyed by
weekday and let an explicit operator override win over the calendar —
the gate exists to shape the UNATTENDED run.

## Measure, but refuse to conclude on nothing

Build the instrument early and the conclusions late.

- Sample each post ONCE PER WINDOW, and set the thresholds BELOW the
  windows they name (20h for "24h"): a daily cron running at the same
  clock time arrives minutes early, and a "24h" reading taken at 48h
  is not the thing it claims to be.
- Record the FORMAT that actually went out, not the one you offered —
  when a platform refuses video and posts the card, a ledger that
  says "video" will make the card look like a well-performing reel
  forever.
- Make the report REFUSE to rank a bucket under ~10 posts and say so.
  With single-digit likes any ranking is noise wearing a table's
  clothes.

## Deleting a post is mostly not possible

Before promising a takedown, know the matrix. Measured 2026-09:
Bluesky and Mastodon delete over their APIs; **Instagram's Content
Publishing API has no delete at all**, **Threads answers
`code 10 "Application does not have permission"`**, and **YouTube's
`videos.delete` needs a broader OAuth scope than the upload-only one
a poster should mint**. Report those as MANUAL with the exact place
to click, never as done — and provide a way to prune the local ledger
after the human deletes, or the removed post keeps its subject
retired.

## The permalink a create call returns may not be one

A published Instagram media id is NOT its shortcode, so
`instagram.com/p/<id>` is a URL shaped like a permalink that goes
nowhere — in your ledger AND in any public feed you drive from it.
Ask the API for the `permalink` field; fall back to the constructed
guess only if that call fails, so a permalink problem can never cost
the post itself.

## See also

- [[autonomous-loop-cadence]] — pacing the loop that drives this
- [[learning-orientation-design]] — the gate that refuses engagement
  bait; a question YOU write has no source, but a film that asks one
  in its own dialogue does
