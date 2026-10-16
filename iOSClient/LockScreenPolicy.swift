import Foundation
import StreamProtocol

// The device's rules for locking and unlocking the Mac (kind 44, StreamProtocol/LockScreen.swift;
// docs/lock-screen-plan.md, P2): when a request may go, what became of the last one, and the words the
// locked card and the Settings panel's row say for it. Pure: Foundation and StreamProtocol only, so a
// check can compile it with swiftc beside them (as AwayCopy is).
//
// Nothing here ever holds the password or PIN: a request's secret goes straight from the card's field
// (or, after Face ID, from the keychain: SavedUnlock) to the wire, and an attempt on record carries its
// action, its token, where its secret came from and the Mac's answer only.

/// The last request this device sent and what became of it. One at a time: the card and the panel's
/// row are disabled while one is `sending`.
struct LockScreenAttempt: Equatable {
    enum Phase: Equatable {
        case sending
        /// The Mac's answer. `outcome` is one of `LockScreenOutcome.known`, or a word this build does
        /// not know, which is shown by its `message`.
        case answered(outcome: String, message: String?)
        /// Nothing came within `LockScreenPolicy.answerWait`. An answer that comes late still settles it.
        case unanswered
    }

    /// `LockScreenAction.lock` or `.unlock`.
    var action: String
    /// The request's token, which the Mac's answer repeats.
    var token: Int
    var phase: Phase
    /// The password came from this device's keychain after Face ID (SavedUnlock), not from the field.
    var fromSaved = false

    var sending: Bool { phase == .sending }
}

enum LockScreenPolicy {
    /// Why a request cannot go now. Each is a state the screen is already leaving or showing words
    /// for, except `cannotType`, which the card says in its own line.
    enum Block: Equatable {
        case notConnected
        /// The window list does not say this connection may unlock (`unlock`), or the Mac does not take
        /// "lock" (`lockScreen`).
        case notAllowed
        /// "unlock" while the Mac is not locked.
        case notLocked
        /// "lock" while the Mac is locked.
        case alreadyLocked
        /// A request is still waiting for its answer.
        case busy
        /// The secret is empty, too long or has a control character (`LockScreenSecret.isTypeable`).
        case cannotType
    }

    /// The window list says this Mac takes "lock" (`lockScreen`).
    static func canLock(hostLockScreen: Int?) -> Bool {
        (hostLockScreen ?? 0) >= LockScreenRequest.generation
    }

    /// The order the plan gives: the session, what the list allows, the lock state, one request at a
    /// time, then the secret.
    static func unlockBlock(connected: Bool, unlock: Bool?, locked: String?, attempt: LockScreenAttempt?,
                            secret: String) -> Block? {
        guard connected else { return .notConnected }
        guard unlock == true else { return .notAllowed }
        guard locked != nil else { return .notLocked }
        guard attempt?.sending != true else { return .busy }
        guard LockScreenSecret.isTypeable(secret) else { return .cannotType }
        return nil
    }

    static func lockBlock(connected: Bool, hostLockScreen: Int?, locked: String?, attempt: LockScreenAttempt?) -> Block? {
        guard connected else { return .notConnected }
        guard canLock(hostLockScreen: hostLockScreen) else { return .notAllowed }
        guard locked == nil else { return .alreadyLocked }
        guard attempt?.sending != true else { return .busy }
        return nil
    }

    /// How long a request waits for its answer: what the Mac itself may take (`UnlockTiming`: the
    /// display's wake, the lock screen's settle, every key of the longest secret, then the verdict;
    /// for "lock", its own wait) and five seconds for the link.
    static func answerWait(action: String) -> Double {
        let margin = 5.0
        if action == LockScreenAction.lock { return UnlockTiming.lockWait + margin }
        return UnlockTiming.wakeWait + UnlockTiming.settle + Double(LockScreenSecret.maxCharacters) * UnlockTiming.keyGap
            + UnlockTiming.verdictWait + margin
    }

    /// The attempt once the Mac has answered it: nil when the answer is not to the request on record
    /// (an earlier connection's, an earlier request's, or a second answer to one that has settled), which
    /// is ignored.
    static func settled(_ attempt: LockScreenAttempt?, by answer: LockScreenOutcome) -> LockScreenAttempt? {
        guard var attempt, attempt.token == answer.token else { return nil }
        if case .answered = attempt.phase { return nil }
        attempt.phase = .answered(outcome: answer.outcome, message: answer.message)
        return attempt
    }

