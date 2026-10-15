# A display for the device (Sidecar-style)

Ivor, 2026-10-15: "Sidecar resolution is on another level", then "plan it, look at the Sidecar
binary too". Status: plan, nothing built. Two read-only studies fed it: Sill's own display and
Desktop paths, and a static read of Sidecar's binaries (macOS 26.6.2, no live session, so every
Sidecar number below is from the binaries, not measured).

## What makes Sidecar sharp

From `SidecarDisplayAgent`, `SidecarRelay`, `SidecarCore` and `AVConference` (symbols and
literals read; the readings in brackets are inferred):

- One `CGVirtualDisplay` per session: vendor 'aapl', product 'iPad', "Sidecar Display",
  `setHiDPI: 1`, `setRefreshDeadline: 0.004`, maxPixels = the iPad's size × scale, sizeInMillimeters
  at exactly 264 ppi, Display P3 primaries with a D65 white. One mode, at the iPad's point size,
  60 Hz. No "Larger Text … More Space" table on the Mac: the size the iPad reports decides it.
- The encode is the iPad's native panel pixels: AVConference's Mac table lists 2732×2048,
  2388×1668, 2224×1668, 2048×1536 (and 3072×1728, 3840×2160), all at 60. Nothing rescales.
- HEVC, H.264 as the fallback, a frame split into several encode tiles, 4:4:4 negotiated when both
  ends can ('444v', '444f', 10-bit 'xf44'; which one Sidecar lands on is not in the binaries).
- At most 40 Mb/s for an iPad, over AWDL or USB, never the Wi-Fi access point. Rate control,
  FEC and the RTP transport are AVConference's own (FaceTime's media engine).
- Capture through CGDisplayStream with private keys (VideoToolbox, GPU boost, idle frames), not
  ScreenCaptureKit [since it passes a display ID and no picker].
- "Exclusive mode" and foveation are Vision Pro's Mac Virtual Display, not the iPad's.

None of it is a secret codec. The sharpness is: the picture's pixels are the device's pixels.

## Where Sill stands

- The Desktop streams the Mac's own screen scaled to the panel. Until d132f07 it also doubled a
  1× display under Retina (5120×2880 at 120 fps from a 2560×1440 monitor: 13 fps on the iPad);
  now it is at most the display's own pixels, still scaled to fit the iPad.
- Sill already creates `CGVirtualDisplay`s (VirtualDisplay.swift, VirtualStage.swift: one display,
  identity 0x5111/1/1, sized to an envelope around a staged window, HiDPI 2×, under the AppKit loop).
  Scale 1 or 2 only.
- The device sends its panel in points (`Viewport`: width, height, Aa scale, fps), never its
  pixel scale. The host keeps one viewport, the last device's.
- The Desktop deliberately avoids the virtual display (WindowCatalog.swift:245,
  StreamCoordinator.swift:331), and every input and pointer mapping reads the Desktop's display
  frame (currentSourceRect, pointerGeometry, DockEdge).

## The feature

A third kind of picture beside a window and the Desktop: **a display for this device**. The Mac
gets a new screen (extended, like Sidecar), sized so that its pixels are exactly the pixels of
the device's picture panel, and Sill streams it 1:1. You drag windows onto it on the Mac, or pick a
window on the device and Sill puts it there (the virtual display staging that exists).

Sizing, per device:

| Device | Panel (pts, landscape, approx.) | Display mode | Encoded |
|---|---|---|---|
| iPad Pro 12.9" (yours, iPad8,11) | 1366×~940 (under the bar) | HiDPI 1366×940 pt | 2732×1880 |
| iPad mini | 1133×~660 | HiDPI 1133×660 pt | 2266×1320 |
| iPhone 16 Pro Max (3×) | 956×~360 | HiDPI 1434×540 pt | 2868×1080 |

The display is the **panel**, not the whole screen, because the bar, the phone's rows and the Duo's
panes take the rest. On a 3× iPhone a 2× display at the panel's pixels ÷ 2 keeps pixels 1:1 and
draws the Mac's UI at 1.5× the iPhone's points (readable on a phone); a 3× HiDPI mode is unknown
territory (probe P1c).

Larger Text … More Space: the existing Aa control. Default (1×) is 1:1 pixels. "More Space"
(Aa 0.75, 0.5) makes a bigger display in points whose pixels exceed the panel's, scaled down on
the way (ScreenCaptureKit's output size), so text gets smaller and less crisp, as Sidecar's own
"More Space" does on macOS. "Larger Text" (Aa 1.25, 1.5) a smaller one, scaled up. Only Default
is 1:1.

## Phases

**P0 probes (no product code; gate the rest).**
- P1a: `--virtual-display-selftest W H` at 1366×940 pt 2× and 1434×540: online, the 2× mode
  selected, ScreenCaptureKit sees it.
- P1b: the encoder at 2732×1880, 60 and 120 fps, with the existing probe and a real-content run
  (the 33 fps slow state hit 3024-class frames before; the new-session fix should cover it).
  Only while no device streams from Sill.app.
- P1c: does `setHiDPI` take a 3× scale (iPhone)?
- P1d: HEVC 4:4:4 encode on this Mac's hardware (`kVTProfileLevel_HEVC_Main42210`/RExt support
  via VTCopySupportedPropertyDictionary) and decode on the iPad (A12Z) and iPhone.
