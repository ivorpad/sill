// Pasteboard watch (Tests/evidence/README.md): polls NSPasteboard.general's changeCount 20 times a
// second and, on each change, prints one JSONL record: the change count, the frontmost app, and the
// digest (PasteboardDigest.swift: types, byte counts and SHA-256 per type, Sill's private markers).
// Never the contents. Evidence only, never linked into Sill.
//
//   pasteboard            watch until Ctrl-C (the current state first)
//   pasteboard --once     the current state, then exit
//
// Reading a type's bytes is what macOS 26's pasteboard privacy may ask about; changeCount and types
// alone are not.
import AppKit

setvbuf(stdout, nil, _IOLBF, 0)

func emit(_ reason: String) {
    var r = PasteboardDigest.read()
    r["k"] = reason
    r["wall"] = Date().timeIntervalSince1970
    r["uptime"] = ProcessInfo.processInfo.systemUptime
    r["frontmost"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? NSNull()
    r["frontmostPid"] = NSWorkspace.shared.frontmostApplication.map { Int($0.processIdentifier) } ?? NSNull()
    if let data = try? JSONSerialization.data(withJSONObject: r, options: [.sortedKeys]),
       let line = String(data: data, encoding: .utf8) { print(line) }
}

emit("state")
if CommandLine.arguments.contains("--once") { exit(0) }

var last = NSPasteboard.general.changeCount
// A main run loop, so NSWorkspace's frontmost app stays current between polls.
Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
    let now = NSPasteboard.general.changeCount
    guard now != last else { return }
    last = now
    emit("change")
}
signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }
RunLoop.main.run()
