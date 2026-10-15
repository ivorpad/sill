import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit

/// A display for one device (docs/sidecar-desktop-plan.md): a HiDPI virtual display, extended, whose
/// pixels are the device's picture panel's (DeviceDisplayGeometry), which the Desktop streams 1:1
/// while the device that picked the Desktop asks for it (its viewport's `deviceDisplay`).
///
/// Separate from VirtualStage, which owns one window on its own display and moves every other
/// window off it. This display is the user's: they drag windows onto it on the Mac, and nothing here
/// moves a window while it lives. Only when it goes do the windows on it go home to the main display
/// first (`moveWindowsHome`), so the window server does not drop them wherever it likes.
///
/// Identity: vendor 0x5111 (Sill's), product 2 (the window stage is 1), serial per paired key
/// (DeviceDisplayGeometry.serial), so macOS remembers where the user put each device's display.
///
/// Lifecycle: made on the Desktop's pick (`ensure`), given a new mode on a rotation or an Aa step
/// (`ensure` again: `setMode` within the square it was made for, else a new display), removed by
/// `release` (a window or nothing picked, the picker gone, the last device gone, quit, a signal).
/// A process that dies takes it along.
///
/// Threading: main actor throughout, like the coordinator. `release` is synchronous with no awaits,
/// so the signal handler (HostShutdown) can run it at any main-actor suspension point. The display's
/// termination handler fires on its private queue and hops here with a generation guard.
@MainActor
final class DeviceDisplay {
    static let vendorID: UInt32 = VirtualStage.vendorID
    static let productID: UInt32 = 0x0002

    enum Failure: Error, CustomStringConvertible {
        case create(Error)
        case neverOnline
        case notListedBySCK
        var description: String {
            switch self {
            case .create(let e): return "creating the display failed (\(e))"
            case .neverOnline: return "the display never came online"
            case .notListedBySCK: return "ScreenCaptureKit never listed the display"
            }
        }
    }

    private(set) var display: VirtualDisplay?
    /// ScreenCaptureKit's view of the display at its current mode (re-listed after every mode change:
    /// an SCDisplay's size is the one it was listed at).
    private(set) var scDisplay: SCDisplay?
    /// The mode it has now, and the serial it was made with.
    private(set) var geometry: DeviceDisplayGeometry?
    private var serial: UInt32 = 0
    /// Bumped per display made, so a late termination callback for an old one is ignored.
    private var generation = 0
    /// The window server tore the display down on its own (sleep, display arbitration). Main actor.
    var onLost: (() -> Void)?
    /// Called just before the display warps the Mac's pointer home (PointerWatch.sillMoved). Main actor.
    var onWarp: (() -> Void)?

    var exists: Bool { display?.isAlive == true }
    var displayID: CGDirectDisplayID? { exists ? display?.displayID : nil }
    /// The display in global points, for input, the pointer and the Dock; nil while there is none.
    var bounds: CGRect? { displayID.map { CGDisplayBounds($0) } }

    /// The display at `mode` for the device whose serial is `serial`, at `refreshHz`, and its
    /// SCDisplay. Kept when it already has all three; re-moded when only the mode differs and it
    /// fits the square it was made for; otherwise made anew (windows on the old one sent home
    /// first). Call only with capture stopped: the old SCDisplay is stale once this returns.
    /// `capacitySide`: the square, in points, a new display is made for. Throws with no display left.
    func ensure(_ mode: DeviceDisplayGeometry, serial: UInt32, refreshHz: Int, capacitySide: Int) async throws -> SCDisplay {
        if let d = display, d.isAlive, let sc = scDisplay, self.serial == serial, Int(d.refreshHz) == refreshHz {
            if geometry == mode { return sc }
            let t0 = Date()
            if mode.fits(side: min(d.maxWidthPt, d.maxHeightPt)), (try? d.setMode(widthPt: mode.widthPt, heightPt: mode.heightPt)) == true {
                geometry = mode
                scDisplay = nil
                let online = await d.waitUntilOnline(timeout: 3)
                if online, display === d, let listed = await listed(d, timeout: 3) {
                    scDisplay = listed
                    Stats.shared.bump("dd.remoded")
                    print("Device display \(d.displayID): now \(mode), \(Self.ms(since: t0)) ms")
                    return listed
                }
                print("Device display \(d.displayID) did not come back at \(mode); making a new one.")
            } else {
                print("Device display \(d.displayID) cannot take \(mode); making a new one.")
            }
        }
        release()

        let t0 = Date()
        let d: VirtualDisplay
        do {
            d = try VirtualDisplay(name: "Sill Display", widthPt: mode.widthPt, heightPt: mode.heightPt, scale: DeviceDisplayGeometry.scale,
                                   refreshHz: Double(refreshHz), vendorID: Self.vendorID, productID: Self.productID, serialNum: serial,
                                   maxSidePt: capacitySide)
        } catch {
            throw Failure.create(error)
        }
        generation += 1
        let gen = generation
        display = d
        geometry = mode
        self.serial = serial
        // Fires on the display's private queue; the owner lives on the main actor.
        d.onTerminated = { [weak self] in Task { @MainActor [weak self] in self?.lost(generation: gen) } }

        // Never blocks main: the reconfiguration arrives through the AppKit loop this await lets run.
        let online = await d.waitUntilOnline(timeout: 3)
        if !online {
            if d.bounds.width == 0 || display !== d { release(); throw Failure.neverOnline }
            print("Device display is online but not at \(d.widthPt)×\(d.heightPt) @2×: backing \(d.pixelSize.width)×\(d.pixelSize.height) px. Modes: \(d.availableModes().joined(separator: "; "))")
        }
        let onlineMs = Self.ms(since: t0)
        guard display === d, let listed = await listed(d, timeout: 3), display === d else {
            release()
            throw Failure.notListedBySCK
        }
        scDisplay = listed
        Stats.shared.bump("dd.created")
        print("Device display \(mode) id \(d.displayID) serial \(serial): online \(onlineMs) ms, listed by ScreenCaptureKit after \(Self.ms(since: t0)) ms, at \(Self.fmt(d.bounds))")
        return listed
    }

