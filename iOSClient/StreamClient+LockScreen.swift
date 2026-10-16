import UIKit
import Security
import StreamProtocol

/// The device's half of locking and unlocking the Mac (kind 44, StreamProtocol/LockScreen.swift;
/// docs/lock-screen-plan.md, P2). The Mac's window list says whether it is locked (`hostLocked`),
/// whether it takes "lock" (`hostLockScreen`) and whether this connection may "unlock" (`hostUnlock`);
/// the locked card (LockedCard) sends the password or PIN once, per tap, and the Settings panel's row
/// sends the lock. The rules and the words are LockScreenPolicy's. Main thread, but the receive.
///
/// The password or PIN passes through here into one request, to the network queue and out, and the card
/// clears its field when `sendUnlock` takes it. Only a password typed with "Use Face ID next time" on is
/// kept: it waits in `savedUnlockPending` for the Mac's answer and goes to the keychain if the Mac
/// unlocked with it (SavedUnlock), which gives it back only after Face ID, for this Mac's pinned key
/// alone. It is never printed, and neither is its length or its character count (the clipboard's lines
/// count characters; these must not). The console says "unlock attempt" and the Mac's outcome word.
extension StreamClient {
    /// The locked card is wanted: the Mac is locked and the person has not hidden the card for this
    /// lock. StreamScreen draws it, with a pairing overlay that is open coming first.
    var lockCardShown: Bool { hostLocked != nil && !lockCardHidden }

    /// Hide: the card goes and the picture is usable, as it is for typing the password by hand.
    func hideLockCard() {
        lockCardHidden = true
    }

    /// The Settings panel's "Unlock ‹Mac›…": the card comes back. What the last attempt said was said
    /// to the card that went, so it goes too, unless a request is still waiting.
    func showLockCard() {
        if lockScreenAttempt?.sending == false { clearLockScreenAttempt() }
        lockCardHidden = false
    }

    /// The panel closed: a lock request's answer (the words under its row) is not kept for the next
    /// time it opens.
    func clearLockScreenAnswer(for action: String) {
        guard let attempt = lockScreenAttempt, attempt.action == action, !attempt.sending else { return }
        clearLockScreenAttempt()
    }

    /// The attempt on record goes, with its timeout.
    func clearLockScreenAttempt() {
        lockScreenExpiry?.cancel()
        lockScreenExpiry = nil
        if lockScreenAttempt != nil { lockScreenAttempt = nil }
    }

    // MARK: Device → Mac

    /// The card's Unlock: `secret` is typed on the Mac's lock screen (kind 44, "unlock"). Only while
    /// connected, while the list says this connection may unlock and the Mac is locked, with no request
    /// waiting and for a secret the Mac can type (`LockScreenSecret.isTypeable`). Nil when it went, else
    /// why not (nothing was sent). One call is one attempt: nothing retries by itself, and the caller
    /// clears its field once this has taken the secret. With `remember`, where the card offers it, the
    /// password is kept for Face ID if the Mac unlocks with it.
    @discardableResult
    func sendUnlock(secret: String, remember: Bool = false) -> LockScreenPolicy.Block? {
        sendUnlock(secret: secret, use: remember && savedOffer == .remember ? .remember : nil)
    }

    private func sendUnlock(secret: String, use: LockScreenPolicy.SavedUse?) -> LockScreenPolicy.Block? {
        if let block = LockScreenPolicy.unlockBlock(connected: connected, unlock: hostUnlock, locked: hostLocked,
                                                    attempt: lockScreenAttempt, secret: secret) {
            return block
        }
        let token = beginLockScreenRequest(LockScreenAction.unlock, fromSaved: use == .saved)
        if let use, let macID = unlockMacID {
            holdForSaved(SavedUnlockPending(token: token, macID: macID, use: use, secret: use == .remember ? secret : nil))
        }
        print(use == .saved ? "lock screen → Mac: unlock attempt with the saved password" : "lock screen → Mac: unlock attempt")
        transmit(LockScreenRequest(action: LockScreenAction.unlock, secret: secret, token: token))
        return nil
    }

