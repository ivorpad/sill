import Foundation
import CoreGraphics
import QuartzCore
import StreamProtocol

extension HostConfig {
    /// The unlock switches as one rule (LockScreen.swift). Here, not in HostConfig.swift, which the
    /// away-quality check compiles without LockScreen.swift (as `clipboardPolicy` sits in ClipboardSync.swift).
    package var unlockPolicy: UnlockPolicy {
        UnlockPolicy(allow: unlockFromDevices, allowAway: unlockAway)
    }
}

/// Types a device's password or PIN into the Mac's lock screen, and locks the Mac (kind 44,
/// docs/lock-screen-plan.md). The caller has judged the request already (`UnlockJudge`: the door, the
/// switches, the console, the secret, the attempt limit) and sends the answer; this is the sequence.
///
/// An unlock attempt: declare user activity at once (`UserActivity`, not throttled) and wait for the
/// main display to wake and the lock screen to settle, clear the field with ⌘A and Delete, then type
/// each character as a Unicode key event (`TextTyping`, as InputInjector.type does), then Return, then wait
/// for the Mac to unlock. Before each key, and before Return, the console is read afresh from the session
/// dictionary (`SessionLock.read`, never the cache) and the attempt stops at the first read that says
/// the lock screen is not up, so the rest of a password never lands in an app. The last read comes a few
/// milliseconds before its key is posted: someone at the Mac who unlocks it with Touch ID in that gap
/// can get one character in their app, and ⌘A and Delete are read too for the same reason.
///
/// The secret is never printed or logged, nor its length, nor the keys that spell it, on any host. It is
/// only walked character by character here. A real attempt posts its events through `postQuietly`, which
/// counts nothing (no `in.text`, no `in.key`: the only stat of an attempt is `in.userActive` once, and the
/// outcome's `lock.*`). A dry run (a --synthetic host) posts nothing and counts the attempt once, `in.dry`
/// 1 whatever the secret's length, so no stats line shows it, and the attempt ends the way the test hooks
/// say (UnlockTestHooks).
///
/// A lock request posts the Lock Screen shortcut, ⌃⌘Q unless App Shortcuts remaps it, through
/// InputInjector.chord.
@MainActor
final class ShieldTyping {
    /// The attempts so far, across every device (UnlockAttempts). The coordinator judges with it.
    private(set) var attempts = UnlockAttempts()
    private var activity = UserActivity()
    private var locking = false
    /// Sill.app's local notification: a device's attempt unlocked this Mac (its name, how it came, when).
    /// The CLI sets none and only logs.
    var onUnlockedByDevice: (@MainActor (_ device: String, _ route: String, _ at: Date) -> Void)?

    /// What an attempt ended with, and whether Sill's own Return unlocked the Mac, which is what lock
    /// again takes over (a Mac someone else unlocked while the attempt was typing is theirs).
    struct Attempt {
        var outcome: LockScreenOutcome
        var unlockedBySill: Bool
    }

    /// An unlock attempt is typing now: key and text input from every device is withheld meanwhile
    /// (StreamCoordinator.takesKeyInput), so a second device cannot add to the typed secret.
    var attemptInFlight: Bool { attempts.inFlight }

    /// The Mac unlocked, by a device or at the Mac: the failure count starts over.
    func macUnlocked() { attempts.macUnlocked() }

    // MARK: Unlock

    func unlock(secret: String, ask: String, token: Int, from device: KeyStrokes.Device, mac: String,
                injector: InputInjector, lock: SessionLock, testHost: Bool) async -> Attempt {
        attempts.began()
        let attempt = await typeSecret(secret, ask: ask, token: token, from: device, mac: mac, injector: injector,
                                       lock: lock, testHost: testHost)
        attempts.ended(outcome: attempt.outcome.outcome, now: CACurrentMediaTime())
        return attempt
    }

