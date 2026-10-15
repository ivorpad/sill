// EventTap (Tests/evidence/README.md): every pointer, scroll, gesture, magnify and modifier event the
// Mac's session sees, one JSONL record each, with the process that posted it, so Sill's own posts
// (SillHost's or Sill.app's pid) read apart from the trackpad's and the mouse's (pid 0). A
// listen-only session tap: it changes nothing and needs Input Monitoring. Key downs and ups log
// their type and flags only, never which key. Evidence only, never linked into Sill.
//
//   eventtap [--out FILE]     JSONL to stdout, or appended to FILE; Ctrl-C stops
//
// `t` is the event's own timestamp (nanoseconds since boot, CGEventTimestamp), `wall` the epoch
// seconds when the tap read it. Locations are CGEvent's: global, top-left origin, points.
import AppKit
import CoreGraphics
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var out: FileHandle = .standardOutput
if let i = CommandLine.arguments.firstIndex(of: "--out"), i + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[i + 1]
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    guard let h = FileHandle(forWritingAtPath: path) else { fputs("eventtap: cannot write \(path)\n", stderr); exit(1) }
    h.seekToEndOfFile()
    out = h
}

let names: [UInt32: String] = [
    0: "null", 1: "leftMouseDown", 2: "leftMouseUp", 3: "rightMouseDown", 4: "rightMouseUp", 5: "mouseMoved",
    6: "leftMouseDragged", 7: "rightMouseDragged", 10: "keyDown", 11: "keyUp", 12: "flagsChanged",
    22: "scrollWheel", 23: "tabletPointer", 24: "tabletProximity", 25: "otherMouseDown",
    26: "otherMouseUp", 27: "otherMouseDragged", 29: "gesture", 30: "magnify", 31: "swipe",
    32: "smartMagnify", 34: "pressure", 18: "rotate", 19: "beginGesture", 20: "endGesture",
    0xFFFFFFFE: "tapDisabledByTimeout", 0xFFFFFFFF: "tapDisabledByUserInput",
]
let mouseish: Set<UInt32> = [1, 2, 3, 4, 5, 6, 7, 25, 26, 27]
var tapPort: CFMachPort?

func flagNames(_ f: CGEventFlags) -> [String] {
    var n: [String] = []
    if f.contains(.maskShift) { n.append("shift") }
    if f.contains(.maskControl) { n.append("control") }
    if f.contains(.maskAlternate) { n.append("option") }
    if f.contains(.maskCommand) { n.append("command") }
    if f.contains(.maskSecondaryFn) { n.append("fn") }
    if f.contains(.maskAlphaShift) { n.append("capsLock") }
    if f.contains(.maskNumericPad) { n.append("numericPad") }
    if f.contains(.maskNonCoalesced) { n.append("nonCoalesced") }
    return n
}

func phaseName(_ p: NSEvent.Phase) -> [String] {
    var n: [String] = []
    if p.contains(.began) { n.append("began") }
    if p.contains(.stationary) { n.append("stationary") }
    if p.contains(.changed) { n.append("changed") }
    if p.contains(.ended) { n.append("ended") }
    if p.contains(.cancelled) { n.append("cancelled") }
    if p.contains(.mayBegin) { n.append("mayBegin") }
    return n
}

func record(_ type: CGEventType, _ event: CGEvent) {
    let raw = type.rawValue
    if raw >= 0xFFFFFFFE {
        // The system turned the tap off (a slow callback, or secure input); turn it back on and say so.
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }
    let loc = event.location
    var r: [String: Any] = [
        "t": event.timestamp, "wall": Date().timeIntervalSince1970,
        "type": names[raw] ?? "type\(raw)", "typeRaw": raw,
        "x": loc.x, "y": loc.y,
        "flags": flagNames(event.flags), "flagsRaw": event.flags.rawValue,
        "pid": event.getIntegerValueField(.eventSourceUnixProcessID),
        "sourceState": event.getIntegerValueField(.eventSourceStateID),
        "userData": event.getIntegerValueField(.eventSourceUserData),
    ]
    if mouseish.contains(raw) {
        r["dx"] = event.getIntegerValueField(.mouseEventDeltaX)
        r["dy"] = event.getIntegerValueField(.mouseEventDeltaY)
        r["clickState"] = event.getIntegerValueField(.mouseEventClickState)
        r["button"] = event.getIntegerValueField(.mouseEventButtonNumber)
        r["subtype"] = event.getIntegerValueField(.mouseEventSubtype)
        r["eventNumber"] = event.getIntegerValueField(.mouseEventNumber)
    }
    if raw == CGEventType.scrollWheel.rawValue {
        r["dx"] = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        r["dy"] = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        r["lineDx"] = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        r["lineDy"] = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        r["fixedDy"] = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        r["continuous"] = event.getIntegerValueField(.scrollWheelEventIsContinuous)
        r["scrollPhase"] = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        r["momentumPhase"] = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        r["scrollCount"] = event.getIntegerValueField(.scrollWheelEventScrollCount)
    }
    // AppKit's reading for what CGEvent has no public field for: magnification, gesture phases.
    if [22, 29, 30, 31, 32, 18, 19, 20, 34].contains(raw), let ns = NSEvent(cgEvent: event) {
        r["nsType"] = ns.type.rawValue
        r["phase"] = phaseName(ns.phase)
        r["momentum"] = phaseName(ns.momentumPhase)
        if raw == 30 || raw == 32 || ns.type == .magnify { r["magnification"] = ns.magnification }
        if ns.type == .rotate { r["rotation"] = ns.rotation }
        if ns.type == .swipe { r["swipeDx"] = ns.deltaX; r["swipeDy"] = ns.deltaY }
        if ns.type == .pressure { r["pressure"] = ns.pressure; r["stage"] = ns.stage }
        if raw == 29 { r["touches"] = ns.allTouches().count }
    }
    if let data = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]) {
        out.write(data + Data([0x0A]))
    }
}

// Every type the session carries: the gesture types (29 and up) are not in CGEventType's list.
let mask: CGEventMask = ~0
let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                   eventsOfInterest: mask,
                                   callback: { _, type, event, _ in record(type, event); return Unmanaged.passUnretained(event) },
                                   userInfo: nil) else {
    fputs("""
    eventtap: no event tap. Grant Input Monitoring (System Settings › Privacy & Security › Input Monitoring) to
      \(binary)
    or, when it runs from a terminal, to that terminal app (macOS asks about the responsible process), then run it again.

    """, stderr)
    exit(3)
}
tapPort = port
let source = CFMachPortCreateRunLoopSource(nil, port, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: port, enable: true)
fputs("eventtap: listening (session tap, listen only); pid \(getpid()); Ctrl-C stops\n", stderr)
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }
CFRunLoopRun()
