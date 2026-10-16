import Foundation
// LAContext is not marked Sendable; `read` hands its one context to the keychain's queue after Face ID,
// and nothing else touches it from then on.
@preconcurrency import LocalAuthentication
import Security

/// A Mac's password kept on this device for Face ID (docs/lock-screen-plan.md, decision 3: Ivor,
/// 2026-10-16). One keychain item for each saved Mac, its account the Mac ID (the key the connection
/// is pinned to, never a name), readable only after Face ID or Touch ID with the faces or fingers
/// enrolled when it was kept (`.biometryCurrentSet`: no passcode in their place, and a change of them
/// leaves it unreadable), on this device only (`WhenPasscodeSetThisDeviceOnly`: never synced, never
/// restored to another device). A PIN is never kept (LockScreenPolicy.savedOffer).
///
/// Nothing here prints the password, its length or its characters. A read hands it to one unlock
/// request (StreamClient.unlockWithSaved), and nothing else holds it.
enum SavedUnlock {
    /// The items' service. Their account is the Mac ID.
    static let service = "me.saffer.sill.unlock"

    /// The biometry LocalAuthentication can use now, or nil: the device has none, none is enrolled, or
    /// it is locked out after failed tries (until the passcode is entered on the Lock Screen).
    static func biometry() -> LockScreenPolicy.Biometry? {
        #if DEBUG
        // `-SillBiometry faceID|touchID|opticID|none`: the card as on such a device, for a photo.
        if let forced = UserDefaults.standard.string(forKey: "SillBiometry") { return LockScreenPolicy.Biometry(rawValue: forced) }
        #endif
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return nil }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return nil
        }
    }

    private static func item(_ macID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: macID]
    }

    /// A context that never shows Face ID: a query that would need it fails at once instead.
    private static func silent() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    /// Whether a password is kept for this Mac, read without Face ID (the item's attributes only), and
    /// the keychain's status, for the console. An item behind Face ID may answer with its attributes,
    /// errSecInteractionNotAllowed or errSecAuthFailed, which all mean it is there; a wrong guess is put
    /// right by the read (`gone`, and the caller removes it).
    static func lookup(_ macID: String) -> (kept: Bool, status: OSStatus) {
        #if DEBUG
        // `-SillLockSaved 1`: the card as it is with one kept, for a photo (nothing is read).
        if UserDefaults.standard.bool(forKey: "SillLockSaved") { return (true, errSecSuccess) }
        #endif
        var query = item(macID)
        query[kSecReturnAttributes as String] = true
        query[kSecUseAuthenticationContext as String] = silent()
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return ([errSecSuccess, errSecInteractionNotAllowed, errSecAuthFailed].contains(status), status)
    }

    /// Keeps `secret` for this Mac in place of one kept before: the keychain's status, errSecSuccess or
    /// why not (the device locked meanwhile, no biometry enrolled).
    static func save(_ secret: String, for macID: String) -> OSStatus {
        SecItemDelete(item(macID) as CFDictionary)
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                                                           .biometryCurrentSet, nil) else { return errSecParam }
        var attributes = item(macID)
        attributes[kSecAttrAccessControl as String] = access
        attributes[kSecValueData as String] = Data(secret.utf8)
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    enum Read {
        case password(String)
        /// The person cancelled Face ID, or the system did (the app left the screen).
        case cancelled
        /// Face ID didn't match or is locked out: the password stays kept. Its words are for the console.
        case failed(String)
        /// Face ID is not there now (turned off for Sill, no face enrolled, no passcode).
        case unavailable
        /// The face matched and the keychain still gave nothing: no password is kept for this Mac, or the
        /// one kept can't be read any more (the enrolled faces changed). The caller removes it.
        case gone
    }

    /// The kept password, after Face ID; the system's sheet says `reason`. Face ID is asked for first
    /// (`evaluatePolicy`), then the keychain is read with that same context, whose match the item's
    /// access control takes without asking again: a failure after a face that matched is the item's, not
    /// the person's. (The simulator keeps the item's access control but never enforces it, so there the
    /// evaluation is the only gate.) The read waits off the main thread.
    static func read(_ macID: String, reason: String) async -> Read {
        let context = LAContext()
        context.localizedFallbackTitle = ""     // no passcode button: the card's field is the other way in
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback: return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet: return .unavailable
            default: return .failed("LAError \(error.code.rawValue)")
            }
        } catch {
            return .failed("\(error)")
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var query = item(macID)
                query[kSecReturnData as String] = true
                query[kSecMatchLimit as String] = kSecMatchLimitOne
                query[kSecUseAuthenticationContext as String] = context
                var result: CFTypeRef?
                let status = SecItemCopyMatching(query as CFDictionary, &result)
                switch status {
                case errSecSuccess:
                    if let data = result as? Data, let secret = String(data: data, encoding: .utf8) {
                        continuation.resume(returning: .password(secret))
                    } else {
                        continuation.resume(returning: .gone)
                    }
                case errSecUserCanceled: continuation.resume(returning: .cancelled)
                case errSecItemNotFound, errSecAuthFailed: continuation.resume(returning: .gone)
                default: continuation.resume(returning: .failed("keychain \(status)"))
                }
            }
        }
    }

    /// Removes the password kept for this Mac, if there is one.
    static func forget(_ macID: String) {
        SecItemDelete(item(macID) as CFDictionary)
    }

    /// Removes every kept password but those of `macIDs`, the saved Macs: a Mac forgotten, replaced by
    /// a pairing with its new key or dropped from the list takes its password with it. The number
    /// removed. Read without Face ID (the items' attributes only).
    @discardableResult
    static func keepOnly(_ macIDs: Set<String>) -> Int {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecUseAuthenticationContext as String: silent()]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return 0 }
        var removed = 0
        for attributes in items {
            guard let account = attributes[kSecAttrAccount as String] as? String, !macIDs.contains(account) else { continue }
            forget(account)
            removed += 1
        }
        return removed
    }
}
