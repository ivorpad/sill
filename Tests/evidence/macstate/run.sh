#!/bin/bash
# Mac state (Tests/evidence/README.md): builds main.swift with ../PasteboardDigest.swift and Sill's
# Sources/StreamProtocol/Clipboard.swift into .build/evidence/macstate/macstate and runs it: one JSON
# object of the Dock's windows and defaults, the pointer, the displays and the pasteboard's hashes.
#
#   Tests/evidence/macstate/run.sh                pretty JSON
#   Tests/evidence/macstate/run.sh --line         one line, to append to a JSONL
#
# No permission needed for the Dock's bounds and layers; window names stay empty without Screen
# Recording, which this tool does not ask for.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/.build/evidence/macstate"
mkdir -p "$out"
bin="$out/macstate"
srcs=("$here/main.swift" "$here/../PasteboardDigest.swift" "$root/Sources/StreamProtocol/Clipboard.swift")
stale=0; [ -x "$bin" ] || stale=1
for s in "${srcs[@]}"; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" = 1 ]; then
    xcrun swiftc -O -swift-version 5 -module-name MacState "${srcs[@]}" -o "$bin"
    codesign -s - --force --identifier me.ivor.sill.macstate "$bin" >/dev/null 2>&1
fi
exec "$bin" "$@"
