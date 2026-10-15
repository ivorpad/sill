#!/bin/bash
# Pasteboard watch (Tests/evidence/README.md): builds main.swift with ../PasteboardDigest.swift and
# Sill's own Sources/StreamProtocol/Clipboard.swift (for ClipboardItem.privateTypes) into
# .build/evidence/pasteboard/pasteboard and runs it with these arguments. Hashes and sizes only.
#
#   Tests/evidence/pasteboard/run.sh              JSONL, one record per change, until Ctrl-C
#   Tests/evidence/pasteboard/run.sh --once       the current state, then exit
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="$root/.build/evidence/pasteboard"
mkdir -p "$out"
bin="$out/pasteboard"
srcs=("$here/main.swift" "$here/../PasteboardDigest.swift" "$root/Sources/StreamProtocol/Clipboard.swift")
stale=0; [ -x "$bin" ] || stale=1
for s in "${srcs[@]}"; do [ "$s" -nt "$bin" ] && stale=1; done
if [ "$stale" = 1 ]; then
    xcrun swiftc -O -swift-version 5 -module-name PasteboardWatch "${srcs[@]}" -o "$bin"
    codesign -s - --force --identifier me.ivor.sill.pasteboard "$bin" >/dev/null 2>&1
fi
exec "$bin" "$@"
