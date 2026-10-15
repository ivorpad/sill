import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// `SillHost --virtual-display-selftest`: creates one 1000×700 pt @2× virtual display from a
/// process that runs the AppKit event loop exactly as `--virtual-display` does, reports what this
/// process, CoreGraphics, AppKit and ScreenCaptureKit see of it, destroys it and exits. The
/// display part needs no permission; SCShareableContent needs Screen Recording and the report
/// says so when it is missing. Exit code 0 when the display came up and went away cleanly.
package enum VirtualDisplaySelfTest {
    package static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let code = await go()
            exit(code)
        }
        app.run()
        exit(0)   // app.run() does not return
    }

    private static func onlineDisplays() -> [CGDirectDisplayID] {
        var n: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetOnlineDisplayList(n, &ids, &n)
        return Array(ids.prefix(Int(n)))
    }

    @MainActor
    private static func go() async -> Int32 {
        print("Virtual display self-test (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
        print("  Screen Recording preflight: \(CGPreflightScreenCaptureAccess()), Accessibility trusted: \(AXIsProcessTrusted()) [informational]")
        let problems = VirtualDisplay.checkPrivateAPI()
        guard problems.isEmpty else {
            for p in problems { print("  FAIL \(p)") }
            return 1
        }
        print("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present")
        let before = onlineDisplays()
        print("  displays before: \(before)")
        let probe = Probe.parse(CommandLine.arguments)
        let mainBefore = describeMain()
        if probe.active { print("  main display before: \(mainBefore)") }

        let t0 = Date()
        let d: VirtualDisplay
        do {
            // `--virtual-display-selftest 120` asks for a 120 Hz display (what a ProMotion device gets).
            let args = CommandLine.arguments
            let hz = args.firstIndex(of: "--virtual-display-selftest").flatMap { i in args.count > i + 1 ? Double(args[i + 1]) : nil } ?? 60
            if probe.active {
                // A device display's size (docs/sidecar-desktop-plan.md, P1a/P1c), under its own
                // test identity, never the window stage's 0x5111/1/1 that Sill.app holds.
                d = try VirtualDisplay(name: "Sill probe", widthPt: probe.width, heightPt: probe.height, scale: 2, refreshHz: hz,
                                       vendorID: VirtualStage.vendorID, productID: 0x0002, serialNum: 0xBEEF,
                                       probeHiDPI: probe.hiDPI)
                print("  probe: \(probe.width)×\(probe.height) pt, identity 0x5111/2/0xBEEF, setHiDPI: \(probe.hiDPI.map(String.init) ?? "1 (scale 2)")")
            } else {
                d = try VirtualDisplay(name: "Sill", widthPt: 1000, heightPt: 700, scale: 2, refreshHz: hz,
                                       vendorID: VirtualStage.vendorID, productID: VirtualStage.productID, serialNum: VirtualStage.serialNum)
            }
            print("  requested refresh: \(Int(hz)) Hz")
        } catch {
            print("  FAIL create: \(error)")
            return 2
        }
        let createdMs = Int(Date().timeIntervalSince(t0) * 1000)
        // With a raw setHiDPI: value (P1c) the requested-mode selection would force the 2× mode
        // and hide what macOS made of it: wait for bounds alone and report the mode as it is.
        let online: Bool
        if probe.hiDPI != nil {
            let until = Date().addingTimeInterval(3)
            while CGDisplayCopyDisplayMode(d.displayID) == nil, Date() < until { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .seconds(1))   // let macOS settle on a mode before reading it
            online = CGDisplayCopyDisplayMode(d.displayID) != nil
        } else {
            online = await d.waitUntilOnline(timeout: 3)
        }
        let onlineMs = Int(Date().timeIntervalSince(t0) * 1000)
        let px = d.pixelSize
        print("  created id \(d.displayID) in \(createdMs) ms; online at requested mode: \(online) after \(onlineMs) ms")
        print("  bounds \(d.bounds), backing \(px.width)×\(px.height) px")
        if let mode = CGDisplayCopyDisplayMode(d.displayID) { print("  current mode refresh: \(Int(mode.refreshRate)) Hz") }
        // Input reachability: the host maps device touches to global coordinates on this display
        // and posts HID mouse events there. If the window server keeps the cursor off virtual
        // displays, every click lands somewhere else. Warp, post a move, read back, restore.
        if let mode = CGDisplayCopyDisplayMode(d.displayID) {
            print("  current mode: \(mode.width)×\(mode.height) pt @ \(mode.pixelWidth)×\(mode.pixelHeight) px, \(Int(mode.refreshRate)) Hz")
        }
        if probe.active {
            let mirrorOf = CGDisplayMirrorsDisplay(d.displayID)
            print("  mirror: in mirror set \(CGDisplayIsInMirrorSet(d.displayID) != 0), mirrors \(mirrorOf) (0: extended); main display mirrors \(CGDisplayMirrorsDisplay(CGMainDisplayID()))")
            print("  placement: CGDisplayBounds \(CGDisplayBounds(d.displayID)), main display \(CGMainDisplayID())")
        }
        // The probe never moves the pointer or posts an event (a probe run beside Sill.app).
        if !probe.active, let before = CGEvent(source: nil)?.location {
            let target = CGPoint(x: d.bounds.midX, y: d.bounds.midY)
            CGWarpMouseCursorPosition(target)
            usleep(30_000)
            let afterWarp = CGEvent(source: nil)?.location ?? .zero
            if let mv = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left) {
                mv.post(tap: .cghidEventTap)
            }
            usleep(30_000)
            let afterPost = CGEvent(source: nil)?.location ?? .zero
            CGWarpMouseCursorPosition(before)
            let onIt = { (p: CGPoint) in d.bounds.contains(p) }
            print("  cursor reach: warp to \(target) → \(afterWarp) (on display: \(onIt(afterWarp))); HID move → \(afterPost) (on display: \(onIt(afterPost))); cursor restored to \(before)")
        }
        print("  CGGetOnlineDisplayList contains it: \(onlineDisplays().contains(d.displayID)); CGDisplayIsActive \(CGDisplayIsActive(d.displayID) != 0)")
        let modes = d.availableModes()
        print("  modes (\(modes.count)): \(modes.joined(separator: "; "))")

        // AppKit's view, which the stage uses for the menu-bar inset.
        let deadline = Date().addingTimeInterval(1)
        while VirtualStage.screen(for: d.displayID) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        if let s = VirtualStage.screen(for: d.displayID) {
            print("  NSScreen: frame \(s.frame), visibleFrame \(s.visibleFrame), menu bar \(Int(s.frame.maxY - s.visibleFrame.maxY)) pt, usable (CG) \(VirtualStage.usableArea(of: d.displayID) ?? .zero)")
        } else {
            print("  NSScreen: not listed after 1 s (the stage would assume a 24 pt menu bar)")
        }

        // ScreenCaptureKit's view. Needs Screen Recording; without it the call has been seen to
        // never return while a virtual display exists, hence the bound (the same one the stage uses).
        let t1 = Date()
        var listed = false
        var answered = false
        while Date().timeIntervalSince(t1) < 3, !listed {
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: 3) {
                answered = true
                if let scd = c.displays.first(where: { $0.displayID == d.displayID }) {
                    listed = true
                    print("  SCDisplay: width \(scd.width) height \(scd.height) frame \(scd.frame)")
                    let filter = SCContentFilter(display: scd, excludingWindows: [])
                    print("  SCContentFilter: contentRect \(filter.contentRect), pointPixelScale \(filter.pointPixelScale)")
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if listed {
            print("  SCShareableContent lists it after \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
        } else if answered {
            print("  SCShareableContent answered but did not list it within 3 s")
        } else {
            print("  SCShareableContent did not answer within \(Int(Date().timeIntervalSince(t1) * 1000)) ms (Screen Recording preflight \(CGPreflightScreenCaptureAccess())); the stage would fall back to the real window")
        }

        let id = d.displayID
        d.destroy()
        let t2 = Date()
        while onlineDisplays().contains(id), Date().timeIntervalSince(t2) < 3 { try? await Task.sleep(for: .milliseconds(50)) }
        let gone = !onlineDisplays().contains(id)
        print("  destroyed: gone from CGGetOnlineDisplayList after \(Int(Date().timeIntervalSince(t2) * 1000)) ms: \(gone)")
        print("  displays after: \(onlineDisplays())")
        if probe.active {
            let mainAfter = describeMain()
            print("  main display after: \(mainAfter) (\(mainAfter == mainBefore ? "unchanged" : "CHANGED"))")
        }
        return (online || px.width > 0) && gone ? 0 : 3
    }

    private static func describeMain() -> String {
        let id = CGMainDisplayID()
        let m = CGDisplayCopyDisplayMode(id)
        return "id \(id) bounds \(CGDisplayBounds(id)) mode \(m?.width ?? 0)×\(m?.height ?? 0) pt @ \(m?.pixelWidth ?? 0)×\(m?.pixelHeight ?? 0) px"
    }

    /// Probe flags (docs/sidecar-desktop-plan.md P1a/P1c): `--vd-size=WxH` in points (scale 2),
    /// `--vd-hidpi=N` the raw setHiDPI: value. Either one switches to the test identity and skips
    /// the cursor check.
    private struct Probe {
        var width = 1000, height = 700
        var hiDPI: UInt32?
        var active = false
        static func parse(_ args: [String]) -> Probe {
            var p = Probe()
            for a in args {
                if a.hasPrefix("--vd-size=") {
                    let wh = a.dropFirst("--vd-size=".count).split(separator: "x").compactMap { Int($0) }
                    if wh.count == 2 { p.width = wh[0]; p.height = wh[1]; p.active = true }
                } else if a.hasPrefix("--vd-hidpi=") {
                    p.hiDPI = UInt32(a.dropFirst("--vd-hidpi=".count)); p.active = true
                }
            }
            return p
        }
    }
}
