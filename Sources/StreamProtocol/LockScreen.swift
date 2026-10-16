import Foundation

/// Kind 44, both ways: locking and unlocking the Mac from a device (docs/lock-screen-plan.md).
///
/// Device → host: `LockScreenRequest`. "lock" goes only to a host whose window list says
/// `lockScreen` 1 or more, and "unlock" only on a connection whose window list says `unlock` true
/// (`UnlockPolicy.advertised`: the Mac's switches allow that connection's route, at a TLS door).
/// Host → device: `LockScreenOutcome`, one for each request, with its token. An older host or
/// device maps the kind to `.unknown` and skips it.
///
/// The secret is the Mac's password, or a smart card's PIN when the lock screen asks for one
/// (`WindowList.locked` "pin"). Neither side logs it, its length or the keys that spell it, and the
/// host types it only while this user's console is locked, reading the lock state again before
/// each character.
///
/// Every action, outcome and ask is a String with a `known` set, never an enum an older peer
/// decodes: a later value reaches an older peer as a string it does not know.
public struct LockScreenRequest: Codable, Equatable {
    /// `LockScreenAction.lock` or `.unlock`. A host answers any other action "refused".
    public var action: String
    /// The password or PIN, with "unlock" only (`LockScreenSecret.isTypeable`).
    public var secret: String?
    /// The device's number for this request, which the outcome repeats.
    public var token: Int

    public init(action: String, secret: String? = nil, token: Int) {
        self.action = action
        self.secret = secret
        self.token = token
    }

    /// The generation `WindowList.lockScreen` says: 1 is "lock" and "unlock" as this file has them.
    public static let generation = 1
}

public enum LockScreenAction {
    public static let lock = "lock"
    public static let unlock = "unlock"
    public static let known: Set<String> = [lock, unlock]
}

public struct LockScreenOutcome: Codable, Equatable {
    /// The request's token.
    public var token: Int
    /// One of `known`. A device shows an outcome it does not know by its `message`.
    public var outcome: String
    /// Words for the device to show as they are (a refusal's reason). Optional.
    public var message: String?

    public init(token: Int, outcome: String, message: String? = nil) {
        self.token = token
        self.outcome = outcome
        self.message = message
    }

    /// The secret was typed and the Mac unlocked, or the Mac was found already unlocked.
    public static let unlocked = "unlocked"
    /// The secret was typed and the Mac is still locked `UnlockTiming.verdictWait` after Return: a
    /// wrong password or PIN, or the lock screen did not take it. The host cannot tell which.
    public static let stillLocked = "stillLocked"
    /// Nothing was typed or posted. `message` says why.
    public static let refused = "refused"
    /// The lock request locked the Mac, or found it locked.
    public static let locked = "locked"
    /// The lock request was posted, but the Mac did not lock within `UnlockTiming.lockWait`.
    public static let notLocked = "notLocked"
    public static let known: Set<String> = [unlocked, stillLocked, refused, locked, notLocked]
}

/// What the lock screen asks for, as `WindowList.locked` says it.
public enum LockScreenAsk {
    public static let password = "password"
    /// A smart card paired for this user's login is in: the field takes its PIN, and each wrong one
    /// uses one of the card's tries (three block a YubiKey's PIV applet).
    public static let pin = "pin"
    public static let known: Set<String> = [password, pin]

    /// The field's label: "Password", "PIN", or "Password or PIN" for a value this build does not
    /// know.
    public static func label(_ ask: String) -> String {
        switch ask {
        case password: return "Password"
        case pin: return "PIN"
        default: return "Password or PIN"
        }
    }

    /// The same inside a sentence: "password", "PIN", or "password or PIN".
    public static func word(_ ask: String) -> String {
        switch ask {
        case password: return "password"
        case pin: return "PIN"
        default: return "password or PIN"
        }
    }
}

/// What a host types: 1 to `maxCharacters` characters, none of them a control character (a "\n"
/// or "\r" would press Return part way through, a "\u{8}" would delete).
public enum LockScreenSecret {
    public static let maxCharacters = 128

