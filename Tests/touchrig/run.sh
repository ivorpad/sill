#!/bin/bash
# The touch rig (docs/trackpad-gestures-plan.md §9.2, H7): the app's real TrackpadView.swift and
# InputOverlay.swift, with TrackpadGestures.swift where the sources have it, compiled into a scratch
# app for the iOS simulator that drives both surfaces with synthesized touches (TouchSynth, private
# UIKit calls, test only) and logs what each would send the Mac. Nothing reaches the Mac: `send` and
# `sendGesture` only log. Never linked into the app.
#
#   Tests/touchrig/run.sh NAME                 the working tree's surfaces; the log is .build/touchrig/NAME.log
#   Tests/touchrig/run.sh --rev REV NAME       the surfaces as they are at REV (git show), for a baseline
#   Tests/touchrig/run.sh --switch off NAME    sendGesture answers false, as with the device's switch off
#   RIG_RELATIVE=1 Tests/touchrig/run.sh NAME  the overlay as landscape's picture (relativeDrag), its sprite logged
#   Tests/touchrig/compare.py BASE.log NEW.log [OFF.log]   H7's verdict
#   Tests/touchrig/run.sh --replay TRACE.jsonl [--rev REV] [--only G7,G13] [--fresh] NAME
#                                              a TouchTrace recording (Tests/evidence/touchtrace) replayed
#                                              into the overlay alone, gesture by gesture, on an iPhone
#   Tests/touchrig/compare_replay.py BASE.log NEW.log      two replays' events, gesture by gesture
#
# The replay keeps each recorded event (coalesced samples left out) as one UIEvent at its recorded
# time, with its touches' identities, phases and tap counts, scaled from the trace's view to the
# overlay, which fills the window. It logs what the overlay would send and every change of the
# picture's zoom (a stub display view; it never follows the Mac's pointer, there being no Mac).
# The zoom carries from gesture to gesture, as on the device; --fresh starts each on the fitted
# picture. RIG_VIDEO=WxH sets the video size (default: the overlay's shape at 3x, a picture that fills it).
# It runs on SILL_TOUCHRIG_SIM (default "Sill touchrig phone"), an iPhone 16 Pro Max on the newest
# iOS, made and deleted the same way. With no --rev, the overlay's sources' `git diff --stat` at
# build time goes next to the log (NAME.diffstat).
#
# It runs on a simulator of its own, named by SILL_TOUCHRIG_SIM (default "Sill touchrig"), made (an
# iPad Pro 11-inch (M5) on the newest iOS) when there is none and deleted afterwards only when this
# run made it. Never the shared iPad Pro 13", never `simctl io recordVideo`, no XCUITest. About 2.5 GB
# while the simulator exists. Limits: synthesized touches, not glass; iPadOS's own gestures and the
# editing overlay are out of its reach.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
rev="" switch=on name="" replay="" only="" fresh=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rev) rev="$2"; shift 2 ;;
        --switch) switch="$2"; shift 2 ;;
        --replay) replay="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"; shift 2 ;;
        --only) only="$2"; shift 2 ;;
        --fresh) fresh=1; shift ;;
        -*) echo "usage: Tests/touchrig/run.sh [--rev REV] [--switch on|off] [--replay TRACE.jsonl [--only G1,G2] [--fresh]] NAME" >&2; exit 2 ;;
        *) name="$1"; shift ;;
    esac
done
[ -n "$name" ] || { echo "usage: Tests/touchrig/run.sh [--rev REV] [--switch on|off] NAME" >&2; exit 2; }
out="$root/.build/touchrig"
work="$out/$name"
rm -rf "$work"; mkdir -p "$work/src" "$work/TouchRig.app"
if [ -z "$rev" ]; then
    { echo "HEAD $(git -C "$root" rev-parse --short HEAD), working tree at $(date -u +%FT%TZ)"
      git -C "$root" diff --stat -- iOSClient/ Sources/StreamProtocol/Input.swift; } > "$out/$name.diffstat"
