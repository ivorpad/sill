#!/bin/bash
# TouchTrace's traces back from the iPhone (Tests/evidence/README.md): copies the app's Documents
# (every touchtrace-*.jsonl and latest.txt) into .build/evidence/touchtrace/pulled/<now>/ and prints
# the newest trace's path and its record counts.
#
#   Tests/evidence/touchtrace/pull.sh
#   SILL_EVIDENCE_DEVICE=<udid|name> Tests/evidence/touchtrace/pull.sh
#
# Copy the newest trace after the last gesture: the app flushes at each gesture change and when it
# leaves the foreground, so lock the phone or swipe home first to be sure the tail is on disk.
set -euo pipefail
# The shell may point DEVELOPER_DIR at the Command Line Tools, which have no iOS SDK or devicectl.
export DEVELOPER_DIR="${SILL_XCODE:-/Applications/Xcode.app/Contents/Developer}"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
device="${SILL_EVIDENCE_DEVICE:-00008140-000558A93C13001C}"
dest="$root/.build/evidence/touchtrace/pulled/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dest"
xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
    --domain-identifier me.ivor.sill.touchtrace --source Documents --destination "$dest" >/dev/null
latest="$(find "$dest" -name latest.txt -print -quit)"
[ -n "$latest" ] || { echo "touchtrace: no latest.txt in the copy at $dest" >&2; exit 1; }
trace="$(dirname "$latest")/$(cat "$latest")"
echo "touchtrace: copied to $dest"
echo "touchtrace: newest $trace"
python3 - "$trace" <<'PY'
import collections, json, sys
kinds, per = collections.Counter(), collections.Counter()
for line in open(sys.argv[1]):
    r = json.loads(line); kinds[r["k"]] += 1
    if r["k"] == "touch": per[r["g"]] += 1
print("records:", dict(kinds))
print("touch records per gesture:", dict(per))
PY
