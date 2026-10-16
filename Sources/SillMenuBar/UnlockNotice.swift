import Foundation
import UserNotifications

/// Sill.app's local notification for an unlock from a device (docs/lock-screen-plan.md, P3): "iPhone
/// (iPhone17,2) unlocked this Mac", with "Through Tailscale at 22:28" under it. The host calls it once for
/// each attempt of Sill's that unlocked the Mac (StreamCoordinator.onDeviceUnlocked); the CLI prints its
/// log line only.
///
/// Permission to notify is asked for when the user turns on "Unlock from devices" (HostSettings
/// .onUnlockSwitchedOn), never at launch. Every call into UserNotifications is guarded by
/// `AppModel.bundled`: `UNUserNotificationCenter.current()` raises an exception in an executable that is
/// not an app bundle's, which is the bare SillMenuBar binary the tests run.
@MainActor
enum UnlockNotice {
    static func requestAuthorization() {
        guard AppModel.bundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func post(device: String, route: String, at: Date) {
        guard AppModel.bundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title(device: device)
        content.body = body(route: route, at: at)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated static func title(device: String) -> String { "\(device) unlocked this Mac" }

    /// "Through Tailscale at 22:28": how the device came (the card's own words, "through Tailscale",
    /// "over Wi‑Fi", "over the USB cable") and when, in the user's time format.
    nonisolated static func body(route: String, at: Date) -> String {
        let time = at.formatted(date: .omitted, time: .shortened)
        guard !route.isEmpty else { return "At \(time)" }
        return "\(route.prefix(1).uppercased() + route.dropFirst()) at \(time)"
    }
}
