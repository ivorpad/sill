import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import StreamProtocol

// MARK: - Stroke observer

/// Feeds a surface's `TrackpadGestures` with every direct touch, so a stroke that has three fingers
/// down before any has moved sends the Mac nothing but its gesture, if it makes one
/// (docs/trackpad-gestures-plan.md §6.2). One on each glass surface: the portrait trackpad and the
/// stream.
///
/// An observer, not the view's own touch callbacks: the pans, taps and long presses cancel the
/// view's touches as they recognize, after which the view hears no more of the stroke. This one sees
/// every direct touch and never recognizes (it stays possible, so UIKit ends it with the last
/// finger), takes none (`cancelsTouchesInView` off), delays none, can neither prevent another
/// recognizer nor be prevented by one, and is its own delegate so it runs beside all of them.
/// Only direct touches are fingers: a Pencil is the mouse, and a Magic Keyboard trackpad's click is
/// one indirect touch. Those only end a finished stroke's silence (`otherTouch`), since the
/// portrait trackpad's recognizers take them too.
final class StrokeObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var strokes = TrackpadGestures()
    /// From three fingers down until the next stroke's first touch: the surface sends nothing.
    var silent: Bool { strokes.silent }
    /// A button the surface pressed is held (the trackpad's press-and-hold drag); asked as each
    /// finger lands, and no stroke goes silent while it is (its button must still come up).
    var holding: () -> Bool = { false }
    /// The stroke just went silent: close what it had opened (a scroll).
    var onSilenced: () -> Void = {}
    /// The decision, at the first lift of a finger that armed the stroke: the gesture and its
    /// fingers, 3 or 4.
    var onGesture: (TrackpadGestures.Gesture, Int) -> Void = { _, _ in }
    /// Each touch of the stroke, numbered as it lands.
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// Several touches of one event in a fixed order (by where they are), so the same touches always
    /// make the same stroke.
    private func ordered(_ touches: Set<UITouch>) -> [UITouch] {
        touches.sorted { a, b in
            let p = a.location(in: view), q = b.location(in: view)
            return p.x != q.x ? p.x < q.x : p.y < q.y
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard touch.type == .direct else { strokes.otherTouch(); continue }
            let id = nextID
            nextID += 1
            ids[ObjectIdentifier(touch)] = id
            if strokes.down(id, at: touch.location(in: view), time: touch.timestamp, holding: holding()) == .silenced { onSilenced() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids[ObjectIdentifier(touch)] else { continue }
            strokes.moved(id, to: touch.location(in: view), time: touch.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            if case .gesture(let gesture, let fingers) = strokes.up(id, at: touch.location(in: view), time: touch.timestamp) {
                onGesture(gesture, fingers)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            strokes.cancelled(id)
        }
    }

    /// UIKit ends the observer with the stroke's last finger, after its touches have ended. A touch
    /// it never heard end (the observer ended early) counts as cancelled, so the next stroke starts
    /// clean and this one decides nothing more.
    override func reset() {
        super.reset()
        for id in ids.values.sorted() { strokes.cancelled(id) }
        ids.removeAll()
    }
}
