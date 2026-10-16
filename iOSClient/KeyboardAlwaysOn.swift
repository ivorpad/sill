import SwiftUI
import GameController

/// Keyboard Always On: the Settings panel's switch under This iPad, kept on this device in
/// `Sill.keyboardAlwaysOn`, off until turned on. While a keyboard is connected to the iPad (GCKeyboard),
/// the stream takes the keyboard whenever nothing else on the screen is using it (StreamScreen's
/// `streamMayTakeKeyboard`: the Settings panel, the Apps drawer and its search, the locked card, the
/// pairing overlay and the tour all keep it while they show), so what is typed goes to the Mac without
/// the Keyboard button. With no keyboard connected it does nothing, so the on-screen keyboard never comes
/// up by itself, and a keyboard that goes takes the stream's keyboard down with it. The Keyboard button
/// still takes it down, until the next time the stream is free to take it.
enum KeyboardAlwaysOn {
    static let defaultsKey = "Sill.keyboardAlwaysOn"
    static let title = "Keyboard Always On"

    static func footnote(mac: String, device: String) -> String {
        "With a keyboard connected to this \(device), what you type goes to \(mac) without the Keyboard button, "
            + "except while Settings, Apps or a card is open."
    }

    /// The switch is on.
    static var on: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    /// The switch is on and a keyboard is connected now.
    static var applies: Bool { on && GCKeyboard.coalesced != nil }
}

/// The switch and its footnote, on an iPad only (HostSettingsPanel's This iPad group).
struct KeyboardAlwaysOnRow: View {
    let mac: String
    @AppStorage(KeyboardAlwaysOn.defaultsKey) private var on = false

    var body: some View {
        Rows {
            Toggle(isOn: $on) {
                Text(KeyboardAlwaysOn.title).foregroundStyle(Palette.text)
            }
            .rowFrame()
        }
        Footnote(text: KeyboardAlwaysOn.footnote(mac: mac, device: StreamClient.deviceWord))
    }
}

/// StreamScreen's hooks for Keyboard Always On, one modifier (the screen's own chain is at the type
/// checker's limit): the stream takes the keyboard whenever nothing else uses it and when a keyboard
/// connects, and a keyboard that goes takes it down, so the on-screen one never stays up by itself.
struct KeyboardAlwaysOnHooks: ViewModifier {
    let streamMayTake: Bool
    let take: () -> Void
    let letGo: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: streamMayTake, initial: true) { _, may in if may { take() } }
            .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in take() }
            .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
                if KeyboardAlwaysOn.on { letGo() }
            }
    }
}
