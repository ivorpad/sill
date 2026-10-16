import Foundation
import IOKit
import QuartzCore
import StreamProtocol

/// Lock again (docs/lock-screen-plan.md, decision 5): what Sill remembers about the device whose attempt
/// unlocked the Mac, so that the Mac can be put back the way the device found it. The rule is
/// `LockAgain.locks` (StreamProtocol); the coordinator's extension schedules the check and acts on it.
///
/// Armed only by an attempt of Sill's that pressed Return and then saw the Mac unlocked. A Mac that is
/// locked again by any means disarms it (that unlock is over), and so does the check itself, unless
/// the device is back. The device is its key's fingerprint, so a reconnect is the same device (and
/// cancels a check that waits). All times are `CACurrentMediaTime` seconds, which do not run while the
/// Mac sleeps, as the HID idle time does not either.
@MainActor
final class LockAgainWatch {
    struct Unlocker: Equatable {
        /// Its connection while it is connected; nil once it left, so an ObjectIdentifier that the
        /// system reuses cannot pass for it.
        var connection: ObjectIdentifier?
        /// Its key's fingerprint (a TLS door's peer: unlock is refused at any other).
        var key: Data
        var name: String
    }

    private(set) var unlocker: Unlocker?
    /// When its connection ended; nil while it is connected.
    private(set) var leftAt: Double?
    /// When a connection other than the unlocker's last sent something that acts on the Mac.
    private(set) var lastOtherActivityAt: Double = -1_000
    /// The check that waits out the grace. Replaced when the device leaves again, cancelled when it
    /// returns or the Mac locks.
    var timer: Task<Void, Never>?

    func arm(_ who: Unlocker) {
        unlocker = who
        leftAt = nil
        timer?.cancel()
        timer = nil
    }

    func disarm() {
        unlocker = nil
        leftAt = nil
        timer?.cancel()
        timer = nil
    }

    /// A connection was admitted: true when it is the unlocker's key, back (the grace starts over).
    func joined(_ connection: ObjectIdentifier, key: Data?) -> Bool {
        guard var who = unlocker, let key, key == who.key else { return false }
        who.connection = connection
        unlocker = who
        leftAt = nil
        timer?.cancel()
        timer = nil
        return true
    }

    /// A connection ended: true when it is the unlocker's, which has now left.
    func left(_ connection: ObjectIdentifier, now: Double = CACurrentMediaTime()) -> Bool {
        guard var who = unlocker, who.connection == connection else { return false }
        who.connection = nil
        unlocker = who
        leftAt = now
        return true
    }

    /// A message that acts on the Mac, from a connection other than the unlocker's: another device is using it.
    func noteActivity(_ kind: StreamMessageKind, from connection: ObjectIdentifier, now: Double = CACurrentMediaTime()) {
        switch kind {
        case .input, .gesture, .windowCommand, .launchApp, .pressMenuItem: break
        default: return
        }
        guard unlocker?.connection != connection else { return }
        lastOtherActivityAt = now
    }

    /// Whether the Mac's own keyboard or mouse was used after the device left, pure. `idle` is the
    /// seconds since the last HID event (IOHIDSystem's HIDIdleTime), nil when it can't be read (read as
    /// not used: locking is the safe side for a Mac a device left unlocked). Sill's own posts may reset it
    /// (P0f), so the event counts only if it came after both the departure and Sill's last real post
    /// (`lastPostAt`), by a margin for the two clocks. What follows that post of another device's input is
    /// the caller's (`lastOtherActivityAt`).
    nonisolated static func macUsed(idle: Double?, now: Double, leftAt: Double, lastPostAt: Double) -> Bool {
        guard let idle else { return false }
        return now - idle > max(leftAt, lastPostAt) + 0.5
    }

    /// Seconds since the Mac's last keyboard, mouse or trackpad event, from the IOHIDSystem service's
    /// HIDIdleTime (nanoseconds). A read, which needs no permission.
    nonisolated static func hidIdleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any],
              let idle = dictionary["HIDIdleTime"] as? NSNumber else { return nil }
        return idle.doubleValue / 1_000_000_000
    }
}
