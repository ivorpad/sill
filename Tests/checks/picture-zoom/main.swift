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

// MARK: Following the pointer

for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    let margin = Z.followMargin
    let inner = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))
    // Not zoomed: nothing to follow.
    check(Z().following(pt(0.99, 0.01), margin: margin, fitted: f, in: bounds) == Z(), "\(name): unzoomed stays fitted")
    let z = Z().moved(to: 3, anchor: pt(0.5, 0.5), at: pt(f.midX, f.midY), fitted: f, in: bounds)
    // A point already well inside the view: unchanged.
    check(z.following(pt(0.5, 0.5), margin: margin, fitted: f, in: bounds) == z, "\(name): a point inside moves nothing")
    // Points across the frame, corners included: afterwards inside the inset view, or the picture
    // is at that edge already (a frame corner can sit at most at the view's corner), and the scale
    // never changes.
    for p in [pt(0, 0), pt(1, 1), pt(0.05, 0.9), pt(0.97, 0.2), pt(0.5, 0.02), pt(0.3, 0.99)] {
        let n = z.following(p, margin: margin, fitted: f, in: bounds)
        let r = n.rect(fitted: f, in: bounds)
        let at = at(p, r)
        let insideX = at.x >= inner.minX - 0.001 && at.x <= inner.maxX + 0.001
        let insideY = at.y >= inner.minY - 0.001 && at.y <= inner.maxY + 0.001
        let edgeX = near(r.minX, bounds.minX) || near(r.maxX, bounds.maxX) || r.width <= bounds.width
        let edgeY = near(r.minY, bounds.minY) || near(r.maxY, bounds.maxY) || r.height <= bounds.height
        check(near(n.scale, z.scale), "\(name): following keeps the scale")
        check((insideX || edgeX) && (insideY || edgeY), "\(name): \(p) followed into view, or the picture is at that edge (\(at))")
        check(placedWell(r, bounds), "\(name): following leaves no gap")
        // Following again from there changes nothing: it settles.
        check(n.following(p, margin: margin, fitted: f, in: bounds) == n, "\(name): \(p) followed twice is followed once")
    }
}