    /// The attempt when the wait for request `token` ran out: nil if it has settled or been replaced.
    static func expired(_ attempt: LockScreenAttempt?, token: Int) -> LockScreenAttempt? {
        guard var attempt, attempt.token == token, attempt.phase == .sending else { return nil }
        attempt.phase = .unanswered
        return attempt
    }

    // MARK: Words

    /// What the lock screen asks for, in a sentence: "password", "PIN" or "password or PIN". The Mac's
    /// refusals use the same word (`LockScreenAsk.word`), so the two cannot drift apart.
    static func askWord(_ ask: String) -> String { LockScreenAsk.word(ask) }

    /// The card's title.
    static func title(mac: String) -> String { "\(mac) is locked" }

    /// What the card says where it has no field: this connection may not unlock.
    static func unlockAtTheMac(mac: String) -> String {
        "Unlock \(mac) at the Mac, or turn on Unlock from devices in Sill there."
    }

    /// Under a PIN field: each wrong PIN counts against the smart card, three block it.
    static let pinWarning = "A wrong PIN uses one of the smart card’s tries."

    /// The card's line when the secret cannot be typed: nothing went to the Mac.
    static func cannotType(ask: String) -> String { "Sill can’t type that \(askWord(ask))." }

    /// The card's line under the field for the last unlock request, or nil when there is nothing to
    /// say: none sent, one waiting (the button says so), or "unlocked" (the card goes when the Mac's
    /// list says the Mac is). A refusal, or an outcome this build does not know, is the Mac's own
    /// `message` as it is.
    static func unlockLine(_ attempt: LockScreenAttempt?, ask: String, mac: String) -> String? {
        guard let attempt, attempt.action == LockScreenAction.unlock else { return nil }
        switch attempt.phase {
        case .sending:
            return nil
        case .unanswered:
            return didNotAnswer(mac)
        case .answered(let outcome, let message):
            switch outcome {
            case LockScreenOutcome.unlocked:
                return nil
            case LockScreenOutcome.stillLocked:
                if attempt.fromSaved { return savedForgotten(mac: mac) }
                return "\(mac) is still locked. Check the \(askWord(ask)) and try again."
            default:
                return words(message) ?? "\(mac) didn’t unlock. Try again, or unlock it at the Mac."
            }
        }
    }

    /// The panel's line under the Lock row for the last lock request, or nil: "locked" has nothing to
    /// say (the card comes up), "notLocked" and "refused" do.
    static func lockLine(_ attempt: LockScreenAttempt?, mac: String) -> String? {
        guard let attempt, attempt.action == LockScreenAction.lock else { return nil }
        switch attempt.phase {
        case .sending:
            return nil
        case .unanswered:
            return didNotAnswer(mac)
        case .answered(let outcome, let message):
            switch outcome {
            case LockScreenOutcome.locked:
                return nil
            case LockScreenOutcome.notLocked:
                return words(message) ?? "\(mac) didn’t lock. Try again, or lock it at the Mac."
            default:
                return words(message) ?? "\(mac) wouldn’t lock."
            }
        }
    }

    /// The panel's row: "Lock ‹Mac›" while unlocked, "Locking ‹Mac›…" while that request waits,
    /// "Unlock ‹Mac›…" while locked, which brings the card back.
    static func rowTitle(mac: String, locked: Bool, locking: Bool) -> String {
        if locked { return "Unlock \(mac)…" }
        return locking ? "Locking \(mac)…" : "Lock \(mac)"
    }

    /// Under the panel's row while the Mac is unlocked: what to expect after the lock.
    static func lockFootnote(unlock: Bool?) -> String {
        unlock == true ? "You can unlock it from here or at the Mac." : "You’ll need to unlock it at the Mac."
    }

    /// Under the panel's row while the Mac is locked: what the row does, or, where this connection has
    /// no field to unlock with, what to do instead.
    static func unlockRowFootnote(mac: String, unlock: Bool?) -> String {
        unlock == true ? "Shows the card that unlocks \(mac) again." : unlockAtTheMac(mac: mac)
    }

