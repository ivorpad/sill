import Foundation
import StreamProtocol

// The keys this device sends for a shortcut: the Spotlight key's ⌘Space, the portrait key row's keys
// with whatever is latched, a latched ⌘, ⌃ or ⌥ on the software keyboard, the modifiers the portrait
// trackpad holds down around a click or a drag, and a hardware keyboard's keys. One place, so each
// goes out the way a keyboard sends it: a shortcut's modifiers pressed with their own keys around it,
// and every key's up after its down (2026-09-27, the stuck command after Spotlight). A shortcut sent
// as one key down and up carrying its modifiers left them set on every Mac from before that fix,
// which posted the up as it came, and the next click there was a ⌘-click.
//
// Pure: Foundation and StreamProtocol only, checked with swiftc beside the host's KeyStrokes
// (Tests/checks/key-strokes), which is what the Mac makes of these events.

/// The modifier bits an `InputEvent.key` carries: `UIKeyModifierFlags` raw values, which sit at the
/// same bit positions as the `CGEventFlags` the host posts with, so they travel unchanged.
struct KeyModifiers: OptionSet {
    let rawValue: UInt64

    static let shift   = KeyModifiers(rawValue: 1 << 17)
    static let control = KeyModifiers(rawValue: 1 << 18)
    static let option  = KeyModifiers(rawValue: 1 << 19)
    static let command = KeyModifiers(rawValue: 1 << 20)

    /// The three that make shortcuts instead of characters. Shift is not one of them: it changes
    /// which character the keyboard produces, which the text path already handles.
    static let shortcutMakers: KeyModifiers = [.control, .option, .command]

    /// Each latched modifier as its own key: the HID usage to press, and the bit it contributes.
    /// A pointer event has no modifier field, so a modified click has to hold these down around it.
    var keys: [(usage: UInt16, flag: KeyModifiers)] {
        var out: [(usage: UInt16, flag: KeyModifiers)] = []
        if contains(.control) { out.append((0xE0, .control)) }
        if contains(.shift)   { out.append((0xE1, .shift)) }
        if contains(.option)  { out.append((0xE2, .option)) }
        if contains(.command) { out.append((0xE3, .command)) }
        return out
    }

    /// The modifier a key is (a HID usage: left and right control, shift, option and command, 0xE0 to
    /// 0xE7), or nil for any other key.
    static func flag(forKey usage: UInt16) -> KeyModifiers? {
        switch usage {
        case 0xE0, 0xE4: return .control
        case 0xE1, 0xE5: return .shift
        case 0xE2, 0xE6: return .option
        case 0xE3, 0xE7: return .command
        default: return nil
        }
    }
}

enum KeyChord {
    /// One key with `modifiers`, as a keyboard sends it: each modifier's own key down, the key down
    /// and up carrying them all, each modifier's key up (`modifiersDown`, `modifiersUp`). With nothing
    /// latched, the key alone.
    static func press(_ usage: UInt16, with modifiers: KeyModifiers) -> [InputEvent] {
        modifiersDown(modifiers)
            + [.key(hidUsage: usage, down: true, modifiers: modifiers.rawValue),
               .key(hidUsage: usage, down: false, modifiers: modifiers.rawValue)]
            + modifiersUp(modifiers)
    }

    /// Spotlight on the Mac: exactly ⌘Space, ⌘'s own key down, Space down and up, ⌘ up.
    static let spotlight: [InputEvent] = press(0x2C, with: .command)

    /// Each of `modifiers`' own keys going down, in `KeyModifiers.keys`' order, each carrying the
    /// flags in force once it is down: what a shortcut and the trackpad's modified click or drag
    /// press first.
    static func modifiersDown(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held: KeyModifiers = []
        return modifiers.keys.map { key in
            held.insert(key.flag)
            return .key(hidUsage: key.usage, down: true, modifiers: held.rawValue)
        }
    }