    /// The Settings panel's "Lock ‹Mac›" (kind 44, "lock"), only to a Mac whose list says it takes
    /// kind 44 `LockScreenRequest.generation` or later, while it is unlocked.
    @discardableResult
    func sendLock() -> LockScreenPolicy.Block? {
        if let block = LockScreenPolicy.lockBlock(connected: connected, hostLockScreen: hostLockScreen,
                                                  locked: hostLocked, attempt: lockScreenAttempt) {
            return block
        }
        let token = beginLockScreenRequest(LockScreenAction.lock)
        print("lock screen → Mac: lock")
        transmit(LockScreenRequest(action: LockScreenAction.lock, token: token))
        return nil
    }

    /// The request goes on record as waiting, with its token and the check that gives up on an answer
    /// that never comes.
    private func beginLockScreenRequest(_ action: String, fromSaved: Bool = false) -> Int {
        let token = lockScreenToken
        lockScreenToken += 1
        lockScreenAttempt = LockScreenAttempt(action: action, token: token, phase: .sending, fromSaved: fromSaved)
        lockScreenExpiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lockScreenExpired(token: token) }
        lockScreenExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + LockScreenPolicy.answerWait(action: action), execute: work)
        return token
    }

    private func transmit(_ request: LockScreenRequest) {
        #if DEBUG
        // The layout harness has no Mac: it answers as one would (`-SillLockOutcome`).
        if connection == nil {
            mockLockScreenAnswer(to: request)
            return
        }
        #endif
        let payload = Wire.encode(request)
        queue.async { [weak self] in self?.send(.lockScreen, payload: payload) }
    }

    /// Nothing came for request `token` in `LockScreenPolicy.answerWait`: the card and the row say so,
    /// and a later answer still settles it.
    private func lockScreenExpired(token: Int) {
        guard let expired = LockScreenPolicy.expired(lockScreenAttempt, token: token) else { return }
        lockScreenExpiry = nil
        lockScreenAttempt = expired
        print("lock screen ← Mac: no answer")
    }

    // MARK: Mac → device

    /// The Mac's answer to a request (kind 44, on the network queue). One that does not decode is
    /// dropped: its request's wait runs out.
    func receiveLockScreen(_ data: Data) {
        guard let answer = Wire.decode(LockScreenOutcome.self, from: data) else { return }
        let from = connection
        DispatchQueue.main.async {
            // A replaced connection's answer must not settle the next one's request.
            guard self.connection === from else { return }
            self.lockScreenAnswered(answer)
        }
    }

    /// The answer settles the request on record, if it is that request's (`LockScreenPolicy.settled`).
    /// "unlocked" and "locked" need nothing more: the window list that follows them moves the card.
    private func lockScreenAnswered(_ answer: LockScreenOutcome) {
        // First, and whatever is on record: the Mac's next window list can come before its answer, and
        // one that says it unlocked has cleared the attempt already.
        savedAnswered(answer)
        guard let settled = LockScreenPolicy.settled(lockScreenAttempt, by: answer) else { return }
        lockScreenExpiry?.cancel()
        lockScreenExpiry = nil
        lockScreenAttempt = settled
        print("lock screen ← Mac: " + (LockScreenOutcome.known.contains(answer.outcome) ? answer.outcome : "an outcome this build does not know"))
    }

    // MARK: The password kept for Face ID (SavedUnlock; docs/lock-screen-plan.md, decision 3)

    /// What the card and the Settings panel read: whether a password is kept for this session's Mac, and
    /// this device's biometry, read again when the Mac locks, when the card or the panel shows and after
    /// each change (`refreshSavedUnlock`).
    struct SavedUnlockState: Equatable {
        var saved = false
        var biometry: LockScreenPolicy.Biometry?
    }

    /// An unlock request whose answer decides the kept password (LockScreenPolicy.savedChange), with
    /// the typed password to keep (`.remember` only) until that answer, the request's `answerWait` or
    /// the session's end, whichever comes first.
    struct SavedUnlockPending {
        let token: Int
        let macID: String
        let use: LockScreenPolicy.SavedUse
        let secret: String?
    }

    /// The saved Mac this connection is pinned to by its key, which a kept password belongs to: a
    /// session at home whose connections are pinned to that Mac's saved key, or a remote one (the
    /// remote door is always pinned to a saved Mac's key, and the session takes the Mac ID of the key
    /// that answered: `dialSaved`). Nil at a plain or open door and for a Mac that is not saved: the
    /// Mac's own window list proves nothing here.
    var unlockMacID: String? {
        #if DEBUG
        if mockDiscovery, connection == nil { return connected ? "mock" : nil }   // the layout harness's Mac, which has no key
        #endif
        guard connected, let session, let macID = session.macID,
              let key = savedMac(macID)?.fingerprintData else { return nil }
        if session.route.isRemote { return macID }
        if case .saved(let pin) = session.home, pin == key { return macID }
        return nil
    }

    /// What the card offers beside its field now.
    var savedOffer: LockScreenPolicy.SavedOffer {
        LockScreenPolicy.savedOffer(unlock: hostUnlock, ask: hostLocked, pinned: unlockMacID != nil,
                                    biometry: savedUnlock.biometry, saved: savedUnlock.saved)
    }

    /// The keychain (read without Face ID) and the device's biometry, read again. The console says what
    /// the keychain answered, never more.
    func refreshSavedUnlock() {
        let found = unlockMacID.map(SavedUnlock.lookup)
        let state = SavedUnlockState(saved: found?.kept ?? false, biometry: SavedUnlock.biometry())
        print("lock screen: a saved password for this Mac: \(state.saved ? "yes" : "no")"
              + (found.map { " (keychain \($0.status))" } ?? " (not a Mac pinned by its key)")
              + ", biometry \(state.biometry?.rawValue ?? "none")")
        if savedUnlock != state { savedUnlock = state }
    }

    /// The Settings panel's Forget Saved Password.
    func forgetSavedUnlock() {
        guard let macID = unlockMacID else { return }
        SavedUnlock.forget(macID)
        print("lock screen: the saved password was removed")
        refreshSavedUnlock()
    }

    /// The card's "Unlock with Face ID": the kept password, after Face ID, in one unlock request. All is
    /// judged again when Face ID returns: the same connection, its Mac still locked at a password, still
    /// allowed, nothing waiting (a smart card put in meanwhile makes the field a PIN's, and a password
    /// typed there would use one of its tries). Nil when it went or there is nothing to say (cancelled,
    /// the screen moved on); else the card's line.
    @MainActor
    func unlockWithSaved() async -> String? {
        guard savedOffer == .unlockWithSaved, let macID = unlockMacID, let biometry = savedUnlock.biometry,
              lockScreenAttempt?.sending != true else { return nil }
        let from = connection
        switch await SavedUnlock.read(macID, reason: LockScreenPolicy.savedReason(mac: macName.isEmpty ? "your Mac" : macName)) {
        case .cancelled:
            return nil
        case .failed(let why):
            print("lock screen: Face ID gave no password (\(why)); it stays saved")
            return LockScreenPolicy.savedFailed(biometry)
        case .unavailable:
            print("lock screen: Face ID is not available now")
            refreshSavedUnlock()                  // the button and the switch go with it
            return LockScreenPolicy.savedFailed(biometry)
        case .gone:
            // The face matched and the keychain gave nothing: this item can't be read any more (the
            // enrolled faces changed), so it goes, and the switch to keep a new one comes back.
            SavedUnlock.forget(macID)
            print("lock screen: the saved password could not be read after Face ID, so it was removed")
            refreshSavedUnlock()
            return LockScreenPolicy.savedGone(biometry)
        case .password(let secret):
            guard connection === from, unlockMacID == macID, savedOffer == .unlockWithSaved else { return nil }
            return sendUnlock(secret: secret, use: .saved) == .cannotType ? LockScreenPolicy.cannotType(ask: LockScreenAsk.password) : nil
        }
    }

    /// The saved Macs' list was written (`storeSavedMacs`): a Mac that left it (forgotten, replaced by a
    /// pairing with its new key, past the cap) takes the password kept for it.
    func pruneSavedUnlock() {
        let removed = SavedUnlock.keepOnly(Set(savedMacs.map(\.macID)))
        if removed > 0 { print("lock screen: \(removed == 1 ? "a saved password" : "\(removed) saved passwords") removed with its Mac") }
    }

    private func holdForSaved(_ pending: SavedUnlockPending) {
        savedUnlockPending = pending
        let token = pending.token
        DispatchQueue.main.asyncAfter(deadline: .now() + LockScreenPolicy.answerWait(action: LockScreenAction.unlock)) { [weak self] in
            if self?.savedUnlockPending?.token == token { self?.savedUnlockPending = nil }
        }
    }

    /// The Mac's answer to the request that waits to keep or forget the password (LockScreenPolicy.savedChange).
    private func savedAnswered(_ answer: LockScreenOutcome) {
        guard let pending = savedUnlockPending, pending.token == answer.token else { return }
        savedUnlockPending = nil
        switch LockScreenPolicy.savedChange(pending.use, answer: answer) {
        case .save:
            guard let secret = pending.secret else { return }
            let status = SavedUnlock.save(secret, for: pending.macID)
            print(status == errSecSuccess ? "lock screen: the password is kept for Face ID"
                                          : "lock screen: the password could not be kept (\(status))")
        case .forget:
            SavedUnlock.forget(pending.macID)
            print("lock screen: the saved password left the Mac locked, so it was removed")
        case .leave:
            return
        }
        refreshSavedUnlock()
    }

    #if DEBUG
    /// The layout harness's Mac (MockCatalog): a request is answered 0.4 s after it is sent, as
    /// `-SillLockOutcome` says. For an unlock: `stillLocked` (the default), `refused` or `unlocked`
    /// (which also unlocks the mock, as the Mac's next window list would). For a lock: `locked` (the
    /// default: the mock locks), `notLocked` or `refused`. `silent` is never answered, so the card
    /// stays on "Unlocking…" until the wait runs out.
    private func mockLockScreenAnswer(to request: LockScreenRequest) {
        let choice = UserDefaults.standard.string(forKey: "SillLockOutcome")
        guard choice != "silent" else { return }
        let mac = macName.isEmpty ? "The Mac" : macName
        let answer: LockScreenOutcome
        if request.action == LockScreenAction.unlock {
            switch choice {
            case "unlocked":
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.unlocked)
            case "refused":
                let words = hostLocked == LockScreenAsk.pin
                    ? "Two wrong PINs in a row. Unlock \(mac) at the Mac: a third would block the smart card."
                    : "Wait a few seconds, then try again."
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.refused, message: words)
            default:
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.stillLocked)
            }
        } else {
            switch choice {
            case "notLocked":
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.notLocked)
            case "refused":
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.refused,
                                           message: "\(mac) is showing another user’s session.")
            default:
                answer = LockScreenOutcome(token: request.token, outcome: LockScreenOutcome.locked)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.connection == nil else { return }
            // As a Mac's kind 44 arrives, through the receive path (decoded, handed to main, checked
            // against the connection), then what its next window list would say.
            self.receiveLockScreen(Wire.encode(answer))
            DispatchQueue.main.async {
                if answer.outcome == LockScreenOutcome.unlocked { self.hostLocked = nil }
                if answer.outcome == LockScreenOutcome.locked { self.hostLocked = LockScreenAsk.password }
            }
        }
    }

    /// Why `-SillUnlockAfter`'s stand-in for a tap on Unlock (LockedCard) must not press it here, or
    /// nil when it may: in the harness's mock, which has no connection, and against a synthetic host
    /// dialled on this Mac's loopback (InputScript's guard), never against Sill.app or a real Mac,
    /// where an attempt would type into its lock screen.
    var lockHarnessRefusal: String? {
        guard connection != nil else { return nil }
        return InputScript.refusal(endpoint: connection?.endpoint, hostVersion: hostVersion)
            .map { $0.replacingOccurrences(of: ", which posts input to this Mac", with: ", which types into its lock screen") }
    }
    #endif
}