    public static func isTypeable(_ secret: String) -> Bool {
        !secret.isEmpty && secret.count <= maxCharacters
            && !secret.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }
}

/// The host's waits, in seconds. `settle` and `keyGap` are guesses until the plan's P0a.
public enum UnlockTiming {
    /// How long the host waits for the main display to wake after declaring activity.
    public static let wakeWait: Double = 2
    /// After the display is awake, before the first key, for the lock screen to draw its field.
    public static let settle: Double = 0.3
    /// Between two keys.
    public static let keyGap: Double = 0.015
    /// How long after Return the host waits for the Mac to unlock: loginwindow's own 5 s wait for
    /// user activity, plus a margin.
    public static let verdictWait: Double = 6
    /// After an attempt that left the Mac locked, the next one waits this long.
    public static let afterFailure: Double = 5
    /// How long after posting the lock shortcut the host waits for the Mac to lock.
    public static let lockWait: Double = 2
}

/// The Mac's switches for unlocking from devices (Settings › General): "Unlock from devices", and
/// "Also from devices away from home", which counts only while the first is on. Both off until the
/// Mac's user turns them on, and no device can set either. Shaped as ClipboardPolicy. A connection
/// the Mac counts as away (AwayPolicy.isAway) may unlock only with both on, and only a connection
/// that came through a TLS door ever may: the CLI's plain door never advertises `unlock`.
///
/// The switches decide the unlock card's attempts (kind 44) only. Typing into the lock screen by
/// hand, as any key input, stays open to every paired device whatever they say (the plan's decision
/// 2, Ivor, 2026-10-16: "Keep today's typing").
public struct UnlockPolicy: Equatable {
    public var allow: Bool
    public var allowAway: Bool

    public init(allow: Bool = false, allowAway: Bool = false) {
        self.allow = allow
        self.allowAway = allowAway
    }

    /// Whether a connection home (`away` false) or away may unlock this Mac, door aside.
    public func allows(away: Bool) -> Bool {
        allow && (allowAway || !away)
    }

    /// What the window list says to that connection (`WindowList.unlock`): true, or nil.
    public func advertised(away: Bool, tls: Bool) -> Bool? {
        tls && allows(away: away) ? true : nil
    }
}

/// The host's record of unlock attempts, across every device: one at a time, none within
/// `UnlockTiming.afterFailure` of a failure, and with a PIN lock screen none after
/// `pinFailureStop` failures in a row, so the card keeps a try for the Mac's own keyboard. It
/// starts over whenever the Mac unlocks, by any means.
public struct UnlockAttempts: Equatable {
    public private(set) var inFlight = false
    public private(set) var failuresInARow = 0
    /// When the last attempt that left the Mac locked ended, in seconds.
    public private(set) var lastFailure: Double?

    public static let pinFailureStop = 2

    public init() {}

    /// Why an attempt at `now` would be refused, or nil to go on.
    public func refusal(now: Double, ask: String, mac: String) -> String? {
        if inFlight { return "\(mac) is already being unlocked." }
        if ask == LockScreenAsk.pin, failuresInARow >= Self.pinFailureStop {
            return "Two wrong PINs in a row. Unlock \(mac) at the Mac: a third would block the smart card."
        }
        if let lastFailure, now - lastFailure < UnlockTiming.afterFailure {
            return "Wait a few seconds, then try again."
        }
        return nil
    }

    /// An attempt starts typing.
    public mutating func began() {
        inFlight = true
    }

    /// The attempt that began ended with `outcome` at `now`: "stillLocked" counts a failure,
    /// "unlocked" starts over, anything else only ends it.
    public mutating func ended(outcome: String, now: Double) {
        inFlight = false
        switch outcome {
        case LockScreenOutcome.stillLocked:
            failuresInARow += 1
            lastFailure = now
        case LockScreenOutcome.unlocked:
            failuresInARow = 0
            lastFailure = nil
        default:
            break
        }
    }

