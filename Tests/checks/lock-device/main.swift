import Foundation

// The device's half of locking and unlocking the Mac (docs/lock-screen-plan.md): iOSClient/LockScreenPolicy.swift
// with StreamProtocol's LockScreen.swift, compiled on their own (module.txt names the files; run.sh hands them
// to ../module.py). When a request may go, what becomes of it, the words, and the password kept for Face ID
// (decision 3, Ivor, 2026-10-16): what the card offers, and what each answer of the Mac does to the keychain.
//
// The expectations are written out (sentences, a table of the offer's inputs, a few numbers), never taken from
// the code they check.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = LockScreenPolicy
let mac = "Mac mini"
let password = "password", pin = "pin"
func answer(_ outcome: String, _ message: String? = nil, token: Int = 3) -> LockScreenOutcome {
    LockScreenOutcome(token: token, outcome: outcome, message: message)
}
func attempt(_ phase: LockScreenAttempt.Phase, fromSaved: Bool = false, action: String = "unlock") -> LockScreenAttempt {
    var made = LockScreenAttempt(action: action, token: 3, phase: phase)
    made.fromSaved = fromSaved
    return made
}

// MARK: What the card offers beside its field

check(P.savedOffer(unlock: true, ask: password, pinned: true, biometry: .faceID, saved: false) == .remember,
      "a password, a pinned Mac, Face ID, nothing kept: the switch")
check(P.savedOffer(unlock: true, ask: password, pinned: true, biometry: .faceID, saved: true) == .unlockWithSaved,
      "the same with one kept: the button")
check(P.savedOffer(unlock: true, ask: password, pinned: true, biometry: .touchID, saved: true) == .unlockWithSaved,
      "Touch ID as Face ID")
check(P.savedOffer(unlock: true, ask: pin, pinned: true, biometry: .faceID, saved: true) == .nothing,
      "a PIN: neither, even with a password kept")
check(P.savedOffer(unlock: true, ask: pin, pinned: true, biometry: .faceID, saved: false) == .nothing,
      "a PIN is never offered to be kept")
check(P.savedOffer(unlock: true, ask: "smartcard", pinned: true, biometry: .faceID, saved: true) == .nothing,
      "an ask this build does not know: neither")
check(P.savedOffer(unlock: true, ask: "Password", pinned: true, biometry: .faceID, saved: true) == .nothing,
      "the ask is the wire's word exactly")
check(P.savedOffer(unlock: true, ask: nil, pinned: true, biometry: .faceID, saved: true) == .nothing,
      "not locked: neither")
check(P.savedOffer(unlock: true, ask: password, pinned: false, biometry: .faceID, saved: true) == .nothing,
      "a Mac this connection is not pinned to by its key: never the kept password")
check(P.savedOffer(unlock: true, ask: password, pinned: false, biometry: .faceID, saved: false) == .nothing,
      "nor the switch")
check(P.savedOffer(unlock: nil, ask: password, pinned: true, biometry: .faceID, saved: true) == .nothing,
      "no field (the Mac's switch is off): neither")
check(P.savedOffer(unlock: false, ask: password, pinned: true, biometry: .faceID, saved: true) == .nothing,
      "unlock false as nil")
check(P.savedOffer(unlock: true, ask: password, pinned: true, biometry: nil, saved: true) == .nothing,
      "no biometry now (none enrolled, locked out): neither")
// Every combination, against the rule in a sentence: both only for a field, a password, a pinned Mac and biometry.
var combinations = 0
for unlock in [true, false, nil] as [Bool?] {
    for ask in [password, pin, "smartcard", nil] as [String?] {
        for pinned in [true, false] {
            for biometry in [.faceID, .touchID, .opticID, nil] as [P.Biometry?] {
                for saved in [true, false] {
                    combinations += 1
                    let offered = P.savedOffer(unlock: unlock, ask: ask, pinned: pinned, biometry: biometry, saved: saved)
                    let allowed = unlock == true && ask == password && pinned && biometry != nil
                    let expected: P.SavedOffer = allowed ? (saved ? .unlockWithSaved : .remember) : .nothing
                    check(offered == expected, "\(String(describing: unlock)) \(ask ?? "unlocked") pinned \(pinned) \(String(describing: biometry)) saved \(saved): \(offered), not \(expected)")
                }
            }
        }
    }
}
check(combinations == 192, "the table has every combination")

