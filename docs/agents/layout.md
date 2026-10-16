# Layout

- `Package.swift` — SwiftPM. Products: `StreamProtocol` (shared wire format,
  iOS + macOS), `SillHost` (the CLI, target `SillHostCLI`) and `SillMenuBar`
  (Sill.app's executable). `SillHostCore` (the host, folder `Sources/SillHost`)
  is a library target with no product, so the iOS project never sees it.
- `Sources/StreamProtocol/StreamMessage.swift` — 14-byte header + payload framing,
  message kinds in both directions (44, the lock screen's, is provisional until
  agreed with upstream), HEVC parameter set encoding. Shared by both
  sides. Change it in one place. `Switcher.swift` — the catalog types
  (`WindowList`, with the host's per-launch `launchID` and the lock screen's
  `locked`, `lockScreen` and `unlock`; `WindowInfo`,
  `AppInfo`, `StreamSource`) and image blob framing.
  `HostSettings.swift` — the host settings a device sees and changes (kinds 16
  and 17): `StreamSettings`, `RunningStream`, `HostSettingsState`,
  `HostSettingsChange`, `SettingsChoices` (the Mac menu's values) and
  `QualityPreset` (Low, Efficient, Balanced, High, Pro, Ultra, Extreme). Remote access:
  `Remote.swift` (kinds 18–22's payloads: `MacAddress`, `MacInfo`,
  `SignedMacInfo`, `PairRequest` (with pairing at home's methods `ask` and
  `cancel`, `cable` and `v`), `PairResult` (its `method`, the ask's reasons
  `shown`, `openOnMac` and `locked`, and `message`), `Goodbye` (with
  `pairingRequired`)), `RemoteTLS.swift` (the one TLS 1.3 builder for both
  doors' ends and the tests; `serverALPNs`, the two a host offers for good),
  `RemoteIdentity.swift` (SPKI fingerprints, the Mac ID, the hand-built
  certificate, keys), `Pairing.swift` (`PairingCode`, `PairingProof`,
  `RecognitionTag`, `PairLink`, and `HomeDoorTXT`, the home door's TXT key
  `p`), `AddressParser.swift`, `SafeText.swift`.
  `Compatibility.swift` — `SillProtocol.current` (1), `SillVersion` (tags,
  bundles and the wire's versions, compared part by part) and `Hello` (kind 23,
  the device's first message); `Goodbye` (Remote.swift) carries `message`,
  `minimumVersion` and `reconnect` too, and `WindowList` the host's
  `hostVersion` and `protocol`. `MacMenu.swift` — the Mac's menus (kinds 24,
  25 and 27): `MacMenu` (a top level, or the answer to one fetch or press),
  `MacMenuItem`, `FetchMenu` (with the title the device showed for the menu)
  and `PressMenuItem`. `Pointer.swift` —
  `MacPointer` (kind 26, host → device: where the Mac's pointer is in the
  streamed frame while this device is not moving it, and `seen`, the input
  messages the host had read on the connection). `Gesture.swift` —
  `TrackpadGesture` (kind 28, device → host: a three- or four-finger gesture
  by name, and its fingers), sent only to a host whose `WindowList.gestures`
  is 1 or more. Locking and unlocking the Mac from a device
  (docs/lock-screen-plan.md): `LockScreen.swift` (kind 44, both ways:
  `LockScreenRequest`, device → host with `action` "lock" or "unlock", the
  `secret` and the device's `token`, and `LockScreenOutcome`, host → device, one
  per request, with the `token`, an `outcome` and a `message`; each action,
  outcome and ask a String with a `known` set, never an enum an older peer
  decodes: `LockScreenAction`, `LockScreenAsk`, what the lock screen asks for,
  "password" or "pin"; `LockScreenSecret`, what a host types, 1 to 128
  characters with no control character; `UnlockTiming`, the host's waits;
  `UnlockPolicy`, the Mac's two switches by route and door, which judge kind 44's
  attempts and never typing by hand; `UnlockAttempts`, one at a time across
  devices, none within 5 s of a failure and, with a PIN lock screen, none after
  two in a row; `UnlockJudge`, the verdict on an unlock request in the plan's
  order; `LockAgain`, its conditions and the 30 s grace; `LockShortcut`, ⌃⌘Q or
  the user's own from `NSUserKeyEquivalents`; pure, `Tests/checks/lock-screen`).
  The window list's `locked` is the ask while this user's console is locked,
  `lockScreen` is 1 when the host takes "lock" and `unlock` is true on a
  connection that may unlock; a host or device from before it skips kind 44.
- `Sources/SillHost/` — the `SillHostCore` library. `StreamCoordinator` (main
  actor; owns the pipeline, switches sources on client request, raises the
  picked window in regular mode (never on the virtual display), applies
  viewports, falls back to the software encoder on a hang and re-checks the
  hardware until it can go back (`recheckLoop`), stops capture when the last
  client leaves, takes live settings between pipelines (`setTarget`, from the
  app and from devices' kind 17, at most four a second per connection,
  answered and published as kind 16; a pick made during a restart runs after
  it), keeps each connection's route (home or the remote door's: kind 21 only
  from near the Mac, Direct Wireless never from away), sends kind 18 with the
  catalog, says goodbye (kind 22) at quit, sends the streamed app's menus to
  the devices that ask (`MenuMirror`; a window source's app made active and
  its window key first, as a click does: `focusForMenus`), and writes
  `HostStatus`),
  `HostConfig` (the knobs: maxFPS, captureScale, bitrate per 60 fps, the
  away pair awayBitrate and awayCaptureScale, prioritizeSpeed, virtualDisplay,
  directWireless, remoteAccess, remotePort, internetAccess, requirePairing, and
  the unlock switches unlockFromDevices and unlockAway (off) and lockAgain (on),
  the Mac's alone: `DeviceSettings` never takes them; `standard` is the CLI's
  values and the app's defaults; `effective(away:)`),
  `AwayPolicy` (who counts as away, when the away quality is the target, its
  two lines; pure, `Tests/checks/away-quality`), `LinkJudge` (each device's
  link judged once a second from the sweep: fine, behind, stalled, the carried
  rate, the suggestion, the host's lines, and which restarts judge afresh
  (`judgedAfresh`); pure, `Tests/checks/link-judge`),
  `HostStatus` (the snapshot the app shows, pushed on events; `onChange`
  publishes the devices' settings state), `DeviceSettings` (what a device may
  set, `HostConfig` ↔ wire), `HostLog` (the print shadow, the app's ring and
  log file),
  `WindowCatalog` (polls windows and thumbnails only while a client is
  connected; icons; installed apps in the background),
  `WindowCapture` (ScreenCaptureKit), `SyntheticCapture` (test pattern for
  `--synthetic`; SILL_TEST_PATTERN=noise adds a square of noise,
  SILL_TEST_PATTERN=picture:<path> shows a still picture instead), `HEVCEncoder` (VideoToolbox with one frame inside, a
  one-slot mailbox behind it and a hang watchdog; hardware or software; says
  whether a stalled frame came back; gives a stream whose session settled in
  the slow state a new one), `EncoderSlowState` (when that is, and whether the
  new session ran faster; pure, `Tests/checks/encoder-slowstate`),
  `EncoderMailbox` (its bookkeeping: the frame inside with its watchdog
  clock, the mailbox, the watchdog's test, timestamps and keyframe requests;
  pure, `Tests/checks/encoder-mailbox`), `EncoderProbe` (one small frame
  through a hardware session at launch; for the re-check a short quiet run at
  the stream's size, one frame at a time like a stream, the rate it keeps and
  the rate a return needs), `EncoderSelfTest`
  (`--encoder-selftest`), `CursorShapeWatcher` (NSCursor.currentSystem →
  `.cursorShape`), `StreamServer` (Network.framework + Bonjour `_sill._tcp`, both
  directions, keepalive, dead-client eviction, ping echo, client-stats print;
  a remote client's frames paced by the bytes its connection has not taken
  (`paceRemote`, docs/remote-bundle-plan.md §3); one sweep a second closing
  every client's second into its LinkJudge (`onClientLinkChanged`), the judges
  reset only at another quality (`resetLinks`, apart from `resetForNewStream`);
  `send(each:)`, kind 16 per connection; the test-only
  SILL_TEST_REMOTE_ORIGIN;
  the listener built with or without peer-to-peer and replaced live when Direct
  Wireless changes, and turned off, the devices on peer-to-peer Wi-Fi
  disconnected; the test-only SILL_TEST_SERVICE_TYPE, SILL_TEST_SWAP_FAIL,
  SILL_TEST_PEER_TO_PEER_INTERFACE and SILL_TEST_LOOPBACK), `ClientLink`
  (which route a client came by, from its endpoint's scope, and the menu card's
  word for it: Wired, Wi-Fi, Direct or none; pure, checked on its own with
  `swiftc -package-name sill`, which its `package` access needs),
  `InputInjector` (CGEvents: pointer, scroll with phases, text with modifier
  flags cleared explicitly (a ⌘Space before typing otherwise tainted the text
  events and Spotlight ignored them; the events themselves are `TextTyping`'s),
  HID keys as KeyStrokes gives them, each
  device's keys let go when it leaves and every key and button at the host's
  end, the check after each key's up, a button's up with nowhere to land where
  the pointer is; `postQuietly`, the post an unlock attempt uses, which never
  prints the event; `lastRealPostAt`, when it last really posted, which lock
  again reads; the TEST ONLY input log), `KeyStrokes` (a device's key as the
  Mac's: its virtual key, and the flags each event carries from the modifier
  keys the devices hold down, so a key's up leaves only what is held;
  `KeyUpCheck`, whether an up took its modifiers out of the HID state table;
  `DroppedInput`, what of input with nowhere to land still goes; pure,
  `Tests/checks/key-strokes`), `UserActivity` (the Mac told a user is at it,
  at most once a second while a device's input arrives, as Screen Sharing
  does: posted events alone leave the display asleep and a locked Mac's lock
  screen checking no password; an unlock attempt declares at once, `force`,
  before its first key),
  `WindowSizer` (Accessibility resize for the Aa scale; `placement/move/
  restore` for the virtual display), `VirtualDisplay` (private-API wrapper),
  `VirtualStage` (`--virtual-display`: owns the display and the moved window,
  geometry, prepare/release, emergency restore), `HostShutdown` (signal
  sources + atexit, installed only with the flag in the CLI, always in the app;
  `releaseForQuit` for the app's Quit; `installKeyRelease` for the CLI's
  default path: a device's keys let go, then the signal's own end),
  `VirtualDisplaySelfTest`
  (`--virtual-display-selftest`), `Stats` (1 s lines while active, 30 s
  heartbeat when idle). Remote access: `OriginPolicy` + `InterfaceSnapshot`
  (who may use which door; pure), `RefusalSummary` (one refusal line a minute),
  `HostIdentity` (the `IdentityStore` protocol, `MemoryIdentityStore`, the TEST
  ONLY `FileIdentityStore`, `PairedDevice`, the lock-protected trust snapshot
  the door reads on the network queue), `KeychainIdentityStore` (Sill.app's),
  `PairingWindow` (pure), `RemoteServer` (the remote door), `Reachability`,
  `AddressList` (pure) and `RouterAddress` (read-only NAT-PMP/PCP),
  `RemoteAccess` (main actor; ties them together, signs kind 18; owns
  pairing for both doors: the ask, the cable's devices, Require pairing,
  Remove at both doors). Pairing at home (docs/home-pairing-plan.md): `Door`
  (admission at a TLS door, one class behind both listeners: the pending
  caps, the backoff, the verify block, the device gate, one pairing request
  per `sill-pair/1` connection; `RemoteServer` keeps the remote door's
  listener), `DoorPolicy` (who each door admits, the ask rule's six steps,
  `afterGate`, `isTestHost`: a host that does not advertise and is not
  Sill.app's own executable; pure, `Tests/checks/door-policy`), `CableLink`
  (whether a connection came over the USB cable to an iPhone or iPad, from
  InterfaceSnapshot's IOKit reading, and the device's ID; pure,
  `Tests/checks/cable-link`), `CableReport` (`--print-cable`), `SessionLock`
  (an unlocked console; the console's three states, unlocked, locked and
  elsewhere (another user's session, the login window), cached with a change
  callback, `read` afresh for the typing, refreshed once a second while a
  device is connected and by Sill.app's lock notifications; a test host's is
  simulated: locked only with SILL_TEST_LOCKED, flipped by a dry unlock or
  lock), `TestHooks` (the door, pairing and lock screen hooks a host that
  is not a test host ignores, one line each), `AskLimits` (PairingWindow.swift:
  one device-opened window at a time, three in 10 minutes, the quiet after
  the Mac's Cancel or a stop; `Tests/checks/ask-limits`) and
  `RequirePairingValue` (HostIdentity.swift: Require pairing's record, off
  only with the Mac's own signature). StreamServer's home door is plain (the
  CLI without --pairing), TLS (`Door(.home)`, `p` in its TXT record) or
  closed (no identity: fail closed), `HomeDoorMode`.
  `DeviceGate` (the device floor, "0" in every build so far, and a refusal's
  words and log lines; pure, checked with swiftc; the gate itself, which runs
  only above "0", is StreamServer's, with the TEST ONLY
  SILL_TEST_MIN_DEVICE_VERSION and SILL_TEST_GOODBYE).
  The Mac's menus (docs/menu-bar-plan.md): `MenuFormat` (a shortcut as the
  Mac draws it, "⇧⌘S", "fn ⌃F"; an item and a top-level menu as sent; pure),
  `MenuPolicy` (`MenuPath`, the ids; `MenuCache`, a menu's read kept 1 s,
  answering only under the title it was read under; `ShownTitle`;
  `RequestRate`; `RequestDeadline`, when a request can no longer be answered
  in time for its device; `SubmenuRecord`, the submenus a version has read at
  their places; `PressDecision`, only a leaf whose title now is the one shown;
  `TopLevel`; the refusals' words and log lines; pure; both checked by
  `Tests/checks/menus`), `MenuReader` (every Accessibility call for menus, on
  its own queue `sill.menus`: the top level, one menu's items under the title
  shown, walks checked against the version's record, a press; a 1 s timeout
  per element, 1.5 s a menu, and no item begun that would end past the
  request's deadline), `MenuMirror` (main actor: the target, the version, the
  subscribers (only they are served), one request at a time with its
  deadline, the cache and the kept elements; the TEST ONLY
  SILL_TEST_MENU_PID, honoured only by a synthetic host, makes a process's
  menus the test pattern's) and `MenuSelfTest` (`--menu-selftest[=APP]`,
  read-only).
  The Mac's pointer: `PointerControl` (who moves it, the Mac or the device
  whose input the host read last, with the settle for Sill's own motion; the
  fraction kind 26 carries; pure, `Tests/checks/pointer-control`) and
  `PointerWatch` (the host's sampling of it: PointerControl under a lock, the
  streamed source's rectangle, a regular-mode window's bounds re-read on
  `sill.pointer`, the TEST ONLY scripted pointer `TestPointerPath` and
  `PointerTestHooks`; `Tests/checks/pointer-watch`). StreamServer samples it at
  each tick, and at the stream's frame rate while it moves over the source and
  some device is sent it (`PointerWatch.samplerInterval`), and sends kind 26
  to every device not moving it; InputInjector notes each pointer and scroll
  post just before it and, on a synthetic host, posts nothing (`in.dry`).
  Trackpad gestures: `GestureChords` (kind 28's gesture as the Mac's own
  shortcut for its action, the first of its shortcuts that is on; the view
  Sill's last gesture opened, which the opposite gesture closes; the log line;
  the TEST ONLY `SILL_TEST_HOTKEYS` table; pure, `Tests/checks/gesture-chords`)
  and `SymbolicHotKeys` (the Mac's Keyboard Shortcuts read through SkyLight's
  two getters at each gesture, read-only); the coordinator takes four a second
  per connection, waits for a switch in flight, queues the chord behind held
  input, and on a host that does not advertise posts none (`in.gestureDry`);
  `InputInjector.chord` posts it (`in.gesture`), its key up with the HID
  state table's flags from before it (`KeyStrokes.chord`;
  `in.gestureModifiersLeft` if some stay).
  Locking and unlocking the Mac from a device (docs/lock-screen-plan.md, kind
  44): `ShieldTyping` (main actor; the sequence for a request the coordinator
  has judged: declare user activity, wait for the display and the lock screen,
  clear the field with ⌘A and Delete, each character, Return, then up to 6 s for
  the Mac to unlock, the console read afresh before every key so the rest of a
  password never lands in an app; "unlocked", "stillLocked" or "refused"; the
  lock, the Lock Screen shortcut through `InputInjector.chord`, "locked" or
  "notLocked"; the attempts' record across devices; the secret, its length and
  its keys never printed or counted: a dry attempt is one `in.dry`, a real one
  posts through `postQuietly`; `HostConfig.unlockPolicy`, the switches as one
  rule, here and not in HostConfig.swift, which the away-quality check compiles
  without LockScreen.swift), `TextTyping` (the events of a typed character, of a
  plain key and of a shortcut, made here and posted by the caller:
  `InputInjector.type` for a device's text, ShieldTyping for a password),
  `LockAsk` (password or PIN, by whether TKTokenWatcher lists a
  `com.apple.pivtoken` token, which is not the same as a card paired for login),
  `LockAgainWatch` (which device's attempt unlocked the Mac, by its key's
  fingerprint, when its connection ended, when another connection last acted on
  the Mac, and the Mac's own keyboard and mouse by IOHIDSystem's HIDIdleTime;
  `macUsed` pure), `UnlockTestHooks` (the TEST ONLY SILL_TEST_LOCK_ASK,
  SILL_TEST_UNLOCK_OUTCOME, SILL_TEST_UNLOCK_SECONDS,
  SILL_TEST_LOCK_AGAIN_SECONDS and SILL_TEST_MAC_IDLE, each read only on a test
  host, and the "TEST:" lines at start; pure) and `StreamCoordinator+LockScreen`
  (the coordinator's part: each window list's `locked` and `unlock`; kind 44's
  handler, one answer to the device that asked and one log line without the
  secret; `takesKeyInput` and `withheldDuringAttempt`, the one rule that drops
  every connection's key, text and gesture input, as `in.unlockDrop`, while an
  attempt types; `lockStateChanged`, which sends every device its list again;
  lock again's timer, 30 s after the device that unlocked the Mac leaves, and
  Sill.app's `onDeviceUnlocked`).
- `Sources/SillHostCLI/main.swift` — the CLI: flags, `dispatchMain` vs
  `NSApplication.run`, the Terminal permission hint; `--pairing` (the home
  door's TLS with pairing required, a throwaway identity, the code and link
  on its own stdout), `--print-cable`, and the unlock switches `--unlock`,
  `--unlock-away` (exit 2 without `--unlock`) and `--no-lock-again`.
- `Sources/SillMenuBar/` — the app: `main.swift` (AppKit lifecycle, accessory
  policy), `AppDelegate` (launch order, Quit, the modal-loop rule), `AppModel`
  (owns the coordinator, presentation, App Nap guard, onboarding),
  `HostSettings` (UserDefaults; the presets are StreamProtocol's
  `QualityPreset`; the unlock switches' keys unlockFromDevices, unlockAway and
  lockAgain, and `onUnlockSwitchedOn`), `StatusItemController` (+
  `MenuBuilder`), `StatusText`
  (all status copy), `StatusCard`, `StatusGlyph`, `SettingsWindow` +
  `SettingsPanes` (General has the unlock switches: Unlock from devices, Also
  from devices away from home, and Lock again when the device that unlocked it
  leaves, the last two disabled while the first is off), `Permissions`,
  `LoginItem`, `LogWindow`, `MainMenu` (key
  equivalents), `DebugHooks` (and `DebugHooks+Samples`, the canned update check,
  Remote Access and pairing states of `-SillRenderPreviews`, split out of it
  unchanged), `AppLog` (its print shadow), `DevicesPane`
  (Settings › Devices: Require pairing, the paired devices, Remove and
  rename), `RemoteAccessPane` (Settings › Remote Access), `PairDeviceWindow`
  (the QR code and the typed code; the window a device's ask opens, and the
  cable notice), `PairingWindowAddress` (the address that window gives to type:
  Tailscale's name and IPv4 first, another VPN's IP only under this network's
  address; pure, checked with swiftc), `UpdatePolicy` (the update check's rules
  and words; pure, checked with swiftc), `UpdateChecker` (main actor; asks
  GitHub's releases feed and times the checks; compiles on its own with swiftc)
  and `UnlockNotice` (the local notification for each unlock from a device,
  "‹device› unlocked this Mac" with the route and the time; permission asked for
  when Unlock from devices is turned on, never at launch; every
  UserNotifications call behind `AppModel.bundled`, since the bare SillMenuBar
  binary the tests run would raise an exception).
- `Packaging/` — Sill.app's `Info.plist` and the development entitlements
  (get-task-allow only), the release's (`SillRelease.entitlements`:
  `com.apple.application-identifier`, the team and the keychain group, signed
  in only with `embedded.provisionprofile`, the Developer ID profile, which is
  git-ignored; docs/keychain-plan.md), and `ExportOptions-appstore.plist`, how
  the iOS app's archive is exported for App Store Connect. `Scripts/release-ios.sh`
  makes the iOS app's build: the Release archive (automatic signing on team
  9B2KKVM937, or none with `--sign-at-export` and `--unsigned`), the export
  (destination export; `--upload` adds a second one whose destination is
  upload), the .ipa checked (version and build, the export compliance key,
  the Local Network, Bonjour and camera entries, the privacy manifest, an
  Apple Distribution signature, an App Store profile, no get-task-allow, the
  required-reason APIs against the manifest), `--bump`, `--api-key`,
  `--print-version` and `--privacy-report`; it refuses any Xcode before 27.1
  or after 27 (the iOS 27.1 SDK the iPhone Duo's layouts need; the app it
  checks must say DTPlatformVersion 27.1 or later),
  with `--bump` or `--upload` a working tree with changes (new files in
  iOSClient and Sources/StreamProtocol count), and an App Store address in
  `SillLinks.swift` that isn't one, and sourced it only defines its
  functions (docs/release-checklist.md, TestFlight). `Scripts/make-app.sh`
  builds, iconizes, signs and installs the bundle; `Scripts/release.sh`
  (M6) makes the downloads from it:
  `make-app.sh --release`, `make-dmg.sh --prepare` (the image's tool and
  background, before anything goes to Apple), a zip (`ditto -c -k
  --keepParent`), Apple's notary service (`notarytool submit --wait`, the
  profile in `SILL_NOTARY_PROFILE`), the ticket stapled, the zip made again
  with the ticket inside, and a copy unpacked from it checked with `stapler
  validate` and `spctl` ("Notarized Developer ID"); then the disk image of the
  stapled app (`make-dmg.sh --sign`), notarized on its own, stapled, and
  checked (`hdiutil verify`, `stapler validate`, `spctl -t open --context
  context:primary-signature` as "Notarized Developer ID", mounted `-nobrowse`
  in `$TMPDIR` and the Sill.app inside checked as the zip's copy); it prints
  `.build/Sill-<version>.dmg` and `.zip` with their SHA-256. A dry run makes
  the image too, from the app before stapling, signed with the same identity.
  It refuses to start, before building, without a
  Developer ID Application identity (`SILL_SIGN_IDENTITY`, checked against the
  keychain) or the profile, or on a HEAD without the tag v‹version› (the
  update check's), or with `SILL_RELEASE_TAG` (the release workflow sets it)
  not `v<CFBundleShortVersionString>` or naming another commit (`--check-tag`
  checks only that), and `--dry-run` stops before notarytool (the profile and
  the tag only warned about: it sets `SILL_RELEASE_DRY_RUN=1`, with which
  `make-app.sh --release` builds an untagged commit); it refuses a build
  without Assets.car and AppIcon.icns. `--publish` makes the GitHub Release in
  `SILL_RELEASE_REPO` (default Saffsanity/sill, the only repository the update
  check reads), asks `gh api repos/<repo>` whether it can reach the repository
  (`gh auth status` asks GET /user, which the Actions token can't answer), and
  refuses to start unless origin's tag v‹version› names HEAD (gh would make a
  missing tag from the default branch's tip; not asked in the release
  workflow, whose checkout is that tag and keeps no credentials); in
  Saffsanity/sill it passes gh `--verify-tag`, anywhere else it warns that no
  Sill.app will offer the release. It uploads `Sill.dmg`, `Sill.dmg.sha256`,
  `Sill.zip` and `Sill.zip.sha256` (the zip kept for older links: the download
  page names the image since 0.3.1). Sourced, it only defines its functions.
  `Scripts/make-dmg.sh --sign IDENTITY APP DMG` (`-` for ad hoc) makes the
  image: an HFS+ volume "Sill" (not APFS: Finder names the background by an
  HFS+ alias record, and Finder-made and current third-party images are
  HFS+) with the app (`ditto`), a link to /Applications, `.background/`
  (design/DMGBackground.svg rendered by Quick Look at 1x and 2x, cropped,
  joined by tiffutil into one TIFF; cached in `.build/dmg`) and
  `.VolumeIcon.icns` (the app's AppIcon.icns, with the root's custom-icon
  flag); its window laid out by a `.DS_Store` that `Scripts/dmg-layout`
  (Swift, compiled into `.build/dmg`; DSStore.swift, FinderAlias.swift,
  DMGLayout.swift) writes without Finder and reads back (`check`): 660 x 432
  points, the picture's 400 and macOS 27's 32-point title bar
  (`DMGLayout.titleBar`; `Tests/checks/dmg-layout` checks the writer); converted
  to ULFO (LZFSE, read-only), signed (identifier `me.saffer.sill.dmg`, a
  timestamp unless ad hoc) and checked mounted (exactly five items at the
  root, the link, the layout, the app byte for byte). Mounts are `-nobrowse`
  in a new folder in `$TMPDIR`: mounted under the home folder, fseventsd
  writes `.fseventsd` onto the image as it unmounts. `--prepare` only builds
  the tool and the background. Sourced, it only defines its functions.
  `Scripts/sillclient.py` is the wire-format test client
  (timed `--set=K=V[,K=V]@T` kind 17 changes with tokens 1, 2, 3…,
  `--raw17=JSON@T`, `--pick=none|desktop|window:ID@T`, `--stats`,
  `--expect=K=V[,…]` against the last kind 16, which it prints one per line,
  and each second's frames with their kB (the encoder's output);
  `--host`, `--device`, `--big-payload`, `--flood`, `--stop-ping@T`,
  `--stop-read@T`, `--pairing-wanted@T`; the remote door with `--tls
  --identity=DIR`, `--pair-url`, `--pair-code`, `--pin=FP|none` and
  `--expect-tls-fail`, printing kinds 18, 20 and 22; pairing at home with
  `--pair-ask[=cable]`, `--then-code=FILE`, `--pair-hold=S`, `--pair-cancel`,
  `--pair-v=N` and `--expect-pair=R`; the Mac's pointer with
  `--pointer` (each kind 26), `--move=X,Y@T`, `--tap=X,Y@T`, `--key=USAGE@T`
  and `--input=JSON@T` (a literal kind 8), the input flags only to a
  `--synthetic` host on this Mac (lsof and ps); trackpad gestures with
  `--gesture=NAME[,FINGERS]@T` and `--raw28=JSON@T` (kind 28), likewise only to
  a `--synthetic` host on this Mac; the lock screen with `--unlock=SECRET@T` and
  `--lock@T` (kind 44), likewise, printing each answer and each change of the
  window list's `locked`, `lockScreen` and `unlock`, and never the secret; the
  Mac's menus with
  `--menus` (the subscription; each kind 24 on one line),
  `--fetch=ID[xN][,TITLE]@T` (the title the menu was shown under, by default
  the one listed for the id), `--press=ID[,TITLE]@T`, `--raw25=JSON@T`,
  `--raw27=JSON@T` and
  `--expect-menus=TITLE[,…]`, the fetches and presses only with
  SILL_TEST_MENU_PID in its own environment (against any other host they
  would open and choose the menus of whatever app is in front); every
  argument is checked before it connects, and a bad one exits 2).
  `Scripts/menufixture.swift` (TEST ONLY) is the menu gates' app: an AppKit
  menu bar of known menus (Probe's marks, shortcuts, a disabled item, a
  retitled one, a slow action, Deep three levels, 300 and 600 items), the
  prohibited policy so it can never take the front, its one window off every
  display, every delegate call and action logged (an action also as "PRESS
  'item' in 'menu'"), SIGUSR1 and SIGUSR2 giving Probe › Rebuilt a new NSMenu,
  SIGHUP inserting an item at the top of Probe in place and SIGALRM giving
  Probe a new NSMenu; `menufixture label PID` reads its label over
  Accessibility. `Scripts/menu-check/run.sh` runs the real MenuReader and
  MenuMirror against it with no host and no encoder (safe while Sill.app
  streams; it needs Accessibility for whatever runs it). `Scripts/sillrelay.py` is a
  shaping passthrough relay (`--listen 0 --to HOST:PORT [--delay-ms N]
  [--rate-mbps R] [--blackhole-after S] [--record PREFIX]`; TLS passes
  through). `Scripts/pacing/` is the remote pacing harness
  (docs/remote-bundle-plan.md §3 and §11): `build.sh [BASE]` makes two
  throwaway packages under `.build/pacing`, BASE's StreamServer.swift (default
  origin/main) and the working tree's, each with its neighbours (the Door's
  files too since pairing at home, and `PACING_SERVE_BEFORE_HOME_PAIRING` for a
  BASE from before it, whose `serve` takes no hello) and fed fake
  frames by `main.swift` (no encoder: a binary that links a media framework is
  refused; on cue, new sizes, a still window or a restart); `run.sh [--full]
  [--cases a,b] [--repeat N] [--base REF] [--list]`
  runs each case on both, host → `bottleneck.py` (a downlink rate on a virtual
  clock, a delay, a finite queue, rate changes) or `Scripts/sillrelay.py` →
  `device.py` (the device's reader, pings, stats and liveness;
  `--liveness-bytes` for MessageReader's rule), everything on 127.0.0.1 and
  each run only while the load average is under 20; `summarize.py` prints the
  table and each case's gate.
  `Scripts/encoder-check/` holds the encoder's checks ("The 33 fps plateau"):
  `run.sh` builds and runs those that never touch an encoder (the probe and
  encoder checks, which run in real time with tight bounds and so stay out of
  CI, and through `Tests/checks/encoder-mailbox` and `encoder-slowstate` the
  mailbox and slow-state checks and their mutants; it refuses any binary that
  links VideoToolbox), and `verify-hardware.sh` the hardware runs against a
  base commit built from `git archive` (parity, stream, harness, probe,
  keyframe), each only while `no-device.sh` finds no device connected to
  Sill.app; outputs go to `.build/encoder-check/`.
  `sillclient.py --hello=VER[,PROTO]` (or `none`) sends a device's hello
  first (`--hello-delay=S` S seconds after the connection is up, for a change
  made while a host's device gate holds it), and kind 22's new fields are
  printed. `Scripts/sillfeed.py PORT`
  is a fake GitHub releases feed for the update check's tests (`--tag`,
  `--status`, `--etag`, `--draft`, `--prerelease`, `--html-url`, `--body`,
  `--big`, `--slow`, `--reset`, `--redirect`, `--set-cookie`,
  `--all-headers`; `GET /__control?key=value` changes them while it runs).
- `site/` — the website, for GitHub Pages at the domain in `site/CNAME`:
  `index.html`, `download.html` (links the newest GitHub Release's `Sill.dmg`
  and `Sill.dmg.sha256`; never edited per release), `privacy.html` (the policy
  App Store Connect and the app link to), `support.html`, `terms.html` (the terms of service: the
  Apache license, Apple's EULA for the App Store copy, no warranty, no fees;
  linked in every footer), `style.css` (system
  fonts, light and dark) `icon.svg` (a copy of design/AppIcon.svg) and `preview.jpg` (the
  1200 × 630 share image that the Open Graph and Twitter card tags in every
  page's head name). No
  scripts and nothing loaded from elsewhere: every page's
  Content-Security-Policy is `default-src 'none'`. Links are relative and
  name a file (`download.html`; Home is `index.html`, since `./` opens nothing
  from the folder), so it renders from the folder; GitHub Pages also serves
  each page without `.html`, the form the app and App Store Connect use
  (`/download`, `/privacy`, `/support`). Remote Access paragraphs sit between
  `<!-- Remote Access` and `<!-- /Remote Access -->`, to cut for a release
  without it. `docs/release-checklist.md` is the order of work: the one-time
  setup (Developer ID, notary credentials, hosting and DNS, the App Store
  Connect record) and every release's steps.
- `Sources/VirtualDisplayProbe/` — CLI experiment for milestone 3; run it from
  Terminal (needs Screen Recording + Accessibility): `.build/release/VirtualDisplayProbe "Activity Monitor" --seconds 20`.
- `iOSClient/` — `Sill.xcodeproj` and its sources: `StreamClient` (Bonjour: a
  network browser and, when `DiscoveryPolicy` says, a nearby peer-to-peer one;
  `FoundMac` rows; connection, parsing, reconnect, the move of a session over
  AWDL to the network, a live session following the best path
  (`followBestPath`: to the cable, to Wi-Fi, made again over either), a remote
  session's move home (`moveHomeIfListed`, `MoveKind.fromRemote`), ping,
  generic `send`, and the pointer: kind 26 judged on its queue, `renderPointer`,
  `setOwnPointer`, `sendFromKeyRow`, a hand-over's carry-over),
  `SessionLink` (the session's connection and the one door out
  to the Mac; the moves' fenced hand-overs, which chain, and the hold of a move
  off a lost path: `handOver`, `hold`, `adopt`, `unhold`; the input messages
  counted for the session's connection, `inputsOnSession`, which a kind 26's
  `seen` is judged against; Foundation and Network only, checked with swiftc),
  `MessageReader` (the session's reader: each header, then the payload in
  pieces of at most 256 KB, every piece a sign of life for the liveness check;
  Network and StreamProtocol only, checked with swiftc),
  `DiscoveryPolicy` (when to look nearby, the rows and the word each ends in,
  the session's route word for the Settings panel,
  when a reconnect may take a Direct row, when a session over AWDL moves to
  the network, when a live session at home moves to the cable or to Wi-Fi or is
  made again (`pathPlan`, `upWait`; a remote one only home: `moveHome`, over
  TLS pinned to the saved Mac's key: `moveHomeTrust`, to a row chosen and
  refused by row: `moveHomeRow`, `HomeRows`, its kind 18 held to the floor taken
  as the move starts: `HomeMoveInfo`), the memory of Macs with
  Direct Wireless on, the Remote rows and when a lost saved Mac is dialed away
  from home; pairing at home's rows and words, a tap's dial, the device's
  cable check and how a session at home ends: `rowWord`, `homeDial`,
  `onCable`, `rowMac`, `reconnectEnd`, `macInfoNamesSession`,
  `removalRevokes`; pure, checked with swiftc), `StreamScreen`
  (landscape: top bar, thumbnails, drawer, Aa, Keyboard, Desktop; layout
  selection by size incl. Duo outer display, and `DuoLayout.phoneArrangement`,
  the idiom: which arrangement `.outerPortrait` draws; `DuoLayout.isPortrait`,
  the laptop layouts, where the trackpad's pointer shows), `PortraitStreamScreen`
  (portrait in two arrangements: the halves, the picture over the window bar,
  the key row and the trackpad, at the inner display's size and, for an iPad
  window narrower than 600 pt, the compact one with the key row in two lines;
  and a phone held upright, from `PhonePortraitLayout`; the key row's two sets,
  twelve and six), `PhonePortraitLayout` (a phone upright, `.outerPortrait` on
  an iPhone, as rects from the stream screen's size: the picture's fixed 16:10
  pane, row 1's five buttons in their band, the strip, six caps, the trackpad
  and its vertical span, the Aa ruler, the drawer and the Settings panel across
  row 1, and the dim, and the Menus button ending the strip's row (`menus`,
  `stripBesideMenus`); pure, `Tests/checks/phone-portrait`), `DuoPosture`
  (the iPhone Duo's posture and the rules that follow from it, docs/iphone-duo-plan.md:
  `FoldInfo`, inferred before iOS 27.1 or the fold's band; the laptop pose's
  split at the real fold and open flat's at the picture's shape, the book
  pose's bar, one page for a card (on its targets' page), the connect column
  and the room above the laptop pose's fold, the pairing overlay and the
  window lights; the stream screen's status bar (hidden on the inner display
  in every pose); the hinge from the fold before its first report; the
  harness's stand-in and the displays' safe areas; pure, `Tests/checks/duo`;
  pbxproj AB01/FB01), `DuoPostureReader` (iOS 27.1: `onHingeChange` at the
  app's root into `\.duoEnvironment`, `DuoPosture.read`, the `.division`
  region as a screen's own GeometryReader sees it; StreamScreen hands it to
  its layouts as `\.duoFold` and hides the status bar with `duoStatusBar`;
  AB02/FB02),
  `InputOverlay` (direct touch, Pencil, keyboard, scroll momentum; a
  trackpad's two-finger scroll through a pan of its own, scroll events only
  (`.continuous`, no wheel), into the glass's scroll at the pointer; each input
  says what drew this device's pointer; hardware keys through `ForwardedKeys`,
  let go when the overlay stops taking keys; `InputOverlayProxy.keysBlocked`,
  set by StreamScreen while the locked card is wanted: the view then takes no
  keyboard, whoever asks),
  `KeyChords` (`KeyModifiers`; a
  shortcut with its modifiers' own keys pressed around it, the Spotlight key's
  ⌘Space, the trackpad's modifier keys around a click; `ForwardedKeys`, a
  hardware key's up after its down; `CapsLockEscape`, This iPad's Caps Lock as
  Escape: the key, iPadOS's caps lock left out of every key's flags and every
  letter's case; pure, `Tests/checks/key-strokes` with the host's KeyStrokes),
  `CapsLockEscapeRow` (that switch and its footnote, on an iPad only, kept in
  `Sill.capsLockEscape`; pbxproj AD06/FD06), `KeyboardAlwaysOn` (This iPad's
  Keyboard Always On, `Sill.keyboardAlwaysOn`: while a keyboard is connected
  (GCKeyboard) the stream takes the keyboard whenever the Settings panel, the
  drawer, the locked card, the pairing overlay and the tour are all closed, and
  a keyboard that goes takes it down; `KeyboardAlwaysOnRow`, and
  `KeyboardAlwaysOnHooks`, StreamScreen's one modifier for it; pbxproj
  AD09/FD09), `TextScaleControl` (the Aa control, moved whole out of
  StreamScreen.swift on 2026-10-16; pbxproj AD08/FD08), `TrackpadView` (the relative pad: its
  cursor a `PadCursor`, from the anchor; a recognizer that only counts fingers;
  `verticalSpan`, a phone's width ÷ 1.6, and the DEBUG input test),
  `HEVCDisplayView` (shared display view, the one pointer sprite + DEBUG HUD),
  `DiagnosticsHUD` (client stats reporter),
  `StreamClient+Viewport`, `ContentView` (connect screen with rows ending in
  Wired, Wi-Fi, Direct or Remote, the hint and Search Nearby, Add a Mac…, and
  a footer along the bottom, "Needs the free Sill app on your Mac." with links
  to the download, support and the privacy policy, which open in Safari (one
  line while they fit, else the download link over the other two, as wide as
  the column); the column stays where it would be without the footer
  (centred; in the top half on the Duo's 710×1000, the footer still along the
  bottom; at the top while a field has the keyboard), rises only to keep 24 pt
  clear of the footer, never closer than 16 pt to the top, and scrolls above
  it, 16 pt from the top, when even that does not fit (a 12 pt fade, then
  12 pt clear, both inside the gap); one scroll view
  whatever the fit (`ColumnOverFooter`, measuring a hidden copy of the
  footer), so a fit that changes never builds the card anew (its fields, the
  camera); + DEBUG harness, and `InputScript`, `-SillInputScript`'s steps),
  `SillLinks`
  (the site's addresses, written once; getsill.app is live since 2026-09-25;
  and the App Store address for a Mac's update notice, the App Store Connect
  record's since PR #27),
  `MockCatalog` (harness data, the settings cases and the locked Mac,
  `seedLockScreen`), `HostSettingsLedger`
  (the Mac's settings with this device's unanswered picks; pure logic, checked
  with swiftc), `HostSettingsPanel` (the Settings panel; the route line, Away
  from home, the away line in the header, the link's callout and its button,
  the footnote, the slow-link callout for older Macs, the Lock Screen group's
  Lock ‹Mac› or Unlock ‹Mac›… row and, while a password is kept for Face ID,
  LockedCard.swift's `SavedUnlockRow`; its `Rows`, `Footnote` and `rowFrame()`
  are the module's, for that row), `AwayCopy` (every
  string of away from home and the link on the device, which callout shows,
  and `LinkLine`, the stream screen's line over time; pure,
  `Tests/checks/away-copy`; pbxproj A801/F801). Remote access: `DeviceIdentity`,
  `SavedMacs` (pure; `homeTLS` and `revoked` for pairing at home),
  `RemoteDialPolicy` (pure), `RemoteConnector`, `StreamClient+Remote`
  (pairing, remote dials, the reconnect order, links), `StreamClient+Home`
  (pairing at home: `DeviceTLS`, the one TLS builder for every connection to
  a Mac, the session gate at the first window list, the ask, the cable's
  proof-less ok, the proofs sent to a row, how a session at home ends;
  pbxproj A601/F601), `AddMacCard` (the card, the fields, `EscapeKey`; the
  home card for a row), `CodeScanner` (VisionKit),
  `PairingOverlay` (Pair This iPad…; `OverlayScrim`, the 85% black it and the
  locked card dim the layouts with), `GoodbyePolicy` (the words and the
  reconnect after a session ends, a Mac's notice included; pure, checked with
  swiftc). The Mac's menus (docs/menu-bar-plan.md §7): `StreamClient+Menus`
  (the subscription, the fetches and presses and their answers, moved whole out
  of StreamClient.swift on 2026-10-16; the stored properties stay there;
  pbxproj AD05/FD05), `MacMenuState` (one
  connection's view: the top level, the menus asked for and the choices sent,
  each opened menu's completion settled exactly once, the rows and sections;
  pure, `Tests/checks/menu-state`), `MacMenuElements` (the one builder of
  `UIMenuElement`s for the iPad's bar and the button: uncached deferred
  elements, `UIAction` leaves with the Mac's shortcut as the subtitle, never a
  `UIKeyCommand` or `UICommand`), `SillAppDelegate` (`SillApp`'s
  `@UIApplicationDelegateAdaptor`; only `buildMenu(with:)`) with `MacMenuBar`
  (where the Mac's menus go in the iPadOS 26 bar, once per build, every
  anchor looked up first), `MacMenuHub` (whose session the bar shows: the
  app's one window's while exactly one window scene is connected, none with
  two or more; from each scene's `WindowSessionObserver`; asks for a rebuild)
  and `MacMenuButton` (the bars' Menus button: the bar's look, and
  `MacMenuTrigger`'s clear UIButton with the pull-down over it; `fits`, where
  a bar holds it and still a whole thumbnail).
  `PointerPresence` (the rules of the one pointer sprite: the Mac's
  arrow while the Mac or another device moved it last, this device's own only
  for the portrait trackpad; a kind 26's freshness; the network queue's feed
  with a hand-over's carry-over; the key row keeping what shows; the portrait
  pad's cursor; pure, `Tests/checks/pointer-presence`; pbxproj A301/F301),
  `TrackpadGestures` (which stroke on the glass goes silent and which arms,
  the gesture decided as one of its three fingers lifts, and whether it goes
  to the Mac; pure, `Tests/checks/gestures`; pbxproj A701/F701) and
  `StrokeObserver` (the recognizer on both surfaces that feeds it every direct
  touch and takes none; moved whole out of InputOverlay.swift on 2026-10-16;
  pbxproj AD07/FD07). The
  first-run tour: `TourPolicy` (its steps and targets per layout, the halves,
  a phone's rows and sideways; when it shows by itself, what it remembers,
  what a session decided and the reconnect's, a rotation mid-run, the crease,
  where the card goes, every word; pure, Foundation and CoreGraphics,
  `Tests/checks/tour`) and `TourOverlay` (the dim with the lit cutout and its
  ring, the card placed by a Layout, the targets' preference in the stream
  screen's named space `sill.screen`, `TourStore` for `Sill.tourSeen` and
  `Sill.tourSkipped`, `TouchWatcher`, a recognizer on the window that counts
  every touch and takes none, and DEBUG `TourDebug`); StreamScreen runs it
  (targets, the rule's inputs, the layer above the layouts and under the
  pairing overlay, Take the Tour from the Settings panel's last row).
  Locking and unlocking the Mac (docs/lock-screen-plan.md, P2):
  `StreamClient+LockScreen` (the device's half of kind 44: `hostLocked`,
  `hostLockScreen` and `hostUnlock`, published from each window list;
  `sendUnlock`, one tap one request, whose caller clears its field once it has
  taken the secret, and `sendLock`; the one request on record, settled by the
  answer's token or, when none comes in time, said to be unanswered; the
  secret, its length and its characters printed nowhere; the password kept
  for Face ID (decision 3): `unlockMacID`, the saved Mac this connection is
  pinned to by its key (a home session pinned to that Mac's saved key, or a
  remote one), `savedOffer`, `unlockWithSaved` (Face ID, then the read, then
  everything judged again before one request), `savedUnlockPending` (a typed
  password held until the answer that keeps it), and `pruneSavedUnlock`, which
  storeSavedMacs calls so a Mac that leaves the list takes its password; DEBUG
  `mockLockScreenAnswer`, the harness Mac's answers; pbxproj AD01/FD01),
  `LockedCard` ("‹Mac› is locked": the card over the stream while the list says
  the console is locked, with a secure field (`textContentType(.password)`, so
  the Passwords app can fill it) and Unlock when the list says `unlock`, else a
  line to unlock at the Mac, and Hide; a ZStack sibling of the layouts in
  StreamScreen, which puts the panel and the stream's keyboard away first, sets
  `InputOverlayProxy.keysBlocked` and keeps the card under a pairing overlay
  that is open; for a password to a pinned Mac on a device with Face ID or
  Touch ID, "Use Face ID next time" (off each time it shows) and, once a
  password is kept, "Unlock with Face ID", a tap, never by itself; nothing else
  typed is kept, and a copy made while the card shows is never read, so never
  sent to the Mac's clipboard (StreamClient+Clipboard); also `SavedUnlockRow`,
  the Settings panel's Forget Saved Password; pbxproj AD02/FD02),
  `LockScreenPolicy` (when a request may go (`Block`), what became of the last
  one (`LockScreenAttempt`, with `fromSaved`), how long its answer is waited
  for, what the card offers for a kept password (`savedOffer`, never for a
  PIN) and what each answer does to it (`savedChange`), and every word of the
  card and of the panel's rows; pure, Foundation and StreamProtocol only,
  `Tests/checks/lock-device`; pbxproj AD03/FD03) and `SavedUnlock` (the
  keychain item, one per saved Mac by its Mac ID: service
  `me.saffer.sill.unlock`, `WhenPasscodeSetThisDeviceOnly` and
  `.biometryCurrentSet`, never synced; read after `evaluatePolicy` with the same
  context, so a failure after a face that matched means the item, which goes;
  `keepOnly`, the sweep; DEBUG `-SillBiometry` and `-SillLockSaved`; pbxproj
  AD04/FD04). Info.plist and Info-Debug.plist carry `NSFaceIDUsageDescription`.
  `Info-Debug.plist` is the Debug configuration's Info.plist: Info.plist's
  keys, with `_silltest._tcp` beside `_sill._tcp` for the harness's
  `-SillServiceType` (Release declares `_sill._tcp` alone).
  `PrivacyInfo.xcprivacy`, a resource of the target, is the privacy manifest:
  it declares UserDefaults (CA92.1) and `systemUptime` (35F9.1), and any new
  use of a required-reason API (file dates, disk space, `mach_absolute_time`,
  active keyboards) must add its category and reason there before the next
  upload. New files need their four pbxproj entries by hand.
  Swift 5 language mode.
- `docs/BRIEF.md` — product decisions, competition, scope, risks.
- `docs/DEVELOPMENT.md` — building, running and testing from source; the
  README's developer material until 2026-09-25, so a plan's "README" means a
  section there: the toolchain, make-app.sh, Sill.app's menu and Quality, the
  CLI's flags, the iOS project, Permissions (the TCC reset), settings from a
  device, Direct Wireless, pairing at home (the cable, Require pairing, older
  builds, starting over), remote access (setup, troubleshooting, reset), the
  test tools in brief (Build and run below has them all), measuring latency,
  troubleshooting (slow, frozen, the encoder), releasing, known limitations.
- `README.md` — the public front page: the site's lede, links to getsill.app
  and its download, support, privacy and terms pages, the App Store badge
  (live since 2026-10-10), requirements, how it works, tips, building from
  source in brief,
  contributing, the license. `LICENSE` — the Apache License 2.0.
  `design/screenshots/` — the README's screenshots: the App Store's iPad set at
  half size. Their raw URLs go to open-source app lists: keep the names.
  `.github/FUNDING.yml` — the Sponsor button: GitHub Sponsors (a `ko_fi:`
  line joins it once there is a Ko-fi handle). Tip links live there, in the
  README's Tips and on the site, never in the iOS app. `SECURITY.md` — how to
  report a vulnerability (support@getsill.app, never a public issue) and what
  is in scope. `.github/ISSUE_TEMPLATE/` — issue forms: a bug report, an idea,
  a question, no blank issue. `.gitignore` also leaves out signing keys,
  profiles, keychains and design/reel/.
- `.github/workflows/` — GitHub Actions on the `xcode-27` runner (macOS 27
  with Xcode 27, a public preview; the only image with Xcode 27). `ci.yml`:
  pull requests and pushes to main that touch more than documents or the site
  (`design/` counts: `dmg-layout` reads its SVG), and by hand; `swift build -c release`,
  `Tests/checks/run-all.sh`, the iOS app for the generic simulator (Debug,
  arm64, `CODE_SIGNING_ALLOWED=NO`; with Xcode 27.1, its beta while the image
  has no 27.1 release), and the CLI's paths that exit before the
  host starts (`--internet` alone, exit 2; `--print-reachability`); by hand
  with "mutants", each check's mutants in a job of its own. `release.yml`: a
  pushed tag `v*`, or by hand with one; verify only (the tag, the checks,
  `make-app.sh` signed ad hoc, zipped, and `make-dmg.sh`'s image of it, ad hoc
  too, as two artifacts) unless the repository
  variable `SILL_SIGN_IN_CI` is `true`, then the Developer ID .p12 into a
  temporary keychain, the notary key stored as a profile in it, `release.sh
  --publish`, Apple's notary logs kept as an artifact (`include-hidden-files:
  true`: upload-artifact skips whatever is under a folder whose name starts
  with a dot, `.build` included), and the keychain deleted in an always()
  step. Secrets,
  variables, rotation and costs: docs/release-checklist.md, "Releasing from
  GitHub Actions". `testflight.yml`: by hand only; `release-ios.sh
  --unsigned` without an App Store Connect key, `--sign-at-export` with one
  (the secrets `SILL_TESTFLIGHT_KEY_ID`, `SILL_TESTFLIGHT_ISSUER_ID`,
  `SILL_TESTFLIGHT_KEY_P8`, an Admin key: cloud signing, no certificate or
  profile stored), and `--upload` too when the variable `SILL_TESTFLIGHT_IN_CI`
  is `true`; the .ipa is the artifact for 14 days (docs/release-checklist.md,
  "TestFlight from GitHub Actions"). `.github/actions/select-xcode` —
  selects the newest Xcode of the `version` asked for (27; CI's build 27.1)
  whose folder is not a beta and prints `xcodebuild -version`; with
  `allow-beta: 'true'` (CI's build alone, never a build for App Store
  Connect), a version with no release yet takes its newest release candidate
  or beta; without one, CI warns and takes the newest Xcode there and a
  release (`fallback: false`) fails (CI only: it runs `sudo xcode-select`). The runner's `bash` is 3.2: try `run:`
  steps with `/bin/bash`. Actions are pinned by commit hash.
- `Tests/checks/` — the pure checks, a folder each: `main.swift`, `run.sh`
  (compiles the app's files it names with swiftc into `.build/checks/<name>/`
  and runs; `--mutants` runs `mutants.py`, passing only when every mutant is
  caught), and `build.sh` where a check compiles a module (StreamProtocol's
  sources with `import StreamProtocol` stripped), or a `module.txt` naming the
  files `module.py` compiles as one module (pairing at home's checks and the
  lock screen's):
  `addresses`, `ask-limits`, `cable-link`, `clientlink`, `compatibility`,
  `device-gate`, `dmg-layout` (Scripts/dmg-layout's `.DS_Store` and alias
  writer, against Finder's own layout of the file, make-dmg.sh's layout
  arguments and the SVG's size and edge), `door-policy`, `duo` (DuoPosture;
  `tour` and `phone-portrait` take the Duo's real sizes too), `encoder-mailbox`,
  `encoder-slowstate`, `fence`, `gesture-chords`, `gestures`, `goodbye`,
  `home-device`, `home-model`, `home-records`, `home-txt`, `key-strokes` (the
  host's KeyStrokes and the device's KeyChords, against a model of the Mac's
  HID state table and of a Mac from before), `ledger`, `lock-device`
  (iOSClient's LockScreenPolicy: the device's requests, the card's words and the
  password kept for Face ID), `lock-screen`
  (LockScreen.swift's rules with kind 44 and the window list's `locked`,
  `lockScreen` and `unlock`),
  `menu-state` (iOSClient's MacMenuState), `menus` (the host's MenuFormat and
  MenuPolicy, and MacMenu.swift's JSON), `message-reader`, `origin`,
  `pairing-address`, `phone-portrait`, `pointer-control`, `pointer-presence`,
  `pointer-watch`, `policy` (with its `home.swift`), `protocol`,
  `remote-rules` (with its `home.swift`), `tour`, `update-policy` (the two
  encoder checks refuse a binary that links VideoToolbox). `run-all.sh
  [--mutants] [-v] [name…]` runs them and exits
  with the number that failed (a folder whose `run.sh` is not executable
  fails); `common.sh` is sourced by each `run.sh`; `README.md` lists what each
  compiles and the checks that belong to open branches. A change to a checked
  file updates its check (and a mutant's pattern) in the same commit.
- `Tests/touchrig/` — the touch rig (docs/trackpad-gestures-plan.md §9.2): the
  real `TrackpadView.swift` and `InputOverlay.swift` in a scratch simulator
  app, driven with synthesized touches (`TouchSynth`, private UIKit calls, test
  only, never in the app), every event logged; `run.sh [--rev REV] [--switch
  off] NAME` builds and runs it on a simulator of its own
  (`SILL_TOUCHRIG_SIM`), `compare.py` judges a run against the surfaces
  before, and a stroke made right after a gesture against the same stroke
  made fresh.
- `Tests/duorig/` — TEST ONLY, private interfaces, simulator only: folds and
  turns the iPhone Duo simulator with Device Hub's own events (usage page
  0xFF61, usage 0x5B, an IOCFSerialize dictionary from
  `com.apple.Virtualization.VirtualMachines`), posted from a virtual HID
  service inside the simulator (`xcrun simctl spawn`); `run.sh build`, `run.sh
  UDID pose <closed-upright|closed-side|flat-portrait|flat-landscape|laptop|book>`,
  `run.sh UDID shot <pose> FILE.png`, `hinge`, `orient`, `watch`; only a
  booted iPhone Duo simulator, by UDID (its README).
