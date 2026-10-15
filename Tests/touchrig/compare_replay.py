#!/usr/bin/env python3
"""Two replays of one TouchTrace recording (run.sh --replay) compared, gesture by gesture.

usage: compare_replay.py BASE.log NEW.log

For each gesture (G1..G21): the overlay's events normalised as compare.py's normal() does (times and
touch lines gone, runs of pointer moves by count and last position, scroll deltas by count and sum,
a coast's steps only as being there), with each run of zoom changes as its count and last state;
"same" or a unified diff. Then, from each raw log, what normal() folds away: the zoom the gesture
started from, the pointer's y fractions (min and max over every pointer event), each click's delay
after the lift that made it, and the zoom at the end. Informational: it judges nothing, exits 0."""
import difflib, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare import normal  # noqa: E402

def load(path):
    """Each `=== ` section's lines as (ms, text)."""
    runs, cur = {}, None
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("=== "):
            cur = line[4:]; runs[cur] = []; continue
        m = re.match(r"\s*(-?\d+) (.*)$", line)
        if cur is not None and m: runs[cur].append((int(m.group(1)), m.group(2)))
    return runs

def events(lines):
    """normal(), less the starting zoom, with each run of zoom changes as one line."""
    out = []
    for e in normal([t for _, t in lines if not t.startswith("zoom at start")]):
        if e.startswith("zoom scale="):
            if out and isinstance(out[-1], list):
                out[-1][1] += 1; out[-1][2] = e[5:]
            else:
                out.append(["zoom", 1, e[5:]])
        else:
            out.append(e)
    return [f"zoom ×{o[1]} → {o[2]}" if isinstance(o, list) else o for o in out]

def stats(lines):
    ys, clicks, start, zoom, lift = [], [], None, None, None
    for ms, e in lines:
        if e.startswith("zoom at start"): start = zoom = e[len("zoom at start "):]; continue
        if e.startswith("zoom "): zoom = e[5:]
        if e.startswith("[touch]") and (" ended " in e or " cancelled " in e): lift = ms
        p = re.search(r"pointer\.(\w+)\(([-\d.]+),([-\d.]+)\)", e)
        if p:
            ys.append(float(p.group(3)))
            if p.group(1) in ("leftDown", "rightDown"):
                clicks.append(f"{p.group(1)} +{ms - lift} ms" if lift is not None else f"{p.group(1)} before any lift")
    y = f"pointer y {min(ys):.4f}..{max(ys):.4f} over {len(ys)}" if ys else "no pointer events"
    return f"zoom {start} → {zoom}; {y}; clicks after their lift: {', '.join(clicks) or 'none'}"

def main():
    base, new = load(sys.argv[1]), load(sys.argv[2])
    for g in list(base) + [g for g in new if g not in base]:
        print(f"=== {g}")
        a, b = base.get(g), new.get(g)
        if a is None or b is None:
            print(f"  only in {'NEW' if a is None else 'BASE'}"); continue
        ea, eb = events(a), events(b)
        if ea == eb:
            print("  same:"); print("".join(f"    {e}\n" for e in ea) or "    (nothing sent, no zoom)\n", end="")
        else:
            for d in list(difflib.unified_diff(ea, eb, "BASE", "NEW", n=1, lineterm=""))[2:]:
                print(f"  {d}")
        print(f"  BASE: {stats(a)}")
        print(f"  NEW:  {stats(b)}")

if __name__ == "__main__":
    main()
