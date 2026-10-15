"""Each mutant changes DockEdge.swift in one place and must fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "dock-edge")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/DockEdge.swift")
orig = open(SRC).read()
MOVED = "guard !buttonDown, y >= Self.edge else { since = nil; return false }"
FIRE = "guard let since, since == armed, now - since >= Self.dwell - 0.001 else { return false }"
MUTANTS = {
    "M1 the edge itself left out": (MOVED, MOVED.replace("y >= Self.edge", "y > Self.edge")),
    "M2 no tolerance: a timer a hair early misses": (FIRE, FIRE.replace(" - 0.001", "")),
    "M3 the tolerance inverted": (FIRE, FIRE.replace("Self.dwell - 0.001", "Self.dwell + 0.001")),
    "M4 no dwell at all": (FIRE, FIRE.replace(", now - since >= Self.dwell - 0.001", "")),
    "M5 a button held does not stop arming": (MOVED, MOVED.replace("!buttonDown, ", "")),
    "M6 leaving keeps the arrival": (MOVED, MOVED.replace("{ since = nil; return false }", "{ return false }")),
    "M7 a stale dwell fires (the arrival not compared)": (FIRE, FIRE.replace(" since == armed,", "")),
    "M8 one fire an arrival dropped": ("        self.since = nil\n        return true\n", "        return true\n"),
    "M9 every move at the edge arms again": ("        guard since == nil else { return false }\n", ""),
    "M10 a button down keeps an armed dwell": ("        if down { since = nil }\n", ""),
    "M11 reset keeps a button down": ("        self = DockEdge()\n", "        since = nil\n"),
    "M12 a fraction of 1 lands past the last row": ("y: min(rect.minY + CGFloat(y) * rect.height, rect.maxY - 1))",
                                                   "y: rect.minY + CGFloat(y) * rect.height)"),
    "M13 a fraction of 1 lands past the last column": ("CGPoint(x: min(rect.minX + CGFloat(x) * rect.width, rect.maxX - 1),",
                                                      "CGPoint(x: rect.minX + CGFloat(x) * rect.width,"),
    "M14 the clamp a row short": ("rect.maxY - 1))", "rect.maxY - 2))"),
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
