#!/bin/bash
# ClipboardItem and ClipboardEcho (Sources/StreamProtocol/Clipboard.swift) on their own: what a
# side sends of a copy (text or one image, under each direction's cap, with room for base64 in the
# message's limit), which copies stay on the Mac (concealed, transient, auto-generated), the wire's
# JSON and an older reader of it, the change-count rule that sends each own copy once and never
# sends back what the other side wrote, who shares (the Mac's two switches, home and away), the enable
# moment on each side (a copy made before sharing started is never sent) and the two-minute expiry.
#   Tests/checks/clipboard/run.sh             compile and run the check
#   Tests/checks/clipboard/run.sh --mutants   one-line mutants of Clipboard.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/StreamProtocol/Clipboard.swift "$here/main.swift" -o "$out/check"
"$out/check"
