#!/bin/bash
# EventTap (Tests/evidence/README.md): builds main.swift with swiftc into .build/evidence/eventtap/eventtap
# and runs it with these arguments. A listen-only session event tap: it logs, never changes or posts.
#
#   Tests/evidence/eventtap/run.sh                         JSONL to stdout
#   Tests/evidence/eventtap/run.sh --out FILE              appended to FILE
#   Tests/evidence/eventtap/run.sh --build-only            build, print the binary's path
#
# Needs Input Monitoring for the binary or the terminal that starts it; without it the tool exits 3
# and names the path to grant. A rebuild changes the binary's signature, which can cost the grant.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/.build/evidence/eventtap"
mkdir -p "$out"
bin="$out/eventtap"
if [ ! -x "$bin" ] || [ "$here/main.swift" -nt "$bin" ]; then
    xcrun swiftc -O -swift-version 5 "$here/main.swift" -o "$bin"
    codesign -s - --force --identifier me.ivor.sill.eventtap "$bin" >/dev/null 2>&1
fi
if [ "${1:-}" = "--build-only" ]; then echo "$bin"; exit 0; fi
exec "$bin" "$@"
