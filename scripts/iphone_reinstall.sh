#!/bin/zsh
# Re-signs and installs Register on the iPhone and the Mac.
#
# Apps signed with a free Apple ID (Personal Team) stop working after 7 days.
# This script is run every hour by launchd (see com.webandgrow.register.reinstall
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

notify() {
  osascript -e "display notification \"$1\" with title \"Register\"" 2>/dev/null
}
FAILED_HINT="Register konnte nicht neu signiert werden. Meist hilft: Xcode öffnen → Einstellungen → Accounts → mit der Apple-ID anmelden."

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
    notify "$FAILED_HINT"
  fi
fi

# --- iPhone ---
# Signing does not need the iPhone, installing does. So the profile is
# renewed in time even while the iPhone is locked, and the install follows
# as soon as the iPhone can be reached (this script runs every hour).
INSTALLED_EXPIRY="$STATE_DIR/installed_expiry"

built_left=$(profile_left "$PROJECT/$APP/embedded.mobileprovision" || echo 0)
need_build=0
[[ "${1:-}" == "--force" ]] && need_build=1
(( built_left < RENEW_DAYS * 86400 )) && need_build=1
need_install=$need_build
# A renewed app that could not be installed yet.
[[ ! -f "$STAMP" || "$PROJECT/$APP/embedded.mobileprovision" -nt "$STAMP" ]] &&
  need_install=1
if (( ! need_build && ! need_install )); then
  echo "iPhone: Profil noch $(( built_left / 3600 )) h gültig, nichts zu tun."
  exit 0
fi

cd "$PROJECT" || exit 1
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

# Only install when the iPhone can be reached right now (cable or Wi-Fi).
# Asking for its details opens the connection; the tunnel must then be up.
TUNNEL=""
if [[ -n "$DEVICE" ]]; then
  xcrun devicectl device info details --device "$DEVICE" >/dev/null 2>&1
  TUNNEL=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null |
    python3 -c '
import json, sys
for d in json.load(sys.stdin).get("result", {}).get("devices", []):
    if d["identifier"] == sys.argv[1]:
        print(d.get("connectionProperties", {}).get("tunnelState", ""))
' "$DEVICE")
fi
# Only a connected iPhone can be registered while signing.
[[ "$TUNNEL" == "connected" ]] || UDID=""

if (( need_build )); then
  # Remove iOS profiles of this app that expire soon, so that xcodebuild
  # has to fetch fresh ones (free profiles last 7 days).
  for f in "$PROFILES"/*.mobileprovision(N); do
    info=$(security cms -D -i "$f" 2>/dev/null) || continue
    [[ "$info" == *com.webandgrow.register* ]] || continue
    left=$(profile_left "$f") || continue
    if (( left < RENEW_DAYS * 86400 )); then
      echo "Profil läuft bald ab ($(( left / 3600 )) h), wird erneuert: $(basename "$f")"
      rm -f "$f"
    fi
  done
  # Flutter prepares the project; xcodebuild signs it and creates the
  # profile. With the iPhone at hand it is (re)registered with the Apple ID
  # (the list of devices can be reset, e.g. after signing in again);
  # otherwise a generic destination works while the iPhone is locked.
  dest="generic/platform=iOS"
  [[ -n "$UDID" ]] && dest="id=$UDID"
  if ! flutter build ios --release --config-only ||
     ! xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
         -configuration Release -destination "$dest" \
         -derivedDataPath build/ios_device \
         -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
         build -quiet; then
    echo "Build fehlgeschlagen."
    notify "$FAILED_HINT"
    exit 1
  fi
  echo "iPhone: neu signiert, Profil bis $(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)."
fi

if [[ "$TUNNEL" != "connected" ]]; then
  echo "iPhone gerade nicht erreichbar (${TUNNEL:-nicht gefunden}), Installation beim nächsten Lauf."
  # Warn only when the app on the iPhone stops working within a day.
  installed=$(cat "$INSTALLED_EXPIRY" 2>/dev/null || echo 0)
  if (( installed - $(date +%s) < 86400 )); then
    notify "Register auf dem iPhone muss erneuert werden: iPhone entsperren und ins selbe WLAN wie den Mac (oder per Kabel)."
  fi
  exit 0
fi

if xcrun devicectl device install app --device "$DEVICE" "$APP"; then
  touch "$STAMP"
  exp=$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)
  date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s > "$INSTALLED_EXPIRY"
  echo "Installiert."
else
  echo "Installation fehlgeschlagen."
  exit 1
fi
