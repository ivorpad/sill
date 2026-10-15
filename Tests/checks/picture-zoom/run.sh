#!/bin/bash
# PictureZoom (iOSClient/PictureZoom.swift) on its own: where pinch to zoom draws the picture, that
# scale 1 is the fitted picture exactly, the scale's limits and the snap back, the pinched point
# staying under the fingers, the edges kept covered, and the round trip of a rect through the state.
#   Tests/checks/picture-zoom/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O iOSClient/PictureZoom.swift "$here/main.swift" -o "$out/check"
"$out/check"