    private func typeSecret(_ secret: String, ask: String, token: Int, from device: KeyStrokes.Device, mac: String,
                            injector: InputInjector, lock: SessionLock, testHost: Bool) async -> Attempt {
        let dry = injector.dryRun
        func end(_ outcome: String, _ message: String? = nil, bySill: Bool = false) -> Attempt {
            Attempt(outcome: LockScreenOutcome(token: token, outcome: outcome, message: message), unlockedBySill: bySill)
        }
        /// A fresh read: nil while this user's lock screen is up, else the attempt's end.
        func stopped() -> Attempt? {
            switch lock.read() {
            case .locked: return nil
            case .unlocked: return end(LockScreenOutcome.unlocked)
            case .elsewhere: return end(LockScreenOutcome.refused, "\(mac) is showing another user’s session.")
            }
        }
        /// A real attempt posts each event; a dry one posts and counts none (it counts once, below).
        func post(_ events: [CGEvent]) { if !dry { for event in events { _ = injector.postQuietly(event) } } }
        func tap(_ virtualKey: CGKeyCode) {
            if !dry { TextTyping.tap(virtualKey: virtualKey, source: injector.source) { _ = injector.postQuietly($0) } }
        }
        func pause(_ seconds: Double) async { if !dry { try? await Task.sleep(for: .seconds(seconds)) } }

        if dry {
            Stats.shared.bump("in.dry")     // the attempt, once: never an event for each character
            if injector.testLog { print("Test input: an unlock attempt (not posted: a test host)") }
        }
        if !dry {
            activity.declare(force: true)
            await waitForDisplay()
            await pause(UnlockTiming.settle)
        }
        // Every key this device still holds goes up first, as when it leaves (a modifier would taint the
        // characters, a key whose up was lost would repeat into them).
        injector.releaseKeys(of: device)

        // Clear the field: ⌘A, then Delete. The up of ⌘A carries the flags the table held before it.
        if let ended = stopped() { return ended }
        let before = dry ? CGEventFlags() : CGEventSource.flagsState(.hidSystemState)
        post(TextTyping.shortcut(virtualKey: 0, flags: .maskCommand, before: before, source: injector.source))
        await pause(UnlockTiming.keyGap)
        if let ended = stopped() { return ended }
        tap(51)             // Delete
        await pause(UnlockTiming.keyGap)

        for character in secret {
            if let ended = stopped() { return ended }
            guard let events = TextTyping.character(character, source: injector.source) else {
                return end(LockScreenOutcome.refused, "Sill can’t type that \(LockScreenAsk.word(ask)).")
            }
            post([events.down, events.up])
            await pause(UnlockTiming.keyGap)
        }
        if let ended = stopped() { return ended }
        tap(36)             // Return

        if dry {
            let environment = ProcessInfo.processInfo.environment
            // TEST ONLY: the time a real attempt takes, so a test can reach it while it is in flight.
            if let hold = UnlockTestHooks.attemptSeconds(testHost: testHost, environment: environment) {
                try? await Task.sleep(for: .seconds(hold))
            }
            let result = UnlockTestHooks.outcome(testHost: testHost, environment: environment)
            if result == LockScreenOutcome.unlocked { lock.simulate(locked: false, testHost: testHost) }
            return end(result, bySill: result == LockScreenOutcome.unlocked)
        }
        let deadline = CACurrentMediaTime() + UnlockTiming.verdictWait
        while true {
            switch lock.read() {
            case .unlocked: return end(LockScreenOutcome.unlocked, bySill: true)
            case .elsewhere: return end(LockScreenOutcome.refused, "\(mac) is showing another user’s session.")
            case .locked: break
            }
            if CACurrentMediaTime() >= deadline || Task.isCancelled { return end(LockScreenOutcome.stillLocked) }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// After declaring user activity: up to `UnlockTiming.wakeWait` for the main display to be awake.
    private func waitForDisplay() async {
        let deadline = CACurrentMediaTime() + UnlockTiming.wakeWait
        while CGDisplayIsAsleep(CGMainDisplayID()) != 0, CACurrentMediaTime() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: Lock

    /// Locks the Mac: nothing is posted when it is locked already. Otherwise the Lock Screen shortcut
    /// (`LockShortcut`) is posted through the chord path, and the Mac has `UnlockTiming.lockWait` to
    /// lock. A dry run posts nothing real (the chord's two events are counted, `in.dry`) and ends locked,
    /// flipping a test host's simulated state.
    func lock(token: Int, mac: String, injector: InputInjector, lock: SessionLock, testHost: Bool) async -> LockScreenOutcome {
        func end(_ outcome: String, _ message: String? = nil) -> LockScreenOutcome {
            LockScreenOutcome(token: token, outcome: outcome, message: message)
        }
        switch lock.read() {
        case .locked: return end(LockScreenOutcome.locked)
        case .elsewhere: return end(LockScreenOutcome.refused, "\(mac) is showing another user’s session.")
        case .unlocked: break
        }
        guard !attempts.inFlight else { return end(LockScreenOutcome.refused, "\(mac) is being unlocked.") }
        guard !locking else { return end(LockScreenOutcome.refused, "\(mac) is already being locked.") }
        guard let shortcut = LockShortcut.from(userKeyEquivalent: Self.userLockEquivalent()) else {
            return end(LockScreenOutcome.notLocked, "Lock Screen has no keyboard shortcut on this Mac.")
        }
        guard let key = KeyStrokes.textKey(for: shortcut.key) else {
            return end(LockScreenOutcome.notLocked, "Lock Screen’s keyboard shortcut uses a key Sill can’t press.")
        }
        locking = true
        defer { locking = false }
        var flags: UInt64 = 0
        if shortcut.command { flags |= KeyStrokes.command }
        if shortcut.control { flags |= KeyStrokes.control }
        if shortcut.option { flags |= KeyStrokes.option }
        if shortcut.shift || key.shift { flags |= KeyStrokes.shift }
        injector.chord(keyCode: key.virtualKey, flags: flags)
        if injector.dryRun {
            lock.simulate(locked: true, testHost: testHost)
            return end(LockScreenOutcome.locked)
        }
        let deadline = CACurrentMediaTime() + UnlockTiming.lockWait
        while CACurrentMediaTime() < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            if lock.read() == .locked { return end(LockScreenOutcome.locked) }
        }
        return end(LockScreenOutcome.notLocked, "\(mac) didn’t lock.")
    }

    /// The user's key equivalent for "Lock Screen" from App Shortcuts › All Applications, which the system
    /// keeps in the global domain as NSUserKeyEquivalents. Read from that domain on purpose: Sill's own
    /// App Shortcuts would otherwise answer first. Nil when there is none (`LockShortcut.standard` then).
    nonisolated static func userLockEquivalent() -> String? {
        let value = CFPreferencesCopyValue("NSUserKeyEquivalents" as CFString, kCFPreferencesAnyApplication,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? [String: Any])?["Lock Screen"] as? String
    }
}
