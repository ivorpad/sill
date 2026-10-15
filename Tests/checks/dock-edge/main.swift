import CoreGraphics
import Foundation

// DockEdge (Sources/SillHost/DockEdge.swift), compiled on its own:
//   swiftc -O -package-name sill Sources/SillHost/DockEdge.swift Tests/checks/dock-edge/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let edge = DockEdge.edge, dwell = DockEdge.dwell
let below = edge - 0.001

// MARK: The edge

// Reaching the edge arms a dwell once, at the time it was reached; further moves along it do not.
do {
    var d = DockEdge()
    check(d.moved(y: 1, now: 10), "arriving at the edge arms")
    check(d.since == 10, "armed at the arrival's time (\(String(describing: d.since)))")
    check(!d.moved(y: 1, now: 10.1), "a second move at the edge does not arm again")
    check(!d.moved(y: edge, now: 10.2), "nor a move to exactly the edge")
    check(d.since == 10, "the arrival's time is kept (\(String(describing: d.since)))")
}
// y exactly at the edge counts; just below it does not.
do {
    var d = DockEdge()
    check(d.moved(y: edge, now: 1), "y exactly at the edge arms")
    var e = DockEdge()
    check(!e.moved(y: below, now: 1), "y just below the edge does not arm")
    check(e.since == nil, "and leaves nothing armed")
    check(!e.moved(y: 0.5, now: 1), "the middle of the picture does not arm")
}

// MARK: The dwell

// A rest without another move: the dwell fires when it is up, and the tolerance never makes it late.
do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 10)
    check(!d.fire(armed: 10, now: 10.3), "not before the dwell")
    check(d.since == 10, "an early ask keeps the arrival")
    check(d.fire(armed: 10, now: 10 + dwell), "fires exactly at the dwell")
}
do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 10)
    check(d.fire(armed: 10, now: 10 + dwell - 0.0005), "fires a hair before the dwell (a timer a little early)")
}
do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 10)
    check(!d.fire(armed: 10, now: 10 + dwell - 0.01), "not 10 ms before the dwell")
}
// A pass along the bottom that leaves before the dwell is up: nothing.
do {
    var d = DockEdge()
    check(d.moved(y: 1, now: 0), "the pass reaches the edge")
    _ = d.moved(y: 1, now: 0.2)
    check(!d.moved(y: 0.9, now: 0.3), "leaving arms nothing")
    check(d.since == nil, "leaving forgets the arrival")
    check(!d.fire(armed: 0, now: dwell), "the pass's dwell does not fire once it has left")
}

// MARK: Buttons

// A button down cancels an armed dwell; a drag along the bottom never fires.
do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 0)
    d.button(down: true)
    check(d.since == nil, "a button down forgets the arrival")
    check(!d.fire(armed: 0, now: dwell), "a button down cancels an armed dwell")
}
do {
    var d = DockEdge()
    d.button(down: true)
    var armed = false
    for i in 0..<20 { armed = d.moved(y: 1, now: Double(i) * 0.1) || armed }
    check(!armed, "a drag along the bottom never arms")
    check(!d.fire(armed: 0, now: 5), "and never fires")
    d.button(down: false)
    check(d.moved(y: 1, now: 3), "the button up: the next move at the edge arms")
    check(d.fire(armed: 3, now: 3 + dwell), "and fires at its dwell")
}

// MARK: Leaving and arriving again

// Re-arrival after leaving arms again with the new time; the earlier arrival's dwell is stale.
do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 0)
    _ = d.moved(y: 0.5, now: 0.2)
    check(d.moved(y: 1, now: 0.3), "arriving again arms again")
    check(d.since == 0.3, "with the new arrival's time (\(String(describing: d.since)))")
    check(!d.fire(armed: 0, now: 0.3 + dwell + 0.1), "the first arrival's dwell is stale: no switch")
    check(d.since == 0.3, "a stale ask keeps the new arrival")
    check(d.fire(armed: 0.3, now: 0.3 + dwell + 0.1), "the new arrival's dwell fires")
}

// MARK: One switch an arrival

do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 0)
    check(d.fire(armed: 0, now: dwell), "the dwell fires")
    check(d.since == nil, "firing forgets the arrival")
    check(!d.fire(armed: 0, now: dwell + 0.1), "the same arrival does not fire twice")
    check(!d.fire(armed: 0, now: 5), "nor later")
}

// MARK: Reset

do {
    var d = DockEdge()
    _ = d.moved(y: 1, now: 0)
    d.reset()
    check(d == DockEdge(), "reset clears the arrival")
    check(!d.fire(armed: 0, now: dwell), "a dwell armed before a reset does not fire")
    d.button(down: true)
    d.reset()
    check(d.moved(y: 1, now: 2), "reset forgets a button down too: the next move at the edge arms")
}

// MARK: Where a position lands on the Mac

do {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let window = CGRect(x: 200, y: 120, width: 800, height: 600)
    check(DockEdge.pixel(x: 0.5, y: 1, in: screen) == CGPoint(x: 756, y: 981), "y 1 lands on the screen's last row, not below it")
    check(DockEdge.pixel(x: 1, y: 0.5, in: screen) == CGPoint(x: 1511, y: 491), "x 1 lands on the last column")
    check(DockEdge.pixel(x: 0, y: 0, in: screen) == CGPoint(x: 0, y: 0), "0, 0 is the first pixel")
    check(DockEdge.pixel(x: 0.5, y: 0.5, in: window) == CGPoint(x: 600, y: 420), "the middle of a window off the origin")
    check(DockEdge.pixel(x: 1, y: 1, in: window) == CGPoint(x: 999, y: 719), "a window's far corner is its own last pixel")
    check(DockEdge.pixel(x: 0.25, y: 0.75, in: window) == CGPoint(x: 400, y: 570), "a fraction inside is unchanged")
}

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
