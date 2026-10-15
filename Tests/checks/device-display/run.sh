#!/bin/bash
# DeviceDisplayGeometry (Sources/SillHost/DeviceDisplayGeometry.swift) on its own: the size of a
# display for one device (docs/sidecar-desktop-plan.md): the panel's pixels ÷ 2 in points at 2×,
# the 3× iPhone rule, Aa (More Space larger, Larger Text smaller, Default 1:1), the encoded size
# (never past the panel's pixels, even), the bounds (320×240 to 4096 pt), the capacity a display is
# made for, and the serial per paired key. Its `package` access needs -package-name.
#   Tests/checks/device-display/run.sh             compile and run the check
#   Tests/checks/device-display/run.sh --mutants   one-line mutants of DeviceDisplayGeometry.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/DeviceDisplayGeometry.swift "$here/main.swift" -o "$out/check"
"$out/check"
