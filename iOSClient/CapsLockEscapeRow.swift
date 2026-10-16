import SwiftUI

/// The Settings panel's This iPad group, on an iPad: Caps Lock as Escape for a hardware keyboard
/// (CapsLockEscape, KeyChords.swift). Kept on this device (`Sill.capsLockEscape`), off until turned on;
/// the overlay reads it at each key press, so it takes effect at once, also mid-session.
struct CapsLockEscapeRow: View {
    let mac: String
    @AppStorage(CapsLockEscape.defaultsKey) private var on = false

    var body: some View {
        Rows {
            Toggle(isOn: $on) {
                Text(CapsLockEscape.title).foregroundStyle(Palette.text)
            }
            .rowFrame()
        }
        Footnote(text: CapsLockEscape.footnote(mac: mac, device: StreamClient.deviceWord))
    }
}