    private static func didNotAnswer(_ mac: String) -> String { "\(mac) didn’t answer. Try again." }

    // MARK: The password kept for Face ID (decision 3, Ivor, 2026-10-16)

    /// The device's biometry as LocalAuthentication names it (SavedUnlock.biometry); none where the
    /// device has none, none is enrolled or it is locked out, and then nothing below is offered.
    enum Biometry: String, Equatable {
        case faceID, touchID, opticID

        var name: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .opticID: return "Optic ID"
            }
        }
    }

    /// What the card offers beside its field.
    enum SavedOffer: Equatable {
        case nothing
        /// "Use Face ID next time": a typed password is kept if the Mac unlocks with it.
        case remember
        /// "Unlock with Face ID": the kept password goes, after Face ID.
        case unlockWithSaved
    }

    /// Only where the card has a field (`unlock`), only for a password (a PIN is never kept: a stale one
    /// would use the smart card's tries by itself), only for a Mac this connection is pinned to by its
    /// key (`pinned`: never a plain or open door, never a Mac taken by its name or its own list's word),
    /// and only on a device with biometry.
    static func savedOffer(unlock: Bool?, ask: String?, pinned: Bool, biometry: Biometry?, saved: Bool) -> SavedOffer {
        guard unlock == true, ask == LockScreenAsk.password, pinned, biometry != nil else { return .nothing }
        return saved ? .unlockWithSaved : .remember
    }

    /// How an unlock request used the kept password.
    enum SavedUse: Equatable {
        /// Typed, with "Use Face ID next time" on.
        case remember
        /// The kept password, after Face ID.
        case saved
    }

    /// What the Mac's answer does to the kept password.
    enum SavedChange: Equatable { case save, forget, leave }

    /// "unlocked" keeps a password typed to be remembered, but only without words: the Mac says
    /// "unlocked" with words when it was unlocked already and typed nothing. Without words it is the
    /// Mac's Return that unlocked it, or someone at the Mac who unlocked it while the attempt typed,
    /// which this device can't tell apart; a password kept that way and wrong is forgotten at its first
    /// use. "stillLocked" forgets the kept password that was sent: it no longer unlocks the Mac (changed
    /// there). Anything else leaves the keychain as it is: a refusal typed nothing, and an outcome this
    /// build does not know proves nothing.
    static func savedChange(_ use: SavedUse, answer: LockScreenOutcome) -> SavedChange {
        switch use {
        case .remember:
            return answer.outcome == LockScreenOutcome.unlocked && answer.message == nil ? .save : .leave
        case .saved:
            return answer.outcome == LockScreenOutcome.stillLocked ? .forget : .leave
        }
    }

    /// The card's button.
    static func unlockWithSaved(_ biometry: Biometry) -> String { "Unlock with \(biometry.name)" }

    /// The card's switch under the field, and what it says under it.
    static func rememberTitle(_ biometry: Biometry) -> String { "Use \(biometry.name) next time" }
    static func rememberFootnote(device: String) -> String {
        "If it unlocks the Mac, the password is kept on this \(device) only, never synced."
    }

    /// What the system's Face ID sheet says it is for.
    static func savedReason(mac: String) -> String { "Unlock \(mac)" }

    /// The card's line when the kept password left the Mac locked: it was removed.
    static func savedForgotten(mac: String) -> String {
        "The saved password didn’t unlock \(mac), so it was removed. Type the password."
    }

    /// The card's line when Face ID gave nothing: it didn't match, or the system refused.
    static func savedFailed(_ biometry: Biometry) -> String { "\(biometry.name) didn’t work. Try again, or type the password." }

    /// The card's line when the keychain no longer has the password.
    static func savedGone(_ biometry: Biometry) -> String {
        "The saved password is gone, as it is when \(biometry.name) changes on this device. Type the password."
    }

    /// The Settings panel's row while a password is kept for this Mac, and its footnote.
    static let forgetSaved = "Forget Saved Password"
    static func savedFootnote(mac: String, biometry: Biometry?, device: String) -> String {
        "\(mac)’s password is kept on this \(device) for \(biometry?.name ?? "Face ID")."
    }

    /// The Mac's words, trimmed and kept to a few lines; nil for none.
    private static func words(_ message: String?) -> String? {
        guard let text = message?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(300))
    }
}