// Exactly the margin: a point the follow has to bring in lands on the inset's edge, not at the view's
// edge and not further in, while the picture is not held at an edge of its own.
do {
    let margin = Z.followMargin
    let inner = ipad.insetBy(dx: margin, dy: margin)
    let z = Z().moved(to: 3, anchor: pt(0.5, 0.5), at: middle, fitted: ipadFit, in: ipad)
    let r0 = z.rect(fitted: ipadFit, in: ipad)
    // Frame points just off each side of the view, well away from the frame's own edges.
    let left = pt((ipad.minX - 20 - r0.minX) / r0.width, 0.5)
    let right = pt((ipad.maxX + 20 - r0.minX) / r0.width, 0.5)
    let top = pt(0.5, (ipad.minY - 20 - r0.minY) / r0.height)
    let bottom = pt(0.5, (ipad.maxY + 20 - r0.minY) / r0.height)
    for (side, p, want) in [("left", left, inner.minX), ("right", right, inner.maxX)] {
        let r = z.following(p, margin: margin, fitted: ipadFit, in: ipad).rect(fitted: ipadFit, in: ipad)
        check(near(at(p, r).x, want), "a point off the \(side) comes in to exactly the margin (\(at(p, r).x), wanted \(want))")
        check(near(at(p, r).y, at(p, r0).y), "following it sideways leaves the other axis alone")
    }
    for (side, p, want) in [("top", top, inner.minY), ("bottom", bottom, inner.maxY)] {
        let r = z.following(p, margin: margin, fitted: ipadFit, in: ipad).rect(fitted: ipadFit, in: ipad)
        check(near(at(p, r).y, want), "a point off the \(side) comes in to exactly the margin (\(at(p, r).y), wanted \(want))")
        check(near(at(p, r).x, at(p, r0).x), "following it up or down leaves the other axis alone")
    }
    // A point inside the view but within the margin moves the picture too.
    let near20 = pt((ipad.minX + 20 - r0.minX) / r0.width, 0.5)
    check(z.following(near20, margin: margin, fitted: ipadFit, in: ipad) != z, "a point 20 pt from the edge, inside the view, is followed")
    let at45 = pt((ipad.minX + 45 - r0.minX) / r0.width, 0.5)
    check(z.following(at45, margin: margin, fitted: ipadFit, in: ipad) == z, "a point 45 pt from the edge is left where it is")
}
// A small view: the margin is held to a quarter of it, so a point 35 pt from a 120 pt view's edge
// (inside its 30 pt quarter) stays put rather than being pulled 40 pt in. Needs a followMargin over 35.
do {
    check(Z.followMargin > 35, "the small view's cases assume a followMargin over 35 pt (\(Z.followMargin)): move them with it")
    let small = CGRect(x: 0, y: 0, width: 120, height: 80)
    let smallFit = fitted(CGSize(width: 1200, height: 800), in: small)
    let z = Z().moved(to: 4, anchor: pt(0.5, 0.5), at: pt(60, 40), fitted: smallFit, in: small)
    let r0 = z.rect(fitted: smallFit, in: small)
    let p = pt((35 - r0.minX) / r0.width, (40 - r0.minY) / r0.height)
    check(z.following(p, margin: Z.followMargin, fitted: smallFit, in: small) == z, "a small view: 35 pt from the edge is inside its quarter, left alone")
    let q = pt((10 - r0.minX) / r0.width, 0.5)
    let r = z.following(q, margin: Z.followMargin, fitted: smallFit, in: small).rect(fitted: smallFit, in: small)
    check(near(at(q, r).x, 30), "a small view: a point 10 pt from the edge comes in to its quarter, 30 pt (\(at(q, r).x))")
}

// MARK: The two-finger double tap

for (name, bounds, video) in cases {
    let f = fitted(video, in: bounds)
    // Unzoomed: tapScale about the point between the fingers. An interior point, so 2.5x about it
    // needs no clamp on any panel here (checked: the rect is placed well and the point stays put).
    let anchor = pt(0.45, 0.55)
    let finger = at(anchor, f)
    let z = Z().doubleTapped(at: finger, fitted: f, in: bounds)
    let r = z.rect(fitted: f, in: bounds)
    check(near(z.scale, Z.tapScale), "\(name): a double tap zooms to tapScale (\(z.scale))")
    check(placedWell(r, bounds), "\(name): the tapped zoom leaves no gap")
    check(near(at(anchor, r), finger), "\(name): the tapped point stays under the fingers (\(at(anchor, r)) vs \(finger))")
    // Zoomed, at any scale and wherever the fingers are: back to the fitted picture.
    check(z.doubleTapped(at: finger, fitted: f, in: bounds) == Z(), "\(name): a double tap on a zoomed picture fits it again")
    let five = Z().moved(to: 5, anchor: pt(0.2, 0.8), at: pt(bounds.minX + 5, bounds.maxY - 5), fitted: f, in: bounds)
    check(five.doubleTapped(at: pt(bounds.maxX - 1, bounds.minY + 1), fitted: f, in: bounds) == Z(), "\(name): from 5x too")
    // A tap near a corner zooms there as far as the edges allow: the corner of the view stays covered.
    let corner = Z().doubleTapped(at: pt(f.minX + 2, f.maxY - 2), fitted: f, in: bounds)
    check(near(corner.scale, Z.tapScale) && placedWell(corner.rect(fitted: f, in: bounds), bounds), "\(name): a tap at a corner zooms without a gap")
}
check(Z().doubleTapped(at: middle, fitted: .zero, in: ipad) == Z(), "no video: a double tap changes nothing")

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
