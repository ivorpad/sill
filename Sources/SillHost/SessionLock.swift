import Foundation
import CoreGraphics

/// Whether this Mac's user is at an unlocked console (docs/home-pairing-plan.md §4.3): the ask
/// rule's step 1 (a locked Mac pairs nothing by itself and opens no window, which nobody could
/// see), and --print-cable's last line.
///
/// The witness is `CGSessionCopyCurrentDictionary()`: unlocked when `kCGSSessionOnConsoleKey` is 1
/// (this user's session is the one on the console, not another user's under fast user switching)
/// and `CGSSessionScreenIsLocked` is absent or false; no dictionary counts as locked. That lock key
/// is undocumented, and a rename would read as unlocked, so Sill.app adds a second witness, the
/// distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// (`watchNotifications`): either one saying locked wins. The CLI has the dictionary only.
///
/// Locking and unlocking from a device (docs/lock-screen-plan.md) needs more than that rule: three
/// states (`State`), a cached one that a change calls back on (`state`, `onChange`: the coordinator
/// sends every device its window list again), and a fresh read for the moments the cache is too old
/// (`read`: the dictionary alone, never the notifications, which lag a real unlock by a hop, so
/// typing stops at the first moment the Mac is unlocked). The cache is refreshed by the
/// notifications in Sill.app and, in both hosts, once a second while a device is connected (`watch`).
///
/// Main actor, where the ask is judged. A test host (DoorPolicy.isTestHost) never reads the real
/// console, whose test pattern is not the screen and whose lock state would make a test depend on
/// whether the Mac it runs on is locked: its state is simulated, unlocked unless SILL_TEST_LOCKED=1
/// makes it start locked, and a dry unlock or lock then flips it (`simulate`), so the window list, the
/// ask and every read follow one simulated state.
@MainActor
package final class SessionLock {
    package static let shared = SessionLock()

    /// What the console shows this user.
    package enum State: Equatable {
        /// This user's session is on the console and its lock screen is not up.
        case unlocked
        /// This user's session is on the console and its lock screen is up: the only state a device
        /// may unlock, and the only one a password is typed in.
        case locked
        /// Another user's session or the login window has the console, or there is no session
        /// dictionary: nothing is typed and nothing is locked.
        case elsewhere
    }

    /// The last notification said locked (Sill.app only).
    private var notifiedLocked = false
    private var observers: [NSObjectProtocol] = []

    /// The state as of the last `refresh`. Devices are told it through the window list.
    package private(set) var state = State.unlocked
    /// Called on the main actor when `refresh` finds another state than the one cached: the old and the
    /// new one.
    package var onChange: (@MainActor (_ old: State, _ new: State) -> Void)?
    /// Whether this host is a test host: set once by the coordinator. Only then does the simulation count.
    package var testHost = false

    /// The simulated state of a test host, true while locked; nil on every other host, which reads the
    /// real console.
    private var simulated: Bool?
    private var simulationRead = false
    private var watcher: Task<Void, Never>?

    private init() {}

    /// Whether the console is this user's and unlocked, now. `testHost`: whether the simulation may count.
    package func unlocked(testHost: Bool) -> Bool {
        if let locked = simulatedLocked(testHost: testHost) { return !locked }
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        return Self.unlocked(dictionary: dictionary, notifiedLocked: notifiedLocked)
    }

    // MARK: The state for devices

    /// A fresh read of the console: the session dictionary alone, or the simulated state on a test host.
    /// Not the cache, and not the notifications (see the type's note).
    func read() -> State {
        if let locked = simulatedLocked(testHost: testHost) { return locked ? .locked : .unlocked }
        return Self.state(dictionary: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    /// Reads afresh, keeps the result and says so when it is not what was cached.
    @discardableResult
    func refresh() -> State {
        let now = read()
        if now != state {
            let old = state
            state = now
            onChange?(old, now)
        }
        return now
    }

    /// While a device is connected the console is read once a second (and Sill.app's notifications read
    /// it at once): a lock or an unlock reaches the devices without a request. Nothing runs without a device.
    func watch(_ on: Bool) {
        guard on else { watcher?.cancel(); watcher = nil; return }
        guard watcher == nil else { return }
        refresh()
        watcher = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
            }
        }
    }

    /// TEST ONLY: a dry unlock or lock ended with this state. Ignored on a host that is not a test host.
    func simulate(locked: Bool, testHost: Bool) {
        guard testHost else { return }
        simulationRead = true
        simulated = locked
        refresh()
    }

    private func simulatedLocked(testHost: Bool) -> Bool? {
        guard testHost else { return nil }
        if !simulationRead {
            simulationRead = true
            simulated = Self.testLocked(testHost: true, environment: ProcessInfo.processInfo.environment)
        }
        return simulated
    }

    /// Sill.app: the lock and unlock notifications as a second witness, and the cue to read the console
    /// at once. Call once, on the main actor under the AppKit loop.
    package func watchNotifications() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SessionLock.shared.notifiedLocked = true
                SessionLock.shared.refresh()
            }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SessionLock.shared.notifiedLocked = false
                SessionLock.shared.refresh()
                // The session dictionary can trail the notification by a moment.
                try? await Task.sleep(for: .milliseconds(400))
                SessionLock.shared.refresh()
            }
        })
    }

    /// The rule, pure: unlocked only with a dictionary whose `kCGSSessionOnConsoleKey` is 1 (true)
    /// and whose `CGSSessionScreenIsLocked` is absent or false, and no notification saying locked.
    nonisolated static func unlocked(dictionary: [String: Any]?, notifiedLocked: Bool) -> Bool {
        guard !notifiedLocked, let d = dictionary else { return false }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else { return false }
        if let locked = d["CGSSessionScreenIsLocked"] {
            guard let n = locked as? NSNumber, !n.boolValue else { return false }
        }
        return true
    }

    /// The three states from the session dictionary alone, pure. No dictionary, another user on the
    /// console, or a lock key that is not a number: `elsewhere`, where nothing is typed and nothing locked.
    nonisolated static func state(dictionary: [String: Any]?) -> State {
        guard let d = dictionary, let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else {
            return .elsewhere
        }
        guard let locked = d["CGSSessionScreenIsLocked"] else { return .unlocked }
        guard let n = locked as? NSNumber else { return .elsewhere }
        return n.boolValue ? .locked : .unlocked
    }

    /// --print-cable's words for the console, from the session dictionary (the CLI has no other
    /// witness).
    nonisolated static func consoleDescription(testHost: Bool) -> String {
        if testLocked(testHost: testHost, environment: ProcessInfo.processInfo.environment) { return "locked (SILL_TEST_LOCKED)." }
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return "locked (no console session)." }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else {
            return "locked (another user's session is on the console)."
        }
        return unlocked(dictionary: d, notifiedLocked: false) ? "unlocked, your session on the console." : "locked."
    }

    /// TEST ONLY: SILL_TEST_LOCKED=1, on a test host only.
    nonisolated static func testLocked(testHost: Bool, environment: [String: String]) -> Bool {
        testHost && environment["SILL_TEST_LOCKED"] == "1"
    }
}
