import SwiftUI
import StreamProtocol

/// "‹Mac› is locked" (docs/lock-screen-plan.md, P2): over the stream while the Mac's window list says
/// its console is locked (`StreamClient.hostLocked`), in the view hierarchy as PairingOverlay is (a
/// ZStack sibling of the layouts, never a sheet, popover or alert: StreamScreen).
///
/// When the list also says this connection may unlock (`hostUnlock`), the card has a secure field,
/// labelled as the lock screen asks (Password, PIN, or both when the Mac says something this build does
/// not know), and Unlock, which sends what is typed once (kind 44) and clears the field the moment it is
/// sent. One tap is one attempt and nothing retries. The Passwords app fills the field, after its own
/// Face ID (`textContentType(.password)`). For a password (never a PIN) to a Mac this connection is
/// pinned to, on a device with Face ID or Touch ID (LockScreenPolicy.savedOffer), the card also has
/// "Use Face ID next time", off each time it shows, which keeps a typed password that unlocks the Mac
/// in this device's keychain (SavedUnlock), and once one is kept "Unlock with Face ID", which sends it
/// after Face ID: a tap, never by itself as the card shows, since a glance would unlock the Mac.
/// Without `unlock` the card says to unlock at the Mac. Hide leaves the picture usable, until the Mac
/// locks again or the Settings panel's Unlock row brings the card back.
///
/// No character typed here may also reach the Mac as input, and the stream's own keyboard is where
/// those would go: StreamScreen puts the panel and the stream's keyboard away before this shows, takes
/// every touch away from the layouts under it, and keeps the stream's input view from taking the
/// keyboard back while it shows (`InputOverlayProxy.keysBlocked`).
struct LockedCard: View {
    @ObservedObject var client: StreamClient
    /// What is typed. Cleared when it is sent, when the card goes, when the app leaves the screen and
    /// when the Mac stops taking it.
    @State private var secret = ""
    /// The last Unlock found the secret could not be typed (`LockScreenPolicy.Block.cannotType`): the
    /// line says so and nothing was sent.
    @State private var cannotType = false
    /// "Use Face ID next time": off each time the card shows.
    @State private var remember = false
    /// Face ID is up for the kept password.
    @State private var reading = false
    /// What the last "Unlock with Face ID" ran into, when it sent nothing.
    @State private var savedLine: String?
    @FocusState private var fieldFocused: Bool
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Duo's fold across the stream screen (StreamScreen, iOS 27.1): the card keeps off it.
    @Environment(\.duoFold) private var duoFold
    @Environment(\.scenePhase) private var scenePhase

    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    private var mac: String { client.macName.isEmpty ? "Your Mac" : client.macName }
    /// What the lock screen asks for, as the list says it.
    private var ask: String { client.hostLocked ?? LockScreenAsk.password }
    private var label: String { LockScreenAsk.label(ask) }
    private var canUnlock: Bool { client.hostUnlock == true }
    /// An unlock request is waiting for its answer.
    private var sending: Bool {
        guard let attempt = client.lockScreenAttempt else { return false }
        return attempt.action == LockScreenAction.unlock && attempt.sending
    }

    /// The kept password's button or switch, or neither.
    private var offer: LockScreenPolicy.SavedOffer { client.savedOffer }
    private var biometry: LockScreenPolicy.Biometry { client.savedUnlock.biometry ?? .faceID }

    /// The line under the field: nothing could be typed, Face ID gave nothing, or what the Mac said to
    /// the last attempt.
    private var line: String? {
        if cannotType { return LockScreenPolicy.cannotType(ask: ask) }
        if let savedLine { return savedLine }
        return LockScreenPolicy.unlockLine(client.lockScreenAttempt, ask: ask, mac: mac)
    }

