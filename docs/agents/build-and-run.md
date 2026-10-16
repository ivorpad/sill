# Build and run

```
swift build -c release
swift run -c release SillHost              # nothing streams until the iOS app picks a window
swift run -c release SillHost Safari       # optional: preselect a matching window
swift run -c release SillHost --synthetic  # Desktop streams a test pattern; no Screen Recording needed
swift run -c release SillHost --encoder-selftest   # is the hardware encoder alive? 5 s, exits
swift run -c release SillHost --virtual-display   # picked windows stream from their own HiDPI display (off by default)
swift run -c release SillHost --virtual-display-selftest   # create/destroy one display, report what sees it
swift run -c release SillHost --direct-wireless   # also over peer-to-peer Wi-Fi (AWDL): devices without a shared network (off by default)
swift run -c release SillHost --remote      # the remote door for this run on any free port (--remote=PORT), a throwaway identity; the code and link print here
swift run -c release SillHost --remote --internet   # also admit paired devices from outside this Mac's networks and VPNs
swift run -c release SillHost --print-reachability  # the addresses a device would get away from home, then exit
swift run -c release SillHost --pairing     # the home door speaks TLS, pairing required, a throwaway identity; the code and link print here (with --remote, one pairing for both doors)
swift run -c release SillHost --print-cable # what the cable rule reads on each interface, and whether the console is unlocked; read-only, then exit
swift run -c release SillHost --pairing --unlock   # a paired device may type this Mac's password or PIN into its lock screen (kind 44), as Settings › General's Unlock from devices lets it; --unlock-away adds devices away from home (only through --remote; exits 2 without --unlock), --no-lock-again keeps the Mac unlocked after the device that unlocked it leaves; the plain door never offers unlocking, so --unlock alone only prints a notice; without --synthetic it types into this Mac's real lock screen, so a test always has it
swift run -c release SillHost --menu-selftest=TextEdit   # the menus a device would be sent for that app (a pid, or the start of its name), read once; read-only
python3 Scripts/sillclient.py PORT 5 none --pair-ask --then-code=$T/code --identity=$T/a   # a device's ask at a TLS home door, then the code the host printed (saved in $T/code)
python3 Scripts/sillclient.py PORT 8 desktop --set=bitrate=25000000@3 --expect=bitrate=25000000   # a device's settings change
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # a scripted pointer on the test pattern, on 127.0.0.1 alone, never the hardware encoder
python3 Scripts/sillclient.py PORT 6 desktop --pointer --move=0.25,0.25@3   # each kind 26 as it arrives; input goes only to a --synthetic host
SILL_TEST_INPUT_LOG=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_POINTER_PATH=$T/path .build/release/SillHost --synthetic   # prints each event a dry run would post ("Test input: key 49 up (none)")
python3 Scripts/sillclient.py PORT 3 desktop --input='{"key":{"hidUsage":44,"down":true,"modifiers":1048576}}@1' --input='{"key":{"hidUsage":44,"down":false,"modifiers":1048576}}@1.05' --tap=0.5,0.5@1.5   # an older device's Spotlight key, then a tap
python3 Scripts/sillclient.py PORT 8 none --gesture=swipeUp@3 --gesture=swipeDown@4   # a synthetic host logs "Gesture from …: swipe up → Mission Control (shortcut 108: key 160, fn) (not posted: a test host)"
SILL_TEST_LOOPBACK=1 SILL_TEST_HOTKEYS='108=off,173=off' .build/release/SillHost --synthetic   # TEST ONLY: the gestures read this table (over macOS 27's own; `defaults` alone) instead of this Mac's shortcuts
SILL_TEST_REMOTE_DIR=$T/mac SILL_TEST_NO_ROUTER=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_LOOPBACK=1 SILL_TEST_SERVICE_TYPE=_silltest._tcp .build/release/SillHost --synthetic --pairing --unlock   # a test host with a simulated lock state (unlocked; SILL_TEST_LOCKED=1 starts it locked) whose unlock types nothing; its printed link names port 7455, Sill.app's own: the host's real port is in lsof
python3 Scripts/sillclient.py PORT 14 desktop --pair-code=CODE --identity=$T/a --lock@3 --unlock=TESTSECRET@6 --lock@10   # PORT: lsof -nP -iTCP -sTCP:LISTEN -a -p <pid>; a lock, a dry unlock and a lock again; prints "lock: locked=password lockScreen=1 unlock=True" (locked=- while unlocked) at each change of the window list's three fields and "lockScreen ← token=N outcome=…" for each answer
SILL_TEST_REMOTE_DIR=$T/mac SILL_TEST_NO_ROUTER=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_LOOPBACK=1 SILL_TEST_ORIGIN=vpn .build/release/SillHost --synthetic --remote --unlock   # the away form: pair with --pair-code at the remote door's port ("Remote access: listening on port N") and run the same client; without --unlock-away the list says unlock=- and an unlock is answered refused
SILL_TOUCHRIG_SIM='Sill touchrig' Tests/touchrig/run.sh new && Tests/touchrig/run.sh --rev origin/main base && Tests/touchrig/compare.py .build/touchrig/base.log .build/touchrig/new.log   # the surfaces under synthesized touches
Tests/checks/run-all.sh                 # every pure check, as CI runs them (~5 min; --mutants adds the mutants, well over an hour)
Scripts/pacing/run.sh                   # remote pacing and the link's judge, this tree against origin/main, no encoder, all on loopback (~25 min; --full ~45; --list)
SILL_TEST_LOOPBACK=1 SILL_TEST_SOFTWARE_ENCODER=1 SILL_TEST_NO_ROUTER=1 SILL_TEST_ORIGIN=vpn SILL_TEST_PATTERN=noise .build/release/SillHost --synthetic --remote   # an away session whose stream follows its quality
Scripts/make-app.sh                     # .build/Sill.app, signed with the Apple Development identity (~2 s unchanged)
Scripts/make-app.sh --install --open    # Noah: replace /Applications/Sill.app (a running one quits first), launch it
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' Scripts/make-app.sh --release   # M6
SILL_SIGN_IDENTITY='Developer ID Application: … (9B2KKVM937)' SILL_NOTARY_PROFILE=sill-notary Scripts/release.sh [--dry-run]   # M6: the notarized download (docs/release-checklist.md)
Scripts/release-ios.sh                  # the iOS app for App Store Connect: archive, export .build/ios/export/Sill.ipa, check it; uploads nothing
Scripts/release-ios.sh --bump --upload  # Noah: the next build to TestFlight (docs/release-checklist.md, TestFlight; --privacy-report, --print-version)
Scripts/make-dmg.sh --sign - .build/Sill.app .build/Sill.dmg   # the download's disk image of any build, ad hoc (release.sh makes the real one)
python3 -m http.server 8000 --directory site   # the website at http://localhost:8000
Scripts/encoder-check/run.sh            # the encoder checks that never touch an encoder (safe while Sill.app streams)
Scripts/menu-check/run.sh               # the menus' reader and mirror against Scripts/menufixture.swift, no host, no encoder (needs Accessibility)
Tests/duorig/run.sh UDID pose book && Tests/duorig/run.sh UDID shot book book.png   # TEST ONLY: fold and photograph an iPhone Duo simulator (laptop, flat-portrait, flat-landscape, closed-upright, closed-side)
SILL_TEST_ENCODER_RECYCLE=0 swift run -c release SillHost   # =0 keeps every hardware session, =1 replaces one in the slow state, as by default (A/B on the real Desktop: --synthetic moves every frame and never reaches the slow state)
Scripts/encoder-check/verify-hardware.sh harness   # USES THE HARDWARE ENCODER; skips each run while a device is connected
```
Needs Xcode as the active developer directory with its license accepted; with
Command Line Tools only, add `--build-system native`.
First run prompts for Screen Recording: the CLI's belongs to Terminal (or
whatever launched it), Sill.app's to Sill itself.
Sill.app: the log is `~/Library/Logs/Sill/Sill.log` (`tail -F`, not `-f`: at
10 MB it moves to Sill.1.log; Show Log… in the menu); settings are `defaults
read me.saffer.sill.mac` (maxFPS, captureScale, bitrate, prioritizeSpeed,
virtualDisplay, directWireless, updateCheck; the unlock switches keep
unlockFromDevices and unlockAway (off) and lockAgain (on); the update check keeps
updateLastCheck, updateETag, updateLatestTag and updateLatestURL), and a launch
argument such as `-maxFPS 60` or `-updateCheck 0` overrides one for one run. A device's change from its Settings panel is saved there too, like a
menu click; the CLI keeps a device's change until SillHost quits. Test arguments for the bare binary (`.build/release/SillMenuBar`,
defaults domain `SillMenuBar`; delete it after): `--synthetic` (test pattern,
off Bonjour; the port is in the "Status: Test Pattern Mode" line),
`-SillLogFile <path>`, `-SillSetAfter '<s> key=value[,key=value][; <s> …]'`
(unlockFromDevices, unlockAway and lockAgain among its keys),
`-SillQuitAfter <s>`, `-SillRenderPreviews <dir>` (panes, cards, glyphs,
menu.txt; no permission needed). The update check, in the bare binary (which
has no version and never checks without these) and the app: `-SillUpdateFeed
http://127.0.0.1:P/latest` (a feed on this Mac only: 127.0.0.1, ::1 or
localhost; `Scripts/sillfeed.py P` serves one; test pattern mode checks only
such a feed), `-SillUpdateVersion 0.3.0`, `-SillUpdateNow 1` (one check at
start, as Check Now), `-SillUpdateInterval <s>` (24 h become s seconds, the
retry s/24), `-SillPrintMenuAfter <s>` (the status menu as it would open, and
Settings › General's update line, in the log), `-SillSetAfter '<s>
updateCheck=0'`. Never run a test against GitHub. To make Sill.app check again at
its next launch: `for k in updateLastCheck updateETag updateLatestTag
updateLatestURL; do defaults delete me.saffer.sill.mac $k; done`. Render previews from
`.build/Sill.app/Contents/MacOS/Sill` to see what Sill.app looks like: only the
bundle's copy records the real SDK (make-app.sh sets it with vtool; see Current
step), and the bare binary draws the pre-26 look. `--encoder-selftest` and
`--virtual-display-selftest` work in the app too.
iOS side: open `iOSClient/Sill.xcodeproj`, set your team, run on a real
device on the same Wi-Fi (or with the Mac's Direct Wireless Connection on).
AWDL, headless and without touching a running Sill.app: the synthetic hosts do
not advertise, but `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers them as
"Sill test ‹pid›" under that test type (never `_sill._tcp`, so no device sees
them) with the listener's own peer-to-peer flag, and prints which one it got;
`SILL_TEST_SWAP_FAIL=port|all` makes a replacement's same-port (and any-port)
bind fail; `SILL_TEST_PEER_TO_PEER_INTERFACE=en0` counts a client scoped to that
interface as one on peer-to-peer Wi-Fi, so a test client on the Mac's own en0
link-local address (`ifconfig en0`, `fe80::…%en0`; Python's socket takes it)
stands in for a device on awdl0 when Direct Wireless turns off (a local
connection to the Mac's own awdl0 address never became ready, so awdl0 cannot
be tested headless); all three are honoured only by a host that does not
advertise. `dns-sd -t 3 -includeAWDL -B _silltest._tcp local` lists a
registration that includes AWDL a second time on awdl0's index (`python3 -c
'import socket; print(socket.if_nametoindex("awdl0"))'`, 16 here). dns-sd
options go before the command: `dns-sd -R … -includeAWDL` registers a TXT
record "-includeAWDL" and sets no flag. The kernel's count of AWDL services:
`/usr/bin/log show --last 1m --style compact --predicate 'process == "kernel"
AND eventMessage CONTAINS "BonJourTrig"'` ("ValidSvc N" once a second; a
registration with AWDL adds 2, a peer-to-peer browse 1); `log` is a zsh
builtin, hence `/usr/bin/log`, and `process == "kernel"` keeps the log tool's
own line out. Enable and disable lines ("Enabling AWDL due to Mdns") show only
when nothing else holds AWDL. Keep AWDL-on tests under 20 s and on test types.
Remote access, headless: TEST ONLY variables, honoured only by a host that
does not advertise: `SILL_TEST_REMOTE_DIR=<dir>` (the identity and trust list
in a 0700 directory instead of memory or the keychain; the bare app's
`-SillPairAfter <s>` leaves `pairing.url` and `pairing.code` there, 0600, never
printed), `SILL_TEST_PAIRING_TTL=<s>`, `SILL_TEST_BACKOFF_SECONDS=<s>`,
`SILL_TEST_ORIGIN=vpn|internet` (loopback counts as that origin),
`SILL_TEST_REMOTE_ORIGIN=vpn|internet` (the same at the remote door alone, so
one loopback host serves a device away and one at home: away from home's
H8 and S4) and `SILL_TEST_NO_ROUTER=1` (never ask the router; set it on every
headless host). Away from home and the link, headless (docs/remote-bundle-
plan.md, PR B): `SILL_TEST_PATTERN=picture:<path>` gives a synthetic host a
still picture for its Desktop (any image ImageIO reads, filling the frame:
photographs of a device, docs/iphone-duo-plan.md); `SILL_TEST_PATTERN=noise`
gives it a square of noise, so its stream follows the quality (on the software encoder about 14
frames a second, 3.6 Mbit/s at Low and 10.6 at Balanced), for a test of the
link through `sillrelay.py --rate-mbps 5`; `sillclient.py` prints `away=` and
`link=` on each kind 16, and `--expect` knows `awayBitrate`,
`awayCaptureScale`, `homeBitrate`, `homeCaptureScale`, `thisConnectionAway`,
`awayRunning` and `linkState`.
The Mac's pointer, headless: every synthetic host is a dry run (its input is
counted as `in.dry`, never posted, and activates or raises nothing) and never
reads the real pointer. TEST ONLY, honoured only by a synthetic host (anywhere else one
line says it is ignored): `SILL_TEST_POINTER_PATH=<file>` is a scripted
pointer on the test pattern, lines `T X Y` (seconds since the stream's first
sample, points in the 1512×949 pattern, outside allowed; `#` comments; at most
10,000 steps and 1 MiB, a bad file refused whole with one line): the test
pattern then has a pointer, a test client's input lands in the pattern's space
and a dry-run pointer event moves the scripted pointer (the newer of it and a
step wins); `SILL_TEST_SOFTWARE_ENCODER=1` starts on the software encoder, with
no launch probe and no re-check, so a test never touches the hardware encoder
(60 fps at most: a 120 fps sampler test needs the hardware, and so the
no-device check); `SILL_TEST_INPUT_LOG=1` prints each event the dry run would
post, "Test input: key 49 down (command)" with the flags it was made with, and
a pointer or scroll event with those the last keyboard event would have left
in the HID state table, a button's with where it goes ("Test input: left mouse
down (none) at 756,474"), and each check a key's up arms ("Test input: key 55
up: the table read again in 0.25 s for command"): what a device's keys and
buttons leave for its next click (KeyStrokes), without posting anything.
The device floor, headless: `SILL_TEST_MIN_DEVICE_VERSION=1.2` raises the floor
of a host that does not advertise (a device below it, or one that sends no
hello, gets kind 22 "update" and is closed; a value that does not parse is
ignored with one line), and `SILL_TEST_GOODBYE='<JSON Goodbye>'` makes its
refusals send that payload instead (a reason the device does not know).
Pairing at home, headless: `SillHost --synthetic --pairing` (the bare app's
home door always speaks TLS, as Sill.app's does) with `SILL_TEST_REMOTE_DIR`,
`SILL_TEST_NO_ROUTER=1`, `SILL_TEST_SOFTWARE_ENCODER=1` and
`SILL_TEST_LOOPBACK=1`; the CLI prints its code and link, and again after each
ask. The door and pairing hooks are TEST ONLY and honoured only by a test host
(DoorPolicy.isTestHost: one that does not advertise and is not Sill.app's own
executable; anywhere else TestHooks prints one "ignored" line for each set),
and so are the ones above (SILL_TEST_SERVICE_TYPE and the rest):
`SILL_TEST_CABLE_INTERFACE=<if>` counts a client scoped to that interface as
one on the cable to an "iPad" (serial TEST) and lets this Mac's own address
there through, so a client at this Mac's link-local address on it
(`sillclient.py --host=fe80::…%<if> --pair-ask=cable`) stands in for a device
on the cable, and the simulator's `-SillCableTest 1` for the device's side
(lo0's `fe80::1%lo0` keeps such a test on this Mac; it needs a listener there,
which SILL_TEST_LOOPBACK's 127.0.0.1 alone is not); `SILL_TEST_LOCKED=1` makes
the Mac locked (a test host never reads the real console: its lock state is
simulated, unlocked without this, and a dry unlock or lock, below, flips it);
`SILL_TEST_ASK_QUIET=<s>` shortens the 10 minutes of quiet
after the Mac's Cancel or a stop; `SILL_TEST_ASK_FROM_THIS_MAC=1` skips the
ask rule's step for an ask from this Mac itself (answered `openOnMac` unless a
window is open, and lighting no menu item), so a test client on this Mac opens
windows. The bare app takes `-requirePairing NO`, `-SillSetAfter '<s>
requirePairing=0|1'`, `-SillCancelPairingAfter '<s>[; <s> …]'` (the window
closed as its Cancel does), `-SillCableNoticeAfter <s>` (the cable notice for
a sample device) and `-SillMenuAfter '<s>[; <s> …]'` (the status menu in the
log, line by line). Sill.app itself ignores every `-Sill…After` hook,
`-requirePairing` and `SILL_TEST_REMOTE_DIR` with one line each (any process
can start it with arguments and its grants); `-SillRenderPreviews`,
`-SillLogFile` and the encoder's variables still work there. Require pairing
and the trust list live in the login keychain (service
`me.saffer.sill.remote`, accounts `paired-devices` and `require-pairing`,
beside the key "Sill Remote Access"), never in UserDefaults; Settings ›
Devices' Remove forgets one device, and deleting those items makes this Mac
new to every device.
Locking and unlocking the Mac, headless (kind 44, docs/lock-screen-plan.md):
`SillHost --synthetic --pairing --unlock`, or `--remote --unlock` with
`SILL_TEST_ORIGIN=vpn` for a device away from home (which `--unlock-away` also
lets in), with the variables of pairing at home. These are TEST ONLY, honoured
only by a test host (DoorPolicy.isTestHost; anywhere else TestHooks prints one
"ignored" line for each set), and each one set prints a "TEST: …" line at start,
or says why it is ignored. A test host's console is simulated, so the window
list's `locked`, the pairing ask and every read follow one state: unlocked or,
with `SILL_TEST_LOCKED=1`, locked. `SILL_TEST_LOCK_ASK=pin|password` is what the
lock screen asks for (without it this Mac's own smart-card tokens decide: a PIV
card in says pin), `SILL_TEST_UNLOCK_OUTCOME=unlocked|stillLocked` what a dry
unlock attempt ends with (unlocked by default, which flips the simulated state;
stillLocked leaves it locked and counts a failure: an attempt within 5 s of one
is refused, and with pin so is every one after two in a row),
`SILL_TEST_UNLOCK_SECONDS=N` makes a dry attempt take N seconds, as a real one
takes time, so a second request or key input can arrive while it is in flight,
`SILL_TEST_LOCK_AGAIN_SECONDS=N` replaces lock again's 30 s, and
`SILL_TEST_MAC_IDLE=N` says this Mac's own keyboard and mouse were last used N
seconds ago (a dry host does not read this Mac's HID idle time, whose user is
typing the test's commands; 0 is just now, and without it the Mac was not
used). A dry unlock or lock types and posts nothing; an unlock that ends
unlocked, or a lock of an unlocked Mac, flips the simulated state. It counts
`in.dry` once for an unlock attempt, never for each character, so no stats line
shows a secret's length, and twice for a lock of an unlocked Mac (the two events
of ⌃⌘Q, logged as any chord's; no `in.gesture`); `SILL_TEST_INPUT_LOG=1` prints
"Test input: an unlock attempt (not posted: a test host)" for the attempt and
never its keys, whose codes would spell the secret. No stat of any host depends
on the secret: a real attempt counts `in.userActive` once and its answer, never
`in.text` or `in.key`. Every answer counts `lock.unlocked`, `lock.stillLocked`,
`lock.refused`, `lock.locked` or `lock.notLocked` (a Mac found already unlocked
counts `lock.unlocked`, and lock again's own lock counts too), and key, text and
gesture input from any connection, dropped while an attempt types, counts
`in.unlockDrop` (the up of a key the Mac already has down still goes). The log
has a line for each request and never the secret, its length or its keys:
"Unlock: ‹device› ‹route›: still locked", "Lock: …: locked", "Unlock: …: refused
(‹why›)", and lock again's "Lock again: ‹device› left 30 s ago: locked" or "…:
this Mac was used since, so it stays unlocked". The notification for an unlock
from a device is Sill.app's (UnlockNotice): the bare binary and SillHost only
log. `sillclient.py`'s `--unlock=SECRET@T` and `--lock@T` send kind 44 (tokens
shared with `--set`'s, 1, 2, 3…; the secret is split on the last @, and `\n`,
`\t`, `\xHH` and `\uXXXX` are decoded, so a test can send one the host must
refuse; use a made-up secret, since ps shows the command line). They go only to
a `--synthetic` host on this Mac (127.0.0.1, ::1 or localhost, and lsof and ps
on PORT), as input does, and exit 2 otherwise; the secret is never printed, and
an error names a flag without its value. Each answer prints as "lockScreen ← token=3
outcome=stillLocked message=- at 8.412s" (the message in JSON quotes, - for
none), and the window list's three fields as "lock: locked=password
lockScreen=1 unlock=True at 1.234s", with the first list and at each change (-
for a field the host left out). The live test on a real Mac is its owner's, never
an agent's (docs/agents/standing-rules.md): docs/lock-screen-plan.md's P0
probes, each of which locks this Mac or types into its lock screen.
The Mac's menus, headless: `swiftc -O Scripts/menufixture.swift -o
$T/menufixture -framework AppKit`, then `$T/menufixture serve $T/fixture.log
60` (it exits by itself, 120 s at most, and can never take the front) and a
synthetic host with `SILL_TEST_MENU_PID=<its pid>` (honoured only by a host
that does not advertise; "Test menus: …" at start): the test pattern's menus
are then the fixture's, read and pressed without activating it. `python3
Scripts/sillclient.py PORT 20 desktop --menus --fetch=4@3 --press=4.0@5` (with
SILL_TEST_MENU_PID in the client's environment too) prints each kind 24 on a
line, and `$T/menufixture label PID` what the last press set ("A"); `kill
-HUP` inserts an item at the top of Probe in place (the ids below it move: the
host's next read of a moved place moves the version), `-ALRM` gives Probe a
new menu, and `-USR1`/`-USR2` give Probe › Rebuilt one.
`--menu-selftest=menufixture` reads it. Presses go only to the fixture, and a
real app's menus are read only with `--menu-selftest=TextEdit`, never a bare
`--menu-selftest` (the frontmost app); the plan's §10 has the gates.
The bare app takes `-remoteAccess 1 -remotePort P`, `-SillSetAfter '3
remotePort=P2'`, `-SillPairAfter <s>` and `-SillUnpairAfter <s>`; its
`-SillRenderPreviews` adds the Remote Access pane's states and the pairing
window's. A session through a shaped link: `python3 Scripts/sillrelay.py
--listen 0 --to 127.0.0.1:P --delay-ms 150 --rate-mbps 2`, then
`sillclient.py RELAYPORT 90 desktop --tls --identity=$T/a --stats` after
`--pair-url=URL` once. Never let a test binary take a connection from another
machine: the Application Firewall prompts. `SILL_TEST_LOOPBACK=1`, honoured only
by a host that does not advertise, makes both doors of a test host listen on
127.0.0.1 alone ("Test listener: loopback only …"; `lsof` lists
`127.0.0.1:PORT`); a device on this Mac, the simulator included, and the test
clients reach it by 127.0.0.1. Reset the app's remote settings with
`for k in remoteAccess remotePort internetAccess remoteAddressName
remoteDevicesSeen; do defaults delete me.saffer.sill.mac $k; done`.
Debug harness (simulator; the iPhone Duo's from the iOS 27.1 runtime, folded
by Tests/duorig): launch arguments `-SillLayout 951x669` (inner landscape) /
`669x951` / `466x678` / `678x466` (the cover), each with the safe area its
display gives Sill, the status bar's strip included but on the stream screen
upright with `-SillHinge half` or `flat` (`-SillSafeArea T,L,B,R` sets
another; the first guesses, `1000x710` / `710x1000` / `500x710` / `710x500`,
have none), `-SillHinge
closed|half|flat` (the hinge and a 40 pt fold across the middle of the longer
side; without it the harness knows no hinge, even on the Duo's simulator),
`-SillLive 1` (real client inside the frame), `-SillDrawer 1`,
`-SillActive none|desktop|<windowID>` (mock), `-SillHUD 1` (diagnostics overlay),
`-SillSettings 1` (the Settings panel open), `-SillArrows 1` (a phone upright:
the arrows cross open; with `-SillKeyboard 1` where it goes with the keyboard
up), `-SillMacMenu
code|blender|long|stale|noaccess|none|slow|timeout|refuse` (the mock Mac's
menus; `code` by default, VS Code's ten), `-SillMenusOpen 1` (the Menus
pull-down opens after launch) or `-SillMenusOpen 'File/Open Recent'` (opens
on that menu, each level fetched on the way), `-SillMenuPress 'File/Save'`
(chooses that item once the menus are in; both live too, but only on the test
app's menus through a test host: `-SillConnect` to a loopback address, no host
version, menufixture's top level; anything else prints "refused"),
`-SillMenusAt <s>` and `-SillMenusCloseAfter <s>` (when the pull-down opens,
and closes after it), and on an iPad `-SillMenuBarLayout perMenu|replace|one`,
`-SillMenuDump 1` (the main menu's root after each build, on the console),
`-SillMenuBuildTwice 1` and `-SillMenuNoView 1` (the insertion's guards),
`-SillSecondWindow 1` (a second window 2 s after launch: the bar then gets
none of the Mac's menus; the console's "menus: …" and "menubar: …" lines say
what happened), `-SillSettingsCase
default|cli|software|custom|vdproblem|vdstream|legacy|pending|timeout|direct|
directlink|nodirect|wired|noroute` (the mock Mac's settings; it answers a pick
after 0.35 s; the readout's route is Wi-Fi except `directlink` Direct, `wired`
Wired, `noroute` none, and `remote`, `remoteinternet` and `remoteslow` none,
where the route line says how), away from home's and the link's settings cases
`away|awaymixed|awayhome|linkbehind|linkmixed|linklow|linkstalled` (the header's
away line, the footnote, the callout; `linkstalled` shows none) and
`-SillLinkLine behind` (the mock reports the link behind: the stream's line),
`-SillSettingsScript '<t> set K=V[,K=V] | suggestion; …'` (a live session to a
synthetic host on loopback: the panel's controls and the link callout's button,
t seconds after the first window list), `-SillMoveHomeTest to:HOST:PORT|refused|
other:PORT` (with `-SillDialSaved 1`: the saved Mac listed as a network row a
second into the remote session at a door that speaks TLS, so the move home
runs against a synthetic `--remote --pairing` host with SILL_TEST_REMOTE_ORIGIN
and SILL_TEST_REMOTE_DIR, dialed pinned to the saved Mac's key), `-SillDialSaved
remotely` (as Connect Remotely: never moves home),
`-SillConnectCase looking|hint|nearby|methods|denied|update|notice` (the connect screen in a discovery
state; `methods` has a row ending in each word, none, and long names; `update` a
Mac's refusal with "Update Sill in the App Store" when `-SillAppStoreURL
https://apps.apple.com/app/id000000000` gives it an address, `notice` a goodbye
reason the device does not know; the mock never browses) and remote access's `remote|addmac|addcode|addcodeerror|
pairing|remotedial|remotefail|camera|externalpair` (`-SillRemoteFailure
vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|
remoteoff` picks remotefail's words), the settings cases `remote|remoteinternet|
remoteslow|remotepair|remoteoff|noremote`, `-SillSettingsEnd 1` (the panel
scrolled to its end), `-SillSettingsScroll gestures|lock` (the panel scrolled to
its This iPad group, or to the Lock Screen group above it; the mock Mac takes
gestures in every case but `legacy`),
`-Sill.trackpadGestures 0` (the device's Three-Finger Gestures off for one run,
in the normal app too), `-Sill.capsLockEscape 1` (an iPad's Caps Lock as Escape
on for one run; with `-SillSettings 1 -SillSettingsEnd 1` the panel shows its
switch), `-Sill.keyboardAlwaysOn 1` (Keyboard Always On for one run; the console
says "keyboard: Keyboard Always On, the stream takes the keyboard" each time it
does; a simulator's GCKeyboard is there even when its on-screen keyboard shows), `-SillVoiceOver 1` (that group as with VoiceOver on:
its footnote says the rows do the gestures), `-SillScanOverlay 1` (Pair This
iPad…'s overlay; `-SillOverlayLine asking|shown|openonmac|locked|noanswer` the
line its ask's answer sets; under `-SillLive 1` it opens over the live session
and asks), locking and unlocking the Mac in the mock (docs/lock-screen-plan.md;
LockedCard, StreamClient+LockScreen): `-SillLocked password|pin` (the mock Mac
is locked: its window list says what its lock screen asks for, any other word
reads as locked with the field "Password or PIN", and the locked card covers the
stream, the panel and the stream's keyboard put away), `-SillUnlock 1` (its list
says this connection may unlock: the card has the field and Unlock, else it says
to unlock at the Mac), `-SillLockCardHidden 1` (starts with the card hidden for
this lock, so the Settings panel's Unlock row shows, with `-SillSettings 1`;
unlocked, the panel has "Lock Mac mini": every settings case but `legacy` takes
kind 44's "lock"), `-SillLockOutcome
stillLocked|refused|unlocked|notLocked|locked|silent` (what the mock answers
0.4 s after a request: to an unlock `stillLocked` (the default), `refused` or
`unlocked`, which unlocks the mock; to a lock `locked` (the default: the mock
locks), `notLocked` or `refused`; `silent` is never answered, and the card says
so after 15 s, the panel's row after 7), `-SillLockFocus 1` (the card's field
has the keyboard as the card shows, for a photo of it above the keyboard),
`-SillUnlockAfter <s>` and `-SillLockAfter <s>` (stand-ins for a finger: s
seconds after the card shows, a made-up string goes into its field and a second
later Unlock is pressed; s seconds after the Settings panel shows, its Lock
Screen row is pressed, Lock Mac mini or, while locked, Unlock Mac mini…; each
once per launch, and only in the mock or against a synthetic host on this Mac's
loopback, `-SillConnect` with InputScript's guard, never against Sill.app or a
real Mac, whose lock screen they would type into; the console says "lock
screen: …" at each step and never a password, its length or its characters),
the password kept for Face ID (decision 3; SavedUnlock): `-SillRemember 1`
(with `-SillUnlockAfter`, the stand-in also turns on "Use Face ID next time"
where the card has it), `-SillFaceIDAfter <s>` (s seconds after the card shows,
a stand-in for a tap on "Unlock with Face ID", under the same guard; the Face ID
that follows is the simulator's: enrol with `xcrun simctl spawn UDID notifyutil
-s com.apple.BiometricKit.enrollmentChanged 1` and then `-p` of the same name,
and answer with `notifyutil -p com.apple.BiometricKit_Sim.pearl.match` or
`.pearl.nomatch`; no permission alert showed on iOS 27.0's simulator), and for
photos `-SillBiometry faceID|touchID|opticID|none` (the device's biometry as
given) and `-SillLockSaved 1` (a password counts as kept, nothing read). The
simulator's keychain stores the item's access control but never enforces it, so
there only the `evaluatePolicy` before the read is the gate (measured
2026-10-16: the read alone returned the item with no Face ID evaluated); the
item's own `.biometryCurrentSet` is proved on a device only. For an end to end
run, pair a private simulator by code with a `--pairing --remote=PORT --unlock
--unlock-away` synthetic host (`-SillPairCode <digits> -SillPairAddress
127.0.0.1:PORT`): a `--pairing` host alone prints 7455, Sill.app's remote port,
in its link, so a remote dial after pairing could go there. The device's DEBUG
console prints a remote dial's candidates, this Mac's own addresses among them.
pairing at home's connect cases `homerows|homeasking|homecard|homecode|
homecodeerror|homelocked|homeopenonmac|homerevoked|homecabledone|homeolder|
pairingrequired` and settings cases `paired|pairedoff|openpair`,
`-SillPointer mac@X,Y|device@X,Y|hidden|pencil@X,Y` (the pointer sprite in one
of docs/pointer-visibility-plan.md's states over the mock's frame, which it
draws as a dim rectangle; `-SillPencilPointer 1` is Q2's flip), and in
the normal app and under `-SillLive 1` `-SillPairURL '<sill://pair…>'` (pair
at launch, no confirmation, at the link's own addresses only: a confirmed link
tries the home rows first, which `-SillTapRow` and `-SillHomeLink` below reach),
`-SillPairCode <12 digits> -SillPairAddress host:port`,
`-SillDialSaved 1`, `-SillForgetMacs 1`, `-Sill.savedMacs '<JSON>'` (one run;
`'[]'` empties), `-SillRemoteRoute vpn|internet` (a loopback session counts as
that route), `-SillHelloVersion <v>` (the version the hello gives, against a
host's floor), `-SillScreenFPS 120` (a 120 Hz screen) and `-SillDeviceKeySE 1`
(a Secure Enclave device key, R0-a); for pairing at home (the normal app and
`-SillLive 1`), `-SillServiceType _silltest._tcp` (the browsers look for the
test type, so a test host registered with SILL_TEST_SERVICE_TYPE is a real
row with its TXT record and no real Mac is; only the Debug build's
Info-Debug.plist declares it), `-SillHomeDoor paired|open|plain` (what a
`-SillConnect` address counts as, since an address has no TXT record:
`plain`, the default, dials it plainly as before; `paired` pins the one saved
Mac, else asks; `open` an open door), `-SillCableTest 1` (this device's path
counts as the cable), `-SillForgetHomeTLS 1` (forget which Macs were seen over
TLS, to dial another branch's older Sill.app plainly), `-SillTapRow <name
prefix>` (tap that row once it is listed), `-SillHomeCode <digits>` and
`-SillHomeLink <sill://pair…>` (the home card's code or scan once the Mac
answers `shown`), `-SillOverlayCode <digits>` (Pair This iPad…'s ask, then
that code, on a TLS session at home) and `-SillNoAutoDesktop 1` (the device
never picks the Desktop by itself: a live gate streams nothing); `xcrun
simctl openurl <udid> 'sill://pair…'` shows the link's confirmation after the
system's "Open in Sill?". `-Sill.directWirelessMacs '("Mac mini")'` (seeds the
device's memory of Macs with Direct Wireless on for one run; `'()'` empties it),
`-SillConnect 127.0.0.1:PORT`
(connect by address, also in the normal app: the only way to reach the
off-Bonjour synthetic hosts from the simulator), `-SillMoveTest
1|refused|other:PORT|to:HOST:PORT` (with `-SillConnect`: that session counts as
direct and a second later the same address, or its port 1, or its port PORT, or
HOST:PORT, is listed as the Mac's network row, so the move to the network runs
against a synthetic host; `other:` with a second synthetic host on PORT is
another launch, refused at its first window list and not tried again, and with
`-SillConnect` through a delay proxy to the first host's own PORT the fence
waits out the proxy's round trip; `to:` reads HOST:PORT as `-SillConnect` does,
`[::1]:P` too, and this Mac's `fe80::…%en0` address from `127.0.0.1` shows the
panel's route word change at the hand-over; the console's "discovery: …" and
"session: …" lines, `xcrun simctl launch --console-pty`, say what happened),
`-SillWiredTest HOST:PORT` (a wired dial's fallback under test:
`-SillConnect`'s dial, a network row's and a move's go to HOST:PORT first,
`192.0.2.1:9` giving way after 2.5 s and `127.0.0.1:1` at once), `-SillPathTest
'<spec>'` (with `-SillConnect`: the session's Mac listed as a network row whose
cable and Wi-Fi come and go on cue, so the session follows the best path for
real; the spec is ContentView's contract, the console's "path: …" lines say
what happened), `-SillInputScript '<t> <step>; …'` (with `-SillLive 1`: input
with no finger, t seconds after the session's first window list: `down`, `pad
DX,DY`, `lift` and `click` on the portrait pad, `tap X,Y` on the stream at a
frame fraction, `key USAGE` a hardware key, `row USAGE` a key of the portrait
key row, `gesture NAME[,FINGERS]` a three-finger gesture through
`StreamClient.sendGesture`; the console's "input script: …" and "pointer: …" lines say what
happened; it runs only when the session was dialled by `-SillConnect` to a
loopback address, `127.0.0.1:P`, `::1:P` or `localhost:P`, and the host's first
window list has no version: Sill.app's always has, and would post the input to
this Mac, so the console says "input script: refused: …" and nothing is sent;
point it only at `--synthetic` hosts; `[::1]:P` works too: the argument domain
drops a launch argument that starts with `[`, and StreamClient.init registers
`-SillConnect`'s, `-SillWiredTest`'s and `-SillPairAddress`'s from the command
line). The first-run tour, in the mock, under `-SillLive 1` and in
the normal app: `-SillTourState fresh|landscape|done|skipped|saved` turns the
automatic tour on (a Debug build never shows it by itself otherwise; `saved`
reads and writes `Sill.tourSeen` and `Sill.tourSkipped`, the others last one
run), `-SillTour touch|bar|settings|laptop` starts it at that step, and the
stand-ins `-SillTourPress next@S|skip@S`, `-SillTourActivityAt S` (the app
run's first session only), `-SillTakeTourAt S` (Settings, then its Take the
Tour) and
`-SillTourVoiceOver 1`; `-SillOrientation landscape|portrait` asks the normal
app's scene for that orientation (a phone simulator sideways with its real
safe areas); the console's "tour: …" lines say what happened, and a card's
line gives its frame and tail. `xcrun simctl launch --console-pty` streams the
console; `--stdout=PATH` writes inside the simulated device's own file system.
A fake screen wider than the
simulator but fitting on its side (1133x744 on an upright iPad Pro 13") is
drawn a quarter turn clockwise; `sips -r 270` the screenshot. One that fits
neither way (the Duo's or an iPad's size on an iPhone simulator) is drawn
scaled down and laid out at its own size ("harness: 710x1000 drawn at 0.62");
a phone's whole stream screen on that phone (440x894 on an 18 Pro Max, 402x812
on an 18 Pro) reaches into the simulator's safe area and runs its trackpad past
its bottom edge: photograph it on a larger simulator, or in the normal app.
`-SillKeyboard 1` raises the software keyboard for real in a live session (the
mock only lights the button), `-SillKeyboardToggle <s>[,<s>…]` toggles it at
those seconds as the Keyboard button does, and in a live session (the normal
app with `-SillConnect`, or `-SillLive 1`) `-SillDrawer 1`, `-SillSettings 1`
and `-SillScaleOpen 1` open theirs 1.5 s after the stream starts. The console
prints `viewport: 386×241 pt, scale none, 60 fps` for each viewport sent.
`-SillIdiom pad` draws a screen taller than wide and narrower than 600 pt as
an iPad does (the compact halves) rather than as a phone, so an iPhone
simulator photographs it (`phone` the other way round; the normal app too).
`-SillInputTest 1`, with `-SillConnect` on this Mac's loopback: once, the
portrait key row taps cmd, esc, shift and ctrl through its caps' action, then
the trackpad checks that a touch at its centre lands on it, strokes, taps with
the latched keys held and scrolls, through its own code ("input test: …"); a
synthetic host counts what it gets as `in.dry` and posts nothing, but a real
host (Sill.app, SillHost without `--synthetic`) posts it on this Mac and the
test does not look at which host it reached, so point it only at a synthetic
host, or put a relay in front that reads the device's frames (the 14-byte
header: kind, then the payload's length at bytes 10–13) and drops kind 8
(`sillrelay.py` passes everything).
