// Mac state (Tests/evidence/README.md): one JSON object of what the Mac objectively shows at this
// moment, to take before and after a gesture: the Dock's windows (CGWindowListCopyWindowInfo, owner
// "Dock": layer, bounds, alpha, on screen), the Dock's autohide and orientation defaults, the pointer
// both ways, the main display's frame and the pasteboard's digest (hashes, never contents).
// Evidence only, never linked into Sill.
//
//   macstate             pretty JSON
//   macstate --line      one line (for appending to a JSONL)
//
// Coordinates: `pointer.cg` and the windows' bounds are global, top-left origin (Quartz);
// `pointer.appKit` and `mainDisplay.appKitFrame` are bottom-left origin (AppKit). Both in points.
// A missing Dock default reads null: autohide is then off and the orientation is bottom.
import AppKit
import CoreGraphics

func defaultsRead(_ key: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    p.arguments = ["read", "com.apple.dock", key]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func rect(_ r: CGRect) -> [String: Double] {
    ["x": Double(r.origin.x), "y": Double(r.origin.y), "w": Double(r.width), "h": Double(r.height)]
}

let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerName as String] as? String) == "Dock" }
    .map { w -> [String: Any] in
        var bounds = CGRect.zero
        if let b = w[kCGWindowBounds as String] as! CFDictionary? { bounds = CGRect(dictionaryRepresentation: b) ?? .zero }
        return [
            "id": w[kCGWindowNumber as String] ?? NSNull(),
            "name": w[kCGWindowName as String] ?? NSNull(),
            "layer": w[kCGWindowLayer as String] ?? NSNull(),
            "alpha": w[kCGWindowAlpha as String] ?? NSNull(),
            "onscreen": (w[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            "bounds": rect(bounds),
        ]
    }

let display = CGMainDisplayID()
let screen = NSScreen.screens.first
let state: [String: Any] = [
    "wall": Date().timeIntervalSince1970,
    "uptime": ProcessInfo.processInfo.systemUptime,
    "dock": [
        "autohide": defaultsRead("autohide") ?? NSNull(),
        "orientation": defaultsRead("orientation") ?? NSNull(),
        "autohideDelay": defaultsRead("autohide-delay") ?? NSNull(),
        "windows": windows,
    ] as [String: Any],
    "pointer": [
        "cg": ["x": Double(CGEvent(source: nil)?.location.x ?? .nan), "y": Double(CGEvent(source: nil)?.location.y ?? .nan)],
        "appKit": ["x": Double(NSEvent.mouseLocation.x), "y": Double(NSEvent.mouseLocation.y)],
    ] as [String: Any],
    "mainDisplay": [
        "id": Int(display),
        "cgBounds": rect(CGDisplayBounds(display)),
        "pixelsWide": CGDisplayPixelsWide(display), "pixelsHigh": CGDisplayPixelsHigh(display),
        "appKitFrame": screen.map { rect($0.frame) } ?? NSNull(),
        "appKitVisibleFrame": screen.map { rect($0.visibleFrame) } ?? NSNull(),
        "backingScale": screen.map { Double($0.backingScaleFactor) } ?? NSNull(),
    ] as [String: Any],
    "displays": NSScreen.screens.map { ["frame": rect($0.frame), "visibleFrame": rect($0.visibleFrame)] },
    "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? NSNull(),
    "pasteboard": PasteboardDigest.read(),
]
let options: JSONSerialization.WritingOptions = CommandLine.arguments.contains("--line") ? [.sortedKeys] : [.sortedKeys, .prettyPrinted]
let data = try JSONSerialization.data(withJSONObject: state, options: options)
print(String(decoding: data, as: UTF8.self))
