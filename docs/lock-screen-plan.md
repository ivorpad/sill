# Lock and unlock the Mac from the device

Ivor, 2026-10-15: the Mac's password typed from the iPhone was refused at the lock screen ("Why?").
On 2026-10-16, from a list of next ideas: "plan 1", locking and unlocking the Mac from the phone.
Status: P1, P2 and P3 built on this branch on 2026-10-16 (Ivor: "build it"), with decisions 3 to 7
as recommended and decision 2 as Ivor chose it (below). None of it is committed, and Sill.app 0.5.1
(598) in /Applications has only P0's fix (`Sources/SillHost/UserActivity.swift`). Verified without
a real host: `swift build -c release`, the iOS app as CI builds it, `Tests/checks/run-all.sh` with
the new `lock-screen` check (384 cases, 157 of 157 mutants), and synthetic hosts driven by
`sillclient.py`: lock, unlock and lock again over a paired TLS home door, the switch off, the plain
door, away from home with and without its switch, a PIN lock screen's 5 s wait and 2-failure stop,
input during an attempt, and lock again after the device left. The device's card and panel row were
checked in a private simulator. Still open: the P0 probes and the first live unlock, both the
user's. Line references are this branch's at d3bce48 plus that change. After the rebase onto
upstream's main, the clipboard ones move to upstream's ClipboardPolicy.swift.

## Why the password was refused

