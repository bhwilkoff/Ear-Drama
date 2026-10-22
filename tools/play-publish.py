#!/usr/bin/env python3
"""Upload a signed Android App Bundle to Google Play and create a release on a track, via the Google
Play Developer API v3 — no Android Studio, no manual upload (the Play analog of the App Store
tools/asc_*.py scripts). Uses the "edits" transaction: insert an edit, upload the .aab, point a track
at the new versionCode with release notes, then commit.

Usage:  play-publish.py <app-release.aab> [--track production|internal|alpha|beta]
                        [--notes "release notes" | --notes @notes.txt] [--rollout 0.1] [--draft]

Release notes over Play's 500-character limit are refused before anything is
uploaded. A 5xx from Play is retried with backoff. When Play refuses to send the
change for review automatically (changesNotSentForReview), the edit is committed
without the review request and the owner is told to send it from the Console.
Env:    PLAY_SERVICE_ACCOUNT_JSON  path to the service-account JSON key
                                   (default ~/.config/play/PLAY_SERVICE_ACCOUNT.json)
        PLAY_PACKAGE               package name (default com.example.appname)
                                   NOTE: this is the Play applicationId, which can DIFFER from the
                                   Gradle `namespace`. Use the applicationId here.

The service account must be granted release permissions for the app in Play Console
(Users and permissions). The JSON key belongs in NO git repo — keep it under ~/.config/play.
Requires: google-api-python-client, google-auth (tools/submit-play.sh installs them into a venv).
"""
import sys, os, argparse, time

# Play caps release notes at 500 characters and enforces it at COMMIT, the last
# call, after the bundle is built and uploaded. A 513-character note once failed a
# run seven minutes in, with the AAB already uploaded into an edit that had to be
# thrown away:
#   "The release created has notes in language en-US with length 513,
#    which is too long (max: 500)."
# The limit is knowable before any of that, so it is checked before any of that
# (tools/submit-play.sh checks it again before it bumps versionCode). Refused, not
# truncated: a note cut mid-sentence goes to every user, and choosing what to drop
# is the author's job.
NOTES_MAX = 500
RETRY_STATUSES = (500, 502, 503, 504)


def http_status(e):
    return getattr(e, "status_code", None) or getattr(getattr(e, "resp", None), "status", None)


def with_retries(what, call, http_error, tries=5):
    """Google answers a plain 503 "The service is currently unavailable" now and
    then, even on the first call of a run. That is Google's weather, not our
    release: retry a 5xx with backoff before anyone is emailed a red X for it.
    Only for calls that are safe to repeat; a 4xx is our mistake and fails now."""
    for attempt in range(1, tries + 1):
        try:
            return call()
        except http_error as e:
            status = http_status(e)
            if status not in RETRY_STATUSES or attempt == tries:
                raise
            wait = 15 * attempt
            print(f"  {what}: Play answered {status}; retry {attempt}/{tries - 1} in {wait}s")
            time.sleep(wait)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("aab")
    ap.add_argument("--track", default="production")
    ap.add_argument("--notes", default=None, help="release notes (en-US); or @path to read a file")
    ap.add_argument("--rollout", type=float, default=None, help="staged rollout fraction 0<f<1 (else full)")
    ap.add_argument("--draft", action="store_true", help="create the release as a draft (not live)")
    args = ap.parse_args()

    notes = args.notes
    if notes and notes.startswith("@"):
        notes = open(os.path.expanduser(notes[1:])).read().strip()
    if notes and len(notes) > NOTES_MAX:
        raise SystemExit(
            f"release notes are {len(notes)} characters; Play's limit is {NOTES_MAX}. "
            f"Shorten them by {len(notes) - NOTES_MAX} and re-run; nothing has been "
            f"uploaded.")

    pkg = os.environ.get("PLAY_PACKAGE", "com.example.appname")
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/PLAY_SERVICE_ACCOUNT.json"))
    if not os.path.isfile(args.aab):
        raise SystemExit(f"AAB not found: {args.aab}")
    if not os.path.isfile(key):
        raise SystemExit(f"Service-account JSON not found: {key}\n"
                         f"Set PLAY_SERVICE_ACCOUNT_JSON or place it at ~/.config/play/PLAY_SERVICE_ACCOUNT.json")

    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from googleapiclient.errors import HttpError

    creds = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edits = service.edits()

    try:
        edit_id = with_retries("open edit",
                               lambda: edits.insert(body={}, packageName=pkg).execute(),
                               HttpError)["id"]
        print(f"edit {edit_id} opened for {pkg}")

        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
        # The client's own retry resumes the upload from its last chunk on a 5xx.
        up = edits.bundles().upload(packageName=pkg, editId=edit_id,
                                    media_body=media).execute(num_retries=4)
        vc = up["versionCode"]
        print(f"uploaded AAB → versionCode {vc}")

        status = "draft" if args.draft else ("inProgress" if args.rollout else "completed")
        release = {"versionCodes": [str(vc)], "status": status}
        if args.rollout and not args.draft:
            release["userFraction"] = args.rollout
        if notes:
            release["releaseNotes"] = [{"language": "en-US", "text": notes}]

        # A PUT of the whole track: repeating it is harmless.
        with_retries("update track", lambda: edits.tracks().update(
            packageName=pkg, editId=edit_id, track=args.track,
            body={"track": args.track, "releases": [release]}).execute(), HttpError)
        print(f"track '{args.track}' → versionCode {vc} ({status}"
              + (f", rollout {args.rollout}" if args.rollout and not args.draft else "") + ")")

        # The commit is NOT retried blindly: a 5xx after Play actually committed
        # would turn a shipped release into an "edit not found" failure.
        try:
            edits.commit(packageName=pkg, editId=edit_id).execute()
            print(f"✓ committed. versionCode {vc} is now '{status}' on the '{args.track}' track"
                  + ("" if args.draft else " — Play review then rollout."))
        except HttpError as e:
            # While an app sits in a REJECTED state (and for some managed-publishing
            # states) Play refuses to send changes for review over the API:
            # "Changes cannot be sent for review automatically. Please set the query
            # parameter changesNotSentForReview to true." The upload is still valid;
            # commit it without the review request and let a human send it for
            # review. Losing the upload over this means rebuilding and re-uploading
            # the bundle for nothing.
            if "changesNotSentForReview" not in str(e):
                raise
            edits.commit(packageName=pkg, editId=edit_id,
                         changesNotSentForReview=True).execute()
            print(f"✓ committed. versionCode {vc} is on the '{args.track}' track, "
                  "but NOT yet sent for review.")
            print("  Play refuses automatic review submission in this app state "
                  "(usually a rejected update).")
            print("  OWNER: Play Console → Publishing overview → 'Send changes for review'.")
    except HttpError as e:
        raise SystemExit(f"Play API error: {http_status(e) or ''} {e}")

if __name__ == "__main__":
    main()
