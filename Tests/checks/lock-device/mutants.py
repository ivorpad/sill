"""Mutants of the device's lock screen rules (iOSClient/LockScreenPolicy.swift): each changes one place and must
compile and make the check (main.swift) fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "iOSClient/LockScreenPolicy.swift"

OFFER = "        guard unlock == true, ask == LockScreenAsk.password, pinned, biometry != nil else { return .nothing }\n"
REMEMBER = "            return answer.outcome == LockScreenOutcome.unlocked && answer.message == nil ? .save : .leave\n"
FORGET = "            return answer.outcome == LockScreenOutcome.stillLocked ? .forget : .leave\n"
# unlockBlock's first two guards and its last two: lockBlock has lines like them, so each is taken with its neighbour.
SESSION = "        guard connected else { return .notConnected }\n        guard unlock == true else { return .notAllowed }\n"
BUSY = ("        guard attempt?.sending != true else { return .busy }\n"
        "        guard LockScreenSecret.isTypeable(secret) else { return .cannotType }\n")
M = [
    # What the card offers
    ("F1 a Mac not pinned by its key is offered the kept password", F, OFFER,
     "        guard unlock == true, ask == LockScreenAsk.password, biometry != nil else { return .nothing }\n"),
    ("F2 a PIN is offered too", F, OFFER,
     "        guard unlock == true, ask != nil, pinned, biometry != nil else { return .nothing }\n"),
    ("F3 offered without the card's field", F, OFFER,
     "        guard ask == LockScreenAsk.password, pinned, biometry != nil else { return .nothing }\n"),
    ("F4 offered without biometry", F, OFFER,
     "        guard unlock == true, ask == LockScreenAsk.password, pinned else { return .nothing }\n"),
    ("F5 the button and the switch swapped", F, "        return saved ? .unlockWithSaved : .remember\n",
     "        return saved ? .remember : .unlockWithSaved\n"),
    # What the Mac's answer does
    ("F6 kept when the Mac was unlocked already (nothing typed)", F, REMEMBER,
     "            return answer.outcome == LockScreenOutcome.unlocked ? .save : .leave\n"),
    ("F7 kept whatever the outcome, without words", F, REMEMBER,
     "            return answer.message == nil ? .save : .leave\n"),
    ("F8 never kept", F, REMEMBER, "            return .leave\n"),
    ("F9 the kept password removed after a refusal too", F, FORGET,
     "            return answer.outcome != LockScreenOutcome.unlocked ? .forget : .leave\n"),
    ("F10 the kept password never removed", F, FORGET, "            return .leave\n"),
    ("F11 removed when it worked", F, FORGET,
     "            return answer.outcome == LockScreenOutcome.unlocked ? .forget : .leave\n"),
    # The card's line and the attempt's record
    ("F12 the kept password's failure reads as a typed one's", F,
     "                if attempt.fromSaved { return savedForgotten(mac: mac) }\n", ""),
    ("F13 an attempt counts as the kept password's unless it says otherwise", F,
     "    var fromSaved = false\n", "    var fromSaved = true\n"),
    # When a request may go, and its record
    ("F14 the list's permission judged before the session", F, SESSION,
     "        guard unlock == true else { return .notAllowed }\n        guard connected else { return .notConnected }\n"),
    ("F15 a settled attempt blocks the next", F, BUSY,
     "        guard attempt == nil else { return .busy }\n"
     "        guard LockScreenSecret.isTypeable(secret) else { return .cannotType }\n"),
    ("F16 the secret's limits not judged", F, BUSY,
     "        guard attempt?.sending != true else { return .busy }\n"),
    ("F17 a second answer settles again", F, "        if case .answered = attempt.phase { return nil }\n", ""),
    ("F18 an answered attempt expires", F,
     "guard var attempt, attempt.token == token, attempt.phase == .sending else { return nil }",
     "guard var attempt, attempt.token == token else { return nil }"),
    ("F19 the link's margin shorter", F, "        let margin = 5.0\n", "        let margin = 4.0\n"),
    # Words
    ("F20 Touch ID called Face ID", F, '            case .touchID: return "Touch ID"\n', '            case .touchID: return "Face ID"\n'),
    ("F21 -SillBiometry's words changed", F, "        case faceID, touchID, opticID\n",
     '        case faceID = "face", touchID, opticID\n'),
    ("F22 the switch's footnote drops never synced", F,
     '"If it unlocks the Mac, the password is kept on this \\(device) only, never synced."',
     '"If it unlocks the Mac, the password is kept on this \\(device)."'),
    ("F23 Face ID's failure names Face ID always", F,
     '"\\(biometry.name) didn’t work. Try again, or type the password."',
     '"Face ID didn’t work. Try again, or type the password."'),
    ("F24 the panel's footnote without biometry", F, 'biometry?.name ?? "Face ID"', 'biometry?.name ?? "biometry"'),
]
sys.exit(0 if module.mutate("lock-device", M, sys.argv[1]) else 1)
