#!/bin/bash
# ClipboardItem and ClipboardEcho (Sources/StreamProtocol/Clipboard.swift) on their own: what a
# side sends of a copy (text or one image, under each direction's cap, with room for base64 in the
# message's limit), which copies stay on the Mac (concealed, transient, auto-generated), the wire's
# JSON and an older reader of it, and the change-count rule that sends each own copy once and never
# sends back what the other side wrote.
#   Tests/checks/clipboard/run.sh             compile and run the check
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
swiftc -O Sources/StreamProtocol/Clipboard.swift "$here/main.swift" -o "$out/check"
"$out/check"