- P1e: iPad decode of 2732×1880 HEVC at 60 and 120 fps (frame age in the client's stats).
  Not a P0 gate: nothing on this Mac produces that size without the feature, and a test host may
  not take a LAN connection. Measured on the first P1 device run; the device half of P1d (4:4:4
  decode) likewise, and it only gates P3.

**P0 results (2026-10-15, Mac15,6 M3 Pro, macOS 26.6.2; raw output in the session's scratchpad).**
- P1a: 1366×940 pt comes up extended at 2732×1880 px in 578 ms, 1434×540 pt at 2868×1080 in
  487 ms; SCK sees pointPixelScale 2. macOS places it left of the main display with its own menu
  bar, and offers 1× modes at the same points, so the 2× mode is selected explicitly.
- P1c: setHiDPI is a flag. 3 behaves as 0; no 3× mode exists. Phones get 2× at pixels ÷ 2.
- P1b: 2732×1880 hardware HEVC holds 60.0 fps (14 ms per frame, no drops, 65 s). At 120 it
  runs ~105 fps with ~15 drops a second after the engine's first 3 s at 7 ms. So 60 only. The 33 fps
  slow state appeared after sparse frames and EncoderSlowState recovered it.
- P1d (Mac): the hardware encoder lists Main444, Main44410 and Main42210; an 8-bit 4:4:4 encode at
  this size took 11.0 ms against 10.6 for 4:2:0 (short runs, trivial content).
- Found on the way: the AppleAVE2 heartbeat is absent on macOS 26.6.2, so
  Scripts/encoder-check/engine-free.sh always says "free" here; and no-device.sh takes the start
  time as its bare first argument.

**P1 host (Sources/SillHost).**
- `DeviceDisplay` (new, pure geometry in `DeviceDisplayGeometry`: panel points × device pixel
  scale ÷ Aa → mode points and pixels, the 2×/3× rule, the bounds; a check in
  `Tests/checks/device-display` with mutants).
- Its own identity (product 0x5111/2, serial per device ID) so macOS remembers where the user put it
  and it never collides with the window stage.
- The Desktop source learns a display ID: capture filter, `currentSourceRect`, `pointerGeometry`
  and `DockEdge` read `CGDisplayBounds(id)`; `preferMainDisplay` stays for the Mac's screen.
- Lifecycle as the window stage's: created on pick, kept across rotation by changing its mode
  (Sidecar re-applies settings on rotation), removed on deselect, last device leaving, quit and
  signals (`HostShutdown`); windows on it go home to the main display first.
- 60 fps by default at native size (Sidecar's own choice); 120 only where P1b says it keeps up.

**P2 wire and device (additive only, per the compatibility floor).**
- `Viewport.pixelScale: Double?` (UIScreen.scale); nil from older devices, which keep today's
  Desktop.
- Asking for the display: `StreamSource` keeps its three cases, so the pick is `.desktop` with a
  new optional field on the select message (`deviceDisplay: true`), and the window list says the
  host offers it (`WindowList.deviceDisplay: 1`), as gestures did.
- The device: where to put the choice is a decision (below).

**P3 quality (after P1/P2 work and are measured).**
- Display P3 primaries on the virtual display and a P3 capture colour space (Sill encodes sRGB).
- 4:4:4 where P1d says both ends can: the biggest remaining gain for text, at a bitrate cost.
- A bitrate floor for this mode (Sidecar allows up to 40 Mb/s; Sill's Pro preset is 40).

## Decisions for Ivor

Accepted 2026-10-15 ("go with the recommendations"): (b) the setting, extend only, iPhones
included, and the display follows the device that picked it.

1. **Where the choice lives.** (a) A second Desktop button state: tap Desktop for the Mac's
   screen, hold it for "a display for this iPad"; (b) a setting, Settings › Desktop: "This Mac's
   screen" / "A display for this iPad", which the Desktop button then follows; (c) its own bar
   button. Recommended: (b), no new control in the bar, and it persists per device.
2. **Extend only, or also mirror?** Mirroring would force the 2560×1440 monitor into the iPad's
   mode. Recommended: extend only, as Sidecar does by default.
3. **iPhones.** 2× at pixels ÷ 2 (1:1 pixels, Mac UI 1.5× bigger) or skip phones for the first
   release. Recommended: include them, it is the same code.
4. **Two devices at once.** One pipeline today: the display follows the device that picked it,
   the other sees it scaled. Recommended for the first release; a display per device later.

## Untested and risky

- Extend vs mirror, the menu bar and Dock on the new display, where windows land when it goes:
  only a live run tells (Displays have separate Spaces matters).
- 120 fps at iPad Pro native size is at the encoder's measured limit (~650 MP/s here).
- Private API: `CGVirtualDisplay` is already shipped behind Virtual Display, Developer ID only; the
  App Store never sees it (the Mac app is not on the App Store).
- AWDL and USB carry Sidecar; Sill's home path is the infrastructure Wi-Fi unless the cable or
  Direct Wireless is in use, so on a busy network Sill will stay softer than Sidecar at the same
  pixels.