    /// ScreenCaptureKit's SCDisplay for `d` once it reports the current mode's size: it lists a new
    /// display, and a new mode, a little after CoreGraphics. Bounded: without Screen Recording the
    /// call has been seen to never return while a virtual display exists (VirtualStage).
    private func listed(_ d: VirtualDisplay, timeout: TimeInterval) async -> SCDisplay? {
        let t1 = Date()
        while Date().timeIntervalSince(t1) < timeout {
            let remaining = max(0.2, timeout - Date().timeIntervalSince(t1))
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: remaining),
               let found = c.displays.first(where: { $0.displayID == d.displayID }),
               found.width == d.widthPt, found.height == d.heightPt {
                return found
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    // MARK: Teardown (synchronous, idempotent; the signal handler calls it)

    /// Windows on it home, the pointer home, then the display gone.
    func release() {
        guard let d = display else { return }
        if d.isAlive {
            let b = CGDisplayBounds(d.displayID)
            moveWindowsHome(from: b)
            if let here = CGEvent(source: nil)?.location, b.contains(here) {
                let main = CGDisplayBounds(CGMainDisplayID())
                onWarp?()
                CGWarpMouseCursorPosition(CGPoint(x: main.midX, y: main.midY))
            }
        }
        let id = d.displayID
        display = nil
        scDisplay = nil
        geometry = nil
        d.destroy()
        print("Removed device display \(id)")
    }

    /// Every normal window on the display moves to the main display, centred at its own size
    /// (WindowSizer.homeFrame), as VirtualStage sends a stranger off its display. A full-screen
    /// window cannot be moved from here: the window server places it when the display goes.
    private func moveWindowsHome(from bounds: CGRect) {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b as CFDictionary),
                  rect.width >= 100, rect.height >= 100 else { continue }
            // A window counts as on this display when its middle is (one straddling two displays
            // belongs to the other one).
            guard bounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else { continue }
            let owner = (info[kCGWindowOwnerName as String] as? String) ?? "?"
            guard let ax = WindowSizer.axWindow(pid: pid, frame: rect) else {
                print("A \(owner) window on the device display could not be matched to move it home (\(Self.fmt(rect)))")
                continue
            }
            if WindowSizer.isFullScreen(ax) {
                print("A \(owner) window is full screen on the device display; macOS places it when the display goes")
                continue
            }
            let home = WindowSizer.homeFrame(size: rect.size)
            let err = WindowSizer.setPosition(ax, home.origin)
            print("Moved a \(owner) window off the device display to \(Self.fmt(home)) (\(WindowSizer.axErrorName(err)))")
            Stats.shared.bump("dd.windowHome")
        }
    }

    /// The window server tore the display down. The object is dead and its windows are on some real
    /// display already; the owner's `onLost` restarts the Desktop.
    private func lost(generation gen: Int) {
        guard gen == generation, display != nil else { return }   // our own destroy() may fire this too
        display = nil
        scDisplay = nil
        geometry = nil
        Stats.shared.bump("dd.lost")
        onLost?()
    }

    private static func fmt(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))×\(Int(r.height)))"
    }
    private static func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
}
