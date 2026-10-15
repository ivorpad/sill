#!/bin/bash
# PictureZoom (iOSClient/PictureZoom.swift) on its own: where pinch to zoom draws the picture, that
# scale 1 is the fitted picture exactly, the scale's limits and the snap back, the pinched point
# staying under the fingers, the edges kept covered, the round trip of a rect through the state,
# the follow of the pointer (to exactly the margin) and the two-finger double tap's in or out.
#   Tests/checks/picture-zoom/run.sh             compile and run the check
#   Tests/checks/picture-zoom/run.sh --mutants   one-line mutants of PictureZoom.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PictureZoom.swift "$here/main.swift" -o "$out/check"
"$out/check"