// MARK: What the Mac's answer does to the kept password

check(P.savedChange(.remember, answer: answer("unlocked")) == .save, "typed to be kept, and the Mac unlocked with it: kept")
check(P.savedChange(.remember, answer: answer("unlocked", "Mac mini was already unlocked.")) == .leave,
      "the Mac was unlocked already and typed nothing: not kept")
check(P.savedChange(.remember, answer: answer("stillLocked")) == .leave, "a password that left the Mac locked: not kept")
check(P.savedChange(.remember, answer: answer("refused", "Wait a few seconds, then try again.")) == .leave, "a refusal: not kept")
check(P.savedChange(.remember, answer: answer("locked")) == .leave, "a lock's outcome: not kept")
check(P.savedChange(.remember, answer: answer("notLocked")) == .leave, "notLocked: not kept")
check(P.savedChange(.remember, answer: answer("somethingNew")) == .leave, "an outcome this build does not know: not kept")
check(P.savedChange(.saved, answer: answer("stillLocked")) == .forget, "the kept password left the Mac locked: removed")
check(P.savedChange(.saved, answer: answer("stillLocked", "Check it.")) == .forget, "with words or without")
check(P.savedChange(.saved, answer: answer("unlocked")) == .leave, "the kept password unlocked the Mac: kept as it is")
check(P.savedChange(.saved, answer: answer("unlocked", "Mac mini was already unlocked.")) == .leave, "already unlocked: kept")
check(P.savedChange(.saved, answer: answer("refused", "Wait a few seconds, then try again.")) == .leave,
      "a refusal typed nothing: kept")
check(P.savedChange(.saved, answer: answer("somethingNew", "Later words.")) == .leave, "an outcome this build does not know: kept")

// MARK: The card's line for the last unlock

check(LockScreenAttempt(action: "unlock", token: 1, phase: .sending).fromSaved == false, "an attempt is typed unless it says otherwise")
check(P.unlockLine(attempt(.answered(outcome: "stillLocked", message: nil), fromSaved: true), ask: password, mac: mac)
      == "The saved password didn’t unlock Mac mini, so it was removed. Type the password.",
      "the kept password's failure says it was removed")
check(P.unlockLine(attempt(.answered(outcome: "stillLocked", message: nil)), ask: password, mac: mac)
      == "Mac mini is still locked. Check the password and try again.", "a typed password's says to check it")
check(P.unlockLine(attempt(.answered(outcome: "stillLocked", message: nil)), ask: pin, mac: mac)
      == "Mac mini is still locked. Check the PIN and try again.", "a typed PIN's names the PIN")
check(P.unlockLine(attempt(.answered(outcome: "unlocked", message: nil), fromSaved: true), ask: password, mac: mac) == nil,
      "unlocked: the card goes, nothing to say")
check(P.unlockLine(attempt(.answered(outcome: "refused", message: "Wait a few seconds, then try again."), fromSaved: true),
                   ask: password, mac: mac) == "Wait a few seconds, then try again.", "a refusal is the Mac's words, whatever the source")
check(P.unlockLine(attempt(.answered(outcome: "somethingNew", message: nil), fromSaved: true), ask: password, mac: mac)
      == "Mac mini didn’t unlock. Try again, or unlock it at the Mac.", "an outcome this build does not know, without words")
check(P.unlockLine(attempt(.unanswered, fromSaved: true), ask: password, mac: mac) == "Mac mini didn’t answer. Try again.",
      "no answer")
check(P.unlockLine(attempt(.sending, fromSaved: true), ask: password, mac: mac) == nil, "waiting: the button says so")
check(P.unlockLine(attempt(.answered(outcome: "stillLocked", message: nil), fromSaved: true, action: "lock"), ask: password, mac: mac) == nil,
      "a lock's attempt has no unlock line")

// MARK: When a request may go (the Mac judges again)

