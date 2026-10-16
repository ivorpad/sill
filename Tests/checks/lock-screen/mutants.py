"""Mutants of the lock screen's rules (Sources/StreamProtocol/LockScreen.swift), of kind 44's number
(StreamMessage.swift) and of the window list's three fields (Switcher.swift): each changes one place and must
compile and make the check (main.swift) fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/StreamProtocol/LockScreen.swift"
MSG = "Sources/StreamProtocol/StreamMessage.swift"
LIST = "Sources/StreamProtocol/Switcher.swift"

# The verdict's guards, as the file has them, for the mutants that swap two of them (the plan's order).
DOOR = '        guard tls else { return .refuse("This connection can’t unlock \\(mac).") }\n'
SWITCH = ('        guard policy.allow else {\n'
          '            return .refuse("Unlocking from devices is off on \\(mac). It can be turned on in Sill on the Mac, in Settings › General.")\n'
          '        }\n')
AWAY = ('        guard policy.allows(away: away) else {\n'
        '            return .refuse("Unlocking from devices away from home is off on \\(mac).")\n'
        '        }\n')
CONSOLE = '        guard onConsole else { return .refuse("\\(mac) is showing another user’s session.") }\n'
LOCKED = '        guard locked else { return .alreadyUnlocked }\n'
SECRET = ('        guard let secret, LockScreenSecret.isTypeable(secret) else {\n'
          '            return .refuse("Sill can’t type that \\(LockScreenAsk.word(ask)).")\n'
          '        }\n')
ATTEMPTS = '        if let why = attempts.refusal(now: now, ask: ask, mac: mac) { return .refuse(why) }\n'
# Lock again's conjunction, and the three-line `ended`'s cases.
AGAIN = "enabled && unlockedBySill && !unlockerBack && !locked && !usedSince && now - leftAt >= grace"
ALLOWS = "allow && (allowAway || !away)"
LABEL = 'case password: return "Password"\n        case pin: return "PIN"'      # LockScreenAsk.label's; the word's has the lowercase first line
WORD = 'case password: return "password"\n        case pin: return "PIN"'       # LockScreenAsk.word's
STANDARD = 'LockShortcut(key: "q", command: true, control: true, option: false, shift: false)'
MODIFIERS = "shortcut.command || shortcut.control || shortcut.option"
CONTROL = "$0.properties.generalCategory == .control"
STOP = "if ask == LockScreenAsk.pin, failuresInARow >= Self.pinFailureStop {"
WAIT = "if let lastFailure, now - lastFailure < UnlockTiming.afterFailure {"
LISTINIT = "self.locked = locked; self.lockScreen = lockScreen; self.unlock = unlock"

def swap(a, b):
    """Two neighbouring guards in each other's places: one replacement, since a pattern is found exactly once."""
    return (a + b, b + a)

