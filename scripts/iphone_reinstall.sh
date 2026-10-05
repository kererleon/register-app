#!/bin/zsh
# Re-signs and installs Register on the iPhone.
#
# Apps signed with a free Apple ID (Personal Team) stop working after 7 days.
# This script is run daily by launchd (see com.webandgrow.register.reinstall
# in ~/Library/LaunchAgents) and reinstalls the app when the last install is
# at least MIN_DAYS old. The iPhone must be reachable (cable or same Wi-Fi).
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

mkdir -p "$STATE_DIR"
exec >>"$LOG" 2>&1
echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==="

if [[ "${1:-}" != "--force" && -f "$STAMP" ]]; then
  age_days=$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 86400 ))
  if (( age_days < MIN_DAYS )); then
    echo "Letzte Installation vor $age_days Tagen, nichts zu tun."
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
# Flutter prepares the project; xcodebuild signs it. Only xcodebuild may
# create provisioning profiles and register the iPhone with the Apple ID,
# which free profiles need every week.
APP="build/ios_device/Build/Products/Release-iphoneos/Runner.app"
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