loginwindow keeps an activity semaphore while the lock screen is up and the user has gone idle
("going inactive, create activity semaphore"). A password entered then waits 5 s for user activity
and fails as "INCORRECT password" without being checked ("The user did not become active for
authentication. Fail the auth"). Posted CGEvents are not user activity. Real HID input or a
`UserIsActive` assertion releases the semaphore ("user is active, releasing the activity
semaphore"). Nine tries from the iPhone failed this way on 2026-10-15, at 11:22 and 20:17–20:19.

`UserActivity.swift` declares activity before InputInjector posts, at most once a second
(`IOPMAssertionDeclareUserActivity`, `kIOPMUserActiveLocal`, a fresh assertion released at once).
Apple's Screen Sharing does the same (ScreensharingAgent imports the call), and so does Chrome
Remote Desktop (`WakeUpDisplay` in remoting/host/input_injector_mac.cc, once a second). RustDesk
runs `caffeinate -u -t 5` once per connection.

**P0 result (2026-10-15, Mac15,6, macOS 26.6.2, iPhone17,2).** The Desktop streamed at 1920×1080
with the lock screen up, and capture kept flowing while locked (30 to 55 frames a second). Sill's
assertion came at 22:27:49.154 ("Sill input from an iPhone or iPad") and the semaphore was released
at 22:27:49.166. Attempt 1 (22:27:49.183) was checked ("no activity semaphore, continuing auth")
and was a wrong entry. Attempt 2 (22:28:06.160): "password is CORRECT". `caffeinate -u` on its own
helps for about 30 s only, because the lock screen's own timeout sleeps the display and makes the
semaphore again (20:41:16, with caffeinate still running).

## Where Sill stands

- Unlocking works today, by hand: stream the Desktop (the lock screen is in the picture), open the
  keyboard, type the password, press Return. Nothing tells the device the Mac is locked. With a
  window streaming, whether its picture keeps coming while locked is still remote-access-plan's R6.
- The password goes as ordinary input. `InputOverlayView` (InputOverlay.swift:15) adopts
  `UIKeyInput` with autocorrection, capitalization and smart punctuation off, but sets no
  `isSecureTextEntry` or `textContentType` (:686-690), so the keyboard treats it as any text.
  `insertText` sends `.text`, kind 8 (StreamClient.swift:3039), and `InputInjector.type` (:415)
  posts each character as a Unicode string with the key it sits on (`KeyStrokes.textKey`). The host
  logs only counts (`in.text`). A dry run's test log (`logTest`) prints key codes, which spell the
  text, so tests use a made-up secret.
- `SessionLock.swift` knows whether the console is this user's and whether it is locked
  (`CGSessionCopyCurrentDictionary`, plus the `com.apple.screenIsLocked` and `…Unlocked`
  notifications in Sill.app). Only the pairing ask (RemoteAccess.swift:628) and `--print-cable`
  use it.
- The window list is built per connection (`listMessage(for:)`, StreamCoordinator.swift:2484,
  with `clipboard` per route), and `broadcastList()` sends each connection its own. The device
  copies the list's capability fields into published state in `handle(.windowList)`
  (StreamClient.swift:3420-3429).
- Nothing locks the Mac, and nothing tells the person at the Mac that a device typed into the lock
  screen.
- The device shows no system sheets or alerts (HostSettingsPanel.swift:8-18). `PairingOverlay` is
  the model for a card with a field. It is a ZStack sibling of the layouts
  (StreamScreen.swift:235-241), and it puts the stream's keyboard away first, "so no key reaches
  the Mac while the code is typed" (:454, `putAwayForOverlay` :479-485).
- The device's keychain holds one item, the P-256 device key (`WhenUnlockedThisDeviceOnly`). There
  is no LocalAuthentication and no `NSFaceIDUsageDescription`.
- A Mac paired for smart-card login asks for the card's PIN while the card is in (the field's
  placeholder reads "PIN"), and three wrong PINs block a YubiKey's PIV applet. TKTokenWatcher saw
  only `com.apple.setoken` on this Mac with its YubiKey out. With the key in, a
  `com.apple.pivtoken` token is expected (P0d).

## The feature

**On the device.** While the window list says `locked`, the stream shows a card over the picture:
"‹Mac› is locked". If the list also says `unlock`, the card has a secure field and an Unlock
button. The field is labelled Password or PIN, as `locked` says, and uses
`textContentType(.password)`, so the Passwords app can fill it after Face ID while Sill stores
nothing. Once the attempt is sent the device clears the field and keeps nothing. One tap is one
attempt, and nothing retries by itself. Without `unlock` the card says
"Unlock ‹Mac› at the Mac, or turn on Unlock from devices in Sill there."

The card works like PairingOverlay. It is a sibling of the layouts, in every layout (StreamScreen,
PortraitStreamScreen), and it puts the stream's keyboard away first, so no character of the
password also goes as input. Hiding the card leaves the picture usable. The Settings panel's row
brings it back: inside the host block (HostSettingsPanel.swift:223), as a `Rows { Button }` like
Pair This iPad…, the row reads "Lock ‹Mac›" while the Mac is unlocked and "Unlock ‹Mac›…" while it
is locked. It shows when the list says `lockScreen` 1.

**On the Mac.** Settings › General gets "Unlock from devices" and "Also from devices away from
home". Both are off by default, and the second counts only while the first is on, like the
clipboard's pair (SettingsPanes.swift:143-145). They are kept beside those in HostConfig, the
Mac's alone, so no device can change them. They do not go with the trust list like
`requirePairing`, because they admit no new key, only let a paired device type what it already
knows. A third switch, lock again, is decision 5.

An unlock attempt goes through these steps in order:

1. It is refused unless the connection came through a TLS door (the CLI's plain door never
   advertises `unlock`), the switches allow its route (`AwayPolicy.isAway`), SessionLock says this
   user's console is locked, and the attempt limit allows it. The limit is one attempt at a time
   across all devices, and 5 s after a failure. With a PIN lock screen, no attempts are taken
   after 2 failures in a row until the Mac is unlocked at the Mac, so the card keeps a try.
2. Sill declares activity (`UserActivity`, not throttled for this) and waits for the main display
   to wake (`CGDisplayIsAsleep`, up to 2 s) and the lock screen to settle (P0a).
3. It clears the field with ⌘A then Delete (P0b).
4. It types the secret through the same Unicode path as `InputInjector.type`. It reads
   SessionLock before each character and before Return, and stops at the first read that says
   unlocked, so the rest of a password never lands in an app. Then it presses Return.
5. It waits up to 6 s (loginwindow's 5 s wait plus a margin) for SessionLock to say unlocked. The
   outcome is "unlocked", or "stillLocked" for a wrong entry. The host can't tell which wrong entry
   it was.

Sill.log gets one line per attempt ("Unlock: ‹device› through Tailscale: still locked"). It never
gets the secret or its length.

A lock request posts ⌃⌘Q, the Apple menu's Lock Screen, through `InputInjector.chord`. If the user
remapped "Lock Screen" in App Shortcuts (`NSUserKeyEquivalents`), it posts their shortcut instead.
SessionLock then has 2 s to say locked, and the outcome is "locked" or "notLocked" (P0c).

Lock again (P3) applies only when Sill's attempt unlocked the Mac. If that connection goes (closed,
or evicted by silence), Sill waits 30 s for it to come back. After that it locks the Mac, unless a
device that unlocked it is back or the Mac's own keyboard or mouse has been used since (P0f). This
puts the Mac back the way the device found it. It is not a curtain.

The attempt gets its own kind instead of the `input` text that works today, because text input
goes wherever the focus is. The host has to declare activity and wait for the display before the
first character, type only while the lock screen is up, never log what it types, count attempts
across devices, and check for a smart card.

## The wire (additive only, per the compatibility floor)

- `WindowList.locked: String?` is "password" or "pin" while this user's console is locked ("pin"
  while a token paired for this user's login is present, P0d), and nil otherwise and from older
  hosts. A device reads a value it
  does not know as locked and labels the field "Password or PIN". Every connection gets it, and
  `broadcastList()` runs on each lock and unlock.
- `WindowList.lockScreen: Int?` is 1 when this host takes kind N with `action` "lock". It is nil
  from older hosts, and a device sends them no kind N.
- `WindowList.unlock: Bool?` is true when this connection may send "unlock" (TLS door, the
  switches, its route), per connection like `clipboard`, and nil otherwise.
- Kind N goes both ways, like the clipboard's. From the device it is JSON `LockScreenRequest`:
  `action` ("lock" or "unlock"), `secret` (a String, for unlock only) and `token` (an Int). From
  the host it is JSON `LockScreenOutcome`: `token`, `outcome` ("unlocked", "stillLocked",
  "refused", "locked" or "notLocked") and `message` (a String?). `outcome` is a String, not an enum
  an older peer decodes, and a device shows an unknown outcome's `message` as it is, as it does
  kind 20's reasons.
- N is above 43, and is agreed with upstream after the rebase onto its main. Upstream's main has
  28 for gestures, keeps 29 to 31 reserved and uses 32 for the clipboard. Open PRs #66, #72 and #73
  claim 29 to 31 and 33 to 42, and #94 claims 43. This branch's clipboard, at 29, moves first. The
  `menus` (main.swift:25) and `pointer-control` (main.swift:376) checks list every unknown kind,
  so they change with N.

## Phases

**P0 probes.** These are run by the user, since each one locks or types into this Mac, which no
test host may do. A probe that types uses a made-up string, never the password, with any smart
card out. Nothing built yet stops typing when the Mac unlocks, so a real password that took would
send the following tries into whatever app has the focus.
- Done (above): typing reaches authentication.
- P0a: after the display has slept on the lock screen, how long from the declaration until the
  field takes a key. Send an attempt at once, then at +300 ms and +1 s. loginwindow's "Attempt #"
  lines and the dots in the field show which ones took.
- P0b: ⌘A then Delete clears a half-typed field on the lock screen.
- P0c: a posted ⌃⌘Q locks the Mac with a window app, a full-screen app or the Finder frontmost.
- P0d: with a paired smart card in, TKTokenWatcher lists a `com.apple.pivtoken` token and the
  field says PIN. A token in the port is not the same as one paired for login, so the probe also
  reads the pairing (`sc_auth identities`, or the user record's `AltSecurityIdentities`), and does
  the same with a card that isn't paired.
- P0e: while locked, does a window stream (not the Desktop) keep its picture coming (R6)?
- P0f: do Sill's own posted events reset `HIDIdleTime`? powerd logged WindowServer's
  "iohideventsystem.queue.tickle … process:Sill" at 22:27:43, so they may. If they do, use of the
  Mac's own keyboard or mouse shows as an idle reset at a moment Sill posted nothing.

**P1 Mac and wire (Sources).**
- `Sources/StreamProtocol/LockScreen.swift` (new): the request, the outcome and `UnlockPolicy`.
  The policy is pure, shaped like ClipboardPolicy. It takes the switches, the route, the door, what
  the lock screen asks for and the attempt history, and returns allowed or the refusal's message.
  It gets a check in `Tests/checks/lock-screen`, with mutants.
- `Sources/SillHost/ShieldTyping.swift` (new): the attempt sequence above and the lock route. The
  Unicode typing moves out of `InputInjector` into a helper that both use. That also starts
  InputInjector's split (645 lines against its 500).
- SessionLock gets a change callback that calls `broadcastList()`: the notifications in Sill.app,
  and in the CLI a read of the dictionary every second while a device is connected.
- HostConfig gets `unlockFromDevices`, `unlockAway` and `lockAgain` (every knob is required, so the
  compiler finds each builder), and Settings › General gets their switches.
- StreamCoordinator: the three list fields, `case .lockScreen` in the dispatch, and the lock-again
  timer when a connection leaves.
- A synthetic host (`--synthetic`, `SILL_TEST_LOCKED=1`, `SILL_TEST_LOOPBACK=1`) answers attempts
  without typing (`in.dry`), with a test hook that picks the outcome. `sillclient.py` gets a flag
  that sends one. Both go in docs/agents/build-and-run.md.

**P2 device (iOSClient).**
- `hostLocked`, `hostLockScreen` and `hostUnlock` are published from `handle(.windowList)`. The
  `handle` switch gets a `case .lockScreen` that follows the usual pattern: decode, `from`, hop to
  main, check `connection === from`.
- `LockedCard.swift` (new): the card, with `SecureField` and `.textContentType(.password)`, and the
  outcome shown inline. The panel gets its row. New files need their four pbxproj entries by hand.
- MockCatalog gets a locked Mac for the device checks.

**P3.**
- Lock again (above).
- A notification on the Mac for every unlock from a device, and a line in the Devices pane
  ("unlocked this Mac at 22:28 through Tailscale").

## Decisions for Noah

1. **Scope.** remote-access-plan.md §1 lists "waking or unlocking a Mac" under that step's "Not in
   this step" (line 222). It is not one of CLAUDE.md's decisions, so this asks for a new step
   rather than a reversal.
2. **Typing into the lock screen without the switch.** Any paired device can do it today, as
   above, so with the switch off the switch only gates the card. For it to mean "devices may unlock
   this Mac", the host would drop key and text input while the Mac is locked unless the switches
   allow that connection. That ends unlocking by hand from the Desktop, which works today.
   Devices without the card (the App Store's 0.5.1 (4) and older) would see their keys go nowhere
   while the Mac is locked, with nothing to say why. Against a Mac without UserActivity, typing at
   the lock screen mostly failed for them anyway once the Mac had gone idle (the semaphore), so
   they lose little that worked before. Against this branch's Mac they lose what works now.
   Recommended: drop that input, since a default-off switch that the keyboard gets around is
   misleading.
   **Decided for this branch (Ivor, 2026-10-16): "Keep today's typing".** The switches gate only
   the card's attempts; typing into the lock screen by hand stays open to every paired device.
   While an attempt types, the host drops every connection's key, text and gesture input, so a
   second device can't break into the secret. Noah decides it again for upstream.

## Decisions for Ivor

3. **AutoFill or a saved password.** (a) AutoFill only: the Passwords app fills the field after
   Face ID, and Sill keeps nothing. (b) A Remember switch: a keychain item per Mac with
   `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` and `.biometryCurrentSet`, so one Face ID tap
   unlocks, plus an `NSFaceIDUsageDescription`. Recommended: (a) first.
   **Decided for this branch (Ivor, 2026-10-16): both.** AutoFill stays. For a password (never a
   PIN: a stale one would use the smart card's tries by itself) to a Mac this connection is pinned
   to by its key, on a device with Face ID or Touch ID, the card also has "Use Face ID next time",
   off each time it shows. A typed password is kept only when the Mac answers "unlocked" without
   words (with words it was unlocked already and typed nothing). Once one is kept the card has
   "Unlock with ‹biometry›": a tap, never by itself as the card shows, since a glance would unlock
   the Mac. Face ID is asked first (`evaluatePolicy`) and the keychain read with that context, then
   everything is judged again before the one request. The kept password goes when the Mac answers
   "stillLocked" to it, when it can't be read after a face that matched (the enrolled faces
   changed), when its Mac leaves the saved list, and with Forget Saved Password in the Settings
   panel. The device alone changes: SavedUnlock.swift, LockScreenPolicy's `savedOffer` and
   `savedChange`, `Tests/checks/lock-device`. For upstream: an optional `typed` on the outcome would
   let the Mac say its own Return unlocked it. Without it, someone who unlocks at the Mac while an
   attempt types makes the device keep that password, and its first use corrects it.
4. **Away from home.** Off by default, with its own switch, as the clipboard has. Recommended.
5. **Lock again.** On by default for any session whose attempt unlocked the Mac, with the 30 s
   grace, and skipped when the Mac's own keyboard or mouse was used (P0f). Recommended. Turn it off
   at home if it gets in the way.
6. **The lock route.** ⌃⌘Q needs no private API and goes through the frontmost app's Apple menu.
   `SACLockScreenImmediate` (login.framework) is private. It is what Tinycast Beta calls on this
   Mac, and it would be looked up with dlsym, as SymbolicHotKeys.swift does SkyLight's functions.
   Recommended: ⌃⌘Q, with the private call only if P0c finds a case ⌃⌘Q misses.
7. **A PIN lock screen.** (a) Type the PIN, with "A wrong PIN uses one of the card's tries" on the
   card and the stop after 2 failures. (b) Refuse while a card is in. Recommended: (a).

## Untested and risky

- The settle after the display wakes (P0a). A first character typed while the lock screen animates
  in may be lost, and then the attempt fails as a wrong entry.
- `CGSSessionScreenIsLocked` is undocumented. SessionLock already pairs it with the notifications
  in Sill.app, and the CLI has the dictionary only.
- The last SessionLock read comes a few milliseconds before its character is posted. Someone at
  the Mac who unlocks it with Touch ID in that gap could get one character of the password in
  their focused app. Reading before every character keeps that to one character.
- macOS has its own handling of repeated wrong passwords (delays, the hint). Sill's limit is there
  for the smart card.
- If P0d's pairing read doesn't hold, a card that isn't paired for login makes Sill label the
  field PIN and apply the 2-failure stop to a password. The label is cosmetic, and the stop is the
  cost.
- Lock again could lock out someone who sat down at the Mac after a remote unlock, if P0f's check
  misses them.
- Some cases are refused or out of reach: another user on the console (fast user switching), a Mac
  that restarted and hasn't been logged in to (Sill isn't running yet), and a sleeping Mac, which
  can't be reached (waking is not in this plan).
- No private API, unless decision 6 picks `SACLockScreenImmediate`.
- The kept password's Face ID is proved on a device only. The simulator's keychain stores the item's
  access control (`od` needs `cbio`) but never enforces it, so there only the `evaluatePolicy`
  before the read is the gate. A device should show one Face ID sheet for each tap: two in a row
  would mean the read did not take the evaluated context, and `evaluateAccessControl` on the
  item's own access control is the fix.
