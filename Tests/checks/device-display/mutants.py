"""Each mutant changes DeviceDisplayGeometry.swift in one place and must fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "device-display")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/DeviceDisplayGeometry.swift")
orig = open(SRC).read()
WANT_W = "let wantW = Double(pxW) / Double(Self.scale) / aa"
F = "let f = min(1, Double(pxW) / Double(w * Self.scale), Double(pxH) / Double(h * Self.scale))"
MUTANTS = {
    "M1 Aa multiplies instead of dividing": (WANT_W, WANT_W.replace("/ aa", "* aa")),
    "M2 Aa nil is not Default": ("guard let s, s.isFinite, s > 0 else { return 1 }", "guard let s, s.isFinite, s > 0 else { return 0.5 }"),
    "M3 Aa 0 or below taken as it is": ("guard let s, s.isFinite, s > 0 else { return 1 }", "guard let s, s.isFinite else { return 1 }"),
    "M4 no 3× rule: points are the panel's points": (WANT_W, "let wantW = panelWidth / aa"),
    "M5 the panel's pixels not halved (a 1× display's worth of points)": (WANT_W, "let wantW = Double(pxW) / aa"),
    "M6 the panel's pixels rounded down": ("let pxW = max(1, Int((panelWidth * ps).rounded()))", "let pxW = max(1, Int((panelWidth * ps).rounded(.down)))"),
    "M7 the points rounded to nearest": ("let fw = Int((w * k).rounded(.down)), fh", "let fw = Int((w * k).rounded()), fh"),
    "M8 encoded at the display's pixels, never scaled down": (F, "let f = 1.0"),
    "M9 Larger Text scaled up to the panel": (F, "let f = max(Double(pxW) / Double(w * Self.scale), Double(pxH) / Double(h * Self.scale))"),
    "M10 each side its own factor": (F, "let f = Double(pxW) / Double(w * Self.scale)"),
    "M11 odd encoded sizes": ("static func even(_ v: Double) -> Int { max(2, Int(v.rounded(.down)) & ~1) }",
                              "static func even(_ v: Double) -> Int { max(2, Int(v.rounded(.down))) }"),
    "M12 no longest-side clamp": ("if longest > Double(maxSide) { k = Double(maxSide) / longest }", ""),
    "M13 no floor": ("            k = max(Double(minWidth) / w, Double(minHeight) / h)\n", ""),
    "M14 the floor's factor the smaller one (the shape off the floor)": ("k = max(Double(minWidth) / w, Double(minHeight) / h)", "k = min(Double(minWidth) / w, Double(minHeight) / h)"),
    "M15 no side-by-side clamp": ("return (min(max(fw, minWidth), maxSide), min(max(fh, minHeight), maxSide))", "return (fw, fh)"),
    "M16 the longest side at 8192 pt": ("package static let maxSide = 4096", "package static let maxSide = 8192"),
    "M17 the floor at 240×240": ("package static let minWidth = 320", "package static let minWidth = 240"),
    "M18 a pixel scale under 1 kept": ("return min(max(s, pixelScaleRange.lowerBound), pixelScaleRange.upperBound)", "return min(s, pixelScaleRange.upperBound)"),
    "M19 no pixel scale counts as 3": ("package static let assumedPixelScale = 2.0", "package static let assumedPixelScale = 3.0"),
    "M20 Aa not clamped": ("return min(max(s, textScaleRange.lowerBound), textScaleRange.upperBound)", "return s"),
    "M21 capacity at Default, not the smallest Aa": ("textScale: textScaleRange.lowerBound) else { return nil }", "textScale: nil) else { return nil }"),
    "M22 capacity one side only": ("return max(g.widthPt, g.heightPt)", "return g.widthPt"),
    "M23 fits checks the width only": ("widthPt <= side && heightPt <= side", "widthPt <= side"),
    "M24 the serial may be 0 or 1": ("return h <= unpairedSerial ? h &+ 2 : h", "return h"),
    "M25 an empty key hashed": ("guard let fingerprint, !fingerprint.isEmpty else", "guard let fingerprint else"),
    "M26 the serial is FNV-1, not FNV-1a": ("            h ^= UInt32(byte)\n            h = h &* 0x0100_0193\n",
                                            "            h = h &* 0x0100_0193\n            h ^= UInt32(byte)\n"),
    "M27 a zero panel accepted": ("panelWidth > 0, panelHeight > 0 else { return nil }", "panelWidth >= 0, panelHeight >= 0 else { return nil }"),
    "M28 a side not a number accepted": ("guard panelWidth.isFinite, panelHeight.isFinite, panelWidth > 0", "guard panelWidth > 0"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", "-package-name", "sill", path, os.path.join(SP, "main.swift"),
                        "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