    var body: some View {
        GeometryReader { geo in
            let layout = ConnectLayout(size: geo.size, fold: duoFold)
            let width = min(layout.short ? 640 : 420, (layout.leadingPage ?? geo.size.width) - 32)
            // The field has the keyboard: the card goes to the top, so Unlock stays above it (the
            // stream screen ignores the keyboard's safe area, so nothing moves by itself), as the
            // pairing overlay does. The half-folded Duo's is in the top half already.
            let toTop = fieldFocused && !layout.topHalf
            ZStack(alignment: .top) {
                // The pairing overlay's own scrim, so the layouts under both are dimmed alike. What is
                // under the card takes no touch anyway.
                OverlayScrim()
                // At its own height when it fits, scrolling in the room it has when it does not (a
                // short screen with larger text). On an opaque panel, the Settings panel's: the pairing
                // overlay's viewfinder covers the bar and the keys under it, and this card, which is
                // only words and buttons, would let them show through the scrim.
                ViewThatFits(in: .vertical) {
                    card
                    ScrollView { card }
                        .scrollBounceBehavior(.basedOnSize)
                }
                .padding(16)
                .background(Self.shape.fill(Palette.bar))
                .overlay(Self.shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                .frame(width: width, alignment: .leading)
                .padding(.vertical, 16)
                .frame(maxWidth: layout.leadingPage ?? .infinity, maxHeight: layout.topRoom ?? geo.size.height,
                       alignment: toTop ? .top : .center)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, hide)
        .background(EscapeKey(action: hide))
        .onAppear {
            titleFocused = true
            client.refreshSavedUnlock()
            #if DEBUG
            // `-SillLockFocus 1`: the field has the keyboard as it shows, for a photo of the card above it.
            if UserDefaults.standard.bool(forKey: "SillLockFocus"), canUnlock { fieldFocused = true }
            #endif
        }
        .onChange(of: secret) { _, _ in cannotType = false; savedLine = nil }
        // What was typed for a Mac that stops taking it goes with it.
        .onChange(of: canUnlock) { _, can in
            if !can { secret = ""; fieldFocused = false }
        }
        // Face ID's own sheet makes the scene inactive for a moment; only leaving the screen clears.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { secret = "" }
            if phase == .active { client.refreshSavedUnlock() }    // Face ID may have been set up meanwhile
        }
        .onDisappear { secret = "" }
        #if DEBUG
        .task { await pressFromLaunchArgument() }
        .task { await pressSavedFromLaunchArgument() }
        #endif
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            if canUnlock {
                VStack(alignment: .leading, spacing: 8) {
                    if offer == .unlockWithSaved { savedButton }
                    field
                    if offer == .remember { rememberSwitch }
                    if ask == LockScreenAsk.pin {
                        Text(LockScreenPolicy.pinWarning)
                            .font(.footnote)
                            .foregroundStyle(Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let line { ProblemLine(text: line, scales: true) }
                }
                HStack(spacing: 18) {
                    unlockButton
                    hideButton
                }
            } else {
                Text(LockScreenPolicy.unlockAtTheMac(mac: mac))
                    .font(.subheadline)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                hideButton
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var title: some View {
        Text(LockScreenPolicy.title(mac: mac))
            .font(.headline)
            .foregroundStyle(Palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($titleFocused)
    }

    /// A 48 pt field on the drawer's control colour, like the pairing code's. The text is dots, and the
    /// Passwords app may fill it.
    private var field: some View {
        SecureField("", text: $secret, prompt: Text(label).foregroundColor(Palette.muted))
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($fieldFocused)
            .onSubmit(submit)
            .font(.subheadline)
            .foregroundStyle(Palette.text)
            .accessibilityLabel(label)
            .frame(minHeight: 48)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
            .opacity(sending ? 0.5 : 1)
            .disabled(sending)
    }

    /// "Unlock with Face ID": the password kept on this device, after Face ID (StreamClient.unlockWithSaved).
    private var savedButton: some View {
        let enabled = !sending && !reading
        return Button { Task { await pressSaved() } } label: {
            Label(LockScreenPolicy.unlockWithSaved(biometry), systemImage: Self.symbol(biometry))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(enabled ? 1 : 0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityHint("Sends the password saved on this \(StreamClient.deviceWord) to \(mac).")
    }

    private static func symbol(_ biometry: LockScreenPolicy.Biometry) -> String {
        switch biometry {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        }
    }

    /// "Use Face ID next time", and what it means.
    private var rememberSwitch: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $remember) {
                Text(LockScreenPolicy.rememberTitle(biometry))
                    .font(.subheadline)
                    .foregroundStyle(Palette.text)
            }
            .tint(Palette.accent)
            .disabled(sending)
            .frame(minHeight: 44)
            Text(LockScreenPolicy.rememberFootnote(device: StreamClient.deviceWord))
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unlockButton: some View {
        let enabled = !sending && !reading && !secret.isEmpty
        return Button(action: submit) {
            Text(sending ? "Unlocking…" : "Unlock")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black)
                .frame(minWidth: 88, minHeight: 44)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.accent.opacity(enabled ? 1 : 0.4)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(sending ? "Unlocking \(mac)" : "Unlock \(mac)")
    }

    private var hideButton: some View {
        Button("Hide", action: hide)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.accent)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityHint("Shows the picture of \(mac). The Unlock row in Settings brings this back.")
    }

    /// Unlock and Return: one attempt. The field is cleared the moment it is sent, and the keyboard
    /// goes down so the Mac's answer is in view.
    private func submit() {
        // Return on an empty field only puts the keyboard away: on a phone on its side it can cover
        // Hide, and nothing else would take it down.
        guard !secret.isEmpty else { fieldFocused = false; return }
        guard !sending, !reading else { return }
        switch client.sendUnlock(secret: secret, remember: remember && offer == .remember) {
        case nil:
            secret = ""
            cannotType = false
            savedLine = nil
            fieldFocused = false
        case .cannotType?:
            cannotType = true
        default:
            // Not connected, no longer locked, no longer allowed: the screen is already changing.
            break
        }
    }

    /// "Unlock with Face ID": one attempt with the kept password, or the line saying why none went.
    @MainActor private func pressSaved() async {
        guard !reading, !sending else { return }
        reading = true
        cannotType = false
        savedLine = nil
        fieldFocused = false
        let said = await client.unlockWithSaved()
        reading = false
        savedLine = said
    }

    /// Hide, Esc and the VoiceOver escape gesture.
    private func hide() {
        secret = ""
        fieldFocused = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { client.hideLockCard() }
    }

    #if DEBUG
    /// DEBUG `-SillUnlockAfter <s>`: a stand-in for a finger, which the simulator gates do not have.
    /// `s` seconds after the card first shows in this launch, a made-up string (never a password) is put
    /// in the field and, a second later, Unlock is pressed as a tap would press it. Only where
    /// `StreamClient.lockHarnessRefusal` lets it (the mock, or a synthetic host on this Mac's loopback).
    @MainActor private func pressFromLaunchArgument() async {
        guard !Self.pressed, let raw = UserDefaults.standard.string(forKey: "SillUnlockAfter"),
              let seconds = Double(raw), seconds >= 0 else { return }
        Self.pressed = true
        if let why = client.lockHarnessRefusal {
            print("lock screen: harness: -SillUnlockAfter refused: \(why)")
            return
        }
        try? await Task.sleep(for: .seconds(seconds))
        guard canUnlock, !Task.isCancelled else { return }
        secret = "made-up, not a password"
        // `-SillRemember 1`: and "Use Face ID next time" on, where the card has it.
        if UserDefaults.standard.bool(forKey: "SillRemember"), offer == .remember { remember = true }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
        print("lock screen: harness: the stand-in presses Unlock\(remember ? " with Use Face ID next time on" : "")")
        submit()
    }
    private static var pressed = false

    /// DEBUG `-SillFaceIDAfter <s>`: a stand-in for a tap on "Unlock with Face ID", s seconds after the
    /// card first shows in this launch. The Face ID that follows is the simulator's (Features › Face
    /// ID, or `notifyutil -p com.apple.BiometricKit_Sim.pearl.match` in it). The same guard as
    /// `-SillUnlockAfter`'s: the mock, or a synthetic host on this Mac's loopback.
    @MainActor private func pressSavedFromLaunchArgument() async {
        guard !Self.savedPressed, let raw = UserDefaults.standard.string(forKey: "SillFaceIDAfter"),
              let seconds = Double(raw), seconds >= 0 else { return }
        Self.savedPressed = true
        if let why = client.lockHarnessRefusal {
            print("lock screen: harness: -SillFaceIDAfter refused: \(why)")
            return
        }
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        guard offer == .unlockWithSaved else {
            print("lock screen: harness: no saved password offered (\(offer))")
            return
        }
        print("lock screen: harness: the stand-in presses \(LockScreenPolicy.unlockWithSaved(biometry))")
        await pressSaved()
        if let savedLine { print("lock screen: harness: the card says: \(savedLine)") }
    }
    private static var savedPressed = false
    #endif
}

/// The Settings panel's Lock Screen group, while a password is kept on this device for this session's
/// Mac (SavedUnlock): Forget Saved Password, and what is kept where. The panel reads the keychain again
/// as the group shows (`refreshSavedUnlock`).
struct SavedUnlockRow: View {
    @ObservedObject var client: StreamClient
    let mac: String

    var body: some View {
        if client.savedUnlock.saved {
            Rows {
                Button(action: client.forgetSavedUnlock) {
                    Text(LockScreenPolicy.forgetSaved)
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Removes \(mac)’s password from this \(StreamClient.deviceWord).")
                .rowFrame()
            }
            Footnote(text: LockScreenPolicy.savedFootnote(mac: mac, biometry: client.savedUnlock.biometry,
                                                          device: StreamClient.deviceWord))
        }
    }
}
