import Foundation
import StreamProtocol

/// The TEST ONLY variables for locking and unlocking (docs/lock-screen-plan.md), honoured only on a test
/// host (DoorPolicy.isTestHost), as SILL_TEST_LOCKED is. Anywhere else each one set is ignored with one
/// line (TestHooks.reportIgnored). Every function is pure: the environment comes in as an argument.
///
/// - SILL_TEST_LOCKED=1: the simulated lock state starts locked (SessionLock).
/// - SILL_TEST_LOCK_ASK=pin|password: what the lock screen asks for, whatever tokens this Mac has.
/// - SILL_TEST_UNLOCK_OUTCOME=unlocked|stillLocked: what a dry unlock attempt ends with (default unlocked).
///   A dry "unlocked" flips the simulated state to unlocked, and a dry lock flips it to locked.
/// - SILL_TEST_UNLOCK_SECONDS=N: a dry unlock attempt takes N seconds (default none), the time a real one takes
///   to type and wait, so a test can send a second request or key input while one is in flight (the
///   attempt limit, StreamCoordinator.takesKeyInput).
/// - SILL_TEST_LOCK_AGAIN_SECONDS=N: lock again waits N seconds instead of `LockAgain.grace`.
/// - SILL_TEST_MAC_IDLE=N: the Mac's own keyboard and mouse were last used N seconds ago (0: just now). A
///   dry host reads no HID idle time of this Mac, whose user is typing the test commands.
enum UnlockTestHooks {
    static let outcomes = [LockScreenOutcome.unlocked, LockScreenOutcome.stillLocked]

    static func outcome(testHost: Bool, environment: [String: String]) -> String {
        guard testHost, let value = environment["SILL_TEST_UNLOCK_OUTCOME"], outcomes.contains(value) else {
            return LockScreenOutcome.unlocked
        }
        return value
    }

    static func ask(testHost: Bool, environment: [String: String]) -> String? {
        guard testHost, let value = environment["SILL_TEST_LOCK_ASK"], LockScreenAsk.known.contains(value) else { return nil }
        return value
    }

    static func attemptSeconds(testHost: Bool, environment: [String: String]) -> Double? {
        number("SILL_TEST_UNLOCK_SECONDS", testHost: testHost, environment: environment, positive: true)
    }

    static func lockAgainSeconds(testHost: Bool, environment: [String: String]) -> Double? {
        number("SILL_TEST_LOCK_AGAIN_SECONDS", testHost: testHost, environment: environment, positive: true)
    }

    static func macIdleSeconds(testHost: Bool, environment: [String: String]) -> Double? {
        number("SILL_TEST_MAC_IDLE", testHost: testHost, environment: environment, positive: false)
    }

    private static func number(_ name: String, testHost: Bool, environment: [String: String], positive: Bool) -> Double? {
        guard testHost, let text = environment[name], let value = Double(text), value.isFinite,
              positive ? value > 0 : value >= 0 else { return nil }
        return value
    }

    /// What `start` prints on a test host for each of these that is set: what it does, or why it is ignored.
    static func lines(testHost: Bool, environment: [String: String]) -> [String] {
        guard testHost else { return [] }
        var lines: [String] = []
        if SessionLock.testLocked(testHost: true, environment: environment) {
            lines.append("TEST: this Mac is simulated locked (SILL_TEST_LOCKED); a dry unlock or lock changes that, nothing is typed or posted.")
        }
        if let value = environment["SILL_TEST_UNLOCK_OUTCOME"], !value.isEmpty {
            lines.append(outcomes.contains(value)
                         ? "TEST: a dry unlock attempt ends \(value) (SILL_TEST_UNLOCK_OUTCOME)."
                         : "SILL_TEST_UNLOCK_OUTCOME=\(value) ignored: \(outcomes.joined(separator: " or ")).")
        }
        if let value = environment["SILL_TEST_LOCK_ASK"], !value.isEmpty {
            lines.append(LockScreenAsk.known.contains(value)
                         ? "TEST: the lock screen asks for a \(value) (SILL_TEST_LOCK_ASK)."
                         : "SILL_TEST_LOCK_ASK=\(value) ignored: password or pin.")
        }
        if let value = environment["SILL_TEST_UNLOCK_SECONDS"], !value.isEmpty {
            lines.append(attemptSeconds(testHost: true, environment: environment) != nil
                         ? "TEST: a dry unlock attempt takes \(value) s (SILL_TEST_UNLOCK_SECONDS)."
                         : "SILL_TEST_UNLOCK_SECONDS=\(value) ignored: a number of seconds above 0.")
        }
        if let value = environment["SILL_TEST_LOCK_AGAIN_SECONDS"], !value.isEmpty {
            lines.append(lockAgainSeconds(testHost: true, environment: environment) != nil
                         ? "TEST: lock again waits \(value) s (SILL_TEST_LOCK_AGAIN_SECONDS), not \(Int(LockAgain.grace))."
                         : "SILL_TEST_LOCK_AGAIN_SECONDS=\(value) ignored: a number of seconds above 0.")
        }
        if let value = environment["SILL_TEST_MAC_IDLE"], !value.isEmpty {
            lines.append(macIdleSeconds(testHost: true, environment: environment) != nil
                         ? "TEST: this Mac's own keyboard and mouse were last used \(value) s ago (SILL_TEST_MAC_IDLE)."
                         : "SILL_TEST_MAC_IDLE=\(value) ignored: a number of seconds, 0 or more.")
        }
        return lines
    }
}
