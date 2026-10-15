#!/usr/bin/env python3
"""TouchTrace's raw traces measured (Tests/evidence/README.md): the numbers the gesture thresholds in
docs/pointer-and-clipboard-plan.md are set from. Coalesced samples are left out (each event's last
touch only), so speeds are per delivered event.

usage: analyze.py TRACE.jsonl"""
import collections, json, math, sys

recs = [json.loads(l) for l in open(sys.argv[1])]
sess = recs[0]
H, W = sess["viewH"], sess["viewW"]
touches = collections.defaultdict(list)
for r in recs:
    if r["k"] == "touch" and not r.get("coalesced"):
        touches[r["g"]].append(r)

def strokes(g):
    """Each touch id's life: began..ended/cancelled, as a list of records."""
    live, out = {}, []
    for r in touches[g]:
        if r["phase"] == "began": live[r["id"]] = [r]
        elif r["id"] in live:
            live[r["id"]].append(r)
            if r["phase"] in ("ended", "cancelled"): out.append(live.pop(r["id"]))
    return out

def travel(s): return max(math.dist((p["x"], p["y"]), (s[0]["x"], s[0]["y"])) for p in s)
def dur(s): return s[-1]["t"] - s[0]["t"]

def taps2(g):
    """Two-finger taps: strokes whose begins are within 0.15 s of each other, paired."""
    ss = sorted(strokes(g), key=lambda s: s[0]["t"])
    out, i = [], 0
    while i < len(ss) - 1:
        a, b = ss[i], ss[i + 1]
        if b[0]["t"] - a[0]["t"] < 0.15:
            out.append(dict(start=a[0]["t"], end=max(a[-1]["t"], b[-1]["t"]),
                            dur=max(dur(a), dur(b)), travel=max(travel(a), travel(b)),
                            gap=math.dist((a[0]["x"], a[0]["y"]), (b[0]["x"], b[0]["y"])),
                            land=b[0]["t"] - a[0]["t"],
                            centre=((a[0]["x"] + b[0]["x"]) / 2, (a[0]["y"] + b[0]["y"]) / 2)))
            i += 2
        else: i += 1
    return out

def fmt(xs, unit=""):
    xs = sorted(xs)
    if not xs: return "none"
    return f"n={len(xs)} min={xs[0]:.3f} med={xs[len(xs)//2]:.3f} max={xs[-1]:.3f}{unit}"

print(f"device {sess['model']} iOS {sess['os']} view {W}x{H} pt @{sess['scale']}x, {sess['maxFPS']} Hz")
print("\n# One finger")
for g in ("G1", "G2"):
    sp = [travel(s) / max(dur(s), 1e-3) for s in strokes(g)]
    print(g, "stroke speed pt/s", fmt(sp))
t7 = strokes("G7")
print("G7 tap duration s", fmt([dur(s) for s in t7]), "| travel pt", fmt([travel(s) for s in t7]))
for g, f in (("G3", lambda p: p["y"]), ("G4", lambda p: H - p["y"]), ("G5", lambda p: p["x"]), ("G6", lambda p: W - p["x"])):
    print(g, "closest approach to that edge pt", fmt([min(f(p) for p in s) for s in strokes(g)]))

print("\n# Two-finger taps")
for g in ("G13", "G14", "G15", "G16"):
    tp = taps2(g)
    gaps = [b["start"] - a["end"] for a, b in zip(tp, tp[1:])]
    cdist = [math.dist(a["centre"], b["centre"]) for a, b in zip(tp, tp[1:])]
    print(g, f"taps={len(tp)}")
    print("   tap duration s ", fmt([t["dur"] for t in tp]))
    print("   finger travel pt", fmt([t["travel"] for t in tp]))
    print("   finger spacing pt", fmt([t["gap"] for t in tp]))
    print("   landing skew s ", fmt([t["land"] for t in tp]))
    print("   lift-to-next-land s", fmt(gaps))
    print("   centre shift between taps pt", fmt(cdist))
s17 = strokes("G17")
print("G17 scroll stroke travel pt", fmt([travel(s) for s in s17]), "| duration s", fmt([dur(s) for s in s17]))

print("\n# Pinch")
for g in ("G8", "G9", "G10", "G11", "G12"):
    ev = collections.defaultdict(dict)
    for r in touches[g]: ev[r["t"]][r["id"]] = (r["x"], r["y"])
    rates, prev, cmove = [], None, []
    pos = {}
    for t in sorted(ev):
        pos.update(ev[t])
        if len(pos) >= 2:
            a, b = list(pos.values())[:2]
            d, c = math.dist(a, b), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            if prev and t > prev[0]:
                rates.append(abs(math.log(max(d, 1) / max(prev[1], 1))) / (t - prev[0]))
                cmove.append(math.dist(c, prev[2]))
            prev = (t, d, c)
        for r in touches[g]:
            pass
        ended = [r["id"] for r in touches[g] if r["t"] == t and r["phase"] in ("ended", "cancelled")]
        for i in ended: pos.pop(i, None)
        if len(pos) < 2: prev = None
    print(g, "|log scale| per s", fmt(rates), "| centroid step pt", fmt(cmove))

print("\n# Bottom edge")
for g in ("G18", "G19", "G20"):
    for s in strokes(g):
        near = [p for p in s if H - p["y"] <= 10]
        dwell = (near[-1]["t"] - near[0]["t"]) if near else 0
        print(g, f"closest {min(H - p['y'] for p in s):.1f} pt from bottom, within 10 pt for {dwell:.2f} s,",
              f"max y/H {max(p['y'] for p in s) / H:.4f}, duration {dur(s):.2f} s, ended {s[-1]['phase']}")
print("\n# Graze")
for s in strokes("G21"):
    print("G21", f"radius max {max(p['r'] for p in s):.1f} pt, duration {dur(s):.2f} s, travel {travel(s):.0f} pt, x from {s[0]['x']:.0f}")
print("touch radius on deliberate fingers (G1,G7,G13) pt", fmt([p["r"] for g in ("G1", "G7", "G13") for p in touches[g]]))
