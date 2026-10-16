#!/bin/bash
# Locking and unlocking the Mac from a device (docs/lock-screen-plan.md), Sources/StreamProtocol/LockScreen.swift
# with StreamMessage.swift's kind 44 and Switcher.swift's `locked`, `lockScreen` and `unlock`, on their own:
# kind 44's JSON and an older reader of it, what a host may type, the Mac's two switches for each route and
# door, the record of attempts (one at a time, 5 s after a failure, the PIN stop after 2), the verdict on an
# unlock request in the plan's order, lock again's conditions and grace, and the lock shortcut.
# Compiled with the files in module.txt as one module (../module.py).
#   Tests/checks/lock-screen/run.sh             compile and run the check
#   Tests/checks/lock-screen/run.sh --mutants   one-line mutants of LockScreen.swift and the two files beside it; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
