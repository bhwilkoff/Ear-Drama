# Google OAuth client setup for Android and web sync

I want Android and web folks to get the same quiet sync that Apple
devices get from CloudKit. Decision 015 routes Android and web sync
through the person's own Google Drive (the hidden App Data folder), with
no backend to run. The code can be built and waiting, but it needs OAuth
client IDs that only the project owner can create. It takes about 15
minutes, it is free, and it needs no billing account.

## Step 1: the project and consent screen (once)

1. https://console.cloud.google.com, New Project, name it `[APP NAME]`.
2. APIs & Services, **Library**, search "Google Drive API", Enable.
3. APIs & Services, **OAuth consent screen**:
   - User type: **External**, Create.
   - App name `[APP NAME]`, support email is your email.
   - Scopes: Add, filter `drive.appdata`, check
     `https://www.googleapis.com/auth/drive.appdata`, Update.
   - Test users: add your own Google account. While the app is in
     Testing, only listed users can sign in. Publish later for everyone;
     `drive.appdata` is a non-sensitive scope with no review.

## Step 2: the web client ID

1. APIs & Services, **Credentials**, Create Credentials, OAuth client ID.
2. Application type: **Web application**, name `[APP NAME] Web`.
3. Authorized JavaScript origins:
   - `https://<your-domain>`
   - `http://localhost:8080` (local dev)
4. Create, then copy the client ID (`...apps.googleusercontent.com`).
5. Paste it into the activation constant in `index.html` (for example
   `window.APP_GOOGLE_CLIENT_ID = ''`) and push. The web sync module
   that reads it (for example `js/drivesync.js`) is one you create. A
   "Sign in with Google to sync across devices" button then appears in
   the Library view.

## Step 3: the Android client IDs

OAuth for Android validates by package name plus signing certificate.
There is no secret.

1. Credentials, Create Credentials, OAuth client ID, **Android**.
2. Package name: `com.example.appname` (your real application ID).
3. SHA-1: one client per certificate, so create THREE Android clients:
   - the upload key: `keytool -list -v -keystore
     ~/keystores/<appname>-upload.jks -alias upload | grep SHA1`
   - the debug key: `keytool -list -v -keystore ~/.android/debug.keystore
     -alias androiddebugkey -storepass android | grep SHA1`
   - the **Play App Signing** key: Play Console, your app, Setup, App
     signing, App signing key certificate, SHA-1. This is the one
     production installs use. Without it, sync fails only in
     production (the classic trap).
4. Android sign-in also needs a client to EXCHANGE for tokens. Reuse the
   Web client ID from Step 2 as the `serverClientId`. The Android wiring
   lands in the Google Play flavor only. The Fire TV flavor stays free
   of Google Mobile Services (Decision 028 and the
   `androidtv-compose-focus` skill).

## Step 4: hand back to the agent

Reply with the Web client ID (or confirm it is pasted into
`index.html`). The Android client IDs need no code; only the Web client
ID doubles as `serverClientId`. The agent then finishes the Android
sign-in and Drive plumbing and verifies that a browser and a phone
converge on one record.

Fifteen minutes, then sync is live.