check(P.unlockBlock(connected: false, unlock: true, locked: password, attempt: nil, secret: "s") == .notConnected, "not connected")
check(P.unlockBlock(connected: true, unlock: nil, locked: password, attempt: nil, secret: "s") == .notAllowed, "not allowed")
check(P.unlockBlock(connected: false, unlock: nil, locked: nil, attempt: nil, secret: "") == .notConnected, "the session first")
check(P.unlockBlock(connected: true, unlock: true, locked: nil, attempt: nil, secret: "s") == .notLocked, "not locked")
check(P.unlockBlock(connected: true, unlock: true, locked: password, attempt: attempt(.sending), secret: "s") == .busy, "one at a time")
check(P.unlockBlock(connected: true, unlock: true, locked: password, attempt: attempt(.unanswered), secret: "s") == nil,
      "an attempt that settled doesn't block the next")
check(P.unlockBlock(connected: true, unlock: true, locked: password, attempt: nil, secret: "") == .cannotType, "an empty secret")
check(P.unlockBlock(connected: true, unlock: true, locked: password, attempt: nil, secret: "a\nb") == .cannotType, "a Return inside it")
check(P.unlockBlock(connected: true, unlock: true, locked: pin, attempt: nil, secret: "123456") == nil, "a PIN goes as typed")
check(P.lockBlock(connected: true, hostLockScreen: 1, locked: nil, attempt: nil) == nil, "a lock to a Mac that takes it")
check(P.lockBlock(connected: true, hostLockScreen: nil, locked: nil, attempt: nil) == .notAllowed, "none to a Mac before kind 44")
check(P.lockBlock(connected: true, hostLockScreen: 1, locked: password, attempt: nil) == .alreadyLocked, "none while locked")

// MARK: An attempt on record

let sent = attempt(.sending, fromSaved: true)
let settled = P.settled(sent, by: answer("stillLocked"))
check(settled?.phase == .answered(outcome: "stillLocked", message: nil), "the answer settles it")
check(settled?.fromSaved == true, "and keeps where its password came from")
check(P.settled(sent, by: answer("unlocked", token: 4)) == nil, "another request's answer is ignored")
check(P.settled(settled, by: answer("unlocked")) == nil, "a second answer is ignored")
check(P.expired(sent, token: 3)?.phase == .unanswered && P.expired(sent, token: 3)?.fromSaved == true, "the wait ran out")
check(P.expired(settled, token: 3) == nil, "an answered attempt does not expire")
check(P.answerWait(action: "lock") == 7, "a lock waits its 2 s and 5 for the link")
check(abs(P.answerWait(action: "unlock") - 15.22) < 1e-9, "an unlock: 2 + 0.3 + 128 × 0.015 + 6 + 5")

// MARK: Words

check(P.Biometry.faceID.name == "Face ID" && P.Biometry.touchID.name == "Touch ID" && P.Biometry.opticID.name == "Optic ID",
      "the biometry's names")
check(P.Biometry(rawValue: "faceID") == .faceID && P.Biometry(rawValue: "touchID") == .touchID
      && P.Biometry(rawValue: "opticID") == .opticID && P.Biometry(rawValue: "none") == nil, "-SillBiometry's words")
check(P.unlockWithSaved(.faceID) == "Unlock with Face ID" && P.unlockWithSaved(.touchID) == "Unlock with Touch ID", "the button")
check(P.rememberTitle(.faceID) == "Use Face ID next time" && P.rememberTitle(.opticID) == "Use Optic ID next time", "the switch")
check(P.rememberFootnote(device: "iPhone") == "If it unlocks the Mac, the password is kept on this iPhone only, never synced.",
      "under the switch")
check(P.savedReason(mac: mac) == "Unlock Mac mini", "the Face ID sheet's reason")
check(P.savedFailed(.touchID) == "Touch ID didn’t work. Try again, or type the password.", "Face ID gave nothing")
check(P.savedGone(.faceID) == "The saved password is gone, as it is when Face ID changes on this device. Type the password.",
      "the keychain has none")
check(P.forgetSaved == "Forget Saved Password", "the panel's row")
check(P.savedFootnote(mac: mac, biometry: .touchID, device: "iPad") == "Mac mini’s password is kept on this iPad for Touch ID.",
      "the panel's footnote")
check(P.savedFootnote(mac: mac, biometry: nil, device: "iPhone") == "Mac mini’s password is kept on this iPhone for Face ID.",
      "with no biometry now, Face ID")

print(failures == 0 ? "ok: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
