# App Review screen recording (Guideline 2.1, Information Needed, 2026-11-14)

App Review asked for "a screen recording captured on a physical device, running
the latest operating system, demonstrating the app's functionality. The recording
must begin with launching the app and show the typical user flow," including
sign-in, account deletion, and the reporting and blocking of user content. The
written answers are in `APP-REVIEW-NOTES.md`.

The recording is two clips joined into one file:

1. **The agent's clip** (`build/store-video/ear-drama-tour.mp4`, gitignored):
   everything that needs no Face ID, recorded on the iPhone Duo (iOS 27.2.1,
   the latest public release on 2026-11-15) by an XCUITest at a human pace,
   muted. It starts with a cold launch and covers: Home with On the air and
   Listen Live, Browse, a series, an episode, Play, Now Playing (pause and
   resume), Search, Record, a play, Read (two page turns, Contents, I'm
   playing a part), Record in the studio (signed out it asks for an account,
   with Sign in with Apple), deleting the production that made, Library, and
   Account signed out (Sign in with Apple).

   How it is recorded: the Duo is on the network, not USB, so neither
   `devicectl device capture screen-record` ("not supported by this device")
   nor CoreMediaIO screen capture works. Device Hub (Xcode's device window,
   `devices://device/open?id=...`) streams the open display, and a
   ScreenCaptureKit recorder captures only that window. Run
   `build/store-video/tools/record_tour.sh` (it builds, installs, drives,
   records, cuts and extracts frames to `build/store-video/frames/`). **The
   owner must be at the Duo**: about a minute in, iOS asks "Enable UI
   Automation: Touch ID to continue with XCTest"; without the touch the run
   times out and records nothing of the app. Read every frame before using
   the clip, then delete `raw-tour.mp4` (it holds the home screen).
2. **The owner's clip** (recorded on your own iPhone): the steps that need your
   Face ID. Script below.

## The owner's clip

Before you start: turn on Do Not Disturb (Control Center, Focus) so no
notification appears, and use a phone on the latest iOS (27.2.1 or later).
Keep the clip short (1 to 2 minutes); pause a second on each screen so a
reviewer can read it.

1. Control Center, Screen Recording (the record button). Wait for the
   countdown.
2. Open **Ear Drama**.
3. **Library**, scroll to the bottom, **Account**. It says Not signed in.
4. Tap **Sign in with Apple** and confirm with Face ID. Account now shows
   "Signed in with Apple".
5. **Report and Block** (they appear only for another member of a shared
   production):
   - If you already have a shared production with a second person: **Record**
     tab, the production under **Yours**, **People**. Show the other member's
     row with **Report** and **Block**. Tap **Report**, show the reasons, then
     **Cancel**. Tap **Block**, show the confirmation, then dismiss it (don't
     block your helper unless you mean to). **Done**.
   - If you have none: make one first (before you start recording, so the clip
     stays short). On your iPhone, signed in: **Record** tab, a play, **Read**,
     **I'm playing** a part, **Record** (this makes the production); back on the
     production's cast sheet tap **Share**, type a name, then **Invite** and
     send the link to a second Apple ID: a family member's iPhone, or an iPad
     signed in with another Apple ID. They open the link in Ear Drama, sign in
     with Apple, and join. Then record step 5 as above.
   - If no second person is available today, skip step 5: the notes
     (`APP-REVIEW-NOTES.md`, "User content") describe Report and Block, and the
     reviewer can test them with two accounts.
6. Back to **Library**, **Account**, **Delete Account**, confirm **Delete
   Account**, and confirm with Face ID when Apple asks. Account shows Not signed
   in again.
7. Stop the recording (the red status pill, Stop). It lands in Photos.

### Sending it to the agent

In Photos, select the recording, Share, **AirDrop**, this Mac. It lands in
`~/Downloads` (for example `~/Downloads/RPReplay_Final1763200000.MP4`). Tell
the main session the file name; don't trim it, the join trims it.

