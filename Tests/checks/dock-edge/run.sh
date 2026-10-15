#!/bin/bash
# DockEdge (Sources/SillHost/DockEdge.swift) on its own: when a device's pointer held at a streamed
# window's bottom edge switches the picture to the Desktop with the Dock (the edge, the dwell, a pass
# along the bottom, a drag, a stale dwell, one switch an arrival), and where a device's position lands
# on the Mac (`pixel`: a fraction of 1 on the last row, not past it). Its `package` access needs
# -package-name.
#   Tests/checks/dock-edge/run.sh             compile and run the check
#   Tests/checks/dock-edge/run.sh --mutants   one-line mutants of DockEdge.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/DockEdge.swift "$here/main.swift" -o "$out/check"
"$out/check"