M = [
    # Kind 44 and the window list's three fields
    ("K1 the lock screen is kind 45", MSG, "case lockScreen = 44", "case lockScreen = 45"),
    ("K2 the list's locked not kept", LIST, LISTINIT, "self.locked = nil; self.lockScreen = lockScreen; self.unlock = unlock"),
    ("K3 the list's lockScreen not kept", LIST, LISTINIT, "self.locked = locked; self.lockScreen = nil; self.unlock = unlock"),
    ("K4 the list's unlock not kept", LIST, LISTINIT, "self.locked = locked; self.lockScreen = lockScreen; self.unlock = nil"),
    ("K5 the list says locked unless told otherwise", LIST, "locked: String? = nil", 'locked: String? = "password"'),
    ("K6 the list says lockScreen 1 unless told otherwise", LIST, "lockScreen: Int? = nil", "lockScreen: Int? = 1"),
    ("K7 the list says unlock unless told otherwise", LIST, "unlock: Bool? = nil", "unlock: Bool? = true"),
    # The request and the outcome
    ("R1 generation 2", F, "public static let generation = 1", "public static let generation = 2"),
    ("R2 the request's action not kept", F, "self.action = action", 'self.action = "unlock"'),
    ("R3 the request's secret not kept", F, "self.secret = secret", "self.secret = nil"),
    ("R4 the request's token not kept", F, "self.secret = secret\n        self.token = token", "self.secret = secret\n        self.token = 0"),
    ("R5 the outcome's token not kept", F, "self.token = token\n        self.outcome = outcome", "self.token = 0\n        self.outcome = outcome"),
    ("R6 the outcome's word not kept", F, "self.outcome = outcome", 'self.outcome = "refused"'),
    ("R7 the outcome's message not kept", F, "self.message = message", "self.message = nil"),
    # The words
    ("W1 the lock action's word", F, 'public static let lock = "lock"', 'public static let lock = "Lock"'),
    ("W2 the unlock action's word", F, 'public static let unlock = "unlock"', 'public static let unlock = "open"'),
    ("W3 unlock is not a known action", F, "Set<String> = [lock, unlock]", "Set<String> = [lock]"),
    ("W4 the unlocked outcome's word", F, 'public static let unlocked = "unlocked"', 'public static let unlocked = "unlockd"'),
    ("W5 the stillLocked outcome's word", F, 'public static let stillLocked = "stillLocked"', 'public static let stillLocked = "stilllocked"'),
    ("W6 the refused outcome's word", F, 'public static let refused = "refused"', 'public static let refused = "Refused"'),
    ("W7 the locked outcome's word", F, 'public static let locked = "locked"', 'public static let locked = "Locked"'),
    ("W8 the notLocked outcome's word", F, 'public static let notLocked = "notLocked"', 'public static let notLocked = "notlocked"'),
    ("W9 notLocked is not a known outcome", F, "[unlocked, stillLocked, refused, locked, notLocked]", "[unlocked, stillLocked, refused, locked]"),
    ("W10 the password ask's word", F, 'public static let password = "password"', 'public static let password = "Password"'),
    ("W11 the pin ask's word", F, 'public static let pin = "pin"', 'public static let pin = "PIN"'),
    ("W12 pin is not a known ask", F, "Set<String> = [password, pin]", "Set<String> = [password]"),
    ("W13 the PIN label", F, LABEL, LABEL.replace('"PIN"', '"Pin"')),
    ("W14 the PIN label says password", F, LABEL, LABEL.replace('"PIN"', '"Password"')),
    ("W15 the password label", F, 'case password: return "Password"', 'case password: return "password"'),
    ("W16 an unknown ask's label", F, 'default: return "Password or PIN"', 'default: return "Password"'),
    ("W17 the word for a password is capitalized", F, 'case password: return "password"', 'case password: return "Password"'),
    ("W18 the word for a PIN is lowercase", F, WORD, WORD.replace('"PIN"', '"pin"')),
    ("W19 the word for a PIN says password", F, WORD, WORD.replace('"PIN"', '"password"')),
    ("W20 an unknown ask's word is the label", F, 'default: return "password or PIN"', 'default: return "Password or PIN"'),
    ("W21 an unknown ask's word is a password", F, 'default: return "password or PIN"', 'default: return "password"'),
    ("W22 an unknown ask's word lowercases the PIN", F, 'default: return "password or PIN"', 'default: return "password or pin"'),
    # What a host may type
    ("S1 129 characters", F, "public static let maxCharacters = 128", "public static let maxCharacters = 129"),
    ("S2 127 characters", F, "public static let maxCharacters = 128", "public static let maxCharacters = 127"),
    ("S3 an empty secret typed", F, "!secret.isEmpty && secret.count <= maxCharacters", "secret.count <= maxCharacters"),
    ("S4 the cap's edge left out", F, "secret.count <= maxCharacters", "secret.count < maxCharacters"),
    ("S5 bytes counted, not characters", F, "secret.count <= maxCharacters", "secret.utf8.count <= maxCharacters"),
    ("S6 scalars counted, not characters", F, "secret.count <= maxCharacters", "secret.unicodeScalars.count <= maxCharacters"),
    ("S7 no cap", F, "secret.count <= maxCharacters", "true"),
    ("S8 only the first scalar checked for control", F, "!secret.unicodeScalars.contains { " + CONTROL + " }",
     "!(secret.unicodeScalars.first?.properties.generalCategory == .control)"),
    ("S9 only the last scalar checked for control", F, "!secret.unicodeScalars.contains { " + CONTROL + " }",
     "!(secret.unicodeScalars.last?.properties.generalCategory == .control)"),
    ("S10 control characters typed", F, "!secret.unicodeScalars.contains { " + CONTROL + " }", "true"),
    ("S11 only a secret with a control character typed", F, "!secret.unicodeScalars.contains {", "secret.unicodeScalars.contains {"),
    ("S12 control means below a space", F, CONTROL, "$0.value < 0x20"),
    ("S13 control means below a space, and delete", F, CONTROL, "$0.value < 0x20 || $0.value == 0x7F"),
    ("S14 control means a Return", F, CONTROL, '$0 == "\\n" || $0 == "\\r"'),
    ("S15 white space is a control", F, CONTROL, "$0.properties.isWhitespace"),
    # The host's waits
    ("T1 the wait after a failure is 4 s", F, "afterFailure: Double = 5", "afterFailure: Double = 4"),
    ("T2 the wait after a failure is 6 s", F, "afterFailure: Double = 5", "afterFailure: Double = 6"),
    ("T3 the verdict does not outlast loginwindow", F, "verdictWait: Double = 6", "verdictWait: Double = 5"),
    ("T4 no wait for the display", F, "wakeWait: Double = 2", "wakeWait: Double = 0"),
    ("T5 no settle", F, "settle: Double = 0.3", "settle: Double = 0"),
    ("T6 no gap between keys", F, "keyGap: Double = 0.015", "keyGap: Double = 0"),
    ("T7 no wait for the lock", F, "lockWait: Double = 2", "lockWait: Double = 0"),
    # The Mac's two switches
    ("P1 unlocking on by default", F, "public init(allow: Bool = false, allowAway: Bool = false)", "public init(allow: Bool = true, allowAway: Bool = false)"),
    ("P2 away on by default", F, "public init(allow: Bool = false, allowAway: Bool = false)", "public init(allow: Bool = false, allowAway: Bool = true)"),
    ("P3 the first switch not kept", F, "self.allow = allow", "self.allow = true"),
    ("P4 the second switch not kept", F, "self.allowAway = allowAway", "self.allowAway = false"),
    ("P5 the away gate dropped", F, ALLOWS, "allow"),
    ("P6 the away switch lets in by itself", F, ALLOWS, "(allow || allowAway) && (allowAway || !away)"),
    ("P7 the first switch ignored", F, ALLOWS, "allowAway || !away"),
    ("P8 the away gate inverted", F, ALLOWS, "allow && (allowAway || away)"),
    ("P9 a connection home needs the away switch too", F, ALLOWS, "allow && allowAway"),
    ("P10 the door ignored in the list", F, "tls && allows(away: away) ? true : nil", "allows(away: away) ? true : nil"),
    ("P11 the switches ignored in the list", F, "tls && allows(away: away) ? true : nil", "tls ? true : nil"),
    ("P12 the list says false, not nothing", F, "tls && allows(away: away) ? true : nil", "tls && allows(away: away) ? true : false"),
    ("P13 the list says unlock for either", F, "tls && allows(away: away) ? true : nil", "tls || allows(away: away) ? true : nil"),
    # The record of attempts
    ("A1 a second attempt in flight is taken", F, '        if inFlight { return "\\(mac) is already being unlocked." }\n', ""),
    ("A2 the in-flight refusal without the Mac's name", F, '"\\(mac) is already being unlocked."', '"The Mac is already being unlocked."'),
    ("A3 an attempt that began is not in flight", F, "        inFlight = true", "        inFlight = false"),
    ("A4 an attempt never ends", F, "        inFlight = false\n        switch outcome {", "        switch outcome {"),
    ("A5 the PIN stop for a password too", F, STOP, "if failuresInARow >= Self.pinFailureStop {"),
    ("A6 the PIN stop for a password only", F, STOP, "if ask != LockScreenAsk.pin, failuresInARow >= Self.pinFailureStop {"),
    ("A7 the PIN stop after 3", F, STOP, "if ask == LockScreenAsk.pin, failuresInARow > Self.pinFailureStop {"),
    ("A8 the PIN stop is 3", F, "public static let pinFailureStop = 2", "public static let pinFailureStop = 3"),
    ("A9 the PIN stop is 1", F, "public static let pinFailureStop = 2", "public static let pinFailureStop = 1"),
    ("A10 the PIN stop without the Mac's name", F, "Unlock \\(mac) at the Mac", "Unlock the Mac at the Mac"),
    ("A11 the wait's edge left in", F, WAIT, "if let lastFailure, now - lastFailure <= UnlockTiming.afterFailure {"),
    ("A12 the wait inverted", F, WAIT, "if let lastFailure, now - lastFailure > UnlockTiming.afterFailure {"),
    ("A13 no wait", F, WAIT, "if let lastFailure, now - lastFailure < 0 {"),
    ("A14 the wait's words", F, '"Wait a few seconds, then try again."', '"Try again."'),
    ("A15 a failure counted once and for all", F, "failuresInARow += 1", "failuresInARow = 1"),
    ("A16 a failure counted twice", F, "failuresInARow += 1", "failuresInARow += 2"),
    ("A17 a failure's time not kept", F, "            lastFailure = now\n", ""),
    ("A18 a refusal counted as a failure", F, "case LockScreenOutcome.stillLocked:", "case LockScreenOutcome.refused:"),
    ("A19 any other ending counted as a failure", F, "        default:\n            break\n", "        default:\n            failuresInARow += 1\n"),
    ("A20 an unlock leaves the count", F, "case LockScreenOutcome.unlocked:\n            failuresInARow = 0\n            lastFailure = nil\n",
     "case LockScreenOutcome.unlocked:\n            lastFailure = nil\n"),
    ("A21 an unlock leaves the time", F, "case LockScreenOutcome.unlocked:\n            failuresInARow = 0\n            lastFailure = nil\n",
     "case LockScreenOutcome.unlocked:\n            failuresInARow = 0\n"),
    ("A22 the Mac unlocking changes nothing", F, "public mutating func macUnlocked() {\n        failuresInARow = 0\n        lastFailure = nil\n    }",
     "public mutating func macUnlocked() {\n    }"),
    ("A23 the Mac unlocking leaves the count", F, "public mutating func macUnlocked() {\n        failuresInARow = 0\n        lastFailure = nil\n    }",
     "public mutating func macUnlocked() {\n        lastFailure = nil\n    }"),
    ("A24 the Mac unlocking leaves the time", F, "public mutating func macUnlocked() {\n        failuresInARow = 0\n        lastFailure = nil\n    }",
     "public mutating func macUnlocked() {\n        failuresInARow = 0\n    }"),
    ("A25 the Mac unlocking ends an attempt still typing", F, "public mutating func macUnlocked() {\n        failuresInARow = 0\n",
     "public mutating func macUnlocked() {\n        inFlight = false\n        failuresInARow = 0\n"),
    # The verdict
    ("V1 the door not judged", F, "guard tls else {", "guard true else {"),
    ("V2 the first switch not judged", F, "guard policy.allow else {", "guard true else {"),
    ("V3 the away switch not judged", F, "guard policy.allows(away: away) else {", "guard true else {"),
    ("V4 the console not judged", F, "guard onConsole else {", "guard true else {"),
    ("V5 an unlocked Mac is typed into", F, "guard locked else { return .alreadyUnlocked }", "guard true else { return .alreadyUnlocked }"),
    ("V6 an unlocked Mac goes", F, "guard locked else { return .alreadyUnlocked }", "guard locked else { return .go }"),
    ("V7 the secret's typeability not judged", F, "guard let secret, LockScreenSecret.isTypeable(secret) else {", "guard secret != nil else {"),
    ("V8 a missing secret goes", F, "guard let secret, LockScreenSecret.isTypeable(secret) else {", "guard secret == nil || LockScreenSecret.isTypeable(secret!) else {"),
    ("V9 the attempts not judged", F, ATTEMPTS, "        _ = attempts.refusal(now: now, ask: ask, mac: mac)\n"),
    ("V10 the verdict goes to an unlocked Mac", F, "        return .go\n    }\n}\n\n/// Lock again", "        return .alreadyUnlocked\n    }\n}\n\n/// Lock again"),
    ("V11 the door judged after the switch", F, *swap(DOOR, SWITCH)),
    ("V12 the switch judged after the away switch", F, *swap(SWITCH, AWAY)),
    ("V13 the away switch judged after the console", F, *swap(AWAY, CONSOLE)),
    ("V14 the console judged after the lock state", F, *swap(CONSOLE, LOCKED)),
    ("V15 the lock state judged after the secret", F, *swap(LOCKED, SECRET)),
    ("V16 the secret judged after the attempts", F, *swap(SECRET, ATTEMPTS)),
    ("V17 the door's refusal without the Mac's name", F, '"This connection can’t unlock \\(mac)."', '"This connection can’t unlock this Mac."'),
    ("V18 the switch's refusal without the Mac's name", F, "Unlocking from devices is off on \\(mac). It can be", "Unlocking from devices is off on this Mac. It can be"),
    ("V19 the switch's refusal without where to turn it on", F, " It can be turned on in Sill on the Mac, in Settings › General.", ""),
    ("V20 the away refusal without the Mac's name", F, '"Unlocking from devices away from home is off on \\(mac)."', '"Unlocking from devices away from home is off on this Mac."'),
    ("V21 the console's refusal without the Mac's name", F, '"\\(mac) is showing another user’s session."', '"The Mac is showing another user’s session."'),
    ("V22 the secret's refusal in capitals", F, "LockScreenAsk.word(ask)", "LockScreenAsk.label(ask)"),
    ("V23 the secret's refusal lowercases the PIN", F, "LockScreenAsk.word(ask)", "LockScreenAsk.label(ask).lowercased()"),
    ("V24 the secret's refusal repeats it", F, 'return .refuse("Sill can’t type that \\(LockScreenAsk.word(ask)).")',
     'return .refuse("Sill can’t type that \\(secret ?? "secret").")'),
    # Lock again
    ("L1 no grace", F, "public static let grace: Double = 30", "public static let grace: Double = 0"),
    ("L2 a minute's grace", F, "public static let grace: Double = 30", "public static let grace: Double = 60"),
    ("L3 the switch ignored", F, AGAIN, AGAIN.replace("enabled &&", "true &&", 1)),
    ("L4 whoever unlocked it ignored", F, AGAIN, AGAIN.replace("unlockedBySill &&", "true &&", 1)),
    ("L5 the device's return ignored", F, AGAIN, AGAIN.replace("!unlockerBack", "true", 1)),
    ("L6 an unlocked Mac required locked", F, AGAIN, AGAIN.replace("!locked", "locked", 1)),
    ("L7 a Mac locked already locked again", F, AGAIN, AGAIN.replace("!locked", "true", 1)),
    ("L8 use since ignored", F, AGAIN, AGAIN.replace("!usedSince", "true", 1)),
    ("L9 use since required", F, AGAIN, AGAIN.replace("!usedSince", "usedSince", 1)),
    ("L10 the grace's edge left out", F, AGAIN, AGAIN.replace(">= grace", "> grace", 1)),
    ("L11 the grace ignored", F, AGAIN, AGAIN.replace("now - leftAt >= grace", "now >= leftAt", 1)),
    ("L12 the grace counted the other way", F, AGAIN, AGAIN.replace("now - leftAt >= grace", "leftAt - now >= grace", 1)),
    ("L13 any one condition is enough", F, AGAIN, AGAIN.replace("enabled && unlockedBySill", "enabled || unlockedBySill", 1)),
    # The lock shortcut
    ("H1 the standard key", F, "static let standard = " + STANDARD, "static let standard = " + STANDARD.replace('key: "q"', 'key: "l"')),
    ("H2 the standard without ⌘", F, "static let standard = " + STANDARD, "static let standard = " + STANDARD.replace("command: true", "command: false")),
    ("H3 the standard without ⌃", F, "static let standard = " + STANDARD, "static let standard = " + STANDARD.replace("control: true", "control: false")),
    ("H4 the standard with ⌥", F, "static let standard = " + STANDARD, "static let standard = " + STANDARD.replace("option: false", "option: true")),
    ("H5 the standard with ⇧", F, "static let standard = " + STANDARD, "static let standard = " + STANDARD.replace("shift: false", "shift: true")),
    ("H6 no key equivalent is no shortcut", F, "guard let equivalent = userKeyEquivalent else { return standard }", "guard let equivalent = userKeyEquivalent else { return nil }"),
    ("H7 @ is ⌃", F, 'case "@": shortcut.command = true', 'case "@": shortcut.control = true'),
    ("H8 ^ is ⌘", F, 'case "^": shortcut.control = true', 'case "^": shortcut.command = true'),
    ("H9 ~ is ⇧", F, 'case "~": shortcut.option = true', 'case "~": shortcut.shift = true'),
    ("H10 $ is ⌥", F, "default: shortcut.shift = true", "default: shortcut.option = true"),
    ("H11 $ is not a modifier", F, '"@^~$".contains(first)', '"@^~".contains(first)'),
    ("H12 ~ is not a modifier", F, '"@^~$".contains(first)', '"@^$".contains(first)'),
    ("H13 two keys are a shortcut", F, "guard rest.count == 1, let key", "guard rest.count >= 1, let key"),
    ("H14 a space is a key", F, ", !key.isWhitespace else { return nil }", " else { return nil }"),
    ("H15 a key alone is a shortcut", F, "guard " + MODIFIERS + " else { return nil }", "guard true else { return nil }"),
    ("H16 ⇧ counts as a modifier", F, MODIFIERS, MODIFIERS + " || shortcut.shift"),
    ("H17 ⌥ does not count as a modifier", F, MODIFIERS, "shortcut.command || shortcut.control"),
    ("H18 both ⌘ and ⌃ are needed", F, MODIFIERS, "shortcut.command && shortcut.control"),
    ("H19 the key keeps its case", F, "shortcut.key = Character(key.lowercased())", "shortcut.key = key"),
    ("H20 the shortcut's key not kept", F, "self.key = key", 'self.key = "q"'),
    ("H21 the shortcut's ⌘ not kept", F, "self.command = command", "self.command = true"),
    ("H22 the shortcut's ⌃ not kept", F, "self.control = control", "self.control = true"),
    ("H23 the shortcut's ⌥ not kept", F, "self.option = option", "self.option = false"),
    ("H24 the shortcut's ⇧ not kept", F, "self.shift = shift", "self.shift = false"),
]
sys.exit(0 if module.mutate("lock-screen", M, sys.argv[1]) else 1)
