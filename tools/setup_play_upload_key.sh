#!/usr/bin/env bash
# One-time: create Ear Drama's Android upload keystore and the repo secrets
# play-release.yml reads. Run by the owner (`! bash tools/setup_play_upload_key.sh`);
# the agent's permission check refuses secret-store writes.
#
# The keystore lives outside git (~/keystores/eardrama-upload.jks); its password
# lives only in the macOS Keychain and in GitHub's secret store, never in a file.
# Play App Signing holds the real signing key; this is the UPLOAD key, which Play
# registers from the first bundle uploaded, and which Play support can reset if lost.
set -euo pipefail
KT="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
KS="$HOME/keystores/eardrama-upload.jks"
ITEM="Ear Drama Android upload keystore"
SA="$HOME/.config/play/archivewatch-play.json"
cd "$(dirname "$0")/.."

[ -x "$KT" ] || { echo "no keytool at $KT"; exit 1; }
[ -f "$SA" ] || { echo "no service-account key at $SA"; exit 1; }
[ -e "$KS" ] && { echo "$KS already exists; refusing to replace an upload key"; exit 1; }

mkdir -p "$HOME/keystores"
PW=$(openssl rand -base64 30 | tr -d '/+=' | cut -c1-32)
security add-generic-password -a eardrama-upload -s "$ITEM" -w "$PW"
"$KT" -genkeypair -storetype PKCS12 -keystore "$KS" -alias upload -keyalg RSA \
  -keysize 4096 -validity 10000 -storepass "$PW" -keypass "$PW" \
  -dname "CN=Ear Drama, O=Learning Is Change, C=US" >/dev/null 2>&1
chmod 600 "$KS"

base64 -i "$KS" | gh secret set UPLOAD_KEYSTORE_B64
printf '%s' "$PW" | gh secret set UPLOAD_KEYSTORE_PASSWORD
printf '%s' "$PW" | gh secret set UPLOAD_KEY_PASSWORD
printf 'upload' | gh secret set UPLOAD_KEY_ALIAS
gh secret set PLAY_SERVICE_ACCOUNT_JSON < "$SA"
unset PW

echo "Upload key fingerprints (DEEP_LINKS.md's assetlinks step wants the SHA-256):"
"$KT" -list -v -keystore "$KS" -storepass "$(security find-generic-password -a eardrama-upload -s "$ITEM" -w)" \
  2>/dev/null | grep -E "SHA1:|SHA256:"
echo "Secrets now set:"; gh secret list | cut -f1 | grep -E "UPLOAD_|PLAY_"