fi

# The sources, from the working tree or REV. A file REV does not have is left out.
fetch() {
    if [ -z "$rev" ]; then
        [ -f "$root/$1" ] && cp "$root/$1" "$work/src/$(basename "$1")" || true
    else
        git -C "$root" show "$rev:$1" > "$work/src/$(basename "$1")" 2>/dev/null || rm -f "$work/src/$(basename "$1")"
    fi
}
for f in iOSClient/TrackpadView.swift iOSClient/InputOverlay.swift iOSClient/PointerPresence.swift \
         iOSClient/TrackpadGestures.swift iOSClient/KeyChords.swift iOSClient/PortraitStreamScreen.swift \
         iOSClient/PictureZoom.swift \
         Sources/StreamProtocol/Input.swift; do
    fetch "$f"
done
cd "$work/src"
# One module: StreamProtocol's Input.swift is compiled in, so its import goes.
sed -i '' '/^import StreamProtocol$/d' TrackpadView.swift InputOverlay.swift $(ls KeyChords.swift 2>/dev/null)
# HIDKey, the app's own, cut from PortraitStreamScreen.swift, with KeyModifiers where the sources keep
# it there (before KeyChords.swift, which the surfaces' shortcuts and hardware keys go through).
sed -n '/^\/\/ MARK: - Keys$/,/^\/\/ MARK: - Screen$/p' PortraitStreamScreen.swift > Keys.swift
rm PortraitStreamScreen.swift
flags=()
# The gestures when the surfaces have them (the stroke gate and `sendGesture`).
if grep -q "var sendGesture" TrackpadView.swift; then flags+=(-D GESTURES); fi
# Pinch to zoom when the overlay has it (the display view's `zoom`, PictureZoom.swift).
if grep -q "PictureZoom" InputOverlay.swift; then flags+=(-D ZOOM); fi
# Landscape's relative drag when the overlay has it (RIG_RELATIVE=1 turns it on).
if grep -q "var relativeDrag" InputOverlay.swift; then flags+=(-D RELATIVE); fi
cp "$here/Stubs.swift" "$here/main.swift" "$here/TouchSynth.h" "$here/TouchSynth.m" "$here/Bridging.h" .

target=arm64-apple-ios17.0-simulator
xcrun -sdk iphonesimulator clang -target $target -fobjc-arc -Wall -c TouchSynth.m -o TouchSynth.o
xcrun -sdk iphonesimulator swiftc -target $target -swift-version 5 -module-name TouchRig -Onone ${flags[@]+"${flags[@]}"} \
    -import-objc-header Bridging.h Stubs.swift Keys.swift Input.swift $(ls PointerPresence.swift TrackpadGestures.swift KeyChords.swift PictureZoom.swift 2>/dev/null) \
    TrackpadView.swift InputOverlay.swift main.swift TouchSynth.o -o "$work/TouchRig.app/TouchRig"
cat > "$work/TouchRig.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TouchRig</string>
<key>CFBundleIdentifier</key><string>me.saffer.sill.touchrig</string>
<key>CFBundleName</key><string>TouchRig</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/></dict>
<key>UIApplicationSupportsIndirectInputEvents</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST

# The replay's trace, prepared: per gesture, the events UIKit delivered, `dt` from the gesture's
# first. Every event lists every finger down, so a new event starts where a touch id repeats, or
# where a changed (not stationary) touch's time differs from the event's; a stationary touch keeps
# its last change's time. A touch whose first record in the gesture is not `began` is the trace
# app's hold button (its touch began on the excluded bar) and is left out.
if [ -n "$replay" ]; then
    python3 -I - "$replay" "$only" > "$work/TouchRig.app/replay.json" <<'PY'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