    /// The same keys going up in the reverse order, each carrying the flags still in force after it:
    /// what the shortcut and the click or the drag release after.
    static func modifiersUp(_ modifiers: KeyModifiers) -> [InputEvent] {
        var held = modifiers
        return modifiers.keys.reversed().map { key in
            held.remove(key.flag)
            return .key(hidUsage: key.usage, down: false, modifiers: held.rawValue)
        }
    }
}

/// A hardware keyboard's keys on their way to the Mac (InputOverlayView's pressesBegan, pressesEnded
/// and pressesCancelled). A key goes to the Mac as a key, or to the text system, when it goes down, and
/// its up follows the same way whatever the modifier flags say by then. Judged again at the release,
/// as before, a key held while ⌘ was let go went up in the text system and stayed down on the Mac, and
/// ⌘'s own release reached the Mac with command still on it, or not at all (UIKit's flags at a
/// modifier's release are those before or after it), so the Mac kept ⌘ held.
///
/// A key's down carries the flags UIKit gives it (the shortcut: ⌘⇧S with shift held for the text
/// system too); a modifier's own key and every up carry only the modifier keys down on the Mac, as a
/// keyboard would leave them, so a Mac from before 2026-09-27, which posts each key's flags as they
/// come, is left with nothing this device does not hold there.
struct ForwardedKeys {
    /// The keys whose down went to the Mac and whose up has not, in the order they went down.
    private(set) var down: [UInt16] = []
    /// Caps Lock as Escape (CapsLockEscape): the overlay sets it from the device's setting at each press.
    var capsLockEscape = false
    /// A key whose down went to the Mac as another key (Caps Lock as Escape): its up goes as that one,
    /// whatever the setting says by then.
    private var sentAs: [UInt16: UInt16] = [:]
    /// The flags UIKit gave the last key the text system took, until its up: what `typed` reads.
    private var textFlags: UInt64?

    /// The keys the text system never delivers, which go to the Mac as keys whatever is held: the
    /// arrows, escape, forward delete, home, end, page up and down, F1 to F12, and ⌘, ⌃ and ⌥
    /// themselves (so a click while one is held is a modified click on the Mac).
    static let keyUsages: Set<UInt16> = [
        0x4F, 0x50, 0x51, 0x52,                                                   // right, left, down, up
        0x29, 0x4C, 0x4A, 0x4D, 0x4B, 0x4E,                                       // escape, forward delete, home, end, page up and down
        0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45,   // F1…F12
        0xE0, 0xE2, 0xE3, 0xE4, 0xE6, 0xE7,                                       // control, option, command, left and right
    ]

    /// Whether a key pressed with these modifiers goes to the Mac as a key rather than to the text
    /// system: one of `keyUsages`, or any key while ⌘, ⌃ or ⌥ is held, as those make shortcuts (⌘S,
    /// ⌃A, ⌥←) and never reach the text system. Shift alone makes characters, which the text system
    /// composes (shifted, dead-keyed, from an IME) and sends as text.
    static func goesAsKey(_ usage: UInt16, modifiers: UInt64) -> Bool {
        keyUsages.contains(usage) || modifiers & KeyModifiers.shortcutMakers.rawValue != 0
    }

    /// A key pressed, with the modifier flags UIKit gives it: its down, when it goes to the Mac as a
    /// key; nil when the text system takes it. With Caps Lock as Escape on, Caps Lock goes as Escape
    /// and no key carries iPadOS's caps lock (CapsLockEscape).
    mutating func began(_ usage: UInt16, modifiers: UInt64) -> InputEvent? {
        let sent = CapsLockEscape.usage(usage, on: capsLockEscape)
        let flags = CapsLockEscape.modifiers(modifiers, on: capsLockEscape)
        guard Self.goesAsKey(sent, modifiers: flags) else {
            textFlags = modifiers
            return nil
        }
        if sent != usage { sentAs[usage] = sent }
        if !down.contains(sent) { down.append(sent) }
        let isModifier = KeyModifiers.flag(forKey: sent) != nil
        return .key(hidUsage: sent, down: true, modifiers: isModifier ? held : flags)
    }

