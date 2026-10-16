import Foundation
import Network
import QuartzCore
import StreamProtocol

// Locking and unlocking the Mac from a device (kind 44, docs/lock-screen-plan.md), the coordinator's part.
// The sequence that types is ShieldTyping's, the console's state SessionLock's, lock again's memory
// LockAgainWatch's, and the rules are StreamProtocol's (LockScreen.swift: UnlockJudge, UnlockPolicy,
// LockAgain). This file connects them to the connections: the window list's three fields, the request's
// handler, the one rule for key input while the Mac is locked, and lock again's timer.

extension StreamCoordinator {
    // MARK: The window list

    /// `WindowList.locked`: what the lock screen asks for while this user's console is locked, else nil.
    /// Read from the cache, which every connect (`sendCatalog`), every change and every second while a device
    /// is connected refresh.
    func lockedAsk() -> String? {
        guard SessionLock.shared.state == .locked else { return nil }
        return LockAsk.current(testHost: server.isTestHost)
    }

    /// `WindowList.unlock` for one connection: true when the Mac's switches let it unlock, at a TLS door
    /// (`ClientRoute.encrypted`: a home session with a key, or any remote one). The plain door never
    /// advertises it. A connection with no route yet counts as away and as not TLS.
    func unlockAdvertised(for id: ObjectIdentifier) -> Bool? {
        config.unlockPolicy.advertised(away: routes[id]?.isAway ?? true, tls: routes[id]?.encrypted ?? false)
    }

    /// Sill.app's local notification for an unlock from a device (name, how it came, when). The CLI sets none.
    package var onDeviceUnlocked: (@MainActor (_ device: String, _ route: String, _ at: Date) -> Void)? {
        get { shield.onUnlockedByDevice }
        set { shield.onUnlockedByDevice = newValue }
    }

    // MARK: Kind 44

    /// A device's lock or unlock request. Judged here (UnlockJudge), typed or posted by ShieldTyping, and
    /// answered to that device alone with the same token, one LockScreenOutcome. One line in the log for
    /// each, which never has the secret, its length or its keys: the request is decoded, its `secret` goes
    /// only to ShieldTyping and nothing interpolates the request itself.
    func handleLockScreen(_ message: StreamMessage, from connection: NWConnection) async {
        guard let request = Wire.decode(LockScreenRequest.self, from: message.payload) else { return }   // no token to answer
        let id = ObjectIdentifier(connection)
        let token = request.token
        let who = deviceName(connection)
        let route = routeWords(for: id)
        let testHost = server.isTestHost
        let outcome: LockScreenOutcome
        var alreadyUnlocked = false
        let action: String

        switch request.action {
        case LockScreenAction.unlock:
            action = "Unlock"
            let state = SessionLock.shared.refresh()
            let ask = LockAsk.current(testHost: testHost)
            let verdict = UnlockJudge.verdict(tls: routes[id]?.encrypted ?? false, policy: config.unlockPolicy,
                                              away: routes[id]?.isAway ?? true, onConsole: state != .elsewhere,
                                              locked: state == .locked, secret: request.secret, ask: ask,
                                              attempts: shield.attempts, now: CACurrentMediaTime(), mac: macName)
            switch verdict {
            case .refuse(let words):
                outcome = LockScreenOutcome(token: token, outcome: LockScreenOutcome.refused, message: words)
            case .alreadyUnlocked:
                alreadyUnlocked = true
                outcome = LockScreenOutcome(token: token, outcome: LockScreenOutcome.unlocked, message: "\(macName) was already unlocked.")
            case .go:
                guard let secret = request.secret else { return }   // the judge went only with one
                let key = routes[id]?.fingerprint
                let attempt = await shield.unlock(secret: secret, ask: ask, token: token, from: id, mac: macName,
                                                  injector: injector, lock: SessionLock.shared, testHost: testHost)
                outcome = attempt.outcome
                if attempt.unlockedBySill, let key { deviceUnlocked(id, key: key, name: who, route: route) }
            }
        case LockScreenAction.lock:
            action = "Lock"
            outcome = await shield.lock(token: token, mac: macName, injector: injector, lock: SessionLock.shared, testHost: testHost)
        default:
            action = "Lock screen request"
            outcome = LockScreenOutcome(token: token, outcome: LockScreenOutcome.refused, message: "\(macName) doesn’t take that request.")
        }

        server.send(each: [(connection, StreamMessage(kind: .lockScreen, timestamp: Date().timeIntervalSince1970,
                                                      isKeyframe: false, payload: Wire.encode(outcome)))])
        Stats.shared.bump("lock.\(outcome.outcome)")
        print(Self.lockLine(action, who: who, route: route, outcome: outcome, alreadyUnlocked: alreadyUnlocked))
        SessionLock.shared.refresh()    // every device hears of a changed lock state at once, not at the next second
    }

