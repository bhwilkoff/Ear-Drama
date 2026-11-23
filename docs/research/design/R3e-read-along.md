# R3e: A first-rate read-along

2026-11-23. The owner, after TestFlight 1.0.159 on the iPhone: *"when you press the read along button, it
should highlight the words or underline them as they are read. It should also advance the pages as the read
along happens. Overall we need to update the read along interface. You should be able to control speed and it
should be a first-rate play reading experience."* This note feeds PLAYS-DESIGN §2.11 (rewritten the same day).

## What the best follow-along experiences do

| Product | What is lit | How the page moves | Speed | Notes |
|---|---|---|---|---|
| Apple Books Read Aloud (EPUB 3 Media Overlays) | The element the SMIL file names, styled by the book's `-epub-media-overlay-active` class; Apple asks for word-by-word timing in children's books and draws a default blue highlight when the book sets none | Turns the page itself when narration reaches the next page (fixed-layout books only) | The system's narration controls | The timing is authored, never guessed: each `<par>` pairs a text fragment with an audio clip's begin and end [1][2] |
| Kindle Immersion Reading (Audible + Kindle, Whispersync for Voice) | Word by word, over a professional narration | The text follows the narration | The Audible player's narration speed | Needs a matched ("Read & Listen") book and audiobook; the alignment is made ahead, not on the device [3][4] |
| Kindle Assistive Reader (text to speech) | The words being read | Turning a page restarts reading at the top of the new page | Its own speed control, plus back 30 seconds | A transport at the foot of the page [5] |
| Speechify | The sentence, with the word inside it | Auto-scroll keeps the reading in view; a reader who scrolls away gets a way back | 0.5x to 4.5x (about 100 to 900 words per minute) | Word inside sentence is the pattern people describe as "following along" [6][7] |
| Voice Dream Reader | Word and line (the "speech cursor"), sentence optional | Auto-scroll, with a full-screen focused mode after Play | 50 to 500 words per minute, changeable while it plays, remembered per book; two-finger swipe changes rate | Skip by sentence, paragraph or page, not only by seconds [8][9] |
| Apple Music time-synced lyrics | The line, and word by word on lyrics delivered with word timing (TTML) | The current line held in view; the view stops following when the person scrolls and returns after | n/a | Timing comes in the file; line-only lyrics stay line-only [10] |
| Karaoke and live captions | Word (a wipe across the word) or phrase | Two lines in view: the one sung and the next | n/a | The wipe needs per-word timing; captioning guidance favors phrases over single words for reading comfort |

## What makes them feel first-rate

1. **Two levels at once**: the unit being read (sentence, line) stays softly lit and the word inside it is
   marked strongly. Readers keep their place by the line and follow by the word. Word alone flickers; line
   alone loses the voice inside a long speech.
2. **Timing comes from the source, never from a guess.** Every product above that lights words has real word
   timing (SMIL clips, an aligned audiobook, the speech engine's own word callbacks, TTML). Apps without it
   light the line only. This matches our rule 6 (no guessed sync).
3. **The page turns itself** at the boundary, the same turn a person makes, and stops following the moment
   the reader moves the page, with one obvious way back (Apple Music, Speechify).
4. **Speed is one control in the transport**, usually 0.5x to 2x in quarter steps for listening apps
   (Speechify and Voice Dream go further for speed readers; a play is performed speech, and above 2x the
   device voices garble and a take loses its acting). It changes while playing and is remembered.
5. **Skip by the text's own unit** (sentence, line, page), not by seconds (Voice Dream). For a play the unit
   is the line.
6. **The transport is small**: play or pause, back, forward, speed, and where you are. Nothing explains
   itself.

## Accessibility

- **Reduce Motion**: page turns cut instead of sliding; the word mark moves without animation (it is a
  state, never a transition).
- **VoiceOver**: a screen reader user already hears the voice; the highlight must not steal focus or announce
  each word. The line heard is the element VoiceOver lands on when the person moves to the page, and the
  transport's buttons are labeled ("Previous line", "Next line", "Speed, 1.25 times").
- **Contrast**: the word mark must read in light and dark at WCAG AA against the line tint; a fill plus an
  underline survives color-blindness better than color alone.

## What it means for Ear Drama

- Device voices give real word timing on every platform: Apple `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)`,
  Android `UtteranceProgressListener.onRangeStart`, the web `SpeechSynthesisUtterance` `boundary` event
  (Chrome and Safari fire it for local voices; some network voices fire none, then the line stays lit).
- Kokoro's duration model predicts frames per phoneme token before the decoder runs; summing frames to each
  phoneme word gives measured word starts for the audio we are about to play (frames x 600 samples at 24 kHz,
  divided by the playback pitch). Phoneme words pair with printed words only when their counts agree;
  otherwise that line stays lit without a word mark (never a stretch by character counts).
- Human takes and finished dramas have no word timing. They light the line only, as Apple Music does with
  line-only lyrics. A forced aligner on the device would be a guess presented as a fact, and rule 6 forbids it.
- Speed: 0.5x to 2x in 0.25 steps. Device voices and Kokoro take it from their next line; takes and finished
  dramas take it at once (AVAudioPlayer `rate`, AVPlayer `rate` with the time-domain pitch algorithm,
  Android `PlaybackParameters`, the web `playbackRate` with `preservesPitch`).

## Sources

1. W3C, EPUB Media Overlays 3.2: https://www.w3.org/publishing/epub32/epub-mediaoverlays.html
2. Apple Books Asset Guide, read aloud and `-epub-media-overlay-active`: https://help.apple.com/itc/booksassetguide/en.lproj/itcf373ff8f8.html
3. Audible Help, What is Immersion Reading: https://help.audible.com/s/article/what-is-immersion-reading
4. Android Authority, Kindle app immersive reading: https://www.androidauthority.com/kindle-app-immersive-reading-3643858/
5. Amazon Help, Assistive Reader in Kindle apps: https://digprjsurvey.amazon.com/csad/help/node/TqLHvK6eo6O7DJVQoZ
6. Speechify on the App Store: https://apps.apple.com/us/app/speechify-text-to-speech/id1209815023
7. Stanford OAE, Speechify tips and tricks (auto-scroll): https://oae.stanford.edu/resources/speechify-tips-tricks
8. Voice Dream on the App Store: https://apps.apple.com/us/app/voice-dream-natural-reader/id496177674
9. Voice Dream support, Getting Started: https://supportapp.freshdesk.com/support/solutions/articles/154000153109-getting-started
10. Apple Support, lyrics in Apple Music on iPhone and iPad: https://support.apple.com/HT204459
11. DAISY Knowledge Base, highlighting synchronized text: https://kb.daisy.org/publishing/docs/sync-media/highlight.html