    /// The Mac unlocked, by a device or at the Mac: the count starts over.
    public mutating func macUnlocked() {
        failuresInARow = 0
        lastFailure = nil
    }
}

/// What the host does with an unlock request.
public enum UnlockVerdict: Equatable {
    /// Type it.
    case go
    /// Answer "unlocked" without typing: the Mac is not locked.
    case alreadyUnlocked
    /// Answer "refused" with these words, typing nothing.
    case refuse(String)
}

public enum UnlockJudge {
    /// The plan's order: the door, the switches for this route, the console, the lock state, the
    /// secret, the attempt limit. `onConsole` is false while another user's session or the login
    /// window has the console; `locked` is this user's lock screen being up.
    public static func verdict(tls: Bool, policy: UnlockPolicy, away: Bool, onConsole: Bool, locked: Bool,
                               secret: String?, ask: String, attempts: UnlockAttempts, now: Double,
                               mac: String) -> UnlockVerdict {
        guard tls else { return .refuse("This connection can’t unlock \(mac).") }
        guard policy.allow else {
            return .refuse("Unlocking from devices is off on \(mac). It can be turned on in Sill on the Mac, in Settings › General.")
        }
        guard policy.allows(away: away) else {
            return .refuse("Unlocking from devices away from home is off on \(mac).")
        }
        guard onConsole else { return .refuse("\(mac) is showing another user’s session.") }
        guard locked else { return .alreadyUnlocked }
        guard let secret, LockScreenSecret.isTypeable(secret) else {
            return .refuse("Sill can’t type that \(LockScreenAsk.word(ask)).")
        }
        if let why = attempts.refusal(now: now, ask: ask, mac: mac) { return .refuse(why) }
        return .go
    }
}

/// Lock again (the plan's decision 5): only after Sill's attempt unlocked the Mac, `grace` after the
/// device that unlocked it left, and only while that device is not back, the Mac is still unlocked,
/// and neither the Mac's own keyboard and mouse nor another device's input was used since it left.
/// It puts the Mac back the way the device found it; it is not a curtain.
public enum LockAgain {
    public static let grace: Double = 30

    public static func locks(enabled: Bool, unlockedBySill: Bool, leftAt: Double, now: Double,
                             unlockerBack: Bool, locked: Bool, usedSince: Bool) -> Bool {
        enabled && unlockedBySill && !unlockerBack && !locked && !usedSince && now - leftAt >= grace
    }
}

/// The Apple menu's Lock Screen shortcut: ⌃⌘Q, unless App Shortcuts gives "Lock Screen" another
/// one (NSUserKeyEquivalents in the global domain, written "@^q": @ ⌘, ^ ⌃, ~ ⌥, $ ⇧, then the
/// key).
public struct LockShortcut: Equatable {
    /// The key, lowercased.
    public var key: Character
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool

    public init(key: Character, command: Bool, control: Bool, option: Bool, shift: Bool) {
        self.key = key
        self.command = command
        self.control = control
        self.option = option
        self.shift = shift
    }

    public static let standard = LockShortcut(key: "q", command: true, control: true, option: false, shift: false)

    /// The shortcut from the user's key equivalent for "Lock Screen": `standard` when there is none,
    /// nil when it can't be read or has no modifier (the user removed it, or a key alone, which
    /// Sill does not post as a lock).
    public static func from(userKeyEquivalent: String?) -> LockShortcut? {
        guard let equivalent = userKeyEquivalent else { return standard }
        var shortcut = LockShortcut(key: " ", command: false, control: false, option: false, shift: false)
        var rest = Substring(equivalent)
        while let first = rest.first, "@^~$".contains(first) {
            switch first {
            case "@": shortcut.command = true
            case "^": shortcut.control = true
            case "~": shortcut.option = true
            default: shortcut.shift = true
            }
            rest = rest.dropFirst()
        }
        guard rest.count == 1, let key = rest.first, !key.isWhitespace else { return nil }
        guard shortcut.command || shortcut.control || shortcut.option else { return nil }
        shortcut.key = Character(key.lowercased())
        return shortcut
    }
}
