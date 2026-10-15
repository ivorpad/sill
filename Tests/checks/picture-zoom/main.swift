import CoreGraphics
import Foundation

// PictureZoom (iOSClient/PictureZoom.swift), compiled on its own:
//   swiftc -O iOSClient/PictureZoom.swift Tests/checks/picture-zoom/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }
func near(_ a: CGPoint, _ b: CGPoint) -> Bool { near(a.x, b.x) && near(a.y, b.y) }
func near(_ a: CGRect, _ b: CGRect) -> Bool { near(a.origin, b.origin) && near(a.width, b.width) && near(a.height, b.height) }
typealias Z = PictureZoom

/// Aspect-fit, as HEVCDisplayView.fittedRect draws it.
func fitted(_ video: CGSize, in bounds: CGRect) -> CGRect {
    let s = min(bounds.width / video.width, bounds.height / video.height)
    let w = video.width * s, h = video.height * s
    return CGRect(x: bounds.minX + (bounds.width - w) / 2, y: bounds.minY + (bounds.height - h) / 2, width: w, height: h)
}
/// Where frame fraction `f` lands in the view for `rect`.
func at(_ f: CGPoint, _ rect: CGRect) -> CGPoint { pt(rect.minX + f.x * rect.width, rect.minY + f.y * rect.height) }
/// Whether `rect` covers `bounds` on every axis where it is at least as large, and is centred on the others.
func placedWell(_ rect: CGRect, _ bounds: CGRect) -> Bool {
    func axis(_ lo: CGFloat, _ size: CGFloat, _ blo: CGFloat, _ bsize: CGFloat) -> Bool {
        size <= bsize + 0.001 ? near(lo + size / 2, blo + bsize / 2) : (lo <= blo + 0.001 && lo + size >= blo + bsize - 0.001)
    }
    return axis(rect.minX, rect.width, bounds.minX, bounds.width) && axis(rect.minY, rect.height, bounds.minY, bounds.height)
}

// The panels: an iPad sideways under the bar (a 16:10 window letterboxed left and right), an iPhone
// upright's 16:10 pane (pillarboxed above and below by a 4:3 window), a portrait iPad's top half, and
// one not at the origin.
let cases: [(String, CGRect, CGSize)] = [
    ("iPad sideways, wide window", CGRect(x: 0, y: 0, width: 1180, height: 720), CGSize(width: 2560, height: 1600)),
    ("iPhone pane, 4:3 window", CGRect(x: 0, y: 0, width: 390, height: 244), CGSize(width: 1600, height: 1200)),
    ("portrait iPad half, tall window", CGRect(x: 0, y: 0, width: 820, height: 560), CGSize(width: 1200, height: 1800)),
    ("offset panel", CGRect(x: 8, y: 30, width: 600, height: 400), CGSize(width: 1920, height: 1080)),
]

// MARK: Scale 1 is the fitted picture, unchanged

for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    check(near(Z().rect(fitted: f, in: bounds), f), "\(name): no zoom draws the fitted rect")
    check(!Z().isZoomed, "\(name): a new zoom is not zoomed")
    check(Z().rect(fitted: .zero, in: bounds) == .zero, "\(name): no video stays .zero")
    // A pinch that never got past 1, or went below it, is no zoom at all.
    for s in [1.0, 0.8, 0.2, -3.0] as [CGFloat] {
        check(Z().moved(to: s, anchor: pt(0.3, 0.7), at: pt(bounds.midX, bounds.midY), fitted: f, in: bounds) == Z(),
              "\(name): scale \(s) gives the fitted picture back")
    }
}

// MARK: The pinched point stays under the fingers, where the edges allow