only = set(filter(None, sys.argv[2].split(",")))
sess = recs[0]
phases = {"began": 0, "moved": 1, "stationary": 2, "ended": 3, "cancelled": 4}
texts = {s["id"]: s["text"] for s in sess["script"]}
events = {}   # gesture → [[time, [(id, phase, x, y, taps)]], ...]
live, dropped = {}, {}   # gesture → touch ids replayed, and left out
for r in recs:
    if r["k"] != "touch" or r.get("coalesced"): continue
    g, i = r["g"], r["id"]
    if i not in live.setdefault(g, set()):
        if r["phase"] != "began":
            dropped.setdefault(g, set()).add(i); continue
        live[g].add(i)
    evs = events.setdefault(g, [])
    changed = r["phase"] != "stationary"
    if (not evs or any(t[0] == i for t in evs[-1][1])
            or (changed and evs[-1][0] is not None and abs(r["t"] - evs[-1][0]) > 5e-4)):
        evs.append([None, []])
    if changed and evs[-1][0] is None: evs[-1][0] = r["t"]
    evs[-1][1].append((i, phases[r["phase"]], r["x"], r["y"], r.get("taps", 1)))
for g, ids in dropped.items():
    print(f"touchrig: {g} leaves out touch {sorted(ids)} (began before the gesture: the hold button)", file=sys.stderr)
out = []
for s in sess["script"]:
    g = s["id"]
    if g not in events or (only and g not in only): continue
    evs = [e for e in events[g] if e[0] is not None]   # an event of stationary touches alone: nothing to deliver
    t0, last, rows = evs[0][0], -1.0, []
    for t, touches in evs:
        dt = max(t - t0, last + 1e-4)   # never out of order
        last = dt
        rows.append({"dt": round(dt, 5), "t": [list(x) for x in touches]})
    out.append({"g": g, "text": texts[g], "events": rows})
    print(f"touchrig: {g} {len(rows)} events over {last:.2f} s", file=sys.stderr)
json.dump({"viewW": sess["viewW"], "viewH": sess["viewH"], "gestures": out}, sys.stdout)
PY
fi
codesign -s - --force "$work/TouchRig.app" >/dev/null 2>&1

# The simulator.
devtype=com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB
sim="${SILL_TOUCHRIG_SIM:-Sill touchrig}"
if [ -n "$replay" ]; then
    devtype=com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max
    sim="${SILL_TOUCHRIG_SIM:-Sill touchrig phone}"
fi
udid="$(xcrun simctl list devices -j | python3 -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for d in devices:
        if d["name"] == name and d.get("isAvailable", True): print(d["udid"]); raise SystemExit
' "$sim")"
made=0
if [ -z "$udid" ]; then
    runtime="$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
print(sorted(ios, key=lambda r: [int(x) for x in r["version"].split(".")])[-1]["identifier"])')"
    udid="$(xcrun simctl create "$sim" "$devtype" "$runtime")"
    made=1
fi
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$work/TouchRig.app"
log="$out/$name.log"
SIMCTL_CHILD_RIG_REPLAY="${replay:+replay.json}" SIMCTL_CHILD_RIG_REPLAY_FRESH="$fresh" SIMCTL_CHILD_RIG_VIDEO="${RIG_VIDEO:-}" SIMCTL_CHILD_RIG_SWITCH="$switch" SIMCTL_CHILD_RIG_RELATIVE="${RIG_RELATIVE:-}" perl -e 'alarm shift; exec @ARGV' 600 \
    xcrun simctl launch --console-pty --terminate-running-process "$udid" me.saffer.sill.touchrig > "$log" 2>&1 || true
xcrun simctl uninstall "$udid" me.saffer.sill.touchrig || true
if [ "$made" = 1 ]; then xcrun simctl shutdown "$udid" || true; xcrun simctl delete "$udid" || true; fi
grep -q '^RIG done' "$log" || { echo "touchrig: the run did not finish; see $log" >&2; exit 1; }
echo "touchrig: $(grep -c '^===' "$log") scenarios, the log is $log"