    /// A key released, or its press cancelled (the app going to the background, the keyboard gone):
    /// its up, when its down went to the Mac, with the modifier keys still down there; nil when the
    /// text system had it.
    mutating func ended(_ usage: UInt16) -> InputEvent? {
        let sent = sentAs.removeValue(forKey: usage) ?? usage
        guard let i = down.firstIndex(of: sent) else {
            textFlags = nil
            return nil
        }
        down.remove(at: i)
        return .key(hidUsage: sent, down: false, modifiers: held)
    }

    /// Every key still down on the Mac going up, the last pressed first, each with the modifier keys
    /// still down after it: the overlay no longer taking keys (the Settings panel, the tour) or leaving
    /// the screen, after which UIKit sends it no release.
    mutating func releaseAll() -> [InputEvent] {
        var ups: [InputEvent] = []
        while let usage = down.last, let up = ended(usage) { ups.append(up) }
        sentAs = [:]
        return ups
    }

    /// What the text system typed (the overlay's insertText), as it goes to the Mac: with Caps Lock
    /// as Escape on, a letter from a hardware key pressed while iPadOS's caps lock was on is as it
    /// would be with caps lock off (CapsLockEscape.text). That key's flags are spent.
    mutating func typed(_ text: String) -> String {
        defer { textFlags = nil }
        return CapsLockEscape.text(text, pressFlags: textFlags, on: capsLockEscape)
    }

    /// The modifier flags of the modifier keys down on the Mac.
    private var held: UInt64 { down.reduce(0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) } }
}

/// Caps Lock as Escape: the Settings panel's switch under This iPad (CapsLockEscapeRow), kept on this
/// device in `Sill.capsLockEscape`, off until turned on. A hardware keyboard's Caps Lock then goes to the
/// Mac as Escape. iPadOS keeps its own caps lock below the app and may still turn it on with that key,
/// so while this is on that state goes into nothing sent: not into a key's flags, not into a letter's
/// case. iPadOS's own Modifier Keys setting does the same for every app, without the state.
enum CapsLockEscape {
    static let defaultsKey = "Sill.capsLockEscape"
    static let capsLock: UInt16 = 0x39
    static let escape: UInt16 = 0x29
    /// UIKeyModifierFlags.alphaShift, which the Mac posts as caps lock (KeyStrokes.capsLock).
    static let capsLockFlag: UInt64 = 1 << 16

    /// The key a hardware key goes to the Mac as.
    static func usage(_ usage: UInt16, on: Bool) -> UInt16 { on && usage == capsLock ? escape : usage }

    /// The flags a hardware key carries to the Mac.
    static func modifiers(_ modifiers: UInt64, on: Bool) -> UInt64 { on ? modifiers & ~capsLockFlag : modifiers }

    /// One character the text system typed for a hardware key pressed with `pressFlags`: with caps lock
    /// on there, as it would be with caps lock off, upper case with shift held and lower case without
    /// (a digit or a symbol has no case to change). Any other text (more than one character, no key
    /// pressed: the software keyboard, dictation) is left as it is.
    static func text(_ text: String, pressFlags: UInt64?, on: Bool) -> String {
        guard on, let flags = pressFlags, flags & capsLockFlag != 0, text.count == 1 else { return text }
        return flags & KeyModifiers.shift.rawValue != 0 ? text.uppercased() : text.lowercased()
    }

    static let title = "Caps Lock as Escape"

    static func footnote(mac: String, device: String) -> String {
        "Caps Lock on a keyboard connected to this \(device) sends Esc to \(mac), and letters type as if Caps Lock were off. "
            + "iPadOS’s own Modifier Keys setting (Settings › General › Keyboard › Hardware Keyboard) does this in every app."
    }
}
