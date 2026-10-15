#!/bin/bash
# TouchTrace (Tests/evidence/README.md): builds main.swift with swiftc into a scratch app for a real
# iPhone, signs it by hand with the team's wildcard development profile (4G96FT99AH.*), installs it
# and launches it. The owner then performs the script's gestures on the glass; pull.sh copies the
# JSONL back. Evidence only, never linked into Sill.
#
#   Tests/evidence/touchtrace/run.sh                 build, install and launch on the default iPhone
#   Tests/evidence/touchtrace/run.sh --build-only    build and sign only
#   SILL_EVIDENCE_DEVICE=<udid|name> ...             another device (default "iPhone Ivor"'s UDID)
#
# Needs Xcode (SILL_XCODE, default /Applications/Xcode.app/Contents/Developer), the "Apple Development: Ivor
# Padilla" identity in the keychain and the wildcard profile in Xcode's profile folder with the device
# in it. The app is .build/evidence/touchtrace/TouchTrace.app, bundle me.ivor.sill.touchtrace. The
# device must be unlocked to launch.
set -euo pipefail
# The shell may point DEVELOPER_DIR at the Command Line Tools, which have no iOS SDK or devicectl.
export DEVELOPER_DIR="${SILL_XCODE:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
device="${SILL_EVIDENCE_DEVICE:-00008140-000558A93C13001C}"
team=4G96FT99AH
bundle=me.ivor.sill.touchtrace
build_only=0
[ "${1:-}" = "--build-only" ] && build_only=1
out="$root/.build/evidence/touchtrace"
app="$out/TouchTrace.app"
rm -rf "$app"; mkdir -p "$app"

# The profile: the newest unexpired one for the team's wildcard app ID.
profile="$(python3 - "$team" <<'PY'
import glob, os, plistlib, subprocess, sys, datetime
team = sys.argv[1]
best = None
for f in glob.glob(os.path.expanduser("~/Library/Developer/Xcode/UserData/Provisioning Profiles/*.mobileprovision")) + \
         glob.glob(os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles/*.mobileprovision")):
    raw = subprocess.run(["security", "cms", "-D", "-i", f], capture_output=True).stdout
    if not raw: continue
    p = plistlib.loads(raw)
    if p.get("Entitlements", {}).get("application-identifier") != f"{team}.*": continue
    exp = p["ExpirationDate"].replace(tzinfo=None)
    if exp < datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None): continue
    if best is None or exp > best[0]: best = (exp, f)
print(best[1] if best else "")
PY
)"
[ -n "$profile" ] || { echo "touchtrace: no unexpired $team.* development profile in Xcode's profile folders" >&2; exit 1; }
# The signing identity: the profile's own certificate, by SHA-1.
identity="$(security cms -D -i "$profile" | python3 -c '
import hashlib, plistlib, sys
print(hashlib.sha1(plistlib.loads(sys.stdin.buffer.read())["DeveloperCertificates"][0]).hexdigest().upper())')"

xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -swift-version 5 -O -module-name TouchTrace \
    "$here/main.swift" -o "$app/TouchTrace"
cat > "$app/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchTrace</string>
<key>CFBundleIdentifier</key><string>$bundle</string>
<key>CFBundleName</key><string>TouchTrace</string>
<key>CFBundleDisplayName</key><string>TouchTrace</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
<key>MinimumOSVersion</key><string>17.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
<key>UIStatusBarHidden</key><true/>
<key>UIRequiresFullScreen</key><true/>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict/>
</dict>
<key>UIFileSharingEnabled</key><true/>
</dict></plist>
PLIST
cp "$profile" "$app/embedded.mobileprovision"
cat > "$out/entitlements.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>application-identifier</key><string>$team.$bundle</string>
<key>com.apple.developer.team-identifier</key><string>$team</string>
<key>get-task-allow</key><true/>
<key>keychain-access-groups</key><array><string>$team.$bundle</string></array>
</dict></plist>
PLIST
codesign --force --sign "$identity" --entitlements "$out/entitlements.plist" --timestamp=none "$app"
codesign --verify --strict "$app"
echo "touchtrace: built and signed $app (profile $(basename "$profile"))"
[ "$build_only" = 1 ] && exit 0

xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" --terminate-existing "$bundle"
echo "touchtrace: running on $device. Hold ▶ (top right) 1 s for the next gesture, ◀ (top left) to go back."
echo "touchtrace: then Tests/evidence/touchtrace/pull.sh"
