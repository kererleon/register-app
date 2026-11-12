#!/bin/zsh
# Builds Register Rust for the iPhone, signs it with the Apple ID from Xcode
# and installs it on the connected iPhone (cable or same Wi-Fi).
set -e
cd "$(dirname "$0")"
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.cargo/bin:/opt/homebrew/bin:$PATH"
# The team stays local (not in the repository).
cp ../../../ios/Flutter/Team.xcconfig Team.xcconfig
(cd ../.. && cargo build --release --target aarch64-apple-ios -p register)
xcodegen generate --quiet
UDID=$(xcrun devicectl list devices 2>/dev/null | grep -i physical | grep -oE "[0-9A-F]{8}-[0-9A-F]{16}" | head -1)
DEST="generic/platform=iOS"
[[ -n "$UDID" ]] && DEST="id=$UDID"
xcodebuild -project RegisterRust.xcodeproj -scheme RegisterRust -configuration Release \
  -destination "$DEST" -derivedDataPath build -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration build -quiet
APP=build/Build/Products/Release-iphoneos/RegisterRust.app
DEVICE=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -c '
import json, sys
for d in json.load(sys.stdin)["result"]["devices"]:
    if d.get("hardwareProperties", {}).get("reality") != "simulated": print(d["identifier"]); break')
xcrun devicectl device install app --device "$DEVICE" "$APP" | tail -2
