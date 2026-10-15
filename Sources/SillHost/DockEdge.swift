import CoreGraphics

/// The Dock from a streamed window: a device's pointer held against the window's bottom edge, no
/// button down, for `dwell` seconds, switches the picture to the Desktop with the Dock shown, as the
/// pointer at the bottom of a Mac's screen shows a hidden Dock. A window's bottom is not the
/// screen's, and the Dock is not in a window's picture, so the Desktop is where it can be seen.
///
/// Pure: the coordinator feeds it each pointer event of a window stream and asks `fire` when a
/// dwell it armed is up (the finger may rest without sending another move). Checked by
/// Tests/checks/dock-edge.
package struct DockEdge: Equatable {
    /// How far down the picture counts as the edge: a fraction of the frame. A finger dragged past
    /// the picture's bottom arrives clamped at 1.
    package static let edge = 0.995
    /// How long the pointer stays there first, so a pass along the bottom does not switch.
    package static let dwell = 0.5

    /// When the pointer reached the edge, while it stays; nil otherwise.
    package private(set) var since: Double?
    private var buttonDown = false

    package init() {}

    /// A move to `y` (a fraction of the frame) at `now`. True when it arms a dwell: ask `fire` at
    /// `now + dwell`.
    package mutating func moved(y: Double, now: Double) -> Bool {
        guard !buttonDown, y >= Self.edge else { since = nil; return false }
        guard since == nil else { return false }
        since = now
        return true
    }

    /// A button went down or up. A drag along the bottom (a selection, a window moved) is no Dock.
    package mutating func button(down: Bool) {
        buttonDown = down
        if down { since = nil }
    }

    /// The dwell armed at `armed` is up at `now`: true when the pointer is still at the edge from
    /// that same arrival, which it then forgets (one switch an arrival).
    package mutating func fire(armed: Double, now: Double) -> Bool {
        guard let since, since == armed, now - since >= Self.dwell - 0.001 else { return false }
        self.since = nil
        return true
    }

    /// Another source, or none: start over.
    package mutating func reset() {
        self = DockEdge()
    }

    /// Where a device's position (`x`, `y`, fractions of the frame) lands on the Mac: its fraction
    /// of `rect`, on one of the rect's own pixels. A fraction of 1 is the last row or column, not the
    /// first past it: the Desktop's bottom row is where a hidden Dock shows, and the row below the
    /// screen shows nothing. InputInjector places every pointer and scroll through it.
    package static func pixel(x: Double, y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: min(rect.minX + CGFloat(x) * rect.width, rect.maxX - 1),
                y: min(rect.minY + CGFloat(y) * rect.height, rect.maxY - 1))
    }
}