for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    // The middle of the frame, pinched at the middle of the view: it stays there at every scale.
    for s in [1.5, 2, 3, 5] as [CGFloat] {
        let z = Z().moved(to: s, anchor: pt(0.5, 0.5), at: pt(f.midX, f.midY), fitted: f, in: bounds)
        let r = z.rect(fitted: f, in: bounds)
        check(near(z.scale, s), "\(name): scale \(s) taken")
        check(near(r.width, f.width * s) && near(r.height, f.height * s), "\(name): \(s)× is \(s)× the fitted size")
        check(near(at(pt(0.5, 0.5), r), pt(f.midX, f.midY)), "\(name): the middle stays put at \(s)×")
        check(placedWell(r, bounds), "\(name): \(s)× keeps the view covered")
    }
    // A point well inside the frame, pinched where it is drawn, stays under the fingers: at 3× the
    // picture grown about it still covers every panel here, so nothing has to be clamped.
    let anchor = pt(0.45, 0.55)
    let z = Z().moved(to: 3, anchor: anchor, at: at(anchor, f), fitted: f, in: bounds)
    check(near(at(anchor, z.rect(fitted: f, in: bounds)), at(anchor, f)), "\(name): a pinched point stays under the fingers")
}

// MARK: Limits and the snap back

let ipad = CGRect(x: 0, y: 0, width: 1180, height: 720)
let ipadFit = fitted(CGSize(width: 2560, height: 1600), in: ipad)
let middle = pt(ipad.midX, ipad.midY)
check(near(Z().moved(to: 40, anchor: pt(0.5, 0.5), at: middle, fitted: ipadFit, in: ipad).scale, Z.maximum), "held to the maximum")
check(Z().moved(to: 1.05, anchor: pt(0.5, 0.5), at: middle, fitted: ipadFit, in: ipad).settled == Z(), "let go under snapBelow: fitted again")
check(Z().moved(to: Z.snapBelow, anchor: pt(0.5, 0.5), at: middle, fitted: ipadFit, in: ipad).settled.isZoomed, "let go at snapBelow: stays zoomed")
let two = Z().moved(to: 2, anchor: pt(0.5, 0.5), at: middle, fitted: ipadFit, in: ipad)
check(two.settled == two, "settled leaves a real zoom alone")
check(Z().moved(to: 2, anchor: pt(0.5, 0.5), at: middle, fitted: .zero, in: ipad) == Z(), "no video: a pinch changes nothing")

// MARK: The edges stay covered

// Pinching a corner of the frame pulls it no further than the view's corner.
for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    for corner in [pt(0, 0), pt(1, 0), pt(0, 1), pt(1, 1)] {
        let z = Z().moved(to: 4, anchor: corner, at: pt(bounds.midX, bounds.midY), fitted: f, in: bounds)
        let r = z.rect(fitted: f, in: bounds)
        check(placedWell(r, bounds), "\(name): corner \(corner) pinched to the middle leaves no gap")
    }
}
// On the iPad's letterboxed axis, 1.01× of a 1152 pt wide picture in 1180 pt is still narrower:
// centred, whatever the fingers do.
let narrow = Z().moved(to: 1.01, anchor: pt(0, 0.5), at: pt(1100, 360), fitted: ipadFit, in: ipad)
check(near(narrow.rect(fitted: ipadFit, in: ipad).midX, ipad.midX), "still narrower than the view: centred on that axis")

// MARK: The state reproduces the rect it was moved to

// 2,000 random pinches and moves, each step from the last: the rect `rect(fitted:in:)` gives is the
// one the move placed (the anchor under the fingers whenever placedWell needed no clamp), the view
// stays covered, and the scale stays in 1...maximum.
var rng = SystemRandomNumberGenerator()
var roundTrips = 0
for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    var z = Z()
    for _ in 0..<500 {
        let anchor = pt(.random(in: 0...1, using: &rng), .random(in: 0...1, using: &rng))
        let finger = pt(.random(in: bounds.minX...bounds.maxX, using: &rng), .random(in: bounds.minY...bounds.maxY, using: &rng))
        let s = z.scale * .random(in: 0.5...2, using: &rng)
        let next = z.moved(to: s, anchor: anchor, at: finger, fitted: f, in: bounds)
        let r = next.rect(fitted: f, in: bounds)
        let again = next.moved(to: next.scale, anchor: next.center, at: pt(f.midX, f.midY), fitted: f, in: bounds)
        guard next.scale >= 1, next.scale <= Z.maximum, placedWell(r, bounds), near(again.rect(fitted: f, in: bounds), r) else {
            check(false, "\(name): step from \(z) to scale \(s), anchor \(anchor) at \(finger): \(next), \(r)")
            break
        }
        roundTrips += 1
        z = next
    }
}
check(roundTrips == 2_000, "every random step held (\(roundTrips) of 2000)")

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
