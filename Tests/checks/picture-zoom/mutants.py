"""Each mutant changes PictureZoom.swift in one place and must fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "picture-zoom")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PictureZoom.swift")
orig = open(SRC).read()
# Left out as equivalent: `guard s > 1` as `>= 1` (scale 1 placed is the fitted picture, centre 0.5,
# 0.5), `max(scale, 1)` dropped (the guard after it), `place`'s `<=` as `<` (an equal size gives
# `start` either way), `guard target != at` dropped (moving to where it is changes nothing).
INNER = "let inner = bounds.insetBy(dx: min(margin, bounds.width / 4), dy: min(margin, bounds.height / 4))"
TARGET = "let target = CGPoint(x: min(max(at.x, inner.minX), inner.maxX), y: min(max(at.y, inner.minY), inner.maxY))"
MUTANTS = {
    # The scale and its limits
    "M1 no maximum": ("let s = min(max(scale, 1), Self.maximum)", "let s = max(scale, 1)"),
    "M3 isZoomed at 1": ("var isZoomed: Bool { scale > 1 }", "var isZoomed: Bool { scale >= 1 }"),
    "M4 the snap's edge taken in": ("scale < Self.snapBelow ? PictureZoom() : self", "scale <= Self.snapBelow ? PictureZoom() : self"),
    "M5 no snap back": ("var settled: PictureZoom { scale < Self.snapBelow ? PictureZoom() : self }", "var settled: PictureZoom { self }"),
    "M6 the scale not applied to the drawn size": ("let width = fitted.width * scale, height = fitted.height * scale",
                                                  "let width = fitted.width, height = fitted.height"),
    # The anchor: the pinched point under the fingers
    "M7 zoomed about the middle, not the fingers (x)": ("point.x - anchor.x * width", "point.x - 0.5 * width"),
    "M8 zoomed about the middle, not the fingers (y)": ("point.y - anchor.y * height", "point.y - 0.5 * height"),
    "M9 the state read back from the wrong edge": ("zoom.center = CGPoint(x: (fitted.midX - x) / width", "zoom.center = CGPoint(x: (fitted.minX - x) / width"),
    "M10 the drawn rect ignores the state's centre": ("fitted.midX - center.x * width", "fitted.midX - 0.5 * width"),
    "M11 no video still zooms": ("        guard fitted.width > 0, fitted.height > 0 else { return self }\n        let s =", "        let s ="),
    # The edges
    "M12 a narrower axis not centred": ("        if size <= length { return start + (length - size) / 2 }\n", ""),
    "M13 a wider axis not kept over the view": ("return min(max(origin, start + length - size), start)", "return origin"),
    "M14 only the far edge kept covered": ("return min(max(origin, start + length - size), start)", "return max(origin, start + length - size)"),
    # Following the pointer
    "M15 the follow ignores the margin": (INNER, "let inner = bounds"),
    "M16 the margin not held to a quarter of a small view": (INNER, "let inner = bounds.insetBy(dx: margin, dy: margin)"),
    "M17 the follow centres the pointer": (TARGET, "let target = CGPoint(x: bounds.midX, y: bounds.midY)"),
    "M18 the follow only sideways": (TARGET, "let target = CGPoint(x: min(max(at.x, inner.minX), inner.maxX), y: at.y)"),
    "M19 the follow pushes past the margin (always to the near inset edge)": (TARGET,
        "let target = CGPoint(x: at.x < bounds.midX ? inner.minX : inner.maxX, y: at.y < bounds.midY ? inner.minY : inner.maxY)"),
    "M20 the follow resets the zoom": ("return moved(to: scale, anchor: point, at: target, fitted: fitted, in: bounds)",
                                       "return moved(to: Self.tapScale, anchor: point, at: target, fitted: fitted, in: bounds)"),
    "M21 the follow moves the picture unzoomed": ("guard isZoomed, fitted.width > 0, fitted.height > 0 else { return self }\n        let r = rect",
                                                  "guard fitted.width > 0, fitted.height > 0 else { return self }\n        if !isZoomed { return moved(to: Self.tapScale, anchor: point, at: CGPoint(x: bounds.midX, y: bounds.midY), fitted: fitted, in: bounds) }\n        let r = rect"),
    # The two-finger double tap
    "M22 a double tap on a zoomed picture zooms further": ("if isZoomed { return PictureZoom() }", "if isZoomed { return moved(to: Self.maximum, anchor: center, at: CGPoint(x: fitted.midX, y: fitted.midY), fitted: fitted, in: bounds) }"),
    "M23 a double tap never zooms out": ("        if isZoomed { return PictureZoom() }\n", ""),
    "M24 a double tap never zooms in": ("return moved(to: Self.tapScale, anchor: anchor, at: point, fitted: fitted, in: bounds)", "return self"),
    "M25 a double tap to the maximum": ("return moved(to: Self.tapScale, anchor: anchor, at: point", "return moved(to: Self.maximum, anchor: anchor, at: point"),
    "M26 a double tap about the middle, not the fingers": ("return moved(to: Self.tapScale, anchor: anchor, at: point", "return moved(to: Self.tapScale, anchor: CGPoint(x: 0.5, y: 0.5), at: point"),
    "M27 a double tap's anchor from the view, not the picture": ("let anchor = CGPoint(x: (point.x - r.minX) / r.width, y: (point.y - r.minY) / r.height)",
                                                               "let anchor = CGPoint(x: (point.x - bounds.minX) / bounds.width, y: (point.y - bounds.minY) / bounds.height)"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