    /// "Unlock: iPhone (iPhone17,2) through Tailscale: still locked", "Lock: … : locked",
    /// "Unlock: … : refused (Unlocking from devices is off on Mac…)".
    static func lockLine(_ action: String, who: String, route: String, outcome: LockScreenOutcome, alreadyUnlocked: Bool) -> String {
        "\(action): \(who)\(route.isEmpty ? "" : " " + route): \(outcomeWords(outcome, alreadyUnlocked: alreadyUnlocked))"
    }

    /// An outcome in the log's words: "unlocked", "still locked", "locked", "not locked (why)", "refused (why)".
    static func outcomeWords(_ outcome: LockScreenOutcome, alreadyUnlocked: Bool = false) -> String {
        let why = outcome.message.map { " (\($0))" } ?? ""
        switch outcome.outcome {
        case LockScreenOutcome.unlocked: return alreadyUnlocked ? "already unlocked" : "unlocked"
        case LockScreenOutcome.stillLocked: return "still locked"
        case LockScreenOutcome.locked: return "locked"
        case LockScreenOutcome.notLocked: return "not locked" + why
        default: return "refused" + why
        }
    }

    /// How a connection came, in the words of the Mac's card and log: "through Tailscale", "over Wi‑Fi"…
    func routeWords(for id: ObjectIdentifier) -> String {
        guard let route = routes[id] else { return "" }
        return route.label ?? Self.homeRouteWords(route, link: status.snapshot.devices.first { $0.id == id }?.route)
    }

    // MARK: Key input while an unlock attempt types

    /// Whether this connection's key and text input, and its trackpad gestures, reach the Mac now. THE one
    /// place this rule lives. Never while an unlock attempt is typing, from any connection, so a second
    /// device cannot add to the secret. Otherwise always, the Mac locked or not: the plan's decision 2
    /// (Ivor, 2026-10-16, "Keep today's typing") leaves typing into the lock screen by hand open to every
    /// paired device, whatever the unlock switches say, which decide the attempts of kind 44 only. Pointer
    /// and scroll input are not judged here.
    func takesKeyInput(from id: ObjectIdentifier) -> Bool {
        !shield.attemptInFlight
    }

    /// Key or text input that `takesKeyInput` keeps from the Mac: dropped and counted (`in.unlockDrop`). True
    /// when the caller has nothing more to do with it. The up of a key the Mac already has down still goes, as
    /// input with nowhere to land does (DroppedInput): a modifier held when the attempt began would otherwise
    /// stay down on the Mac.
    func withheldDuringAttempt(_ event: InputEvent, from device: ObjectIdentifier) -> Bool {
        switch event {
        case .key, .text: break
        default: return false
        }
        guard !takesKeyInput(from: device) else { return false }
        if injector.isUpOfSomethingDown(event) {
            deliver(event, in: .null, from: device)
        } else {
            Stats.shared.bump("in.unlockDrop")
        }
        return true
    }

    // MARK: The console changed

    /// The cached console state changed (SessionLock.onChange): every device gets its window list again, an
    /// unlock by any means starts the attempt count over, and a lock ends Sill's unlock for lock again.
    func lockStateChanged(from old: SessionLock.State, to new: SessionLock.State) {
        if new == .unlocked { shield.macUnlocked() }
        if new == .locked { lockAgain.disarm() }
        broadcastList()
    }

    // MARK: Lock again

