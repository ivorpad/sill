import CoreGraphics

/// The keyboard events a typed character or a plain key becomes, which InputInjector.type (a device's
/// text) and ShieldTyping (a password at the lock screen) both post. Only the events are made here:
/// each caller posts them its own way, so a dry run counts them and the lock screen's are never logged.
enum TextTyping {
    /// A character as a Unicode key event, down and up. The Unicode string carries the character
    /// whatever the Mac's keyboard layout is, which is what a software keyboard on the phone means; the
    /// keycode is the US key the character sits on (KeyStrokes.textKey), for apps that read keycodes, and
    /// 0 for anything else. Nil when CoreGraphics makes no event for it.
    static func character(_ character: Character, source: CGEventSource?) -> (down: CGEvent, up: CGEvent)? {
        let units = Array(character.utf16)
        let key = KeyStrokes.textKey(for: character)
        let virtualKey = CGKeyCode(key?.virtualKey ?? 0)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else { return nil }
        down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        // No modifiers, explicitly: the character carries its own case, and an event made from this
        // source after a ⌘Space (the Spotlight key) could otherwise inherit ⌘, which Spotlight's field
        // ignores (typing into Spotlight did nothing, 2026-09-23). Never shift either, for a shifted
        // character: a posted event leaves its flags in the HID state table the next click starts from
        // (KeyStrokes); the string has the case.
        down.flags = []
        up.flags = []
        return (down, up)
    }

    /// A key tapped with no flags, down then up: plain Return, Tab, Delete, never a leftover modifier. Each
    /// event is made and then handed to `post` before the next is made, as InputInjector always did. An
    /// event CoreGraphics does not make is left out.
    static func tap(virtualKey: CGKeyCode, source: CGEventSource?, post: (CGEvent) -> Void) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { continue }
            event.flags = []
            post(event)
        }
    }

    /// A key struck with these flags (⌘A), down then up, the up with `before`, the flags the HID state
    /// table held just before it (KeyStrokes.chord's shape): the shortcut leaves none of its own modifiers
    /// in the table the next click and the characters after it start from. An event CoreGraphics does not
    /// make is left out.
    static func shortcut(virtualKey: CGKeyCode, flags: CGEventFlags, before: CGEventFlags, source: CGEventSource?) -> [CGEvent] {
        [true, false].compactMap { down in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { return nil }
            event.flags = down ? flags : before
            return event
        }
    }
}