## Joining the two clips (main session)

The two clips differ in size, orientation and frame rate (the agent's clip is
the Duo's open display, landscape; an iPhone screen recording is portrait and
may be 60 fps with audio). Both are normalized to one canvas, 1920x1080, 30 fps,
H.264, yuv420p, no audio (the app is muted in the agent's clip, and the owner's
clip may carry system sound), then joined with the concat demuxer, which needs
identical streams.

```sh
cd ~/Documents/GitHub/Ear-Drama/build/store-video
OWNER=~/Downloads/RPReplay_Final1763200000.MP4   # the AirDropped file

# 1. The owner's clip, trimmed if needed (-ss start, -to end, in seconds),
#    fitted inside 1920x1080 with black bars.
ffmpeg -y -i "$OWNER" -an \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p,setsar=1" \
  -c:v libx264 -preset slow -crf 20 -r 30 -movflags +faststart owner-1080.mp4

# 2. The agent's clip, the same canvas.
ffmpeg -y -i ear-drama-tour.mp4 -an \
  -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,fps=30,format=yuv420p,setsar=1" \
  -c:v libx264 -preset slow -crf 20 -r 30 -movflags +faststart tour-1080.mp4

# 3. Check both streams match (codec, 1920x1080, 30/1, yuv420p).
for f in tour-1080.mp4 owner-1080.mp4; do
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,r_frame_rate,pix_fmt -of csv=p=0 "$f"
done

# 4. Join: the tour first (it starts with the launch), then the owner's clip.
printf "file 'tour-1080.mp4'\nfile 'owner-1080.mp4'\n" > concat.txt
ffmpeg -y -f concat -safe 0 -i concat.txt -c copy -movflags +faststart ear-drama-app-review.mp4

# 5. Check: duration, size (App Review takes up to 500 MB), then read frames.
ffprobe -v error -show_entries format=duration,size -of default=nw=1 ear-drama-app-review.mp4
mkdir -p frames-final && ffmpeg -v error -i ear-drama-app-review.mp4 -vf fps=1/3 frames-final/%03d.png
```

Read the frames around the join and every frame of the owner's clip before
uploading: no notification, no personal data beyond the Apple ID sign-in sheet
(blur it if it shows an email address you don't want shown: the sign-in sheet
can show "Hide My Email" instead).

Upload `ear-drama-app-review.mp4` with the reply to the 2.1 message in App
Store Connect (App Review, the message, attach).

## The second recording (2026-11-16, for the resubmission of 1.0.134)

App Review's Guideline 2.1 message asks for account deletion and the reporting and
blocking of user content ON CAMERA, which the first recording only described.
`build/store-video/ear-drama-app-review-2.mp4` (5:46) is the first recording followed
by `AppReviewModerationUITests.testModeration`: People in a shared production with a
second member (the Pixel, signed in with Google, directs "Caesar Rodney's Ride"; the
Duo joined it with `testJoin`), Report and its reasons, Block's confirmation, Account,
Delete Account confirmed, signed out. The owner's only step is Touch ID on Apple's
sheets (sign-in in `testJoin`, re-authorization in Delete Account).

Capture is headless (owner 2026-11-16: never open Device Hub or another Mac window):
two workers loop `xcrun devicectl device capture screenshot --display-unique-id
123-456-789` (the open Duo's inner display; `devicectl info displays` wrongly marks
the outer one active) at about 0.7 frames a second, and ffmpeg's concat demuxer turns
the stamped frames into video. pymobiledevice3's DVT screenshot sees only the outer
display. Swipes on the application element did not scroll on the open Duo because
XCUITest reports the app's frame in portrait (669 x 951) while the window is landscape
(951 x 669); a swipe on the scroll view itself works. Every UI test now scrolls with
`app.scrollUp()` (apple/UITests/UITestScrolling.swift), which swipes the largest scroll
container. The recorded take reached Account through the DEBUG door
`APP_START_TAB=account`, made before the cause was found.