    /// An attempt of Sill's unlocked the Mac for the device on `id` (its key `key`): lock again is armed for
    /// it, and Sill.app notifies the Mac's user. A device that went meanwhile has left already.
    private func deviceUnlocked(_ id: ObjectIdentifier, key: Data, name: String, route: String) {
        shield.onUnlockedByDevice?(name, route, Date())
        lockAgain.arm(LockAgainWatch.Unlocker(connection: id, key: key, name: name))
        if connections[id] == nil, lockAgain.left(id) { scheduleLockAgainCheck(after: lockAgainGrace) }
    }

    /// How long lock again waits: `LockAgain.grace`, or a test host's SILL_TEST_LOCK_AGAIN_SECONDS.
    private var lockAgainGrace: Double {
        UnlockTestHooks.lockAgainSeconds(testHost: server.isTestHost, environment: ProcessInfo.processInfo.environment) ?? LockAgain.grace
    }

    /// A connection was admitted: the device that unlocked the Mac, back, stops lock again's wait.
    func lockScreenConnectionJoined(_ id: ObjectIdentifier, route: ClientRoute) {
        _ = lockAgain.joined(id, key: route.fingerprint)
    }

    /// A connection ended (closed, or evicted for silence): if it is the unlocker's, the grace begins.
    func lockScreenConnectionLeft(_ id: ObjectIdentifier) {
        guard lockAgain.left(id) else { return }
        scheduleLockAgainCheck(after: lockAgainGrace)
    }

    private func scheduleLockAgainCheck(after seconds: Double) {
        lockAgain.timer?.cancel()
        lockAgain.timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            await self.lockAgainCheck(grace: seconds)
        }
    }

    /// The grace is up. `LockAgain.locks` decides from what is true now: the switch, whether the device
    /// is back, whether the Mac is still unlocked, and whether anyone used it since the device left (the
    /// Mac's own keyboard or mouse by its HID idle time against Sill's last real post, or another
    /// connection's input). Whatever it says, this unlock is over unless the device is back.
    private func lockAgainCheck(grace: Double) async {
        // This task is the timer: let go of it, or `disarm` below would cancel the very task that waits for the lock.
        lockAgain.timer = nil
        guard let who = lockAgain.unlocker, let leftAt = lockAgain.leftAt else { return }
        let now = CACurrentMediaTime()
        // The timer ran through a sleep that the clock did not: wait out the rest.
        if now - leftAt < grace - 0.5 { scheduleLockAgainCheck(after: grace - (now - leftAt)); return }
        let back = connections.keys.contains { routes[$0]?.fingerprint == who.key }
        let state = SessionLock.shared.refresh()
        let environment = ProcessInfo.processInfo.environment
        let testHost = server.isTestHost
        // A dry host reads no HID idle time of this Mac: SILL_TEST_MAC_IDLE says it, else the Mac was not used.
        let idle = injector.dryRun ? UnlockTestHooks.macIdleSeconds(testHost: testHost, environment: environment)
                                   : LockAgainWatch.hidIdleSeconds()
        let used = lockAgain.lastOtherActivityAt > leftAt
            || LockAgainWatch.macUsed(idle: idle, now: now, leftAt: leftAt, lastPostAt: injector.lastRealPostAt)
        // LockAgain waits `LockAgain.grace`; a test host's shorter wait moves the departure back by the difference.
        let go = LockAgain.locks(enabled: config.lockAgain, unlockedBySill: true, leftAt: leftAt - (LockAgain.grace - grace),
                                 now: now, unlockerBack: back, locked: state != .unlocked, usedSince: used)
        if !back { lockAgain.disarm() }
        let left = "\(who.name) left \(Int(grace.rounded())) s ago"
        guard go else {
            if !back, state == .unlocked, config.lockAgain { print("Lock again: \(left): this Mac was used since, so it stays unlocked") }
            return
        }
        let outcome = await shield.lock(token: 0, mac: macName, injector: injector, lock: SessionLock.shared, testHost: testHost)
        Stats.shared.bump("lock.\(outcome.outcome)")
        print("Lock again: \(left): \(Self.outcomeWords(outcome))")
        SessionLock.shared.refresh()
    }
}
