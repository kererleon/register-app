#!/bin/zsh
# Re-signs and installs Register on the iPhone and the Mac.
#
# Apps signed with a free Apple ID (Personal Team) stop working after 7 days.
# This script is run daily by launchd (see com.webandgrow.register.reinstall
# in ~/Library/LaunchAgents) and reinstalls the app when its provisioning
# profile expires within RENEW_DAYS (or the last install is MIN_DAYS old).
# Profiles about to expire are deleted first, because Xcode keeps using a
# still valid profile instead of making a new one.
# The iPhone must be reachable (cable or same Wi-Fi).
#
# Usage: iphone_reinstall.sh [--force]

set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="$HOME/Library/Application Support/RegisterInstaller"
STAMP="$STATE_DIR/last_install"
LOG="$HOME/Library/Logs/RegisterInstaller.log"
MIN_DAYS=5
RENEW_DAYS=2
APP="build/ios_device/Build/Products/Release-iphoneos/Runner.app"
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"

# Seconds until a provisioning profile expires (negative when expired).
profile_left() {
  local exp
  exp=$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw - 2>/dev/null) || return 1
  echo $(( $(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s) - $(date +%s) ))
}

mkdir -p "$STATE_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

# --- Mac: the app in /Applications has the same 7-day limit. ---
MAC_APP="/Applications/Register.app"
mac_left=$(profile_left "$MAC_APP/Contents/embedded.provisionprofile" || echo 0)
if [[ -d "$MAC_APP" ]] && (( mac_left < RENEW_DAYS * 86400 )); then
  echo "Mac: Profil noch $(( mac_left / 3600 )) h gültig, wird erneuert."
  for f in "$PROFILES"/*.provisionprofile(N); do
    info=$(security cms -D -i "$f" 2>/dev/null) || continue
    [[ "$info" == *com.webandgrow.register* ]] || continue
    left=$(profile_left "$f") || continue
    (( left < RENEW_DAYS * 86400 )) && rm -f "$f"
  done
  if (cd "$PROJECT" && flutter build macos --release --config-only &&
      cd macos && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
        -configuration Release -allowProvisioningUpdates \
        -derivedDataPath ../build/macos -quiet); then
    was_running=0
    pgrep -x Register >/dev/null && was_running=1
    osascript -e 'quit app "Register"' 2>/dev/null
    sleep 2
    ditto "$PROJECT/build/macos/Build/Products/Release/Register.app" "$MAC_APP" &&
      echo "Mac: installiert."
    (( was_running )) && open "$MAC_APP"
  else
    echo "Mac: Build fehlgeschlagen."
  fi
fi

# --- iPhone ---
if [[ "${1:-}" != "--force" && -f "$STAMP" ]]; then
  age_days=$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 86400 ))
  left=$(profile_left "$PROJECT/$APP/embedded.mobileprovision" || echo 0)
  if (( age_days < MIN_DAYS && left > RENEW_DAYS * 86400 )); then
    echo "Letzte Installation vor $age_days Tagen, Profil noch $(( left / 3600 )) h gültig, nichts zu tun."
    exit 0
  fi
fi

# The paired physical iPhone (not a simulator).
DEVICE=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null |
  python3 -c '
import json, sys
data = json.load(sys.stdin)
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    conn = d.get("connectionProperties", {})
    if hw.get("reality") != "simulated" and hw.get("platform") == "iOS" \
       and hw.get("deviceType") == "iPhone" and conn.get("pairingState") == "paired":
        print(d["identifier"], hw.get("udid")); break
')
UDID="${DEVICE#* }"
DEVICE="${DEVICE%% *}"

if [[ -z "$DEVICE" ]]; then
  echo "Kein gekoppeltes iPhone gefunden."
  exit 0
fi

# Only build when the iPhone can be reached right now (cable or Wi-Fi).
# Asking for its details opens the connection; the tunnel must then be up.
xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1
TUNNEL=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null |
  python3 -c '
import json, sys
for d in json.load(sys.stdin).get("result", {}).get("devices", []):
    if d["identifier"] == sys.argv[1]:
        print(d.get("connectionProperties", {}).get("tunnelState", ""))
' "$DEVICE")
if [[ "$TUNNEL" != "connected" ]]; then
  echo "iPhone gerade nicht erreichbar ($TUNNEL), versuche es beim nächsten Lauf erneut."
  exit 0
fi
echo "iPhone: $DEVICE ($UDID)"

cd "$PROJECT" || exit 1
# Remove iOS profiles of this app that expire soon, so that xcodebuild has
# to fetch fresh ones (free profiles last 7 days).
for f in "$PROFILES"/*.mobileprovision(N); do
  info=$(security cms -D -i "$f" 2>/dev/null) || continue
  [[ "$info" == *com.webandgrow.register* ]] || continue
  left=$(profile_left "$f") || continue
  if (( left < RENEW_DAYS * 86400 )); then
    echo "Profil läuft bald ab ($(( left / 3600 )) h), wird erneuert: $(basename "$f")"
    rm -f "$f"
  fi
done
# Flutter prepares the project; xcodebuild signs it. Only xcodebuild may
# create provisioning profiles and register the iPhone with the Apple ID,
# which free profiles need every week.
if ! flutter build ios --release --config-only ||
   ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
       -configuration Release -destination "id=$UDID" \
       -derivedDataPath build/ios_device \
       -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
       build -quiet; then
  echo "Build fehlgeschlagen."
  exit 1
fi

if xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  touch "$STAMP"
  echo "Installiert."
else
  echo "Installation fehlgeschlagen."
  exit 1
fi
