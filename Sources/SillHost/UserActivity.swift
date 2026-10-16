import Foundation
import QuartzCore
import IOKit.pwr_mgt

/// Tells the Mac a user is at it, at most once a second while a device's input arrives
/// (InputInjector calls `declare` before it posts), as Screen Sharing (it calls
/// `IOPMAssertionDeclareUserActivity`) and Chrome Remote Desktop (a `UserIsActive` assertion per
/// input, its WakeUpDisplay) do.
///
/// Posted events are not user activity: the display stays asleep, and a locked Mac that went idle
/// checks no password until there is some. loginwindow waits 5 s for it, then fails the attempt as
/// "INCORRECT password" without checking it (its "activity semaphore": every password typed from an
/// iPhone was refused so on 2026-10-15, and `caffeinate -u`, which makes the same `UserIsActive`
/// assertion, ended the wait). Local, as `caffeinate -u` declares. A fresh declaration each time,
/// released at once, as Chrome Remote Desktop's: the display wakes only when one is made, and the
/// activity outlives it.
///
/// Threading: InputInjector's, the main actor. A synthetic host declares nothing, as it posts
/// nothing (InputInjector.dryRun).
struct UserActivity {
    /// When `declare` last declared.
    private var last: CFTimeInterval = -1_000

    /// `force`: declare now whatever the last declaration was, as an unlock attempt does before its
    /// first key (ShieldTyping), which must find the display awake and loginwindow's semaphore released.
    mutating func declare(force: Bool = false) {
        let now = CACurrentMediaTime()
        guard force || now - last >= 1 else { return }
        last = now
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionDeclareUserActivity("Sill input from an iPhone or iPad" as CFString, kIOPMUserActiveLocal, &id)
        guard result == kIOReturnSuccess else {
            Stats.shared.bump("in.userActiveRefused")
            return
        }
        IOPMAssertionRelease(id)
        Stats.shared.bump("in.userActive")
    }
}
