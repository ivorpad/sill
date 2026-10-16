#!/bin/bash
# The device's half of locking and unlocking the Mac (docs/lock-screen-plan.md), iOSClient/LockScreenPolicy.swift
# with StreamProtocol's LockScreen.swift, on their own: when a request may go, what becomes of it, the card's and
# the Settings panel's words, and the password kept for Face ID (decision 3): what the card offers for each
# lock screen, connection and device, and what the Mac's answer does to the keychain.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/lock-device/run.sh             compile and run the check
#   Tests/checks/lock-device/run.sh --mutants   one-line mutants of LockScreenPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
