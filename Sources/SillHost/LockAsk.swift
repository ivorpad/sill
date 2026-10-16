import Foundation
import CryptoTokenKit
import StreamProtocol

/// What the lock screen asks for (`WindowList.locked`): the Mac's password, or a smart card's PIN while a
/// card is in. A Mac paired for smart-card login asks for the PIN while the card is in, and three wrong
/// ones block a YubiKey's PIV applet (`UnlockAttempts.pinFailureStop` keeps a try for the Mac's keyboard).
///
/// The witness is TKTokenWatcher: a token whose ID starts with "com.apple.pivtoken". A token in the port
/// is not the same as one paired for this user's login: the plan's P0d reads the pairing as well
/// (`sc_auth identities`, or the user record's AltSecurityIdentities). Until it does, a card that is in
/// but not paired makes the field read PIN and the two-failure stop apply to a password. The label is
/// cosmetic, and the stop is the cost. This Mac with its YubiKey out lists only `com.apple.setoken`.
@MainActor
enum LockAsk {
    private static let watcher = TKTokenWatcher()

    static func current(testHost: Bool, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let forced = UnlockTestHooks.ask(testHost: testHost, environment: environment) { return forced }
        return hasPIVToken(watcher.tokenIDs) ? LockScreenAsk.pin : LockScreenAsk.password
    }

    /// Whether any token ID is a PIV card's, pure.
    nonisolated static func hasPIVToken(_ ids: [String]) -> Bool {
        ids.contains { $0.hasPrefix("com.apple.pivtoken") }
    }
}
